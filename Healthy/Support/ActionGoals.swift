import Foundation

/// 行动页可配置目标：步数目标、减肥目标与由减肥目标推导的每日卡路里阈值。
/// 与 IntakeGoal 一样存 UserDefaults，供 @AppStorage 直接绑定，保证改完配置行动页即时刷新。
/// 注意：这里的阈值只用于行动页卡片与设置页展示 / 进度计算，不改写评分引擎既有口径。
enum ActionGoal {
    // MARK: - 睡眠

    /// 睡眠目标的展示基准（小时）：只用于睡眠卡进度条，不参与评分口径。
    static let sleepTargetHours = 8.0

    // MARK: - 步数

    static let defaultStepsTarget = 8_000.0
    static let stepsRange: ClosedRange<Double> = 1_000...50_000
    static let stepsDefaultsKey = "healthy.action.stepsTarget"

    // MARK: - 减肥目标

    /// 0 表示维持体重，其余为每周计划减重（kg/周）。
    static let weeklyWeightLossOptions: [Double] = [0, 0.25, 0.5, 0.75, 1.0]
    static let defaultWeeklyWeightLossKg = 0.5
    static let weeklyWeightLossDefaultsKey = "healthy.action.weeklyWeightLossKg"
    static let defaultMaintenanceKcal = 2_000.0
    /// 每减少 1 kg 脂肪约需 7700 kcal 热量缺口。
    static let kcalPerKgBodyFat = 7_700.0
    /// 每日摄入的安全下限，避免极端减重速度推出过低阈值（经验值，非医学建议）。
    static let minimumCalorieThreshold = 1_200.0

    // MARK: - 读写

    static func stepsTarget(defaults: UserDefaults = .standard) -> Double {
        clamp(defaults.object(forKey: stepsDefaultsKey) as? Double ?? defaultStepsTarget, in: stepsRange)
    }

    static func setStepsTarget(_ value: Double, defaults: UserDefaults = .standard) -> Double {
        let clamped = clamp(value, in: stepsRange)
        defaults.set(clamped, forKey: stepsDefaultsKey)
        return clamped
    }

    static func weeklyWeightLossKg(defaults: UserDefaults = .standard) -> Double {
        let raw = defaults.object(forKey: weeklyWeightLossDefaultsKey) as? Double ?? defaultWeeklyWeightLossKg
        return clamp(raw, in: 0...1.0)
    }

    static func setWeeklyWeightLossKg(_ value: Double, defaults: UserDefaults = .standard) -> Double {
        let clamped = clamp(value, in: 0...1.0)
        defaults.set(clamped, forKey: weeklyWeightLossDefaultsKey)
        return clamped
    }

    /// 维持热量估算：优先取近 7 个完整日「静息能量 + 活动能量」的均值，
    /// 一个完整日都没有时退回今天（当天未过完会偏低），仍无数据返回 nil 由调用方兜底。
    /// 入参只用纯数值，不依赖 SwiftData 模型，便于单测覆盖。
    /// - Parameters:
    ///   - historyEnergies: 历史各日的能量消耗（静息 + 活动），顺序不限。
    ///   - todayEnergy: 当日能量消耗，可为 nil。
    static func estimatedMaintenanceKcal(
        historyEnergies: [Double],
        todayEnergy: Double?
    ) -> Double? {
        let complete = historyEnergies.filter { $0 > 0 }
        if !complete.isEmpty {
            return complete.reduce(0, +) / Double(complete.count)
        }
        return todayEnergy
    }

    /// 一天的能量消耗：健康 App 静息能量 + 活动能量，任一缺失或非法都不参与估算。
    static func dailyEnergy(basal: Double?, active: Double?) -> Double? {
        guard let basal, let active, basal > 0, active >= 0 else { return nil }
        return basal + active
    }

    /// 每日卡路里摄入阈值 = 维持热量 − 每周减重所需日均缺口。
    /// 维持体重（0 kg/周）时阈值等于维持热量；结果不低于安全下限。
    static func calorieThreshold(maintenanceKcal: Double, weeklyLossKg: Double) -> Double {
        let deficit = clamp(weeklyLossKg, in: 0...1.0) * kcalPerKgBodyFat / 7
        return max(minimumCalorieThreshold, maintenanceKcal - deficit).rounded()
    }

    static func clamp(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
