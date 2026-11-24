import Foundation
import HealthKit

enum HealthKitError: LocalizedError {
    case unavailable
    case authorizationRequired
    /// 只影响「写回喝水」这一路，读取同步应继续完成。
    case writeAuthorizationRequired
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "这台设备不支持健康数据。"
        case .authorizationRequired:
            return "还没有授权读取健康数据，请先完成授权。"
        case .writeAuthorizationRequired:
            return "健康 App 未允许本 App 写入喝水量 / 咖啡因及饮品营养（碳水、蛋白质、脂肪），双向同步暂只同步到本 App。"
        case .queryFailed(let message):
            return "读取健康数据失败：\(message)"
        }
    }
}

struct SleepAggregate: Sendable {
    var inBed: Double = 0
    var core: Double = 0
    var deep: Double = 0
    var rem: Double = 0
    var awake: Double = 0
    var firstAsleepStart: Date?
    var lastAsleepEnd: Date?
    var awakeCount: Int = 0
    var stages: [SleepStageInterval] = []

    var asleep: Double { core + deep + rem }

    /// 主睡眠区间 = 最长的一段连续睡眠（合并间隔 < mergeGapMinutes 的片段）。
    /// 用于入睡点 / 睡眠中点 / 醒来点，自动忽略远离夜间的午睡等短时片段，
    /// 否则午睡会拉偏 firstAsleepStart / lastAsleepEnd，使中点计算严重偏差。
    /// 纯算法见 SleepModels.mainSleepSpan(from:mergeGapMinutes:)，此处仅做 asleep 片段筛选后委托。
    func mainSleepSpan(mergeGapMinutes: Double = 240) -> (start: Date, end: Date)? {
        let asleep = stages.filter { $0.stage == .core || $0.stage == .deep || $0.stage == .rem }
        return Healthy.mainSleepSpan(from: asleep, mergeGapMinutes: mergeGapMinutes)
    }
}

struct StateOfMindAggregate: Sendable {
    var valence: Double
    var count: Int
}

struct WorkoutAggregate: Sendable {
    var count: Int = 0
    var minutes: Double = 0
}

/// 健身 App 活动圆环的官方摘要（HKActivitySummary），与「健身」App 完全同源。
/// 数值口径：activeEnergyBurned 千卡 / exerciseTime 分钟 / standHours 小时；
/// 三个 goal 是用户在健身 App 里设置的真实圆环目标（可能随时被用户修改）。
struct ActivityRingSummary: Sendable {
    var activeEnergyKcal: Double
    var exerciseMinutes: Double
    var standHours: Double
    var activeGoalKcal: Double?
    var exerciseGoalMinutes: Double?
    var standGoalHours: Double?
}

struct HealthCharacteristics: Sendable, Equatable {
    /// 健康档案里的真实出生日期（dateOfBirthComponents 解析结果）。
    /// 设置页必须用它，不能用「年龄取整反推」，否则生日会差到半年。
    var birthDate: Date? = nil
    var chronologicalAge: Double?
    var isMale: Bool?
    var notice: String? = nil
}

actor HealthKitService {
    private let store = HKHealthStore()
    /// 观察查询需要自己持有强引用，释放后系统就不再投递更新。
    private var waterObserverQuery: HKObserverQuery?
    private var caffeineObserverQuery: HKObserverQuery?

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        return try await withCheckedThrowingContinuation { continuation in
            store.requestAuthorization(
                toShare: HealthKitTypes.writeTypes,
                read: HealthKitTypes.readTypes
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// 个人特征类型不会弹系统授权界面，但 HealthKit 要求先声明读取：
    /// 老版本只在 readTypes 里声明了数量/类别类型，导致出生日期与性别一直停留在
    /// notDetermined，dateOfBirthComponents() 抛 "Authorization is not determined"。
    /// 这里只对两个特征类型补一次声明，不触碰其他已授权项、也不会弹授权界面。
    func ensureCharacteristicAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let types = HealthKitTypes.characteristicTypes
        guard types.contains(where: { store.authorizationStatus(for: $0) == .notDetermined }) else { return }
        _ = try? await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            store.requestAuthorization(toShare: [], read: types) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: success)
                }
            }
        }
    }

    /// 只判断「读取」是否已请求过：写回喝水量是可选的增强能力，
    /// 写权限缺失不应挡住原有的只读同步（写权限由 canWriteWater 单独检查）。
    func authorizationRequestStatus() async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: HealthKitTypes.readTypes) { status, _ in
                continuation.resume(returning: status)
            }
        }
    }

    func fetchDailyMetrics(
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current,
        maxHeartRate: Double? = nil
    ) async throws -> [DailyMetricsDTO] {
        let perfToken = PerformanceTrace.shared.begin(
            "HealthKit · 每日指标 \(days) 天", category: .api, detail: "tz=\(calendar.timeZone.identifier)"
        )
        defer { PerformanceTrace.shared.end(perfToken) }
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }

        let end = now
        let firstDay = calendar.startOfDay(
            for: DayKey.addingDays(-(days - 1), to: end, calendar: calendar)
        )

        var rows: [String: DailyMetricsDTO] = [:]
        for index in 0..<days {
            let date = DayKey.addingDays(index, to: firstDay, calendar: calendar)
            let key = DayKey.key(for: date, calendar: calendar)
            rows[key] = DailyMetricsDTO(dayKey: key, date: date, sourceFlags: 0)
        }

        let averages = try await dailyAverages(start: firstDay, end: end, calendar: calendar)
        let sums = try await dailySums(start: firstDay, end: end, calendar: calendar)
        // 活动 / 锻炼 / 站立以健身 App 官方活动摘要为准（含用户真实圆环目标）；
        // 摘要缺失的日子回退到普通统计查询。
        let activityRings = try await activitySummariesByDay(start: firstDay, end: end, calendar: calendar)
        let sleep = try await sleepByDay(start: firstDay, end: end, calendar: calendar)
        var sleepWindows: [String: DateInterval] = [:]
        for (key, aggregate) in sleep {
            if let onset = aggregate.firstAsleepStart, let wake = aggregate.lastAsleepEnd, wake > onset {
                sleepWindows[key] = DateInterval(start: onset, end: wake)
            }
        }
        let sleepStats = try await sleepWindowStatistics(
            windows: sleepWindows,
            start: firstDay.addingTimeInterval(-24 * 3600),
            end: end
        )
        let workouts = try await workoutsByDay(start: firstDay, end: end, calendar: calendar)
        // 仅在能推算最大心率时折算 workouts 心率区间；否则跳过（卡片会提示需填写年龄）。
        var zoneMinutes: [String: WorkoutZoneMinutes]?
        if let maxHR = maxHeartRate {
            zoneMinutes = try await workoutZoneMinutesByDay(
                start: firstDay, end: end, maxHeartRate: maxHR, calendar: calendar
            )
        }
        let mindful = try await mindfulByDay(start: firstDay, end: end, calendar: calendar)
        let moods = try await stateOfMindByDay(start: firstDay, end: end, calendar: calendar)
        let wristTemperatures = try await wristTemperatureByDay(start: firstDay, end: end, calendar: calendar)
        let nutrition = try await nutritionByDay(start: firstDay, end: end, calendar: calendar)
        let latestHRV = try await latestHRVSample()

        for (key, var row) in rows {
            row.hrvSDNN = averages[HealthKitTypes.hrv]?[key]
            row.restingHR = averages[HealthKitTypes.restingHeartRate]?[key]
            row.avgHR = averages[HealthKitTypes.heartRate]?[key]
            row.walkingHR = averages[HealthKitTypes.walkingHeartRate]?[key]
            row.respiratoryRate = averages[HealthKitTypes.respiratoryRate]?[key]
            row.spo2 = UnitConversion.percent(fromFraction: averages[HealthKitTypes.oxygenSaturation]?[key])
            row.wristTempC = wristTemperatures[key]
            row.vo2Max = averages[HealthKitTypes.vo2Max]?[key]
            row.walkingSpeedMps = averages[HealthKitTypes.walkingSpeed]?[key]
            row.walkingStepLengthCm = UnitConversion.centimeters(fromMeters: averages[HealthKitTypes.walkingStepLength]?[key])
            row.walkingAsymmetryPct = UnitConversion.percent(fromFraction: averages[HealthKitTypes.walkingAsymmetry]?[key])
            row.walkingSteadinessPct = UnitConversion.percent(fromFraction: averages[HealthKitTypes.walkingSteadiness]?[key])
            row.bodyMassKg = averages[HealthKitTypes.bodyMass]?[key]
            row.bodyFatPct = UnitConversion.percent(fromFraction: averages[HealthKitTypes.bodyFatPercentage]?[key])
            row.leanBodyMassKg = averages[HealthKitTypes.leanBodyMass]?[key]
            row.bmi = averages[HealthKitTypes.bodyMassIndex]?[key]
            row.waistCircumferenceCm = UnitConversion.centimeters(fromMeters: averages[HealthKitTypes.waistCircumference]?[key])
            row.systolicBP = averages[HealthKitTypes.bloodPressureSystolic]?[key]
            row.diastolicBP = averages[HealthKitTypes.bloodPressureDiastolic]?[key]
            row.bloodGlucoseMgDl = averages[HealthKitTypes.bloodGlucose]?[key]

            // 外部水量与饮食指标都来自 HealthKit；本 App 回写的样本已在读取时排除。
            if let day = nutrition[key] {
                row.externalWaterMl = day.externalWaterMl
                row.dietaryEnergyKcal = day.energyKcal
                row.dietaryCarbsG = day.carbsG
                row.dietaryProteinG = day.proteinG
                row.dietaryFatG = day.fatG
                row.dietaryFiberG = day.fiberG
                row.dietarySugarG = day.sugarG
                row.dietarySodiumMg = day.sodiumMg
                // 外部咖啡因单独存，最终总量由 WaterMerge 合并本 App 打卡后写入。
                row.externalCaffeineMg = day.caffeineMg
            }

            row.steps = sums[HealthKitTypes.stepCount]?[key]
            row.activeEnergy = sums[HealthKitTypes.activeEnergy]?[key]
            row.basalEnergyKcal = sums[HealthKitTypes.basalEnergy]?[key]
            row.exerciseMinutes = sums[HealthKitTypes.exerciseTime]?[key]
            row.standMinutes = sums[HealthKitTypes.standTime]?[key]
            // 有官方摘要就整体覆盖三环：数值与「健身」App 同源，摘要里的 0 也是官方口径的 0，
            // 不能再回退成统计查询值（否则清晨会出现数值漂移）。
            if let ring = activityRings[key] {
                row.activeEnergy = ring.activeEnergyKcal
                row.exerciseMinutes = ring.exerciseMinutes
                row.standMinutes = ring.standHours * 60
                row.activeEnergyGoal = ring.activeGoalKcal
                row.exerciseGoalMinutes = ring.exerciseGoalMinutes
                row.standGoalHours = ring.standGoalHours
                appLog(
                    .debug, "HealthKit",
                    "活动摘要 \(key): 能量=\(Int(ring.activeEnergyKcal))/\(ring.activeGoalKcal.map { Int($0) }.map(String.init) ?? "?") 卡 "
                    + "锻炼=\(Int(ring.exerciseMinutes))/\(ring.exerciseGoalMinutes.map { Int($0) }.map(String.init) ?? "?") 分 "
                    + "站立=\(Int(ring.standHours))/\(ring.standGoalHours.map { Int($0) }.map(String.init) ?? "?") 小时"
                )
            }
            row.flightsClimbed = sums[HealthKitTypes.flightsClimbed]?[key]
            row.distanceWalkingKm = UnitConversion.kilometers(fromMeters: sums[HealthKitTypes.distanceWalkingRunning]?[key])
            row.daylightMinutes = sums[HealthKitTypes.timeInDaylight]?[key]
            row.environmentalNoiseDb = averages[HealthKitTypes.environmentalAudioExposure]?[key]
            row.mindfulMinutes = mindful[key]
            if let mood = moods[key] {
                row.stateOfMindValence = mood.valence
                row.stateOfMindCount = mood.count
            }

            if let sleepAggregate = sleep[key] {
                row.sleepTotalH = sleepAggregate.asleep > 0 ? sleepAggregate.asleep : nil
                row.deepH = sleepAggregate.deep > 0 ? sleepAggregate.deep : nil
                row.remH = sleepAggregate.rem > 0 ? sleepAggregate.rem : nil
                row.coreH = sleepAggregate.core > 0 ? sleepAggregate.core : nil
                row.awakeH = sleepAggregate.awake > 0 ? sleepAggregate.awake : nil
                row.inBedH = sleepAggregate.inBed > 0 ? sleepAggregate.inBed : nil
                let denominator = sleepAggregate.inBed > 0 ? sleepAggregate.inBed : sleepAggregate.asleep + sleepAggregate.awake
                if denominator > 0 {
                    row.sleepEfficiency = sleepAggregate.asleep / denominator
                }
                if let firstAsleep = sleepAggregate.firstAsleepStart,
                   let lastAsleep = sleepAggregate.lastAsleepEnd {
                    row.sleepBedtimeMinutes = firstAsleep.timeIntervalSince(row.date) / 60
                    let midpoint = firstAsleep.addingTimeInterval(lastAsleep.timeIntervalSince(firstAsleep) / 2)
                    row.sleepMidpointMinutes = midpoint.timeIntervalSince(row.date) / 60
                }
                row.awakeCount = sleepAggregate.awakeCount > 0 ? sleepAggregate.awakeCount : nil
                row.sleepOnsetAt = sleepAggregate.firstAsleepStart
                row.sleepWakeAt = sleepAggregate.lastAsleepEnd
                row.sleepStagesJSON = SleepStageCodec.encode(sleepAggregate.stages)
            }

            if let stats = sleepStats[key] {
                row.sleepAvgHR = stats.avgHR
                row.sleepMinHR = stats.minHR
                row.sleepMaxHR = stats.maxHR
                row.sleepAvgHRV = stats.avgHRV
                row.sleepAvgResp = stats.avgResp
                row.sleepAvgSpo2 = stats.avgSpo2
            }

            if let workout = workouts[key] {
                row.workoutCount = workout.count
                row.workoutMinutes = workout.count > 0 ? workout.minutes : nil
            }

            if let zones = zoneMinutes?[key], zones.total > 0,
               let json = try? JSONEncoder().encode(zones),
               let encoded = String(data: json, encoding: .utf8) {
                row.workoutZoneMinutesJSON = encoded
            }

            rows[key] = row
        }

        if let latestHRV {
            let key = DayKey.key(for: latestHRV.date, calendar: calendar)
            if var row = rows[key] {
                row.hrvLatest = latestHRV.value
                row.hrvLatestAt = latestHRV.date
                if row.hrvSDNN == nil,
                   latestHRV.date >= DayKey.addingDays(-1, to: end, calendar: calendar) {
                    row.hrvSDNN = latestHRV.value
                }
                rows[key] = row
            }
        }

        // 记录本次读取的参数与今日步数，便于和健康 App 对照时确认是「读错了」还是「取旧了」。
        let todayKey = DayKey.key(for: DayKey.startOfDay(end, calendar: calendar), calendar: calendar)
        appLog(
            .info, "HealthKit",
            "读取 \(days) 天 tz=\(calendar.timeZone.identifier) today=\(todayKey) "
            + "steps=\(rows[todayKey]?.steps.map { Int($0.rounded()) }.map(String.init) ?? "nil")"
        )
        return rows.values
            .map { row in
                var row = row
                row.sourceFlags = sourceFlags(for: row)
                return row
            }
            .sorted { $0.date < $1.date }
    }

    private func sourceFlags(for row: DailyMetricsDTO) -> Int {
        var flags = 0
        if row.sleepTotalH != nil || row.inBedH != nil || row.sleepMidpointMinutes != nil {
            flags |= MetricSource.sleep.rawValue
        }
        if row.hrvSDNN != nil { flags |= MetricSource.hrv.rawValue }
        if row.restingHR != nil { flags |= MetricSource.restingHR.rawValue }
        if row.steps != nil || row.activeEnergy != nil || row.basalEnergyKcal != nil
            || row.distanceWalkingKm != nil || row.flightsClimbed != nil || row.workoutCount != nil {
            flags |= MetricSource.activity.rawValue
        }
        if row.respiratoryRate != nil || row.spo2 != nil || row.wristTempC != nil
            || row.systolicBP != nil || row.diastolicBP != nil
            || row.bloodGlucoseMgDl != nil {
            flags |= MetricSource.vitals.rawValue
        }
        if row.daylightMinutes != nil || row.mindfulMinutes != nil
            || row.stateOfMindValence != nil || row.sleepMidpointMinutes != nil {
            flags |= MetricSource.circadian.rawValue
        }
        if row.vo2Max != nil || row.walkingSpeedMps != nil || row.walkingStepLengthCm != nil
            || row.walkingAsymmetryPct != nil || row.walkingSteadinessPct != nil
            || row.bodyMassKg != nil || row.bodyFatPct != nil || row.leanBodyMassKg != nil
            || row.bmi != nil || row.waistCircumferenceCm != nil {
            flags |= MetricSource.fitnessBody.rawValue
        }
        if row.externalWaterMl != nil || row.dietaryEnergyKcal != nil || row.dietaryCarbsG != nil
            || row.dietaryProteinG != nil || row.dietaryFatG != nil || row.dietaryFiberG != nil
            || row.dietarySugarG != nil || row.dietarySodiumMg != nil || row.dietaryCaffeineMg != nil
            || row.externalCaffeineMg != nil {
            flags |= MetricSource.nutrition.rawValue
        }
        return flags
    }

    /// 只查今天的步数：单个 HKStatisticsQuery，比 fetchDailyMetrics 的整套查询轻得多。
    /// 供回前台时刷新使用，避免步数因整体同步的 10 分钟节流一直停在旧值。
    func todayStepCount(now: Date = .now, calendar: Calendar = .current) async -> Double? {
        let perfToken = PerformanceTrace.shared.begin("HealthKit · 今日步数", category: .api)
        defer { PerformanceTrace.shared.end(perfToken) }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let start = calendar.startOfDay(for: now)
        return await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate])
            let query = HKStatisticsQuery(
                quantityType: HealthKitTypes.stepCount,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: .count()))
            }
            store.execute(query)
        }
    }

    private func dailyAverages(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [HKQuantityType: [String: Double]] {
        var result: [HKQuantityType: [String: Double]] = [:]
        for (type, unit) in HealthKitTypes.dailyAverageTypes {
            result[type] = try await statistics(type: type, sum: false, unit: unit, start: start, end: end, calendar: calendar)
        }
        return result
    }

    private func dailySums(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [HKQuantityType: [String: Double]] {
        var result: [HKQuantityType: [String: Double]] = [:]
        for (type, unit) in HealthKitTypes.dailySumTypes {
            result[type] = try await statistics(type: type, sum: true, unit: unit, start: start, end: end, calendar: calendar)
        }
        return result
    }

    /// 按天读取健身 App 的活动摘要（HKActivitySummaryQuery）。
    /// 这是官方圆环的数据源：活动 / 锻炼 / 站立三个环的数值与目标都从这里来。
    /// 没有摘要的日子返回空字典，调用方回退到普通统计查询。
    private func activitySummariesByDay(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: ActivityRingSummary] {
        try await withCheckedThrowingContinuation { continuation in
            // HKActivitySummary 谓词要求 DateComponents 必须显式携带 calendar，否则抛
            // NSInvalidArgumentException: Date components require a calendar。
            var startComponents = calendar.dateComponents([.era, .year, .month, .day], from: start)
            startComponents.calendar = calendar
            var endComponents = calendar.dateComponents([.era, .year, .month, .day], from: end)
            endComponents.calendar = calendar
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart:
                startComponents,
                end: endComponents
            )
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                var result: [String: ActivityRingSummary] = [:]
                for summary in summaries ?? [] {
                    // 摘要的 dateComponents 是「健身 App」口径的日历日；转到本 App 的日历再落 key，
                    // 避免跨时区 / 跨日界线时对错行。
                    guard let date = calendar.date(from: summary.dateComponents(for: calendar)) else { continue }
                    let key = DayKey.key(for: calendar.startOfDay(for: date), calendar: calendar)
                    result[key] = ActivityRingSummary(
                        activeEnergyKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                        exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                        standHours: summary.appleStandHours.doubleValue(for: .count()),
                        activeGoalKcal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                        exerciseGoalMinutes: summary.exerciseTimeGoal?.doubleValue(for: .minute()),
                        standGoalHours: summary.standHoursGoal?.doubleValue(for: .count())
                    )
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    /// 只取今天的活动摘要：单个 HKActivitySummaryQuery，供回前台轻量刷新三环使用。
    func todayActivitySummary(now: Date = .now, calendar: Calendar = .current) async -> ActivityRingSummary? {
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        let start = calendar.startOfDay(for: now)
        return await withCheckedContinuation { (continuation: CheckedContinuation<ActivityRingSummary?, Never>) in
            var startComponents = calendar.dateComponents([.era, .year, .month, .day], from: start)
            startComponents.calendar = calendar
            var endComponents = calendar.dateComponents([.era, .year, .month, .day], from: now)
            endComponents.calendar = calendar
            let predicate = HKQuery.predicate(forActivitySummariesBetweenStart:
                startComponents,
                end: endComponents
            )
            let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, _ in
                guard let summary = summaries?.first else {
                    continuation.resume(returning: nil)
                    return
                }
                let ring = ActivityRingSummary(
                    activeEnergyKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                    exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()),
                    standHours: summary.appleStandHours.doubleValue(for: .count()),
                    activeGoalKcal: summary.activeEnergyBurnedGoal.doubleValue(for: .kilocalorie()),
                    exerciseGoalMinutes: summary.exerciseTimeGoal?.doubleValue(for: .minute()),
                    standGoalHours: summary.standHoursGoal?.doubleValue(for: .count())
                )
                continuation.resume(returning: ring)
            }
            store.execute(query)
        }
    }

    private func statistics(
        type: HKQuantityType,
        sum: Bool,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: sum ? .cumulativeSum : .discreteAverage,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }
                var values: [String: Double] = [:]
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = sum ? statistics.sumQuantity() : statistics.averageQuantity()
                    guard let quantity else { return }
                    let key = DayKey.key(for: statistics.startDate, calendar: calendar)
                    let value = quantity.doubleValue(for: unit)
                    values[key] = value
                    // 步数是最常对不上的指标：把每天聚合值落进 App 内日志，
                    // 配合设置 → 调试日志里的「步数对账」按钮可直接比对三种口径。
                    if type.identifier == HKQuantityTypeIdentifier.stepCount.rawValue {
                        appLog(.debug, "HealthKit", "步数聚合 \(key) = \(Int(value.rounded())) (mode=\(sum ? "cumulativeSum" : "discreteAverage"), predicate=strictStartDate)")
                    }
                }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func sleepByDay(start: Date, end: Date, calendar: Calendar) async throws -> [String: SleepAggregate] {
        let samples = try await samples(of: HealthKitTypes.sleepAnalysis, start: start, end: end)
        var aggregates: [String: SleepAggregate] = [:]
        for case let sample as HKCategorySample in samples {
            guard let category = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            let key = DayKey.key(for: sample.endDate, calendar: calendar)
            let hours = max(0, sample.endDate.timeIntervalSince(sample.startDate) / 3600)
            var aggregate = aggregates[key] ?? SleepAggregate()
            let stage: SleepStageKind? = switch category {
            case .inBed: .inBed
            case .awake: .awake
            case .asleepCore, .asleepUnspecified: .core
            case .asleepDeep: .deep
            case .asleepREM: .rem
            default: nil
            }
            if let stage, sample.endDate > sample.startDate {
                aggregate.stages.append(
                    SleepStageInterval(start: sample.startDate, end: sample.endDate, stage: stage)
                )
            }
            switch category {
            case .inBed:
                aggregate.inBed += hours
            case .asleepCore, .asleepUnspecified:
                aggregate.core += hours
            case .asleepDeep:
                aggregate.deep += hours
            case .asleepREM:
                aggregate.rem += hours
            case .awake:
                aggregate.awake += hours
                aggregate.awakeCount += 1
            default:
                break
            }
            aggregates[key] = aggregate
        }
        // 入睡点 / 中点 / 醒来点统一取「主睡眠区间」，忽略远离夜间的午睡等短时片段。
        for key in aggregates.keys {
            var aggregate = aggregates[key]!
            if let main = aggregate.mainSleepSpan() {
                aggregate.firstAsleepStart = main.start
                aggregate.lastAsleepEnd = main.end
            }
            aggregates[key] = aggregate
        }
        return aggregates
    }

    private func workoutsByDay(start: Date, end: Date, calendar: Calendar) async throws -> [String: WorkoutAggregate] {
        let samples = try await samples(of: HKObjectType.workoutType(), start: start, end: end)
        var aggregates: [String: WorkoutAggregate] = [:]
        for case let workout as HKWorkout in samples {
            let key = DayKey.key(for: workout.startDate, calendar: calendar)
            var aggregate = aggregates[key] ?? WorkoutAggregate()
            aggregate.count += 1
            aggregate.minutes += max(0, workout.duration / 60)
            aggregates[key] = aggregate
        }
        return aggregates
    }

    /// 返回每天（按 workout 开始日期）的训练区间列表，供心率区间折算使用。
    private func workoutIntervalsByDay(
        start: Date, end: Date, calendar: Calendar
    ) async throws -> [String: [WorkoutInterval]] {
        let samples = try await samples(of: HKObjectType.workoutType(), start: start, end: end)
        var result: [String: [WorkoutInterval]] = [:]
        for case let workout as HKWorkout in samples {
            let key = DayKey.key(for: workout.startDate, calendar: calendar)
            result[key, default: []].append(WorkoutInterval(start: workout.startDate, end: workout.endDate))
        }
        return result
    }

    /// 逐段查询 workouts 时间窗内的心率采样，按相邻样本时长积分到各 %HRmax 区间，
    /// 得到每天（Z1–Z5）的训练分钟。心率数据缺失的日子返回空数组（不计入）。
    private func workoutZoneMinutesByDay(
        start: Date, end: Date, maxHeartRate: Double, calendar: Calendar
    ) async throws -> [String: WorkoutZoneMinutes] {
        let intervalsByDay = try await workoutIntervalsByDay(start: start, end: end, calendar: calendar)
        guard !intervalsByDay.isEmpty else { return [:] }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        var result: [String: WorkoutZoneMinutes] = [:]
        for (key, intervals) in intervalsByDay {
            var acc = [Double](repeating: 0, count: WorkoutZoneMinutes.zoneCount)
            for interval in intervals where interval.end > interval.start {
                let hrSamples = try await samples(of: HealthKitTypes.heartRate, start: interval.start, end: interval.end)
                    .compactMap { $0 as? HKQuantitySample }
                var lastDate: Date?
                var lastHR: Double?
                for sample in hrSamples {
                    let hr = sample.quantity.doubleValue(for: bpm)
                    if let lastDate, let lastHR {
                        let delta = sample.startDate.timeIntervalSince(lastDate)
                        // 心率采样间隔通常几秒到几十秒；剔除异常跳变（>10 分钟）避免误把静息段计入。
                        if delta > 0, delta < 600 {
                            let minutes = delta / 60
                            acc[WorkoutZoneMinutes.zoneIndex(heartRate: lastHR, maxHeartRate: maxHeartRate)] += minutes
                        }
                    }
                    lastDate = sample.startDate
                    lastHR = hr
                }
            }
            let minutes = acc.map { ($0 * 100).rounded() / 100 }
            guard minutes.reduce(0, +) > 0 else { continue }
            result[key] = WorkoutZoneMinutes(minutes: minutes)
        }
        return result
    }

    private func mindfulByDay(start: Date, end: Date, calendar: Calendar) async throws -> [String: Double] {
        let samples = try await samples(of: HealthKitTypes.mindfulSession, start: start, end: end)
        var minutes: [String: Double] = [:]
        for case let sample as HKCategorySample in samples {
            let key = DayKey.key(for: sample.startDate, calendar: calendar)
            minutes[key, default: 0] += max(0, sample.endDate.timeIntervalSince(sample.startDate) / 60)
        }
        return minutes
    }

    private func stateOfMindByDay(start: Date, end: Date, calendar: Calendar) async throws -> [String: StateOfMindAggregate] {
        let samples = try await samples(of: HealthKitTypes.stateOfMind, start: start, end: end)
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for case let sample as HKStateOfMind in samples {
            let key = DayKey.key(for: sample.startDate, calendar: calendar)
            sums[key, default: 0] += sample.valence
            counts[key, default: 0] += 1
        }
        var result: [String: StateOfMindAggregate] = [:]
        for (key, count) in counts where count > 0 {
            result[key] = StateOfMindAggregate(valence: (sums[key] ?? 0) / Double(count), count: count)
        }
        return result
    }

    private func wristTemperatureByDay(start: Date, end: Date, calendar: Calendar) async throws -> [String: Double] {
        let samples = try await samples(of: HealthKitTypes.wristTemperature, start: start, end: end)
        var sums: [String: Double] = [:]
        var counts: [String: Int] = [:]
        for case let sample as HKQuantitySample in samples {
            let key = DayKey.key(for: sample.endDate, calendar: calendar)
            sums[key, default: 0] += sample.quantity.doubleValue(for: .degreeCelsius())
            counts[key, default: 0] += 1
        }
        var result: [String: Double] = [:]
        for (key, count) in counts where count > 0 {
            result[key] = (sums[key] ?? 0) / Double(count)
        }
        return result
    }

    // MARK: - 饮水 / 饮食读取与打卡写回

    private func quantityType(for kind: String) -> HKQuantityType {
        kind == SyncableCheckInKind.caffeine.rawValue
            ? HealthKitTypes.dietaryCaffeine
            : HealthKitTypes.dietaryWater
    }

    private func quantityUnit(for kind: String) -> HKUnit {
        kind == SyncableCheckInKind.caffeine.rawValue
            ? HealthKitTypes.milligram
            : HealthKitTypes.milliliter
    }

    /// 样本是否由本 App 回写（喝水 / 咖啡因 / 膳食）；读取外部量时必须排除。
    private func isSelfEchoSample(_ sample: HKQuantitySample, appBundleID: String?) -> Bool {
        let metadata = sample.metadata
        let waterOrigin = metadata?[WaterSyncMetadata.originKey] as? String
        let caffeineOrigin = metadata?[WaterSyncMetadata.caffeineOriginKey] as? String
        let mealOrigin = metadata?[WaterSyncMetadata.mealOriginKey] as? String
        let origin = WaterSyncMetadata.kind(from: waterOrigin) != nil ? waterOrigin
            : (WaterSyncMetadata.kind(from: caffeineOrigin) != nil ? caffeineOrigin : mealOrigin)
        return WaterSyncMetadata.isSelfEcho(
            origin: origin,
            sourceBundleID: sample.sourceRevision.source.bundleIdentifier,
            appBundleID: appBundleID
        )
    }

    /// 按日累计健康 App 的饮水与饮食指标。
    /// 水与咖啡因样本里带本 App 回写标记（或来源就是本 App）的会被跳过：
    /// 它们已经以 ActionCheckIn 的形式存在于本地，重复计入会让当日总量翻倍。
    private func nutritionByDay(
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: NutritionDay] {
        let appBundleID = Bundle.main.bundleIdentifier
        var result: [String: NutritionDay] = [:]
        for metric in NutritionMetric.allCases {
            let samples = try await samples(of: metric.type, start: start, end: end)
            for case let sample as HKQuantitySample in samples {
                // 本 App 回写的喝水 / 咖啡因 / 膳食样本都要排除：它们已在本地以打卡形式存在，
                // 重复计入会让当日营养量翻倍。
                if isSelfEchoSample(sample, appBundleID: appBundleID) { continue }
                let value = sample.quantity.doubleValue(for: metric.unit)
                // 一杯美式这类饮品会写入 0g 的碳蛋脂样本；0 值不参与聚合，
                // 否则会把「当天无饮食数据」误判成「0 摄入」并影响评分。
                guard value > 0 else { continue }
                let key = DayKey.key(for: sample.startDate, calendar: calendar)
                var day = result[key] ?? NutritionDay()
                metric.add(value, to: &day)
                result[key] = day
            }
        }
        return result
    }

    /// 查回本 App 写回 HealthKit 的某类样本（不限时间窗口，便于清理历史孤儿）。
    /// 没有同步标识的本 App 样本不参与对账，也不会被删除，避免误伤用户数据。
    private func appWrittenSamples(kind: String) async throws -> [HKQuantitySample] {
        let all = try await allSamples(of: quantityType(for: kind))
        let appBundleID = Bundle.main.bundleIdentifier
        return all.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample,
                  isSelfEchoSample(quantity, appBundleID: appBundleID),
                  WaterSyncMetadata.localID(
                      from: quantity.metadata?[HKMetadataKeySyncIdentifier] as? String,
                      kind: kind
                  ) != nil
            else { return nil }
            return quantity
        }
    }

    /// 一条打卡涉及的 HealthKit 类型：喝水只有主样本；咖啡因饮品带完整营养成分
    /// （能量 / 碳水 / 蛋白 / 脂肪 / 纤维 / 糖 / 钠）；
    /// 一顿饭写回 7 类膳食样本 + 水 + 咖啡因（饮食里匹配到的饮品要带出含水量与咖啡因）。
    private func relatedQuantityTypes(for kind: String) -> [HKQuantityType] {
        if kind == SyncableCheckInKind.caffeine.rawValue {
            return [HealthKitTypes.dietaryCaffeine] + HealthKitTypes.mealWriteTypes
        }
        if kind == "meal" {
            return HealthKitTypes.mealSampleTypes
        }
        return [quantityType(for: kind)]
    }

    /// 查回本 App 写回的全部相关样本（含营养附属样本），可按 syncID 过滤。
    /// 删除与重写时必须把同一 syncID 的主样本和营养样本一起处理，
    /// 否则会留下孤儿营养样本，或重写时重复写入碳蛋脂。
    private func allWrittenSamples(kind: String, syncID: String? = nil) async throws -> [HKQuantitySample] {
        let appBundleID = Bundle.main.bundleIdentifier
        var result: [HKQuantitySample] = []
        for type in relatedQuantityTypes(for: kind) {
            let all = try await allSamples(of: type)
            for case let sample as HKQuantitySample in all {
                guard isSelfEchoSample(sample, appBundleID: appBundleID) else { continue }
                let localID = WaterSyncMetadata.localID(
                    from: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                    kind: kind
                )
                guard let localID else { continue }
                if let syncID, localID != syncID { continue }
                result.append(sample)
            }
        }
        return result
    }

    private func remoteSamples(
        from samples: [HKQuantitySample],
        kind: String
    ) -> [WaterSyncSample] {
        samples.compactMap { sample in
            guard let id = WaterSyncMetadata.localID(
                from: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                kind: kind
            ) else { return nil }
            let version = (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue
                ?? WaterSyncMetadata.initialSyncVersion
            return WaterSyncSample(
                syncID: id,
                amountMl: sample.quantity.doubleValue(for: quantityUnit(for: kind)),
                date: sample.startDate,
                uuid: sample.uuid.uuidString,
                syncVersion: version,
                kind: kind
            )
        }
    }

    func canWriteCheckIn(kind: String) -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        // 咖啡因饮品一次保存 4 类样本，缺任何一类写权限整批都会失败。
        return relatedQuantityTypes(for: kind).allSatisfy {
            store.authorizationStatus(for: $0) == .sharingAuthorized
        }
    }

    /// 喝水写入权限（兼容旧入口）。
    func canWriteWater() -> Bool {
        canWriteCheckIn(kind: SyncableCheckInKind.water.rawValue)
    }

    /// 两类打卡的写入权限是否都已授予，设置页据此展示。
    func canWriteCheckIns() -> Bool {
        SyncableCheckInKind.allCases.allSatisfy { canWriteCheckIn(kind: $0.rawValue) }
    }

    /// 单条打卡即时写回：同一 syncID 已存在且值一致时不做任何事（幂等）。
    @discardableResult
    func saveCheckIn(_ record: WaterSyncRecord) async throws -> Bool {
        let kind = record.kind
        guard canWriteCheckIn(kind: kind) else { throw HealthKitError.writeAuthorizationRequired }
        let samples = try await appWrittenSamples(kind: kind).filter {
            WaterSyncMetadata.localID(
                from: $0.metadata?[HKMetadataKeySyncIdentifier] as? String,
                kind: kind
            ) == record.syncID
        }
        let remote = remoteSamples(from: samples, kind: kind)
        let related = try await allWrittenSamples(kind: kind, syncID: record.syncID)
        // 咖啡因饮品 = 主样本 + 7 类营养样本；喝水 / 手动输入只有主样本。
        let expectedCount = record.nutrition == nil
            ? 1
            : 1 + HealthKitTypes.mealWriteTypes.count
        if remote.count == 1,
           let existing = remote.first,
           WaterSyncReconciler.matches(existing, record),
           related.count == expectedCount {
            return false
        }
        try await deleteSamples(related, uuids: Set(related.map { $0.uuid.uuidString }))
        try await writeCheckInSamples([record], remote: remote, kind: kind)
        return true
    }

    /// 单条打卡被删除时，同步删掉 HealthKit 里对应的样本。
    func deleteCheckIn(syncID: String, kind: String) async throws {
        guard canWriteCheckIn(kind: kind) else { throw HealthKitError.writeAuthorizationRequired }
        let samples = try await allWrittenSamples(kind: kind, syncID: syncID)
        guard !samples.isEmpty else { return }
        try await deleteSamples(samples, uuids: Set(samples.map { $0.uuid.uuidString }))
    }

    /// 全量对账：补齐离线期间漏写的打卡、删除本地已删的孤儿样本、清理重复样本，
    /// 以及按本地值修复金额不一致的记录。先删后写，保证同一 syncID 不会残留两份。
    @discardableResult
    func reconcileCheckIns(
        localRecords: [WaterSyncRecord],
        kind: String
    ) async throws -> WaterSyncPlan {
        let samples = try await appWrittenSamples(kind: kind)
        let remote = remoteSamples(from: samples, kind: kind)
        let plan = WaterSyncReconciler.reconcile(local: localRecords, remote: remote)
        guard !plan.isEmpty else { return plan }
        guard canWriteCheckIn(kind: kind) else { throw HealthKitError.writeAuthorizationRequired }
        // 需要整体替换 / 清理的 syncID：本地已删的孤儿，以及金额变化要重写的记录。
        // 这些 ID 下的营养附属样本也必须一起删，否则重写后会残留旧碳蛋脂。
        let localIDs = Set(localRecords.map(\.syncID))
        let rewriteIDs = Set(plan.toSave.map(\.syncID))
        let orphanIDs = Set(remote.map(\.syncID)).subtracting(localIDs)
        let purgeIDs = rewriteIDs.union(orphanIDs)
        // 纯重复样本只删 plan 指定的那几条，保留 keeper。
        let duplicateUUIDs = Set(plan.toDelete.filter { !purgeIDs.contains($0.syncID) }.map(\.uuid))
        let allRelated = try await allWrittenSamples(kind: kind)
        let targets = allRelated.filter { sample in
            let localID = WaterSyncMetadata.localID(
                from: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                kind: kind
            )
            guard let localID else { return false }
            return purgeIDs.contains(localID) || duplicateUUIDs.contains(sample.uuid.uuidString)
        }
        try await deleteSamples(targets, uuids: Set(targets.map { $0.uuid.uuidString }))
        try await writeCheckInSamples(plan.toSave, remote: remote, kind: kind)
        return plan
    }

    @discardableResult
    func saveWaterCheckIn(_ record: WaterSyncRecord) async throws -> Bool {
        try await saveCheckIn(record)
    }

    func deleteWaterCheckIn(syncID: String) async throws {
        try await deleteCheckIn(syncID: syncID, kind: SyncableCheckInKind.water.rawValue)
    }

    @discardableResult
    func reconcileWater(localRecords: [WaterSyncRecord]) async throws -> WaterSyncPlan {
        try await reconcileCheckIns(
            localRecords: localRecords,
            kind: SyncableCheckInKind.water.rawValue
        )
    }

    @discardableResult
    func reconcileCaffeine(localRecords: [WaterSyncRecord]) async throws -> WaterSyncPlan {
        try await reconcileCheckIns(
            localRecords: localRecords,
            kind: SyncableCheckInKind.caffeine.rawValue
        )
    }

    // MARK: - 食物识别写回

    /// 膳食 7 类 + 水 + 咖啡因样本的写入权限是否都已授予（拒绝写入不影响只读同步）。
    func canWriteMeal() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return HealthKitTypes.mealSampleTypes.allSatisfy {
            store.authorizationStatus(for: $0) == .sharingAuthorized
        }
    }

    /// 单顿饭即时写回：同一 syncID 已存在且 9 项值一致时幂等跳过。
    /// 编辑饮食记录改了营养 / 水量 / 咖啡因 / 用餐时间时，会先删旧样本再写新值，
    /// 保证健康 App 里的数值与本机记录一致。
    @discardableResult
    /// 一顿饭实际要写的样本类型：只有存在「单独饮用的饮品」时才写水样本。
    /// 没有饮品时跳过水，避免为饭菜本身含水量在健康 App 里创建一条多余条目。
    private static func mealSampleTypes(for nutrition: IntakeNutrition) -> [HKQuantityType] {
        let types = HealthKitTypes.mealSampleTypes
        if nutrition.waterMl > 0 { return types }
        return types.filter { $0 != HealthKitTypes.dietaryWater }
    }

    func saveMeal(_ record: MealSyncRecord) async throws -> Bool {
        guard canWriteMeal() else { throw HealthKitError.writeAuthorizationRequired }
        let written = try await allWrittenSamples(kind: record.kind, syncID: record.syncID)
        let remote = remoteMealSamples(from: written)
        let expectedCount = Self.mealSampleTypes(for: record.nutrition).count
        if remote.count == 1,
           let existing = remote.first,
           MealSyncReconciler.matches(existing, record),
           written.count == expectedCount {
            return false
        }
        try await deleteSamples(written, uuids: Set(written.map { $0.uuid.uuidString }))
        try await writeMealSamples([record], remote: remote)
        return true
    }

    /// 单顿饭被删除时，同步删掉 HealthKit 里对应的 7 类样本。
    func deleteMeal(syncID: String) async throws {
        try await deleteCheckIn(syncID: syncID, kind: "meal")
    }

    // MARK: - 感受记录（心理状态）

    /// 本地感受记录写回健康 App 的载荷；同一天只保留一条，syncID 固定为 mood-日期。
    struct MoodSyncPayload: Sendable {
        var syncID: String
        var date: Date
        var valence: Double
        var note: String?
        var tags: [String]
    }

    func canWriteStateOfMind() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        return store.authorizationStatus(for: HealthKitTypes.stateOfMind) == .sharingAuthorized
    }

    /// 把一条感受记录写回健康 App 的「心理状态」；同一天重复保存时先删旧样本再写。
    @discardableResult
    func saveStateOfMind(_ record: MoodSyncPayload) async throws -> Bool {
        guard canWriteStateOfMind() else { throw HealthKitError.writeAuthorizationRequired }
        let samples = try await allSamples(of: HealthKitTypes.stateOfMind)
        let existing = samples.filter { ($0.metadata?["healthySyncID"] as? String) == record.syncID }
        if !existing.isEmpty {
            try await deleteObjects(existing)
        }
        var metadata: [String: Any] = [
            "healthySyncID": record.syncID,
            HKMetadataKeyExternalUUID: record.syncID,
        ]
        if let note = record.note, !note.isEmpty {
            metadata["healthyNote"] = note
        }
        let sample = HKStateOfMind(
            date: record.date,
            kind: .momentaryEmotion,
            valence: max(-1, min(1, record.valence)),
            labels: Self.labels(for: record.valence),
            associations: Self.associations(for: record.tags),
            metadata: metadata
        )
        try await store.save(sample)
        return true
    }

    /// 心情标签：在健康 App 里显示为具体「感受」词条。
    private static func labels(for valence: Double) -> [HKStateOfMind.Label] {
        switch valence {
        case ..<(-0.6): return [.sad]
        case ..<(-0.2): return [.discouraged]
        case ..<0.2: return [.calm]
        case ..<0.6: return [.content]
        default: return [.happy]
        }
    }

    /// 本地标签是生活场景，对应健康 App 的「关联」；「压力」没有对应项，忽略即可。
    private static func associations(for tags: [String]) -> [HKStateOfMind.Association] {
        let map: [String: HKStateOfMind.Association] = [
            "工作": .work, "学习": .education, "运动": .fitness,
            "社交": .friends, "家庭": .family, "放松": .selfCare,
        ]
        return tags.compactMap { map[$0] }
    }

    /// 删除任意 HKSample：心理状态样本不是数量样本，不能复用 deleteSamples。
    private func deleteObjects(_ objects: [HKSample]) async throws {
        guard !objects.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(objects) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: HealthKitError.queryFailed("删除感受记录失败"))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 全量膳食对账：补齐离线漏写的饭、删除本地已删的孤儿、清理重复、按本地值修复变化。
    /// 先删后写，保证同一 syncID 不会残留两份样本。
    @discardableResult
    func reconcileMeals(localRecords: [MealSyncRecord]) async throws -> MealSyncPlan {
        let written = try await allWrittenSamples(kind: "meal")
        let remote = remoteMealSamples(from: written)
        let plan = MealSyncReconciler.reconcile(local: localRecords, remote: remote)
        guard !plan.isEmpty else { return plan }
        guard canWriteMeal() else { throw HealthKitError.writeAuthorizationRequired }
        // 需要整体替换 / 清理的 syncID：本地已删的孤儿，以及值变化要重写的记录。
        let localIDs = Set(localRecords.map(\.syncID))
        let rewriteIDs = Set(plan.toSave.map(\.syncID))
        let orphanIDs = Set(remote.map(\.syncID)).subtracting(localIDs)
        let purgeIDs = rewriteIDs.union(orphanIDs)
        let deleteUUIDs = Set(plan.toDelete.flatMap(\.uuids))
        let targets = written.filter { sample in
            let localID = WaterSyncMetadata.localID(
                from: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                kind: "meal"
            )
            guard let localID else { return false }
            return purgeIDs.contains(localID) && deleteUUIDs.contains(sample.uuid.uuidString)
        }
        try await deleteSamples(targets, uuids: Set(targets.map { $0.uuid.uuidString }))
        try await writeMealSamples(plan.toSave, remote: remote)
        return plan
    }

    /// 把 9 类样本（7 膳食 + 水 + 咖啡因）按 syncID 聚合为 MealSyncSample（同一组共享 syncID / 来源）。
    private func remoteMealSamples(from samples: [HKQuantitySample]) -> [MealSyncSample] {
        var bySyncID: [String: [HKQuantitySample]] = [:]
        for sample in samples {
            guard let id = WaterSyncMetadata.localID(
                from: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                kind: "meal"
            ) else { continue }
            bySyncID[id, default: []].append(sample)
        }
        var result: [MealSyncSample] = []
        for (syncID, group) in bySyncID {
            var nutrition = IntakeNutrition()
            var date = group.first?.startDate ?? .now
            var version = WaterSyncMetadata.initialSyncVersion
            var uuids: [String] = []
            for sample in group {
                uuids.append(sample.uuid.uuidString)
                let value = sample.quantity.doubleValue(for: HealthKitTypes.unit(for: sample.quantityType))
                switch sample.quantityType {
                case HealthKitTypes.dietaryEnergy: nutrition.energyKcal = value
                case HealthKitTypes.dietaryCarbs: nutrition.carbsG = value
                case HealthKitTypes.dietaryProtein: nutrition.proteinG = value
                case HealthKitTypes.dietaryFat: nutrition.fatG = value
                case HealthKitTypes.dietaryFiber: nutrition.fiberG = value
                case HealthKitTypes.dietarySugar: nutrition.sugarG = value
                case HealthKitTypes.dietarySodium: nutrition.sodiumMg = value
                case HealthKitTypes.dietaryWater: nutrition.waterMl = value
                case HealthKitTypes.dietaryCaffeine: nutrition.caffeineMg = value
                default: break
                }
                if sample.quantityType == HealthKitTypes.dietaryEnergy {
                    date = sample.startDate
                }
                if let v = (sample.metadata?[HKMetadataKeySyncVersion] as? NSNumber)?.intValue {
                    version = max(version, v)
                }
            }
            result.append(MealSyncSample(
                syncID: syncID,
                uuids: uuids,
                date: date,
                nutrition: nutrition,
                syncVersion: version
            ))
        }
        return result
    }

    /// 7 类膳食样本各自的取值：能量 / 碳水 / 蛋白 / 脂肪 / 纤维 / 糖 / 钠。
    /// 饮品与一顿饭共用同一口径，避免两处写回字段不一致。
    /// 9 类膳食样本各自的取值：能量 / 碳水 / 蛋白 / 脂肪 / 纤维 / 糖 / 钠 / 水 / 咖啡因。
    /// 饮品与一顿饭共用同一口径，避免两处写回字段不一致。
    private static func nutritionValue(for type: HKQuantityType, in nutrition: IntakeNutrition) -> Double {
        switch type {
        case HealthKitTypes.dietaryEnergy: return nutrition.energyKcal
        case HealthKitTypes.dietaryCarbs: return nutrition.carbsG
        case HealthKitTypes.dietaryProtein: return nutrition.proteinG
        case HealthKitTypes.dietaryFat: return nutrition.fatG
        case HealthKitTypes.dietaryFiber: return nutrition.fiberG
        case HealthKitTypes.dietarySugar: return nutrition.sugarG
        case HealthKitTypes.dietarySodium: return nutrition.sodiumMg
        case HealthKitTypes.dietaryWater: return nutrition.waterMl
        case HealthKitTypes.dietaryCaffeine: return nutrition.caffeineMg
        default: return 0
        }
    }

    private func writeMealSamples(
        _ records: [MealSyncRecord],
        remote: [MealSyncSample]
    ) async throws {
        guard !records.isEmpty else { return }
        let versions = Dictionary(grouping: remote, by: \.syncID)
            .mapValues { MealSyncReconciler.nextSyncVersion(after: $0) }
        let objects: [HKQuantitySample] = records.flatMap { record -> [HKQuantitySample] in
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: WaterSyncMetadata.syncIdentifier(
                    for: record.syncID,
                    kind: record.kind
                ),
                HKMetadataKeySyncVersion: NSNumber(
                    value: versions[record.syncID] ?? WaterSyncMetadata.initialSyncVersion
                ),
                WaterSyncMetadata.mealOriginKey: WaterSyncMetadata.mealOriginValue,
            ]
            .merging(record.note.map { [WaterSyncMetadata.mealNoteKey: $0] } ?? [:]) { $1 }
            func make(_ type: HKQuantityType, _ value: Double) -> HKQuantitySample {
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: HealthKitTypes.unit(for: type), doubleValue: max(0, value)),
                    start: record.date,
                    end: record.date,
                    metadata: metadata
                )
            }
            return Self.mealSampleTypes(for: record.nutrition).map { type in
                make(type, Self.nutritionValue(for: type, in: record.nutrition))
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(objects, withCompletion: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: HealthKitError.queryFailed("写入膳食记录失败"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func writeCheckInSamples(
        _ records: [WaterSyncRecord],
        remote: [WaterSyncSample],
        kind: String
    ) async throws {
        guard !records.isEmpty else { return }
        let versions = Dictionary(grouping: remote, by: \.syncID)
            .mapValues { WaterSyncReconciler.nextSyncVersion(after: $0) }
        let objects: [HKQuantitySample] = records.flatMap { record -> [HKQuantitySample] in
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: WaterSyncMetadata.syncIdentifier(
                    for: record.syncID,
                    kind: kind
                ),
                HKMetadataKeySyncVersion: NSNumber(
                    value: versions[record.syncID] ?? WaterSyncMetadata.initialSyncVersion
                ),
                WaterSyncMetadata.originKey(for: kind): WaterSyncMetadata.originValue(for: kind),
            ]
            func make(_ type: HKQuantityType, _ unit: HKUnit, _ value: Double) -> HKQuantitySample {
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: unit, doubleValue: max(0, value)),
                    start: record.date,
                    end: record.date,
                    metadata: metadata
                )
            }
            // 主样本与营养样本共用同一 syncID / version / 来源标记，删除时按 syncID 一起清理。
            var samples = [make(quantityType(for: kind), quantityUnit(for: kind), record.amountMl)]
            if kind == SyncableCheckInKind.caffeine.rawValue, let nutrition = record.nutrition {
                // 饮品和一顿饭一样写回 7 类膳食样本，健康 App 里能看到完整营养成分。
                samples.append(contentsOf: HealthKitTypes.mealWriteTypes.map { type in
                    make(type, HealthKitTypes.unit(for: type), Self.nutritionValue(for: type, in: nutrition))
                })
            }
            return samples
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(objects, withCompletion: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: HealthKitError.queryFailed("写入打卡记录失败"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func deleteSamples(
        _ samples: [HKQuantitySample],
        uuids: Set<String>
    ) async throws {
        let targets = samples.filter { uuids.contains($0.uuid.uuidString) }
        guard !targets.isEmpty else { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.delete(targets, withCompletion: { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: HealthKitError.queryFailed("删除打卡记录失败"))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func allSamples(of type: HKSampleType) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: nil,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    /// 每类型一次全区间 HKSampleQuery，代码内按睡眠窗口聚合，避免逐天×逐类型查询。
    private func sleepWindowStatistics(
        windows: [String: DateInterval],
        start: Date,
        end: Date
    ) async throws -> [String: SleepWindowStats] {
        guard !windows.isEmpty else { return [:] }
        let hrSamples = try await samples(of: HealthKitTypes.heartRate, start: start, end: end)
        let hrvSamples = try await samples(of: HealthKitTypes.hrv, start: start, end: end)
        let respSamples = try await samples(of: HealthKitTypes.respiratoryRate, start: start, end: end)
        let spo2Samples = try await samples(of: HealthKitTypes.oxygenSaturation, start: start, end: end)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        func timed(_ samples: [HKSample], unit: HKUnit) -> [TimedValue] {
            samples.compactMap { sample in
                guard let quantity = (sample as? HKQuantitySample)?.quantity else { return nil }
                return TimedValue(date: sample.endDate, value: quantity.doubleValue(for: unit))
            }
        }
        // HKUnit.percent() 对 oxygenSaturation 返回 0–1 比例，日均值链路已换算成
        // 0–100 百分数；睡眠窗口均值走同一口径，否则会出现「1%」和荒谬的 σ 偏差。
        let spo2Values = timed(spo2Samples, unit: .percent()).compactMap { sample -> TimedValue? in
            UnitConversion.percent(fromFraction: sample.value).map {
                TimedValue(date: sample.date, value: $0)
            }
        }
        return SleepAnalysisEngine.aggregate(
            heartRate: timed(hrSamples, unit: bpm),
            hrv: timed(hrvSamples, unit: .secondUnit(with: .milli)),
            respiratory: timed(respSamples, unit: bpm),
            spo2: spo2Values,
            windows: windows
        )
    }

    private func samples(of type: HKSampleType, start: Date, end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            store.execute(query)
        }
    }

    private func latestHRVSample() async throws -> (value: Double, date: Date)? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HealthKitTypes.hrv,
                predicate: nil,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }
                let value = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                continuation.resume(returning: (value, sample.endDate))
            }
            store.execute(query)
        }
    }

    func fetchCurrentSignals(now: Date = .now) async throws -> CurrentSignals {
        let perfToken = PerformanceTrace.shared.begin("HealthKit · 此刻信号", category: .api)
        defer { PerformanceTrace.shared.end(perfToken) }
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let heart = try await latestSample(
            of: HealthKitTypes.heartRate,
            start: now.addingTimeInterval(-6 * 3600),
            end: now
        ) as? HKQuantitySample
        let hrv = try await latestSample(
            of: HealthKitTypes.hrv,
            start: now.addingTimeInterval(-24 * 3600),
            end: now
        ) as? HKQuantitySample
        let workout = try await latestSample(
            of: HKObjectType.workoutType(),
            start: now.addingTimeInterval(-2 * 3600),
            end: now
        ) as? HKWorkout

        return CurrentSignals(
            heartRate: heart?.quantity.doubleValue(for: .count().unitDivided(by: .minute())),
            heartRateAt: heart?.endDate,
            hrv: hrv?.quantity.doubleValue(for: .secondUnit(with: .milli)),
            hrvAt: hrv?.endDate,
            lastWorkoutEndAt: workout?.endDate
        )
    }

    private func latestSample(of type: HKSampleType, start: Date, end: Date) async throws -> HKSample? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                } else {
                    continuation.resume(returning: samples?.first)
                }
            }
            store.execute(query)
        }
    }

    func fetchIntradaySignals(now: Date = .now, calendar: Calendar = .current) async throws -> IntradaySignals {
        let perfToken = PerformanceTrace.shared.begin("HealthKit · 日内压力信号", category: .api)
        defer { PerformanceTrace.shared.end(perfToken) }
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let start = calendar.startOfDay(for: now)
        var pointMap: [Date: (sdnn: Double?, rmssd: Double?)] = [:]

        let sdnnSamples = try await samples(of: HealthKitTypes.hrv, start: start, end: now)
        for case let sample as HKQuantitySample in sdnnSamples {
            let key = minuteBucket(sample.endDate)
            var entry = pointMap[key] ?? (nil, nil)
            entry.sdnn = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
            pointMap[key] = entry
        }

        if #available(iOS 27.0, *), let rmssdType = HealthKitTypes.hrvRMSSD {
            let rmssdSamples = try await samples(of: rmssdType, start: start, end: now)
            for case let sample as HKQuantitySample in rmssdSamples {
                let key = minuteBucket(sample.endDate)
                var entry = pointMap[key] ?? (nil, nil)
                entry.rmssd = sample.quantity.doubleValue(for: .secondUnit(with: .milli))
                pointMap[key] = entry
            }
        }

        let hrvPoints = pointMap
            .map { HRVSamplePoint(date: $0.key, sdnn: $0.value.sdnn, rmssd: $0.value.rmssd) }
            .sorted { $0.date < $1.date }

        let hourly = try await heartRateBuckets(start: start, end: now, minutes: ScoringConfig().intradayBucketMinutes)
        let workoutSamples = try await samples(of: HKObjectType.workoutType(), start: start, end: now)
        let workouts = workoutSamples
            .compactMap { $0 as? HKWorkout }
            .map { WorkoutInterval(start: $0.startDate, end: $0.endDate) }

        return IntradaySignals(hrvPoints: hrvPoints, heartRateBuckets: hourly, workouts: workouts)
    }

    /// 读取当天健康 App 里全部饮水 / 咖啡因样本（逐条，不聚合）。
    /// 与 nutritionByDay 的差别：这里不排除本 App 回写的样本，也不排除任何来源，
    /// 打卡页要展示「健康 App 里这一天的完整记录」；去重由 IntakeEntryMerger 负责。
    /// 未授权时 HKSampleQuery 返回空集合，调用方会自动退回只展示本 App 打卡。
    func fetchIntakeEntries(
        kind: String,
        day: Date,
        calendar: Calendar = .current
    ) async throws -> [IntakeEntry] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        return try await fetchIntakeEntries(kind: kind, from: start, to: end)
    }

    /// 区间版：一次查询覆盖多天，供详情页 / 洞察页批量取数，避免逐日发 60 次请求。
    /// 口径与单日版完全一致（不排除本 App 回写样本，由 IntakeEntryMerger 去重）。
    func fetchIntakeEntries(
        kind: String,
        from start: Date,
        to end: Date
    ) async throws -> [IntakeEntry] {
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let samples = try await samples(of: quantityType(for: kind), start: start, end: end)
        let appBundleID = Bundle.main.bundleIdentifier
        return samples.compactMap { sample -> IntakeEntry? in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            let syncID = WaterSyncMetadata.localID(
                from: quantity.metadata?[HKMetadataKeySyncIdentifier] as? String,
                kind: kind
            )
            let source = quantity.sourceRevision.source
            return IntakeEntry(
                id: "hk-\(quantity.uuid.uuidString)",
                date: quantity.startDate,
                amount: quantity.quantity.doubleValue(for: quantityUnit(for: kind)),
                origin: .healthKit(
                    sourceName: source.name.isEmpty ? "健康 App" : source.name,
                    isOwnApp: isSelfEchoSample(quantity, appBundleID: appBundleID)
                ),
                syncID: syncID,
                isSyncedToHealthKit: true
            )
        }
    }

    /// 轻量刷新：只读取近几天的饮水 / 饮食，供 HealthKit 数据变化观察回调使用，
    /// 避免每次外部改动都跑一遍睡眠、训练、HRV 等全量统计查询。
    func fetchNutrition(
        days: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) async throws -> [String: NutritionDay] {
        let perfToken = PerformanceTrace.shared.begin(
            "HealthKit · 营养摄入 \(days) 天", category: .api
        )
        defer { PerformanceTrace.shared.end(perfToken) }
        guard HKHealthStore.isHealthDataAvailable() else { throw HealthKitError.unavailable }
        let start = calendar.startOfDay(for: DayKey.addingDays(-(days - 1), to: now, calendar: calendar))
        return try await nutritionByDay(start: start, end: now, calendar: calendar)
    }

    /// 前台观察喝水数据变化（健康 App 手动录入 / 第三方 App 写入）。
    /// 不注册后台投递，因此只在 App 运行期间生效；回调里必须调用 completionHandler，
    /// 否则系统不会再投递后续更新。
    func waterChangeStream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        func makeQuery(_ type: HKQuantityType) -> HKObserverQuery {
            HKObserverQuery(sampleType: type, predicate: nil) { _, completionHandler, error in
                if error == nil {
                    continuation.yield()
                }
                completionHandler()
            }
        }
        // 喝水与咖啡因任一侧变化都触发轻量同步；两个 query 都需要强引用持有。
        let waterQuery = makeQuery(HealthKitTypes.dietaryWater)
        let caffeineQuery = makeQuery(HealthKitTypes.dietaryCaffeine)
        waterObserverQuery = waterQuery
        caffeineObserverQuery = caffeineQuery
        store.execute(waterQuery)
        store.execute(caffeineQuery)
        return stream
    }

    func fetchCharacteristics(now: Date = .now, calendar: Calendar = .current) -> HealthCharacteristics {
        var birthDate: Date?
        var notices: [String] = []
        func note(_ text: String) {
            if !notices.contains(text) { notices.append(text) }
        }
        if let cached = UserDefaults.standard.object(forKey: Self.dobCacheKey) as? TimeInterval, cached > 0 {
            birthDate = Date(timeIntervalSince1970: cached)
        } else {
            do {
                let components = try store.dateOfBirthComponents()
                if let date = calendar.date(from: components) {
                    birthDate = date
                    UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.dobCacheKey)
                } else {
                    note(Self.dobHint)
                }
            } catch {
                if Self.isNoDataError(error) {
                    note(Self.dobHint)
                } else if HealthKitTypes.isAuthorizationNotDetermined(error) {
                    note(Self.authHint)
                } else {
                    note("读取出生年份失败：\(error.localizedDescription)")
                }
            }
        }
        var age: Double?
        if let birthDate {
            let days = calendar.dateComponents([.day], from: birthDate, to: now).day ?? 0
            if days > 0 { age = Double(days) / 365.25 }
        }
        var male: Bool?
        do {
            switch try store.biologicalSex().biologicalSex {
            case .male: male = true
            case .female: male = false
            case .notSet: note(Self.sexHint)
            @unknown default: break
            }
        } catch {
            if Self.isNoDataError(error) {
                note(Self.sexHint)
            } else if HealthKitTypes.isAuthorizationNotDetermined(error) {
                note(Self.authHint)
            }
            // 其他失败：VO2max 调整项自动跳过，不额外提示
        }
        return HealthCharacteristics(
            birthDate: birthDate,
            chronologicalAge: age,
            isMale: male,
            notice: notices.isEmpty ? nil : notices.joined(separator: " ")
        )
    }

    /// 特征类型来自健康 App 的个人资料；本 App 需先声明读取，但系统不会为此弹授权界面。
    static let dobHint = "健康档案里还没有出生年份：请在健康 App 点右上角头像 → 健康档案 → 填写出生日期，或在本 App「设置 → 基本资料」直接填写（仅存本机）。"
    static let sexHint = "健康档案里还没有性别，补填后 VO2max 调整项才会参与。"
    static let authHint = "出生年份与性别的读取声明还未完成，重新进入本页或重启 App 即可自动补齐（不会弹授权界面）；也可在「设置 → 基本资料」直接填写。"

    static func clearCharacteristicsCache(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: dobCacheKey)
    }

    private static func isNoDataError(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain && nsError.code == HKError.errorNoData.rawValue
    }

    private static let dobCacheKey = "healthy.characteristics.dateOfBirth"

    private func minuteBucket(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded() * 60)
    }

    private func heartRateBuckets(start: Date, end: Date, minutes: Int) async throws -> [HeartRateBucket] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
            let query = HKStatisticsCollectionQuery(
                quantityType: HealthKitTypes.heartRate,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: start,
                intervalComponents: DateComponents(minute: minutes)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: HealthKitError.queryFailed(error.localizedDescription))
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var points: [HeartRateBucket] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let quantity = statistics.averageQuantity() else { return }
                    points.append(HeartRateBucket(
                        start: statistics.startDate,
                        minutes: minutes,
                        average: quantity.doubleValue(for: .count().unitDivided(by: .minute()))
                    ))
                }
                continuation.resume(returning: points)
            }
            store.execute(query)
        }
    }
}
