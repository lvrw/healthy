import Foundation

enum ScoreSupport {
    /// 判定当天各数据源是否有可用读数。
    /// - Parameters:
    ///   - today: 当天快照。
    ///   - history: 今天之前的历史快照；体能身体里的 VO2max、体重等属于稀疏读数，
    ///     允许取近 28 天最近一次记录，与评分分量的取值窗口保持一致。
    static func availableSources(
        _ today: DailySnapshot,
        history: [DailySnapshot]
    ) -> (count: Int, missing: [MetricSource]) {
        var missing: [MetricSource] = []
        if MetricSanitizer.value(today.sleepTotalH, in: MetricRange.sleepHours) == nil
            && MetricSanitizer.value(today.sleepMidpointMinutes, in: MetricRange.sleepMidpointMinutes) == nil {
            missing.append(.sleep)
        }
        if MetricSanitizer.value(today.hrvSDNN, in: MetricRange.hrv) == nil {
            missing.append(.hrv)
        }
        if MetricSanitizer.value(today.restingHR, in: MetricRange.restingHR) == nil {
            missing.append(.restingHR)
        }
        let hasActivity = MetricSanitizer.value(today.steps, in: MetricRange.steps) != nil
            || MetricSanitizer.value(today.activeEnergy, in: MetricRange.activeEnergy) != nil
            || MetricSanitizer.value(today.distanceWalkingKm, in: MetricRange.distanceKm) != nil
            || MetricSanitizer.value(today.flightsClimbed, in: MetricRange.flightsClimbed) != nil
        if !hasActivity {
            missing.append(.activity)
        }
        let hasVitals = MetricSanitizer.value(today.respiratoryRate, in: MetricRange.respiratoryRate) != nil
            || MetricSanitizer.value(today.spo2, in: MetricRange.spo2) != nil
            || MetricSanitizer.value(today.wristTempC, in: MetricRange.wristTemp) != nil
            || MetricSanitizer.value(today.systolicBP, in: MetricRange.systolicBP) != nil
            || MetricSanitizer.value(today.diastolicBP, in: MetricRange.diastolicBP) != nil
            || MetricSanitizer.value(today.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) != nil
        if !hasVitals {
            missing.append(.vitals)
        }
        let hasCircadian = MetricSanitizer.value(today.daylightMinutes, in: MetricRange.daylightMinutes) != nil
            || MetricSanitizer.value(today.mindfulMinutes, in: MetricRange.mindfulMinutes) != nil
            || MetricSanitizer.value(today.stateOfMindValence, in: MetricRange.stateOfMindValence) != nil
            || MetricSanitizer.value(today.sleepMidpointMinutes, in: MetricRange.sleepMidpointMinutes) != nil
        if !hasCircadian {
            missing.append(.circadian)
        }
        let hasFitnessBody = todayHasFitnessBody(today)
            || history.contains { snapshot in
                snapshot.date >= DayKey.addingDays(-28, to: DayKey.startOfDay(today.date))
                    && todayHasFitnessBody(snapshot)
            }
        if !hasFitnessBody {
            missing.append(.fitnessBody)
        }
        // 饮水取两侧合并后的总量；只有健康 App 同步的饮食记录也算有数据源。
        if !NutritionValues.from(today).hasData {
            missing.append(.nutrition)
        }
        return (MetricSource.allCases.count - missing.count, missing)
    }

    /// 合并「系统判定数据不全」与「用户手动标记不全」，得到当天评分的跳过集合。
    /// - Parameters:
    ///   - today: 当天快照。
    ///   - history: 今天之前的历史快照，供稀疏指标做近 28 天兜底。
    ///   - manualIncomplete: 用户手动标记为不全的数据源。
    static func exclusions(
        today: DailySnapshot,
        history: [DailySnapshot],
        manualIncomplete: Set<MetricSource>
    ) -> ScoreExclusions {
        ScoreExclusions(
            autoMissing: Set(availableSources(today, history: history).missing),
            manualMarked: manualIncomplete
        )
    }

    /// 「体能身体」是否有可用读数：VO2max、步行速度 / 稳定性，或体重 / 体脂 / 瘦体重任一。
    private static func todayHasFitnessBody(_ snapshot: DailySnapshot) -> Bool {
        MetricSanitizer.value(snapshot.vo2Max, in: MetricRange.vo2Max) != nil
            || MetricSanitizer.value(snapshot.walkingSpeedMps, in: MetricRange.walkingSpeed) != nil
            || MetricSanitizer.value(snapshot.walkingSteadinessPct, in: MetricRange.walkingSteadinessPct) != nil
            || MetricSanitizer.value(snapshot.bodyMassKg, in: MetricRange.bodyMassKg) != nil
            || MetricSanitizer.value(snapshot.bodyFatPct, in: MetricRange.bodyFatPct) != nil
            || MetricSanitizer.value(snapshot.leanBodyMassKg, in: MetricRange.leanBodyMassKg) != nil
    }

    static func confidence(baselineDays: Int, completeness: Int, config: ScoringConfig) -> ScoreConfidence {
        if baselineDays < config.minConfidenceDays { return .insufficient }
        if baselineDays < config.minBaselineDays || completeness < config.minCompletenessForFull {
            return .low
        }
        return .full
    }

    static func weightedAverage(_ parts: [(weight: Double, score: Double?)]) -> Double? {
        let usable = parts.compactMap { part in part.score.map { (part.weight, $0) } }
        let totalWeight = usable.reduce(0) { $0 + $1.0 }
        guard totalWeight > 0 else { return nil }
        return usable.reduce(0) { $0 + $1.0 * $1.1 } / totalWeight
    }

    static func clampZ(_ value: Double, _ limit: Double) -> Double {
        max(-limit, min(limit, value))
    }

    static func clampScore(_ value: Double) -> Double {
        max(0, min(100, value))
    }

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count >= 2 else { return nil }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return sqrt(variance)
    }

    static func recentValues(
        windowDays: Int,
        history: [DailySnapshot],
        today: DailySnapshot,
        calendar: Calendar,
        extract: (DailySnapshot) -> Double?
    ) -> [Double] {
        let todayStart = calendar.startOfDay(for: today.date)
        let start = DayKey.addingDays(-(windowDays - 1), to: todayStart, calendar: calendar)
        var values: [Double] = []
        if let value = extract(today) {
            values.append(value)
        }
        for snapshot in history {
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= start, day < todayStart else { continue }
            if let value = extract(snapshot) {
                values.append(value)
            }
        }
        return values
    }

    static func sleepMidpointSD(
        history: [DailySnapshot],
        today: DailySnapshot,
        config: ScoringConfig,
        calendar: Calendar
    ) -> Double? {
        let values = recentValues(
            windowDays: 7,
            history: history,
            today: today,
            calendar: calendar
        ) { snapshot in
            MetricSanitizer.value(snapshot.sleepMidpointMinutes, in: MetricRange.sleepMidpointMinutes)
        }
        guard values.count >= config.minSparseBaselineDays else { return nil }
        return standardDeviation(values)
    }

    /// HealthKit 的 oxygenSaturation 用 HKUnit.percent() 读出来是 0–1 的比例，
    /// 而 App 内所有血氧字段统一存 0–100 的百分数。历史落库数据可能仍是比例，
    /// 展示 / 基线计算前统一走这里归一化。
    static func spo2Percent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value < 2 ? value * 100 : value
    }
}

/// 当日累计型指标的「时间上下文」。
///
/// 饮水、饮食、步数、运动这些量只在清醒时段累积，日照还额外受日光时段限制；
/// 睡眠期间它们根本不可能增长，因此不能按「0–24 点过去了百分之多少」折算。
struct DayProgressContext: Sendable, Equatable {
    /// 清醒窗口（起床 → 就寝）内已过去的比例，0–1。
    var activity: Double
    /// 日光窗口内已过去的比例，0–1；日照专用。
    var daylight: Double
    /// 这一天是否尚未结束（已就寝或历史日期为 false）。
    var isPartialDay: Bool
    /// 供 UI / 智能评分说明使用的窗口描述。
    var windowText: String
    /// 完整日（历史回算、单元测试默认口径）。
    static let complete = DayProgressContext(
        activity: 1,
        daylight: 1,
        isPartialDay: false,
        windowText: "完整日"
    )
}

/// 计算当日进度：历史日期一律完整日 1.0；只有今天按真实睡眠/清醒窗口折算。
///
/// 清醒窗口起点取今早的实际醒来时间（sleepWakeAt），终点用近 7 天平均就寝时刻
/// 推算今晚入睡时间；缺少睡眠数据时退化为 07:00–23:00 的经验窗口。
/// 日光窗口暂用 08:00–18:00 经验值（TODO: 接入日出日落后再按季节动态计算）。
enum DayProgress {
    /// 进度太低时不评估累计型指标：样本太少，折算会放大噪声。
    static let evaluationThreshold = 0.15
    /// 糖 / 钠 / 咖啡因这类「全天上限」至少过半程后才纳入。
    static let ceilingThreshold = 0.5
    static let defaultWakeMinute = 7 * 60
    static let defaultBedMinute = 23 * 60
    static let daylightStartMinute = 8 * 60
    static let daylightEndMinute = 18 * 60

    static func context(
        for day: Date,
        today: DailySnapshot,
        history: [DailySnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> DayProgressContext {
        guard calendar.isDate(day, inSameDayAs: now) else { return .complete }

        let nowMinute = minuteOfDay(now, calendar: calendar)
        // 调用方给的历史可能是正序也可能是倒序，统一按日期取最近 7 天。
        let recentHistory = Array(
            history
                .filter { $0.date < calendar.startOfDay(for: now) }
                .sorted { $0.date > $1.date }
                .prefix(7)
        )
        let wakeMinute = wakeTime(today: today, history: recentHistory, now: now, calendar: calendar)
        let bedMinute = bedTime(history: recentHistory, wakeMinute: wakeMinute)
        let activity = min(1, max(0, Double(nowMinute - wakeMinute) / Double(bedMinute - wakeMinute)))
        // 日光窗口结束之后不再累积，避免夜里用「清醒时间」高估应晒到的太阳。
        let cappedMinute = min(nowMinute, daylightEndMinute)
        let daylight = min(1, max(0, Double(cappedMinute - daylightStartMinute)
                                  / Double(daylightEndMinute - daylightStartMinute)))
        let bedClockMinute = bedMinute % 1_440
        let text = String(
            format: "清醒窗口 %02d:%02d–%02d:%02d（当前进度 %.0f%%）；日光窗口 %02d:%02d–%02d:%02d（当前进度 %.0f%%）",
            wakeMinute / 60, wakeMinute % 60, bedClockMinute / 60, bedClockMinute % 60, activity * 100,
            daylightStartMinute / 60, daylightStartMinute % 60,
            daylightEndMinute / 60, daylightEndMinute % 60, daylight * 100
        )
        return DayProgressContext(
            activity: activity,
            daylight: daylight,
            isPartialDay: activity < 1,
            windowText: text
        )
    }

    /// 按进度缩放后的阶段目标；进度不足（含仍在睡眠中）时返回 nil，调用方跳过该子项。
    static func stagedTarget(_ fullDayTarget: Double, progress: Double) -> Double? {
        guard fullDayTarget > 0, progress >= evaluationThreshold else { return nil }
        return fullDayTarget * min(1, progress)
    }

    /// 把「尚未过完的今天」的累计值折算为全天预估；睡眠中 / 进度过低时返回 nil，
    /// 由调用方直接排除今天的这项数据（而不是当成 0 参与平均）。
    /// ceiling 用于限制外推倍数带来的异常值。
    static func projected(_ value: Double?, progress: Double, ceiling: Double) -> Double? {
        guard let value, value.isFinite, progress >= evaluationThreshold else { return nil }
        return min(max(0, value / min(1, progress)), ceiling)
    }

    // MARK: - 窗口推算

    private static func minuteOfDay(_ date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// 优先用今早真实醒来时间；缺失时取近 7 天醒来时刻均值；仍缺失用 07:00。
    private static func wakeTime(
        today: DailySnapshot,
        history: [DailySnapshot],
        now: Date,
        calendar: Calendar
    ) -> Int {
        if let wake = today.sleepWakeAt,
           calendar.isDate(wake, inSameDayAs: now),
           minuteOfDay(wake, calendar: calendar) < 12 * 60 {
            return minuteOfDay(wake, calendar: calendar)
        }
        let recent = history.compactMap { snapshot -> Int? in
            guard let wake = snapshot.sleepWakeAt else { return nil }
            let minute = minuteOfDay(wake, calendar: calendar)
            return minute < 12 * 60 ? minute : nil
        }
        guard let average = ScoreSupport.mean(recent.map(Double.init)), average > 0 else {
            return defaultWakeMinute
        }
        return Int(average.rounded())
    }

    /// 今晚就寝时刻：用近 7 天 sleepBedtimeMinutes（相对各日 00:00，前一夜为负）推算。
    /// 例如均值 −60 表示前一天 23:00 入睡，对应今晚 23:00（1440 − 60 = 1380 分钟）。
    private static func bedTime(history: [DailySnapshot], wakeMinute: Int) -> Int {
        let recent = history.compactMap { snapshot -> Double? in
            MetricSanitizer.value(snapshot.sleepBedtimeMinutes, in: MetricRange.sleepBedtimeMinutes)
        }
        let estimated = recent.isEmpty
            ? Double(defaultBedMinute)
            : 1_440 + (ScoreSupport.mean(recent) ?? -60)
        // 至少留出 6 小时清醒窗口，避免异常作息把进度压成 0 或无限放大。
        let lower = Double(wakeMinute + 360)
        let upper = Double(wakeMinute + 1_080)
        return Int(min(upper, max(lower, estimated)).rounded())
    }
}

/// 完成度展示换算：DailyScore.completeness 存的是「有效数据源类别数」（0–8），
/// 不是百分数。UI 里直接拼 % 会让 8 类齐全的一天也只显示 8%。
enum CompletenessPresentation {
    static func percent(sourceCount: Int, total: Int = MetricSource.allCases.count) -> Int {
        guard total > 0 else { return 0 }
        let clamped = min(max(sourceCount, 0), total)
        return Int((Double(clamped) / Double(total) * 100).rounded())
    }
}

/// 评分项的跳过集合：系统判定不全 + 用户手动标记。
///
/// 任一源被跳过后，其对应的评分分量直接返回 nil，由 `weightedAverage`
/// 按剩余权重归一化，从而实现「跳过该项、不影响其他完整项」。
struct ScoreExclusions: Sendable, Equatable {
    /// 系统根据当天读数判定为不全的源。
    let autoMissing: Set<MetricSource>
    /// 用户手动标记为不全的源。
    let manualMarked: Set<MetricSource>

    /// 所有被跳过的源。
    var all: Set<MetricSource> { autoMissing.union(manualMarked) }

    /// 判断某源是否被跳过。
    /// - Parameter source: 数据类别。
    func contains(_ source: MetricSource) -> Bool { all.contains(source) }

    /// 实际参与评分的数据源数量。
    var effectiveCount: Int { MetricSource.allCases.count - all.count }

    /// 带原因的跳过列表，按 MetricSource 声明顺序输出以保证结果稳定。
    /// 手动标记优先于系统判定：用户明确标记时展示「已标记」而非「数据不全」。
    var skipped: [SourceSkip] {
        MetricSource.allCases.compactMap { source in
            if manualMarked.contains(source) {
                return SourceSkip(source: source, reason: .manual)
            }
            if autoMissing.contains(source) {
                return SourceSkip(source: source, reason: .incomplete)
            }
            return nil
        }
    }
}
