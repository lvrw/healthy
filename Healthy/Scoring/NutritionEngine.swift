import Foundation

/// 饮水 + 饮食的经验评分（0–100，及格 60 / 优秀 90）。
///
/// 只用于可视化相对变化：所有参考带都来自 ScoringConfig 的经验设定，
/// 不是个体化的医学建议。缺失项一律返回 nil，不参与加权平均，
/// 因此「没有饮食数据」时今日状态评分与旧版完全一致。
/// 饮食质量以饱和脂肪酸、糖、碳水、总脂肪为核心扣分项，膳食纤维与蛋白质为加分项；
/// 健康 App 的每日汇总没有饱和脂肪字段，全天口径以总脂肪覆盖该维度，
/// 单餐打卡（IntakeNutrition.saturatedFatG）则单独评估饱和脂肪。
///
/// progress 为当日进度（0–1，历史日期传 1）：累计型指标按当前时刻应达成的
/// 阶段量评估，避免清晨把尚未过完的一天判为「饮水 / 饮食偏低」。
enum NutritionEngine {
    /// 综合分：饮水占 0.35，其余按饮食子项加权；全部缺失时返回 nil。
    static func score(
        _ values: NutritionValues,
        config: ScoringConfig = ScoringConfig(),
        progress: Double = 1
    ) -> Double? {
        let water = waterScore(values.waterTotalMl, config: config, progress: progress)
        let parts: [(weight: Double, score: Double?)] =
            [(0.35, water)] + dietParts(values, config: config, progress: progress)
        return ScoreSupport.weightedAverage(parts)
    }

    /// 仅饮食分（不含饮水），供身体年龄的「饮食质量」维度使用。
    static func dietScore(
        _ values: NutritionValues,
        config: ScoringConfig = ScoringConfig(),
        progress: Double = 1
    ) -> Double? {
        ScoreSupport.weightedAverage(dietParts(values, config: config, progress: progress))
    }

    /// 全 App 唯一的「饮食评分」口径：饮食质量 70% + 规律饮食 30%。
    /// 状态分 / 压力分 / 详情页展示共用同一个函数，避免两个分数各自计算造成口径不一致。
    /// 缺任一分量时按剩余权重归一化；两者都缺返回 nil（评分层跳过该维度）。
    static func combinedScore(
        _ values: NutritionValues,
        regularity: Double?,
        config: ScoringConfig = ScoringConfig(),
        progress: Double = 1
    ) -> Double? {
        let quality = dietScore(values, config: config, progress: progress)
        return ScoreSupport.weightedAverage([(0.7, quality), (0.3, regularity)])
    }

    /// 饮水达标分：不足按比例扣，超出目标只轻微扣分（喝水过量不等同于线性变差）。
    /// 目标按当日进度缩放；进度太低时不评价这一项。
    static func waterScore(
        _ waterMl: Double?,
        config: ScoringConfig = ScoringConfig(),
        progress: Double = 1
    ) -> Double? {
        guard let raw = MetricSanitizer.value(waterMl, in: MetricRange.waterMl),
              let target = DayProgress.stagedTarget(config.nutritionWaterTargetMl, progress: progress),
              target > 0 else { return nil }
        if raw <= target {
            let deficit = target - raw
            return ScoreSupport.clampScore(100 - deficit / target * 60)
        }
        let excess = (raw - target) / target
        return ScoreSupport.clampScore(100 - min(20, excess * 12))
    }

    // MARK: - 饮食子项

    private static func dietParts(
        _ values: NutritionValues,
        config: ScoringConfig,
        progress: Double
    ) -> [(weight: Double, score: Double?)] {
        // 饮食质量整体作为一个分量（权重 0.65），水在外层 score() 以 0.35 权重单独计入。
        // 全天汇总没有饱和脂肪字段，用总脂肪覆盖该维度；单餐打卡才单独评估饱和脂肪。
        // 咖啡因是全天上限，过半程后才纳入，否则早上第一杯咖啡就会被判成「今日偏高」。
        let quality = dietQuality(
            saturatedFat: nil,
            fat: MetricSanitizer.value(values.fatG, in: MetricRange.dietaryFatG),
            carbs: MetricSanitizer.value(values.carbsG, in: MetricRange.dietaryCarbsG),
            sugar: MetricSanitizer.value(values.sugarG, in: MetricRange.dietarySugarG),
            fiber: MetricSanitizer.value(values.fiberG, in: MetricRange.dietaryFiberG),
            protein: MetricSanitizer.value(values.proteinG, in: MetricRange.dietaryProteinG),
            caffeine: progress >= DayProgress.ceilingThreshold
                ? MetricSanitizer.value(values.caffeineMg, in: MetricRange.dietaryCaffeineMg)
                : nil,
            share: 1,
            proteinTargetOverride: DayProgress.stagedTarget(config.nutritionProteinTargetG, progress: progress),
            config: config
        )
        return [(0.65, quality)]
    }

    /// 饮食质量核心评分（0–100）：饱和脂肪 / 总脂肪 / 碳水 / 糖按「超出参考上限的比例」扣分，
    /// 膳食纤维与蛋白质按达标比例加分；任一核心指标明显偏高时施加硬上限，
    /// 避免优质营养素或低咖啡因把不健康饮食抬成高分。
    /// `share` 为全天参考值的占比：全天传 1，单餐传 MealSlot.energyShare。
    /// 任一核心指标都没有数据时返回 nil，由加权平均自动忽略。
    static func dietQuality(
        saturatedFat: Double?,
        fat: Double?,
        carbs: Double?,
        sugar: Double?,
        fiber: Double?,
        protein: Double?,
        caffeine: Double?,
        share: Double,
        proteinTargetOverride: Double? = nil,
        config: ScoringConfig
    ) -> Double? {
        guard saturatedFat != nil || fat != nil || carbs != nil || sugar != nil else { return nil }

        let saturatedFatLimit = config.nutritionSaturatedFatLimitG * share
        let fatLimit = config.nutritionFatLimitG * share
        let carbLimit = config.nutritionCarbsLimitG * share
        let sugarLimit = config.nutritionSugarLimitG * share
        let fiberTarget = config.nutritionFiberTargetG * share
        let proteinTarget = proteinTargetOverride ?? config.nutritionProteinTargetG * share
        let caffeineLimit = config.nutritionCaffeineLimitMg * share

        // 及格线即基础分：不超标、无加分时刚好及格；纤维与蛋白各加 15 分达到优秀线。
        var score = config.nutritionPassingScore
        var highCount = 0

        func penalty(_ value: Double?, limit: Double, factor: Double, core: Bool) {
            guard let value, limit > 0, value > limit else { return }
            score -= min(config.nutritionHighRatio, (value - limit) / limit) * factor
            if core, value > limit * config.nutritionHighRatio { highCount += 1 }
        }
        func bonus(_ value: Double?, target: Double, max maxBonus: Double) {
            guard let value, target > 0 else { return }
            score += min(1, value / target) * maxBonus
        }

        penalty(saturatedFat, limit: saturatedFatLimit, factor: config.nutritionSaturatedFatPenalty, core: true)
        penalty(fat, limit: fatLimit, factor: config.nutritionFatPenalty, core: true)
        penalty(carbs, limit: carbLimit, factor: config.nutritionCarbPenalty, core: true)
        penalty(sugar, limit: sugarLimit, factor: config.nutritionSugarPenalty, core: true)
        bonus(fiber, target: fiberTarget, max: config.nutritionFiberBonus)
        bonus(protein, target: proteinTarget, max: config.nutritionProteinBonus)
        penalty(caffeine, limit: caffeineLimit, factor: config.nutritionCaffeinePenalty, core: false)

        // 饱和脂肪、糖或脂肪任一偏高都不能评为优秀；两项及以上偏高直接不及格。
        let cap: Double
        if highCount >= 2 { cap = config.nutritionMultiHighCap }
        else if highCount == 1 { cap = config.nutritionSingleHighCap }
        else { cap = 100 }
        return min(ScoreSupport.clampScore(score), cap)
    }
}

// configured by qoder
