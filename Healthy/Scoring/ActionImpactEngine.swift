import Foundation

enum ActionStatus: String, Sendable, Equatable {
    case met
    case notMet
}

enum InsightAction: String, CaseIterable, Identifiable, Sendable {
    case sleep7h
    case sleepEfficiency90
    case daylight20
    case steps8000
    case mindful5
    case flights10
    case shortSleep6h
    case lowDaylight5
    case lowSteps3000
    case water1500
    case caffeineModerate
    case quietUnder55

    var id: String { rawValue }

    /// 手动打卡键（water/caffeine），nil 表示纯 HealthKit 自动行动。
    var manualKey: String? {
        switch self {
        case .water1500: return "water"
        case .caffeineModerate: return "caffeine"
        default: return nil
        }
    }

    var title: String {
        switch self {
        case .sleep7h: return "睡够 7 小时"
        case .sleepEfficiency90: return "睡眠效率 90% 以上"
        case .daylight20: return "日照 20 分钟以上"
        case .steps8000: return "步数 8000 以上"
        case .mindful5: return "正念 5 分钟以上"
        case .flights10: return "爬楼 10 层以上"
        case .shortSleep6h: return "睡眠少于 6 小时"
        case .lowDaylight5: return "日照低于 5 分钟"
        case .lowSteps3000: return "步数低于 3000"
        case .water1500: return "喝水 1500 毫升以上"
        case .caffeineModerate: return "咖啡因 200 毫克以内"
        case .quietUnder55: return "环境声音低于 55 分贝"
        }
    }

    /// 带目标值的展示标题。喝水阈值与咖啡因上限都由用户在配置页自定义，
    /// 标题必须跟着配置走，否则详情页会一直写死「1500 毫升」「200 毫克」。
    /// 其余行动的阈值是固定口径，直接返回 `title`。
    func title(
        waterTargetMl: Double = IntakeGoal.defaultWaterTargetMl,
        caffeineLimitMg: Double = IntakeGoal.defaultCaffeineLimitMg
    ) -> String {
        switch self {
        case .water1500: return "喝水 \(Int(waterTargetMl.rounded())) 毫升以上"
        case .caffeineModerate: return "咖啡因 \(Int(caffeineLimitMg.rounded())) 毫克以内"
        default: return title
        }
    }

    var icon: String {
        switch self {
        case .sleep7h: return "moon.zzz.fill"
        case .sleepEfficiency90: return "bed.double.fill"
        case .daylight20: return "sun.max.fill"
        case .steps8000: return "figure.walk"
        case .mindful5: return "leaf.fill"
        case .flights10: return "stairs"
        case .shortSleep6h: return "moon.fill"
        case .lowDaylight5: return "cloud.fill"
        case .lowSteps3000: return "chair.lounge.fill"
        case .water1500: return "drop.fill"
        case .caffeineModerate: return "mug.fill"
        case .quietUnder55: return "speaker.wave.3.fill"
        }
    }

    /// 判定所依据的当日实测值；nil 表示当天无该指标数据。
    /// 详情页日历与 status 共用同一取值，避免「显示的数值」与「符合判定」来自两条数据路径。
    func metricValue(_ snapshot: DailySnapshot, manual: [String: Double] = [:]) -> Double? {
        switch self {
        case .sleep7h, .shortSleep6h: return snapshot.sleepTotalH
        case .sleepEfficiency90: return snapshot.sleepEfficiency
        case .daylight20, .lowDaylight5: return snapshot.daylightMinutes
        case .steps8000, .lowSteps3000: return snapshot.steps
        case .mindful5: return snapshot.mindfulMinutes
        case .flights10: return snapshot.flightsClimbed
        case .water1500: return manual["water"]
        case .caffeineModerate: return manual["caffeine"]
        case .quietUnder55:
            return MetricSanitizer.value(snapshot.environmentalNoiseDb, in: MetricRange.environmentalNoiseDb)
        }
    }

    /// 日历格子中数值的含义（格子太窄不显示单位，用卡片下方的说明补充）。
    var metricCaption: String {
        switch self {
        case .sleep7h, .shortSleep6h: return "当日睡眠时长（小时）"
        case .sleepEfficiency90: return "当日睡眠效率（%）"
        case .daylight20, .lowDaylight5: return "当日日照时长（分钟）"
        case .steps8000, .lowSteps3000: return "当日步数"
        case .mindful5: return "当日正念时长（分钟）"
        case .flights10: return "当日爬楼层数"
        case .water1500: return "当日饮水量（毫升）"
        case .caffeineModerate: return "当日咖啡因（毫克）"
        case .quietUnder55: return "当日环境音量日均（dB）"
        }
    }

    /// 实测值单位，仅用于当日详情（日历格子太窄不显示）；效率已在文本里带 %，故留空。
    var metricUnit: String {
        switch self {
        case .sleep7h, .shortSleep6h: return "小时"
        case .sleepEfficiency90: return ""
        case .daylight20, .lowDaylight5, .mindful5: return "分钟"
        case .steps8000, .lowSteps3000: return "步"
        case .flights10: return "层"
        case .water1500: return "毫升"
        case .caffeineModerate: return "毫克"
        case .quietUnder55: return "dB"
        }
    }

    /// 日历格子里的数值文本：效率按百分比，万级以上用 k 缩写避免挤出格子。
    func metricText(_ value: Double) -> String {
        if self == .sleepEfficiency90 { return "\(Int((value * 100).rounded()))%" }
        if value >= 10_000 { return String(format: "%.0fk", value / 1_000) }
        return "\(Int(value.rounded()))"
    }

    /// 判定是否符合该行动。
    /// - Parameter waterTargetMl: 喝水目标的生效值（毫升），来自「喝水配置」里的同一组偏好。
    /// - Parameter caffeineLimitMg: 咖啡因上限的生效值（毫克），来自「咖啡因配置」。
    ///   判定与标题共用同一个目标，避免「写 2000、按 1500 判」。
    func status(
        _ snapshot: DailySnapshot,
        manual: [String: Double] = [:],
        waterTargetMl: Double = IntakeGoal.defaultWaterTargetMl,
        caffeineLimitMg: Double = IntakeGoal.defaultCaffeineLimitMg
    ) -> ActionStatus? {
        guard let value = metricValue(snapshot, manual: manual) else { return nil }
        switch self {
        case .sleep7h: return value >= 7 ? .met : .notMet
        case .sleepEfficiency90: return value >= 0.9 ? .met : .notMet
        case .daylight20: return value >= 20 ? .met : .notMet
        case .steps8000: return value >= 8_000 ? .met : .notMet
        case .mindful5: return value >= 5 ? .met : .notMet
        case .flights10: return value >= 10 ? .met : .notMet
        case .shortSleep6h:
            guard value > 0 else { return nil }
            return value < 6 ? .met : .notMet
        case .lowDaylight5: return value < 5 ? .met : .notMet
        case .lowSteps3000: return value < 3_000 ? .met : .notMet
        case .water1500: return value >= waterTargetMl ? .met : .notMet
        case .caffeineModerate: return value <= caffeineLimitMg ? .met : .notMet
        case .quietUnder55: return value <= 55 ? .met : .notMet
        }
    }
}

enum ActionImpactLevel: String, Sendable, Codable {
    case small
    case medium
    case large

    var label: String {
        switch self {
        case .small: return "小"
        case .medium: return "中"
        case .large: return "大"
        }
    }
}

struct ActionDay: Sendable, Equatable {
    var date: Date
    var stress: Double
    var snapshot: DailySnapshot
    var manual: [String: Double] = [:]
}

struct ActionImpact: Sendable, Equatable, Identifiable {
    var id: String { action.rawValue }
    var action: InsightAction
    var daysMet: Int
    var daysNotMet: Int
    var averageStressMet: Double
    var averageStressNotMet: Double
    var delta: Double
    var impact: ActionImpactLevel
    var isPositive: Bool
}

struct ActionImpactSummary: Sendable, Equatable {
    var daysAnalyzed: Int
    var positive: [ActionImpact]
    var negative: [ActionImpact]

    static let empty = ActionImpactSummary(daysAnalyzed: 0, positive: [], negative: [])
}

/// 单个行动的完整统计结果。
/// `ActionImpactSummary` 只保留「过了门槛且差异显著」的行动，
/// 详情页需要区分「到底为什么没有压力差」，所以单独给出未通过门槛的原始分组数据。
enum ActionImpactOutcome: Sendable, Equatable {
    /// 有效天数不足 `minAnalysisDays`，任何结论都不成立。
    case insufficientTotal(daysAnalyzed: Int)
    /// 两组天数都够总天数门槛，但「符合」或「不符合」任一组不足 `minDaysPerGroup`。
    case insufficientGroups(daysMet: Int, daysNotMet: Int)
    /// 两组天数都够，但平均压力差绝对值 < `neutralDelta`，按「无显著差异」处理。
    case notSignificant(
        daysMet: Int,
        daysNotMet: Int,
        averageStressMet: Double,
        averageStressNotMet: Double,
        delta: Double
    )
    /// 通过全部门槛：参与影响分级。
    case impact(ActionImpact)

    /// 符合日压力均值；天数不足时没有均值可算，返回 nil。
    var averageStressMet: Double? {
        switch self {
        case .insufficientTotal, .insufficientGroups: return nil
        case let .notSignificant(_, _, met, _, _): return met
        case let .impact(impact): return impact.averageStressMet
        }
    }

    /// 不符合日压力均值；天数不足时返回 nil。
    var averageStressNotMet: Double? {
        switch self {
        case .insufficientTotal, .insufficientGroups: return nil
        case let .notSignificant(_, _, _, notMet, _): return notMet
        case let .impact(impact): return impact.averageStressNotMet
        }
    }

    /// 不符合日均压力 − 符合日均压力（正数表示符合的日子压力更低）；天数不足时返回 nil。
    var delta: Double? {
        switch self {
        case .insufficientTotal, .insufficientGroups: return nil
        case let .notSignificant(_, _, _, _, delta): return delta
        case let .impact(impact): return impact.delta
        }
    }
}

struct ActionTrendPoint: Sendable, Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var stress: Double
    /// 该行动判定所用的当日实测值（如环境音量 dB），与 status 同源，供详情页日历展示。
    var metricValue: Double
    var status: ActionStatus
}

enum ActionImpactEngine {
    static let minAnalysisDays = 14
    static let minDaysPerGroup = 5
    static let neutralDelta = 2.0

    /// 单个行动的逐日压力分组：把每天按「符合 / 不符合」分到两组里。
    /// 当天没有该行动数据（如没戴表、没日照记录）就跳过，不计入任何一组。
    private static func groupedStress(
        action: InsightAction,
        days: [ActionDay],
        waterTargetMl: Double,
        caffeineLimitMg: Double
    ) -> (met: [Double], notMet: [Double]) {
        var metStress: [Double] = []
        var notMetStress: [Double] = []
        for day in days {
            guard let status = action.status(
                day.snapshot,
                manual: day.manual,
                waterTargetMl: waterTargetMl,
                caffeineLimitMg: caffeineLimitMg
            ) else { continue }
            switch status {
            case .met: metStress.append(day.stress)
            case .notMet: notMetStress.append(day.stress)
            }
        }
        return (metStress, notMetStress)
    }

    /// 单个行动的完整口径：把「天数不足」与「差异不显著」区分开，供详情页展示。
    /// - Parameter days: 与页面统计窗口同一批日子（详情页传近 30 天），保证柱状图天数与压力差同源。
    static func detail(
        action: InsightAction,
        days: [ActionDay],
        waterTargetMl: Double = IntakeGoal.defaultWaterTargetMl,
        caffeineLimitMg: Double = IntakeGoal.defaultCaffeineLimitMg
    ) -> ActionImpactOutcome {
        guard days.count >= minAnalysisDays else {
            return .insufficientTotal(daysAnalyzed: days.count)
        }
        let groups = groupedStress(
            action: action,
            days: days,
            waterTargetMl: waterTargetMl,
            caffeineLimitMg: caffeineLimitMg
        )
        guard groups.met.count >= minDaysPerGroup,
              groups.notMet.count >= minDaysPerGroup
        else {
            return .insufficientGroups(daysMet: groups.met.count, daysNotMet: groups.notMet.count)
        }

        let metAverage = groups.met.reduce(0, +) / Double(groups.met.count)
        let notMetAverage = groups.notMet.reduce(0, +) / Double(groups.notMet.count)
        let delta = notMetAverage - metAverage
        guard abs(delta) >= neutralDelta else {
            return .notSignificant(
                daysMet: groups.met.count,
                daysNotMet: groups.notMet.count,
                averageStressMet: metAverage,
                averageStressNotMet: notMetAverage,
                delta: delta
            )
        }

        return .impact(
            ActionImpact(
                action: action,
                daysMet: groups.met.count,
                daysNotMet: groups.notMet.count,
                averageStressMet: metAverage,
                averageStressNotMet: notMetAverage,
                delta: delta,
                impact: level(for: abs(delta)),
                isPositive: delta > 0
            )
        )
    }

    /// - Parameter waterTargetMl: 喝水目标的生效值（毫升），只影响 `water1500` 的符合判定。
    /// - Parameter caffeineLimitMg: 咖啡因上限的生效值（毫克），只影响 `caffeineModerate` 的符合判定。
    static func evaluate(
        days: [ActionDay],
        waterTargetMl: Double = IntakeGoal.defaultWaterTargetMl,
        caffeineLimitMg: Double = IntakeGoal.defaultCaffeineLimitMg
    ) -> ActionImpactSummary {
        guard days.count >= minAnalysisDays else {
            return ActionImpactSummary(daysAnalyzed: days.count, positive: [], negative: [])
        }

        var positive: [ActionImpact] = []
        var negative: [ActionImpact] = []

        for action in InsightAction.allCases {
            // 只把通过全部门槛（天数够 + 差异 ≥ 2 分）的行动计入汇总；
            // 未通过的原始分组数据由 `detail` 提供给详情页解释。
            guard case let .impact(impact) = detail(
                action: action,
                days: days,
                waterTargetMl: waterTargetMl,
                caffeineLimitMg: caffeineLimitMg
            ) else { continue }

            if impact.delta > 0 {
                positive.append(impact)
            } else {
                negative.append(impact)
            }
        }

        positive.sort { $0.delta > $1.delta }
        negative.sort { $0.delta < $1.delta }
        return ActionImpactSummary(daysAnalyzed: days.count, positive: positive, negative: negative)
    }

    /// - Parameter waterTargetMl: 喝水目标的生效值（毫升），与 `evaluate` 共用同一口径，
    ///   保证日历格子的「符合」点与等级分布来自同一次判定。
    /// - Parameter caffeineLimitMg: 咖啡因上限的生效值（毫克），同上。
    static func trendPoints(
        action: InsightAction,
        days: [ActionDay],
        waterTargetMl: Double = IntakeGoal.defaultWaterTargetMl,
        caffeineLimitMg: Double = IntakeGoal.defaultCaffeineLimitMg
    ) -> [ActionTrendPoint] {
        days.compactMap { day in
            guard let value = action.metricValue(day.snapshot, manual: day.manual),
                  let status = action.status(
                    day.snapshot,
                    manual: day.manual,
                    waterTargetMl: waterTargetMl,
                    caffeineLimitMg: caffeineLimitMg
                  ) else { return nil }
            return ActionTrendPoint(date: day.date, stress: day.stress, metricValue: value, status: status)
        }
    }

    static func level(for absDelta: Double) -> ActionImpactLevel {
        if absDelta >= 15 { return .large }
        if absDelta >= 7 { return .medium }
        return .small
    }
}
