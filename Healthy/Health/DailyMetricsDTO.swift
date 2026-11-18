import Foundation

struct DailyMetricsDTO: Sendable, Equatable {
    var dayKey: String
    var date: Date
    var hrvSDNN: Double?
    var hrvLatest: Double?
    var hrvLatestAt: Date?
    var restingHR: Double?
    var avgHR: Double?
    var walkingHR: Double?
    var respiratoryRate: Double?
    var spo2: Double?
    var wristTempC: Double?
    var sleepTotalH: Double?
    var deepH: Double?
    var remH: Double?
    var coreH: Double?
    var awakeH: Double?
    var inBedH: Double?
    var sleepEfficiency: Double?
    var steps: Double?
    var activeEnergy: Double?
    /// 健康 App 的静息能量（basalEnergyBurned）当日累计，千卡。
    var basalEnergyKcal: Double? = nil
    var exerciseMinutes: Double?
    var standMinutes: Double?
    /// 健身 App 当天活动圆环目标（千卡），来自 HKActivitySummary；缺失回退 500 常量。
    var activeEnergyGoal: Double? = nil
    /// 健身 App 当天锻炼圆环目标（分钟），缺失回退 30 常量。
    var exerciseGoalMinutes: Double? = nil
    /// 健身 App 当天站立圆环目标（小时），缺失回退 12 常量。
    var standGoalHours: Double? = nil
    var workoutCount: Int?
    var workoutMinutes: Double?
    /// 近 7 日 workouts 心率区间累计分钟（Z1–Z5）的 JSON 编码，缺数据为 nil。
    var workoutZoneMinutesJSON: String? = nil
    var sourceFlags: Int

    var vo2Max: Double? = nil
    var walkingSpeedMps: Double? = nil
    var walkingStepLengthCm: Double? = nil
    var walkingAsymmetryPct: Double? = nil
    var walkingSteadinessPct: Double? = nil
    var flightsClimbed: Double? = nil
    var distanceWalkingKm: Double? = nil

    var daylightMinutes: Double? = nil
    var mindfulMinutes: Double? = nil
    var stateOfMindValence: Double? = nil
    var stateOfMindCount: Int? = nil
    var sleepMidpointMinutes: Double? = nil
    var sleepBedtimeMinutes: Double? = nil
    var awakeCount: Int? = nil
    var sleepStagesJSON: String? = nil
    var sleepOnsetAt: Date? = nil
    var sleepWakeAt: Date? = nil
    var sleepAvgHR: Double? = nil
    var sleepMinHR: Double? = nil
    var sleepMaxHR: Double? = nil
    var sleepAvgHRV: Double? = nil
    var sleepAvgResp: Double? = nil
    var sleepAvgSpo2: Double? = nil
    var environmentalNoiseDb: Double? = nil

    var bodyMassKg: Double? = nil
    var bodyFatPct: Double? = nil
    var leanBodyMassKg: Double? = nil
    var bmi: Double? = nil
    var waistCircumferenceCm: Double? = nil

    var systolicBP: Double? = nil
    var diastolicBP: Double? = nil
    var basalBodyTempC: Double? = nil
    var bloodGlucoseMgDl: Double? = nil

    // MARK: - 饮水与饮食（来自健康 App，本 App 回写的喝水样本已排除）
    /// 健康 App / 第三方 App 记录的喝水量（毫升），不含本 App 打卡回写的样本。
    var externalWaterMl: Double? = nil
    /// 本 App 当天喝水打卡累计（毫升），由 SyncCoordinator 合并时写入。
    var localWaterMl: Double? = nil
    /// 两侧合并后的当日总喝水量（毫升），评分与展示统一使用该值。
    var waterTotalMl: Double? = nil
    /// 膳食热量（千卡）。
    var dietaryEnergyKcal: Double? = nil
    /// 碳水化合物（克）。
    var dietaryCarbsG: Double? = nil
    /// 蛋白质（克）。
    var dietaryProteinG: Double? = nil
    /// 总脂肪（克）。
    var dietaryFatG: Double? = nil
    /// 膳食纤维（克）。
    var dietaryFiberG: Double? = nil
    /// 糖（克）。
    var dietarySugarG: Double? = nil
    /// 钠（毫克）。
    var dietarySodiumMg: Double? = nil
    /// 两侧合并后的当日咖啡因总量（毫克），评分与展示统一使用该值。
    var dietaryCaffeineMg: Double? = nil
    /// 健康 App / 第三方 App 记录的咖啡因（毫克），不含本 App 回写样本。
    var externalCaffeineMg: Double? = nil
    /// 本 App 当天咖啡因打卡累计（毫克），由 SyncCoordinator 合并时写入。
    var localCaffeineMg: Double? = nil
}
