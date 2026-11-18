import CryptoKit
import Foundation
import SwiftData

@MainActor
final class BriefingService {
    private let context: ModelContext
    private let client: LLMClient
    private let keychain: KeychainStore
    private let calendar: Calendar

    init(
        context: ModelContext,
        client: LLMClient = LLMClient(),
        keychain: KeychainStore = KeychainStore(),
        calendar: Calendar = .current
    ) {
        self.context = context
        self.client = client
        self.keychain = keychain
        self.calendar = calendar
    }

    static func isConfigured() -> Bool {
        let settings = LLMSettingsStore.load()
        guard !settings.baseURL.isEmpty, !settings.model.isEmpty else { return false }
        return KeychainStore().hasKey(account: settings.provider.rawValue)
    }

    static func settingsSummary() -> String {
        let settings = LLMSettingsStore.load()
        return "\(settings.provider.displayName) · \(settings.model)"
    }

    func generate(dayKey: String, force: Bool = false) async throws -> DailyReport {
        let settings = LLMSettingsStore.load()
        guard let apiKey = keychain.read(account: settings.provider.rawValue), !apiKey.isEmpty else {
            throw LLMError(kind: .notConfigured, message: "请先在设置中填写 API Key")
        }

        let metrics = try context.fetch(FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date)]))
        guard let index = metrics.firstIndex(where: { $0.dayKey == dayKey }) else {
            throw LLMError(kind: .insufficientData, message: "这一天没有健康数据")
        }
        let today = metrics[index]
        let snapshot = today.snapshot
        let history = metrics[..<index].map(\.snapshot)
        let baseline = Baseline.compute(history: history, today: snapshot, calendar: calendar)
        guard baseline.baselineDays >= 3 else {
            throw LLMError(kind: .insufficientData, message: "个人基线还在积累，至少需要 3 天数据")
        }

        let allScores = try context.fetch(FetchDescriptor<DailyScore>())
        let score = allScores.first { $0.dayKey == dayKey }
        let payload = makePayload(
            today: today,
            metrics: metrics,
            history: history,
            baseline: baseline,
            score: score,
            allScores: allScores
        )
        let payloadJSON = try payload.jsonString()
        let inputHash = Self.sha256Hex(payloadJSON)

        let existing = try reportRow(for: dayKey)
        if !force, let existing, existing.status == .success, existing.payloadJSON != nil {
            return existing
        }

        let row = existing ?? DailyReport(dayKey: dayKey)
        if existing == nil { context.insert(row) }
        row.status = .pending
        row.providerID = settings.provider.rawValue
        row.model = settings.model
        row.inputHash = inputHash
        row.errorKind = nil
        row.errorMessage = nil
        row.generatedAt = .now
        try context.save()

        do {
            let content = try await client.complete(
                configuration: .init(
                    baseURL: settings.baseURL,
                    model: settings.model,
                    apiKey: apiKey,
                    provider: settings.provider
                ),
                messages: [
                    .init(role: "system", content: PromptBuilder.systemPrompt),
                    .init(role: "user", content: PromptBuilder.userPrompt(payloadJSON: payloadJSON)),
                ],
                maxTokens: 800,
                jsonMode: true
            )
            let parsed = try BriefingReport.parse(content)
            row.payloadJSON = try parsed.jsonString()
            row.status = .success
            row.errorKind = nil
            row.errorMessage = nil
            row.generatedAt = .now
            try context.save()
            return row
        } catch {
            row.status = .failed
            row.errorKind = (error as? LLMError)?.kind.rawValue ?? LLMErrorKind.unknown.rawValue
            row.errorMessage = error.localizedDescription
            row.generatedAt = .now
            try? context.save()
            throw error
        }
    }

    func previewPayload(dayKey: String) throws -> String {
        let metrics = try context.fetch(FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date)]))
        guard let index = metrics.firstIndex(where: { $0.dayKey == dayKey }) else {
            throw LLMError(kind: .insufficientData, message: "这一天没有健康数据")
        }
        let today = metrics[index]
        let history = metrics[..<index].map(\.snapshot)
        let baseline = Baseline.compute(history: history, today: today.snapshot, calendar: calendar)
        let allScores = try context.fetch(FetchDescriptor<DailyScore>())
        let payload = makePayload(
            today: today,
            metrics: metrics,
            history: history,
            baseline: baseline,
            score: allScores.first { $0.dayKey == dayKey },
            allScores: allScores
        )
        let json = try payload.jsonString()
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(
                  withJSONObject: object,
                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let string = String(data: pretty, encoding: .utf8)
        else {
            return json
        }
        return string
    }

    private func reportRow(for dayKey: String) throws -> DailyReport? {
        let all = try context.fetch(FetchDescriptor<DailyReport>())
        return all.first { $0.dayKey == dayKey }
    }

    private func makePayload(
        today: DailyMetrics,
        metrics: [DailyMetrics],
        history: [DailySnapshot],
        baseline: BaselineResult,
        score: DailyScore?,
        allScores: [DailyScore]
    ) -> BriefingPayload {
        let snapshot = today.snapshot
        let now = Date()
        let config = ScoringConfig()
        // 今天尚未过完时，把真实清醒 / 日光窗口与各指标的阶段目标一并交给模型，
        // 避免它在清晨把「还没来得及喝水、运动」写成全天结论。
        let dayContext = DayProgress.context(
            for: today.date, today: snapshot, history: history, now: now, calendar: calendar
        )
        let readinessComponents = decode(ReadinessComponents.self, from: score?.readinessComponentsJSON)
        let stressComponents = decode(StressComponents.self, from: score?.stressComponentsJSON)
        let missing = score.map { missingLabels($0) } ?? []

        let weekStart = DayKey.addingDays(-6, to: today.date, calendar: calendar)
        let weekSnapshots = metrics.filter { $0.date >= weekStart }.map(\.snapshot)
        let weekKeys = Set(weekSnapshots.map(\.dayKey))
        let sleepAvg = ScoreSupport.mean(
            weekSnapshots.compactMap { MetricSanitizer.value($0.sleepTotalH, in: MetricRange.sleepHours) }
        )
        let readinessAvg = ScoreSupport.mean(
            allScores.filter { weekKeys.contains($0.dayKey) }.compactMap(\.readiness)
        )
        let stressAvg = ScoreSupport.mean(
            allScores.filter { weekKeys.contains($0.dayKey) }.compactMap(\.stress)
        )

        let todayStart = calendar.startOfDay(for: today.date)
        let week7Start = DayKey.addingDays(-7, to: todayStart, calendar: calendar)
        let week28Start = DayKey.addingDays(-28, to: todayStart, calendar: calendar)
        var load7: [Double] = []
        var load28: [Double] = []
        for item in history {
            let start = calendar.startOfDay(for: item.date)
            guard start >= week28Start, start < todayStart else { continue }
            let steps = MetricSanitizer.value(item.steps, in: MetricRange.steps)
            let energy = MetricSanitizer.value(item.activeEnergy, in: MetricRange.activeEnergy)
            guard steps != nil || energy != nil else { continue }
            let load = (energy ?? 0) + (steps ?? 0) * 0.04
            load28.append(load)
            if start >= week7Start { load7.append(load) }
        }

        let zHRV = snapshot.hrvSDNN.flatMap { baseline.zHRV($0) }
        let zRestingHR = snapshot.restingHR.flatMap { baseline.zScore($0, stats: baseline.restingHR) }
        let zRespiratory = snapshot.respiratoryRate.flatMap { baseline.zScore($0, stats: baseline.respiratoryRate) }
        let zWristTemp = snapshot.wristTempC.flatMap { baseline.zScore($0, stats: baseline.wristTempC) }
        let hrvBaselineMs = baseline.hrvLog.map { exp($0.mean) - 1 }

        var caveats = missing.map { "缺少\($0)数据" }
        if baseline.baselineDays < 7 {
            caveats.append("个人基线仅 \(baseline.baselineDays) 天")
        }
        if snapshot.hrvSDNN == nil {
            caveats.append("当天没有 HRV 测量")
        }
        if snapshot.systolicBP == nil && snapshot.diastolicBP == nil {
            caveats.append("没有血压记录")
        }
        if snapshot.bloodGlucoseMgDl == nil {
            caveats.append("没有血糖记录")
        }
        if snapshot.bodyMassKg == nil {
            caveats.append("没有体重记录")
        }
        if !NutritionValues.from(snapshot).hasData {
            caveats.append("没有饮水与饮食记录")
        }
        if dayContext.isPartialDay {
            caveats.append("当日尚未结束，饮水/饮食/运动/日照等累计量只与当前时刻的阶段目标比较")
        }

        let weight7 = ScoreSupport.recentValues(
            windowDays: 7, history: history, today: snapshot, calendar: calendar
        ) { MetricSanitizer.value($0.bodyMassKg, in: MetricRange.bodyMassKg) }
        let weight7Avg = ScoreSupport.mean(weight7)
        let midpointSD = ScoreSupport.sleepMidpointSD(
            history: history,
            today: snapshot,
            config: ScoringConfig(),
            calendar: calendar
        )

        return BriefingPayload(
            date: today.dayKey,
            baselineDays: baseline.baselineDays,
            scores: .init(
                readiness: PayloadNumber.rounded(score?.readiness),
                stress: PayloadNumber.rounded(score?.stress),
                readinessComponents: readinessComponents,
                stressComponents: stressComponents,
                completeness: score?.completeness ?? 0,
                missing: missing,
                confidence: score?.confidenceRaw ?? ScoreConfidence.insufficient.rawValue
            ),
            autonomic: .init(
                hrvDailyAvg: PayloadNumber.rounded(snapshot.hrvSDNN),
                hrvLatest: PayloadNumber.rounded(today.hrvLatest),
                zHRV: PayloadNumber.rounded(zHRV),
                hrvBaselineMs: PayloadNumber.rounded(hrvBaselineMs),
                restingHR: PayloadNumber.rounded(snapshot.restingHR),
                zRestingHR: PayloadNumber.rounded(zRestingHR),
                restingHRBaseline: PayloadNumber.rounded(baseline.restingHR?.mean)
            ),
            sleep: .init(
                totalH: PayloadNumber.rounded(snapshot.sleepTotalH),
                deepH: PayloadNumber.rounded(snapshot.deepH),
                remH: PayloadNumber.rounded(snapshot.remH),
                efficiency: PayloadNumber.rounded(snapshot.sleepEfficiency),
                avg7dH: PayloadNumber.rounded(sleepAvg)
            ),
            activity: .init(
                steps: PayloadNumber.rounded(snapshot.steps),
                activeEnergy: PayloadNumber.rounded(snapshot.activeEnergy),
                exerciseMinutes: PayloadNumber.rounded(snapshot.exerciseMinutes),
                load7d: PayloadNumber.rounded(ScoreSupport.mean(load7)),
                load28d: PayloadNumber.rounded(ScoreSupport.mean(load28))
            ),
            vitals: .init(
                respiratoryRate: PayloadNumber.rounded(snapshot.respiratoryRate),
                spo2: PayloadNumber.rounded(snapshot.spo2),
                wristTempC: PayloadNumber.rounded(snapshot.wristTempC),
                zRespiratoryRate: PayloadNumber.rounded(zRespiratory),
                zWristTemp: PayloadNumber.rounded(zWristTemp)
            ),
            trend7d: .init(
                days: 7,
                readinessAvg: PayloadNumber.rounded(readinessAvg),
                stressAvg: PayloadNumber.rounded(stressAvg),
                sleepAvgH: PayloadNumber.rounded(sleepAvg)
            ),
            caveats: caveats,
            fitness: .init(
                vo2max: PayloadNumber.rounded(latestVO2(today: today, history: history, calendar: calendar)),
                vo2maxBaseline: PayloadNumber.rounded(baseline.vo2Max?.mean),
                walkingSpeedKmh: PayloadNumber.rounded(snapshot.walkingSpeedMps.map { $0 * 3.6 }),
                walkingSteadinessPct: PayloadNumber.rounded(snapshot.walkingSteadinessPct),
                walkingAsymmetryPct: PayloadNumber.rounded(snapshot.walkingAsymmetryPct),
                flightsClimbed: PayloadNumber.rounded(snapshot.flightsClimbed),
                distanceWalkingKm: PayloadNumber.rounded(snapshot.distanceWalkingKm)
            ),
            bodyComposition: .init(
                weightKg: PayloadNumber.rounded(snapshot.bodyMassKg),
                weight7dAvgKg: PayloadNumber.rounded(weight7Avg),
                bodyFatPct: PayloadNumber.rounded(snapshot.bodyFatPct),
                leanMassKg: PayloadNumber.rounded(snapshot.leanBodyMassKg),
                bmi: PayloadNumber.rounded(snapshot.bmi),
                waistCm: PayloadNumber.rounded(snapshot.waistCircumferenceCm)
            ),
            cardio: .init(
                systolic: PayloadNumber.rounded(snapshot.systolicBP),
                diastolic: PayloadNumber.rounded(snapshot.diastolicBP),
                glucoseMgDl: PayloadNumber.rounded(snapshot.bloodGlucoseMgDl),
                basalTempC: nil
            ),
            lifestyle: .init(
                daylightMin: PayloadNumber.rounded(snapshot.daylightMinutes),
                mindfulMin: PayloadNumber.rounded(snapshot.mindfulMinutes),
                moodValence: PayloadNumber.rounded(snapshot.stateOfMindValence),
                sleepMidpointMin: PayloadNumber.rounded(snapshot.sleepMidpointMinutes),
                sleepMidpointSdMin: PayloadNumber.rounded(midpointSD)
            ),
            nutrition: .init(
                waterTotalMl: PayloadNumber.rounded(snapshot.waterTotalMl),
                externalWaterMl: PayloadNumber.rounded(snapshot.externalWaterMl),
                localWaterMl: PayloadNumber.rounded(snapshot.localWaterMl),
                energyKcal: PayloadNumber.rounded(snapshot.dietaryEnergyKcal),
                carbsG: PayloadNumber.rounded(snapshot.dietaryCarbsG),
                proteinG: PayloadNumber.rounded(snapshot.dietaryProteinG),
                fatG: PayloadNumber.rounded(snapshot.dietaryFatG),
                fiberG: PayloadNumber.rounded(snapshot.dietaryFiberG),
                sugarG: PayloadNumber.rounded(snapshot.dietarySugarG),
                sodiumMg: PayloadNumber.rounded(snapshot.dietarySodiumMg),
                caffeineMg: PayloadNumber.rounded(snapshot.dietaryCaffeineMg),
                score: PayloadNumber.rounded(readinessComponents?.nutrition)
            ),
            dayContext: .init(
                observedAt: {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    return formatter.string(from: now)
                }(),
                isPartialDay: dayContext.isPartialDay,
                activityProgress: PayloadNumber.rounded(dayContext.activity) ?? dayContext.activity,
                daylightProgress: PayloadNumber.rounded(dayContext.daylight) ?? dayContext.daylight,
                windowText: dayContext.windowText,
                stageTargets: .init(
                    waterMl: PayloadNumber.rounded(DayProgress.stagedTarget(
                        config.nutritionWaterTargetMl, progress: dayContext.activity)),
                    energyKcalLower: PayloadNumber.rounded(DayProgress.stagedTarget(
                        config.nutritionEnergyLowerKcal, progress: dayContext.activity)),
                    energyKcalUpper: PayloadNumber.rounded(DayProgress.stagedTarget(
                        config.nutritionEnergyUpperKcal, progress: dayContext.activity)),
                    proteinG: PayloadNumber.rounded(DayProgress.stagedTarget(
                        config.nutritionProteinTargetG, progress: dayContext.activity)),
                    fiberG: PayloadNumber.rounded(DayProgress.stagedTarget(
                        config.nutritionFiberTargetG, progress: dayContext.activity)),
                    daylightMin: PayloadNumber.rounded(DayProgress.stagedTarget(
                        config.daylightTargetMinutes, progress: dayContext.daylight)),
                    mindfulMin: PayloadNumber.rounded(DayProgress.stagedTarget(
                        10, progress: dayContext.activity))
                )
            )
        )
    }

    private func latestVO2(today: DailyMetrics, history: [DailySnapshot], calendar: Calendar) -> Double? {
        let cutoff = DayKey.addingDays(-28, to: calendar.startOfDay(for: today.date), calendar: calendar)
        return (history + [today.snapshot])
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .last { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) != nil }?
            .vo2Max
    }

    private func missingLabels(_ score: DailyScore) -> [String] {
        guard !score.missing.isEmpty else { return [] }
        return score.missing.components(separatedBy: "、").filter { !$0.isEmpty }
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
