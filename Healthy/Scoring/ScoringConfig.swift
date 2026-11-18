import Foundation

struct ScoringConfig: Sendable, Equatable {
    var baselineWindowDays = 28
    var minBaselineDays = 7
    var minSparseBaselineDays = 3
    var minConfidenceDays = 3
    var minCompletenessForFull = 4
    var zClamp = 2.5

    var readinessSleepWeight = 0.28
    var readinessAutonomicWeight = 0.24
    var readinessLoadWeight = 0.14
    var readinessVitalsWeight = 0.12
    var readinessCircadianWeight = 0.12
    var readinessFitnessBodyWeight = 0.10
    /// 饮水与饮食分量：只有读到数据时才参与，缺失时原有权重完全不变。
    var readinessNutritionWeight = 0.08
    /// 规律饮食分量：只有本 App 记录过饮食（`mealRegularityScore` 非 nil）才参与，
    /// 缺失时加权平均自动忽略，既有状态分口径完全不变。
    var readinessMealRegularityWeight = 0.06

    var stressHRVWeight = 0.38
    var stressRestingHRWeight = 0.15
    var stressSleepWeight = 0.12
    var stressVitalsWeight = 0.10
    var stressCircadianWeight = 0.13
    var stressMoodWeight = 0.12

    var sleepTargetHours = 7.5
    var sleepLowTargetHours = 7.0
    var sleepHighTargetHours = 9.0
    var deepRemTargetRatio = 0.40
    var minLoadDays = 3
    var minSleepNights = 3
    var daylightTargetMinutes = 60.0
    var sleepMidpointSDFloor = 30.0

    var instantHRWeight = 0.65
    var instantHRVWeight = 0.35
    var instantStateReadinessWeight = 0.60
    var instantStateStressWeight = 0.40
    var instantHRFreshMinutes = 15.0
    var instantHRAcceptableMinutes = 60.0
    var instantHRWindowHours = 6.0
    var instantHRVFreshHours = 6.0
    var instantWorkoutCooldownMinutes = 30.0

    var hrvLogSDFloor = 0.05
    var restingHRSDFloor = 2.0
    var avgHRSDFloor = 8.0
    var hourlyStressWeight = 18.0
    var intradayBucketMinutes = 15
    var activityZThreshold = 2.0
    var sleepOverlapMinutes = 30.0
    var tempSDFloor = 0.1
    var respSDFloor = 0.5
    var spo2SDFloor = 0.5
    var vo2MaxSDFloor = 0.5
    var walkingSpeedSDFloor = 0.05
    var walkingSteadinessSDFloor = 2.0
    var systolicBPSDFloor = 4.0
    var diastolicBPSDFloor = 3.0
    var basalTempSDFloor = 0.1
    var bloodGlucoseSDFloor = 5.0

    var stressLowUpperBound = 30.0
    var stressModerateUpperBound = 50.0
    var stressElevatedUpperBound = 70.0
    /// 压力随饮食评分联动：75 分为中性基准（60 及格 / 90 优秀），
    /// 饮食越差压力越高，饮食越优压力越低；无饮食数据时调整为 0。
    var stressDietNeutralScore = 75.0
    var stressDietFactor = 0.25
    var stressDietImprovementCap = 4.0
    var stressDietWorseningCap = 8.0

    // MARK: - 饮水 / 饮食经验参考值（仅用于可视化相对变化，非医学建议）
    /// 每日喝水目标（毫升），与行动页 1500 ml 目标一致。
    var nutritionWaterTargetMl = 1_500.0
    /// 热量参考带下限 / 上限（千卡）。
    var nutritionEnergyLowerKcal = 1_800.0
    var nutritionEnergyUpperKcal = 2_600.0
    /// 蛋白质参考量（克/天）。
    var nutritionProteinTargetG = 60.0
    /// 膳食纤维参考量（克/天）。
    var nutritionFiberTargetG = 25.0
    /// 糖、钠、咖啡因的建议上限（克 / 毫克 / 毫克）。
    var nutritionSugarLimitG = 50.0
    var nutritionSodiumLimitMg = 2_300.0
    var nutritionCaffeineLimitMg = 200.0
    /// 碳水与脂肪供能占比的参考区间（0–1），保留给展示与历史口径；评分改用绝对上限。
    var nutritionCarbRatioRange = 0.45...0.65
    var nutritionFatRatioRange = 0.20...0.35

    // MARK: - 饮食质量评分（0–100，及格 60 / 优秀 90）
    /// 饮食评分档位：及格线即基础分，优秀线为满分目标。
    var nutritionPassingScore = 60.0
    var nutritionExcellentScore = 90.0
    /// 饱和脂肪 / 总脂肪 / 碳水的每日参考上限（克）；糖的上限沿用 nutritionSugarLimitG。
    /// 单餐按 MealSlot.energyShare 缩放，全天传 1。
    var nutritionSaturatedFatLimitG = 20.0
    var nutritionFatLimitG = 70.0
    var nutritionCarbsLimitG = 250.0
    /// 核心指标超标扣分系数：按「超出上限 / 上限」的比例扣，单项最多按 1.5 倍比例扣。
    /// 饱和脂肪与糖的系数最高，其次总脂肪、碳水，体现「减碳减脂、优先控饱和脂肪与糖」。
    var nutritionSaturatedFatPenalty = 45.0
    var nutritionSugarPenalty = 35.0
    var nutritionFatPenalty = 35.0
    var nutritionCarbPenalty = 25.0
    var nutritionCaffeinePenalty = 10.0
    /// 膳食纤维 / 蛋白质按达标比例加分，最高各 15 分：与扣分一起构成 60–90 的有效区间。
    var nutritionFiberBonus = 15.0
    var nutritionProteinBonus = 15.0
    /// 核心指标「偏高」的判定倍数与分数硬上限：单项偏高不达优秀，多项偏高直接不及格。
    var nutritionHighRatio = 1.5
    var nutritionSingleHighCap = 69.0
    var nutritionMultiHighCap = 59.0

    // MARK: - 餐次 / 每餐评分 / 规律饮食（经验值，非医学建议）
    /// 单餐评分档位：优秀 / 健康 / 一般 的下限，与饮食质量评分口径对齐。
    var mealExcellentThreshold = 90.0
    var mealHealthyThreshold = 70.0
    var mealFairThreshold = 60.0
    /// 单餐水量不足只做轻微辅助扣分（水在全天评分里单独占 0.35）。
    var mealWaterPenaltyFactor = 0.10
    /// 用餐时刻偏离餐次建议窗口、以及夜宵的扣分项。
    var mealOffWindowPenalty = 8.0
    var mealLateNightPenalty = 12.0
    /// 规律饮食：相邻两餐合理间隔（小时）。
    var mealMinGapHours = 3.0
    var mealMaxGapHours = 7.0
    /// 近 N 天进餐时刻稳定性窗口与容差（分钟）。
    var mealRegularityWindowDays = 7
    var mealStableMinuteTolerance = 60.0
    /// 规律 / 基本规律 的分数下限。
    var mealRegularityGoodThreshold = 75.0
    var mealRegularityFairThreshold = 55.0
    /// 身体年龄：规律饮食对「饮食质量」调整的系数与封顶（岁）。
    var bodyAgeMealRegularityFactor = 0.012
    var bodyAgeMealRegularityCap = 0.6
    /// 身体年龄：饮食评分中性基准（及格 60 / 优秀 90 的中点）与联动系数、封顶（岁）。
    /// 评分下降 → 增龄；评分改善 → 减龄。
    var bodyAgeDietNeutralScore = 75.0
    var bodyAgeDietFactor = 0.03
    var bodyAgeDietImprovementCap = 1.5
    var bodyAgeDietWorseningCap = 2.0
}

enum MetricRange {
    static let hrv = 5.0...200.0
    static let restingHR = 30.0...120.0
    static let heartRate = 30.0...220.0
    static let respiratoryRate = 4.0...40.0
    static let spo2 = 70.0...100.0
    static let wristTemp = 30.0...42.0
    static let sleepHours = 0.0...14.0
    static let efficiency = 0.0...1.0
    static let steps = 0.0...100_000.0
    static let activeEnergy = 0.0...5_000.0
    /// 静息能量日累计（千卡）；0 表示没有有效读数，由调用方过滤。
    static let basalEnergyKcal = 0.0...5_000.0

    static let vo2Max = 10.0...80.0
    static let walkingSpeed = 0.3...3.0
    static let walkingStepLengthCm = 20.0...120.0
    static let walkingAsymmetryPct = 0.0...50.0
    static let walkingSteadinessPct = 0.0...100.0
    static let flightsClimbed = 0.0...500.0
    static let distanceKm = 0.0...200.0
    static let daylightMinutes = 0.0...1_440.0
    static let mindfulMinutes = 0.0...720.0
    static let stateOfMindValence = -1.0...1.0
    static let sleepMidpointMinutes = -720.0...720.0
    static let sleepBedtimeMinutes = -720.0...720.0
    static let bodyMassKg = 20.0...300.0
    static let bodyFatPct = 3.0...60.0
    static let leanBodyMassKg = 10.0...150.0
    static let bmi = 10.0...60.0
    static let waistCircumferenceCm = 30.0...200.0
    static let systolicBP = 60.0...250.0
    static let diastolicBP = 30.0...150.0
    static let basalBodyTemp = 30.0...42.0
    static let bloodGlucose = 20.0...600.0
    static let environmentalNoiseDb = 0.0...120.0
    /// 饮水与饮食指标的合理区间；超出按端点收敛，避免异常录入毁掉评分。
    static let waterMl = 0.0...10_000.0
    static let dietaryEnergyKcal = 0.0...8_000.0
    static let dietaryCarbsG = 0.0...1_000.0
    static let dietaryProteinG = 0.0...500.0
    static let dietaryFatG = 0.0...500.0
    static let dietaryFiberG = 0.0...200.0
    static let dietarySugarG = 0.0...500.0
    static let dietarySodiumMg = 0.0...20_000.0
    static let dietaryCaffeineMg = 0.0...2_000.0
}

enum MetricSanitizer {
    static func value(_ raw: Double?, in range: ClosedRange<Double>) -> Double? {
        guard let raw, raw.isFinite else { return nil }
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    static func clamp(_ raw: Double, to range: ClosedRange<Double>) -> Double {
        guard raw.isFinite else { return range.lowerBound }
        return min(max(raw, range.lowerBound), range.upperBound)
    }
}
