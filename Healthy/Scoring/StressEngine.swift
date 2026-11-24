import Foundation

enum StressEngine {
    static func evaluate(
        today: DailySnapshot,
        history: [DailySnapshot],
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current,
        context: DayProgressContext = .complete,
        manualIncomplete: Set<MetricSource> = []
    ) -> StressResult {
        // 系统判定不全 + 用户手动标记，合并为当天的跳过集合。
        let exclusions = ScoreSupport.exclusions(
            today: today, history: history, manualIncomplete: manualIncomplete
        )
        let baseline = Baseline.compute(history: history, today: today, config: config, calendar: calendar)
        // 被跳过的数据源对应分量直接置 nil，不再用历史数据兜底。
        // 心情分量用的心情/正念读数在可用源判定中归入生活节律，故一并跳过。
        let hrv = exclusions.contains(.hrv) ? nil : hrvComponent(today, baseline: baseline, config: config)
        let restingHR = exclusions.contains(.restingHR)
            ? nil
            : restingHRComponent(today, baseline: baseline, config: config)
        let sleep = exclusions.contains(.sleep)
            ? nil
            : sleepComponent(today, history: history, config: config, calendar: calendar)
        let vitals = exclusions.contains(.vitals)
            ? nil
            : vitalsComponent(today, baseline: baseline, config: config)
        let circadian = exclusions.contains(.circadian)
            ? nil
            : circadianComponent(
                history: history, today: today, config: config,
                calendar: calendar, context: context
            )
        let mood = exclusions.contains(.circadian)
            ? nil
            : moodComponent(
                history: history, today: today, config: config,
                calendar: calendar, context: context
            )

        let weighted = ScoreSupport.weightedAverage([
            (config.stressHRVWeight, hrv),
            (config.stressRestingHRWeight, restingHR),
            (config.stressSleepWeight, sleep),
            (config.stressVitalsWeight, vitals),
            (config.stressCircadianWeight, circadian),
            (config.stressMoodWeight, mood),
        ])
        // 饮食质量联动：饮食评分下降则压力升高，饮食改善则压力降低。
        // 手动标记饮食不全时联动归零；系统判定营养素缺失但仍有规律饮食记录时，
        // 沿用 combinedScore 的既有口径，不因完整度标记而丢弃可用评分。
        let dietAdjustment = manualIncomplete.contains(.nutrition)
            ? 0
            : dietComponent(today, config: config, context: context)
        // 完成度按实际参与评分的源数计算（手动标记同样扣除）。
        let confidence = ScoreSupport.confidence(
            baselineDays: baseline.baselineDays,
            completeness: exclusions.effectiveCount,
            config: config
        )
        let score = confidence == .insufficient
            ? nil
            : weighted.map { ScoreSupport.clampScore($0 + dietAdjustment) }

        return StressResult(
            score: score,
            level: score.map { level(for: $0, config: config) },
            components: StressComponents(
                hrv: hrv,
                restingHR: restingHR,
                sleep: sleep,
                vitals: vitals,
                circadian: circadian,
                mood: mood
            ),
            completeness: exclusions.effectiveCount,
            missing: MetricSource.allCases.filter { exclusions.autoMissing.contains($0) },
            confidence: confidence,
            baselineDays: baseline.baselineDays,
            skipped: exclusions.skipped
        )
    }

    static func level(for score: Double, config: ScoringConfig) -> StressLevel {
        if score < config.stressLowUpperBound { return .low }
        if score < config.stressModerateUpperBound { return .moderateLow }
        if score < config.stressElevatedUpperBound { return .elevated }
        return .high
    }

    /// 饮食评分对压力分的联动量（正数为压力升高，负数为压力降低）。
    /// 复用全 App 统一的饮食评分口径（饮食质量 0.7 + 规律饮食 0.3），
    /// 两者都缺失时返回 0。75 分为中性基准，每低 1 分压力 +0.25，改善时最多 -4 分。
    private static func dietComponent(
        _ today: DailySnapshot,
        config: ScoringConfig,
        context: DayProgressContext
    ) -> Double {
        guard let score = NutritionEngine.combinedScore(
            NutritionValues.from(today),
            regularity: today.mealRegularityScore,
            config: config,
            progress: context.activity
        ) else { return 0 }
        return min(
            config.stressDietWorseningCap,
            max(-config.stressDietImprovementCap,
                (config.stressDietNeutralScore - score) * config.stressDietFactor)
        )
    }

    private static func hrvComponent(
        _ today: DailySnapshot,
        baseline: BaselineResult,
        config: ScoringConfig
    ) -> Double? {
        guard let hrv = MetricSanitizer.value(today.hrvSDNN, in: MetricRange.hrv),
              let z = baseline.zHRV(hrv)
        else { return nil }
        return ScoreSupport.clampScore(50 - 16 * ScoreSupport.clampZ(z, config.zClamp))
    }

    private static func restingHRComponent(
        _ today: DailySnapshot,
        baseline: BaselineResult,
        config: ScoringConfig
    ) -> Double? {
        guard let restingHR = MetricSanitizer.value(today.restingHR, in: MetricRange.restingHR),
              let z = baseline.zScore(restingHR, stats: baseline.restingHR)
        else { return nil }
        return ScoreSupport.clampScore(50 + 14 * ScoreSupport.clampZ(z, config.zClamp))
    }

    private static func sleepComponent(
        _ today: DailySnapshot,
        history: [DailySnapshot],
        config: ScoringConfig,
        calendar: Calendar
    ) -> Double? {
        let todayStart = calendar.startOfDay(for: today.date)
        let windowStart = DayKey.addingDays(-7, to: todayStart, calendar: calendar)
        var nights: [Double] = []
        if let tonight = MetricSanitizer.value(today.sleepTotalH, in: MetricRange.sleepHours) {
            nights.append(tonight)
        }
        for snapshot in history {
            let start = calendar.startOfDay(for: snapshot.date)
            guard start < todayStart, start >= windowStart else { continue }
            if let hours = MetricSanitizer.value(snapshot.sleepTotalH, in: MetricRange.sleepHours) {
                nights.append(hours)
            }
        }
        guard nights.count >= config.minSleepNights, let average = ScoreSupport.mean(nights) else {
            return nil
        }
        return ScoreSupport.clampScore(100 - 18 * (config.sleepTargetHours - average))
    }

    private static func vitalsComponent(
        _ today: DailySnapshot,
        baseline: BaselineResult,
        config: ScoringConfig
    ) -> Double? {
        var available = false
        var score = 50.0

        if let resp = MetricSanitizer.value(today.respiratoryRate, in: MetricRange.respiratoryRate),
           let z = baseline.zScore(resp, stats: baseline.respiratoryRate) {
            available = true
            score += 25 * max(0, ScoreSupport.clampZ(z, config.zClamp))
        }
        if let temp = MetricSanitizer.value(today.wristTempC, in: MetricRange.wristTemp),
           let z = baseline.zScore(temp, stats: baseline.wristTempC) {
            available = true
            score += 25 * max(0, ScoreSupport.clampZ(z, config.zClamp))
        }
        if let systolic = MetricSanitizer.value(today.systolicBP, in: MetricRange.systolicBP),
           let diastolic = MetricSanitizer.value(today.diastolicBP, in: MetricRange.diastolicBP) {
            available = true
            if systolic >= 140 || diastolic >= 90 {
                score += 25
            }
        }
        if let glucose = MetricSanitizer.value(today.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) {
            available = true
            if let z = baseline.zScore(glucose, stats: baseline.bloodGlucose), z > 2 {
                score += 15
            }
        }

        return available ? ScoreSupport.clampScore(score) : nil
    }

    private static func circadianComponent(
        history: [DailySnapshot],
        today: DailySnapshot,
        config: ScoringConfig,
        calendar: Calendar,
        context: DayProgressContext
    ) -> Double? {
        var parts: [(weight: Double, score: Double?)] = []

        // 日照只在日光时段累积；睡眠或夜间不该因「还没晒太阳」抬高压力分。
        if let daylight = MetricSanitizer.value(today.daylightMinutes, in: MetricRange.daylightMinutes),
           let target = DayProgress.stagedTarget(config.daylightTargetMinutes, progress: context.daylight) {
            let score = ScoreSupport.clampScore(100 - daylight / target * 70)
            parts.append((0.50, score))
        }
        if let sd = ScoreSupport.sleepMidpointSD(
            history: history,
            today: today,
            config: config,
            calendar: calendar
        ) {
            let score = ScoreSupport.clampScore((sd - config.sleepMidpointSDFloor) * 1.5)
            parts.append((0.50, score))
        }
        return ScoreSupport.weightedAverage(parts)
    }

    private static func moodComponent(
        history: [DailySnapshot],
        today: DailySnapshot,
        config: ScoringConfig,
        calendar: Calendar,
        context: DayProgressContext
    ) -> Double? {
        var parts: [(weight: Double, score: Double?)] = []

        let valences = ScoreSupport.recentValues(
            windowDays: 7, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.stateOfMindValence, in: MetricRange.stateOfMindValence) }
        if let average = ScoreSupport.mean(valences) {
            parts.append((0.70, ScoreSupport.clampScore(50 - 30 * average)))
        }

        // 正念分钟同样是清醒时段的累计量，按清醒窗口的阶段目标比较。
        if let mindful = MetricSanitizer.value(today.mindfulMinutes, in: MetricRange.mindfulMinutes),
           let target = DayProgress.stagedTarget(10, progress: context.activity) {
            parts.append((0.30, ScoreSupport.clampScore(50 - 2 * (mindful - target))))
        }

        return ScoreSupport.weightedAverage(parts)
    }
}
