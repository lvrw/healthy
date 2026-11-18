import Foundation
import Testing

/// 行动页改造的回归测试：完成度换算、目标读数、格子排序、环境音量展示口径。
/// 都是纯逻辑，不依赖 SwiftData / SwiftUI，可直接在测试包里跑。
struct ActionPageRegressionTests {
    // MARK: - 完成度

    /// DailyScore.completeness 存的是「数据源类别数」（0–8），UI 必须换算成百分比：
    /// 8 类齐全的一天是 100%，不是 8%。
    @Test func completenessPercentConvertsSourceCountToPercentage() {
        let total = MetricSource.allCases.count
        #expect(total == 8)
        #expect(CompletenessPresentation.percent(sourceCount: 8) == 100)
        #expect(CompletenessPresentation.percent(sourceCount: 4) == 50)
        #expect(CompletenessPresentation.percent(sourceCount: 1) == 13)
        #expect(CompletenessPresentation.percent(sourceCount: 0) == 0)
        // 越界值不应显示超过 100% 或负数。
        #expect(CompletenessPresentation.percent(sourceCount: 99) == 100)
        #expect(CompletenessPresentation.percent(sourceCount: -3) == 0)
    }

    // MARK: - 喝水目标读数

    /// 行动页卡片读的是 IntakeGoal 的同一组键：用户配置 2000 就必须显示 2000，
    /// 不能因为默认值是 1500 就退回默认。
    @Test func waterTargetFollowsStoredConfiguration() {
        let defaults = UserDefaults(suiteName: "healthy.tests.actionpage")!
        defaults.removePersistentDomain(forName: "healthy.tests.actionpage")
        defer { defaults.removePersistentDomain(forName: "healthy.tests.actionpage") }

        #expect(IntakeGoal.waterTargetMl(defaults: defaults) == IntakeGoal.defaultWaterTargetMl)
        _ = IntakeGoal.setWaterTargetMl(2_000, defaults: defaults)
        #expect(IntakeGoal.waterTargetMl(defaults: defaults) == 2_000)
        // 超出范围的值按范围钳制，不会让卡片显示异常数字。
        _ = IntakeGoal.setWaterTargetMl(99_999, defaults: defaults)
        #expect(IntakeGoal.waterTargetMl(defaults: defaults) == IntakeGoal.waterRange.upperBound)
    }

    // MARK: - 步数目标 / 减肥目标

    @Test func stepsTargetAndCalorieThreshold() {
        let defaults = UserDefaults(suiteName: "healthy.tests.actiongoal")!
        defaults.removePersistentDomain(forName: "healthy.tests.actiongoal")
        defer { defaults.removePersistentDomain(forName: "healthy.tests.actiongoal") }

        #expect(ActionGoal.stepsTarget(defaults: defaults) == ActionGoal.defaultStepsTarget)
        _ = ActionGoal.setStepsTarget(12_000, defaults: defaults)
        #expect(ActionGoal.stepsTarget(defaults: defaults) == 12_000)

        // 维持体重：阈值等于维持热量。
        #expect(ActionGoal.calorieThreshold(maintenanceKcal: 2_200, weeklyLossKg: 0) == 2_200)
        // 每周减 0.5 kg：2200 − 0.5 × 7700 ÷ 7 = 1650。
        #expect(ActionGoal.calorieThreshold(maintenanceKcal: 2_200, weeklyLossKg: 0.5) == 1_650)
        // 极端减重速度也不会低于安全下限。
        #expect(ActionGoal.calorieThreshold(maintenanceKcal: 1_300, weeklyLossKg: 1.0) == 1_200)
    }

    /// 维持热量估算：优先历史完整日均值，没有历史才退到当天。
    @Test func maintenanceKcalPrefersHistoryAverage() {
        #expect(ActionGoal.estimatedMaintenanceKcal(historyEnergies: [2_000, 2_200], todayEnergy: 900) == 2_100)
        #expect(ActionGoal.estimatedMaintenanceKcal(historyEnergies: [], todayEnergy: 1_800) == 1_800)
        #expect(ActionGoal.estimatedMaintenanceKcal(historyEnergies: [], todayEnergy: nil) == nil)
        // 静息能量缺失或非法时不参与估算。
        #expect(ActionGoal.dailyEnergy(basal: nil, active: 300) == nil)
        #expect(ActionGoal.dailyEnergy(basal: 1_600, active: 300) == 1_900)
    }

    // MARK: - 格子排序

    @Test func gridOrderDefaultsAndPersists() {
        let defaults = UserDefaults(suiteName: "healthy.tests.gridorder")!
        defaults.removePersistentDomain(forName: "healthy.tests.gridorder")
        defer { defaults.removePersistentDomain(forName: "healthy.tests.gridorder") }

        #expect(ActionGridTile.storedOrder(defaults: defaults) == ActionGridTile.defaultOrder)
        let custom: [ActionGridTile] = [.steps, .noise, .mindful, .daylight]
        ActionGridTile.store(custom, defaults: defaults)
        #expect(ActionGridTile.storedOrder(defaults: defaults) == custom)
        // 偏好里只存了部分 id 时，缺失项按默认顺序补齐，不会丢格子。
        defaults.set(["noise"], forKey: "healthy.actionGridOrder")
        let restored = ActionGridTile.storedOrder(defaults: defaults)
        #expect(restored.count == ActionGridTile.allCases.count)
        #expect(restored.first == .noise)
    }

    // MARK: - 环境音量

    /// 环境音量只用来展示「当日日均」，无样本时明确写「无数据」而不是 0。
    @Test func noisePresentationKeepsDailyAverageSemantics() {
        #expect(NoisePresentation.tileValue(nil) == "无数据")
        #expect(NoisePresentation.tileValue(54.8) == "55 dB")
        #expect(NoisePresentation.tileValue(31.2) == "31 dB")
        #expect(NoisePresentation.detailValue(62.4) == "62 dB")
        #expect(NoisePresentation.tileCaption.contains("日均"))
        #expect(NoisePresentation.sourceNote.contains("环境音量"))
    }

    // MARK: - 今日摄入热量合并

    /// 常规路径：stored 是上一轮「外部 + 本地」合并总量，先扣旧本地量再加本轮本地量。
    @Test func nutritionMergeUsesExternalPlusCurrentLocal() {
        // 外部 100 + 上一轮本地 300 = 400；本轮本地涨到 420，结果应为 520。
        #expect(NutritionMerge.total(stored: 400, previousLocal: 300, currentLocal: 420) == 520)
        // 本轮删掉了全部打卡：只剩外部量。
        #expect(NutritionMerge.total(stored: 400, previousLocal: 300, currentLocal: 0) == 100)
    }

    /// 回归：轻量同步把 stored 覆盖成纯外部量（或 nil）却没清本地快照时，
    /// 旧算法会算出负外部量，把本 App 的 meal 热量抵消成 0，行动页饮食卡显示「—」。
    @Test func nutritionMergeDoesNotCancelLocalMealEnergy() {
        // 外部没有能量样本、本地 3 餐合计 421 千卡：必须显示 421。
        #expect(NutritionMerge.total(stored: nil, previousLocal: 421, currentLocal: 421) == 421)
        // 外部有 80 千卡时也要叠加，不能只留一边。
        #expect(NutritionMerge.total(stored: 80, previousLocal: 421, currentLocal: 421) == 501)
    }

    /// 当天确实没有任何摄入时返回 nil，UI 才显示「— / 阈值」而不是 0。
    @Test func nutritionMergeReturnsNilForEmptyDay() {
        #expect(NutritionMerge.total(stored: nil, previousLocal: 0, currentLocal: 0) == nil)
        #expect(NutritionMerge.total(stored: 0, previousLocal: 0, currentLocal: 0) == nil)
    }
}
