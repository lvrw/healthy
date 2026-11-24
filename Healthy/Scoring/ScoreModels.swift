import Foundation

struct DailySnapshot: Sendable, Equatable {
    var dayKey: String
    var date: Date
    var hrvSDNN: Double? = nil
    var restingHR: Double? = nil
    var respiratoryRate: Double? = nil
    var spo2: Double? = nil
    var wristTempC: Double? = nil
    var sleepTotalH: Double? = nil
    var sleepEfficiency: Double? = nil
    var deepH: Double? = nil
    var remH: Double? = nil
    var steps: Double? = nil
    var activeEnergy: Double? = nil
    /// 健康 App 的静息能量当日累计（千卡）。
    var basalEnergyKcal: Double? = nil
    var exerciseMinutes: Double? = nil
    /// 近 7 日 workouts 心率区间累计分钟（Z1–Z5），由 HealthKit 心率采样折算；缺失为 nil。
    var workoutZoneMinutes: [Double]? = nil
    var avgHR: Double? = nil

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

    /// 健康 App 同步来的外部喝水量（毫升）。
    var externalWaterMl: Double? = nil
    /// 本 App 喝水打卡累计（毫升）。
    var localWaterMl: Double? = nil
    /// 两侧合并后的当日总喝水量（毫升）。
    var waterTotalMl: Double? = nil
    /// 以下饮食指标均由 HealthKit 按日累计，单位分别为千卡 / 克 / 毫克。
    var dietaryEnergyKcal: Double? = nil
    var dietaryCarbsG: Double? = nil
    var dietaryProteinG: Double? = nil
    var dietaryFatG: Double? = nil
    var dietaryFiberG: Double? = nil
    var dietarySugarG: Double? = nil
    var dietarySodiumMg: Double? = nil
    /// 两侧合并后的当日咖啡因总量（毫克）。
    var dietaryCaffeineMg: Double? = nil
    /// 健康 App 同步来的外部咖啡因（毫克）。
    var externalCaffeineMg: Double? = nil
    /// 本 App 咖啡因打卡累计（毫克）。
    var localCaffeineMg: Double? = nil

    /// 当日规律饮食评分（0–100）；无饮食打卡时为 nil。
    var mealRegularityScore: Double? = nil
    /// 当日各餐健康评分平均值（0–100）；仅用于展示。
    var mealAverageScore: Double? = nil
    /// 当日饮食打卡条数。
    var mealCount: Int? = nil
    /// 当日覆盖到的主餐数（0–3）。
    var mealCoveredMainMeals: Int? = nil
}

struct BaselineStats: Sendable, Equatable {
    var mean: Double
    var sd: Double
    var count: Int
}

struct BaselineResult: Sendable, Equatable {
    var hrvLog: BaselineStats?
    var restingHR: BaselineStats?
    var averageHeartRate: BaselineStats?
    var wristTempC: BaselineStats?
    var respiratoryRate: BaselineStats?
    var spo2: BaselineStats?
    var vo2Max: BaselineStats?
    var walkingSpeed: BaselineStats?
    var walkingSteadiness: BaselineStats?
    var systolicBP: BaselineStats?
    var diastolicBP: BaselineStats?
    var basalBodyTemp: BaselineStats?
    var bloodGlucose: BaselineStats?
    var baselineDays: Int

    func zScore(_ value: Double, stats: BaselineStats?) -> Double? {
        guard let stats else { return nil }
        return (value - stats.mean) / stats.sd
    }

    func zHRV(_ value: Double) -> Double? {
        guard let stats = hrvLog else { return nil }
        return (log(value + 1) - stats.mean) / stats.sd
    }
}

struct ReadinessComponents: Sendable, Codable, Equatable {
    var sleep: Double?
    var autonomic: Double?
    var load: Double?
    var vitals: Double?
    var circadian: Double? = nil
    var fitnessBody: Double? = nil
    /// 饮水与饮食分量；无数据时为 nil，历史 JSON 里缺字段也能正常解码。
    var nutrition: Double? = nil
    /// 规律饮食分量；只有本 App 记录过饮食时才有值，历史 JSON 缺字段自动解码为 nil。
    var mealRegularity: Double? = nil
    /// 身体成分分组卡的展示分（仅展示，不并入综合评分加权）。
    var bodyComposition: Double? = nil
}

struct StressComponents: Sendable, Codable, Equatable {
    var hrv: Double?
    var restingHR: Double?
    var sleep: Double?
    var vitals: Double?
    var circadian: Double? = nil
    var mood: Double? = nil
}

enum ScoreConfidence: String, Sendable, Codable {
    case full
    case low
    case insufficient
}

enum StressLevel: String, Sendable, Codable, CaseIterable {
    case low
    case moderateLow
    case elevated
    case high

    var label: String {
        switch self {
        case .low: return "低"
        case .moderateLow: return "中低"
        case .elevated: return "偏高"
        case .high: return "高"
        }
    }
}

/// 评分项被跳过的原因。
enum ScoreSkipReason: String, Sendable, Codable, Equatable {
    /// 系统根据当天原始读数判断该项数据不全。
    case incomplete
    /// 用户手动把该项标记为不全。
    case manual
}

/// 被跳过的评分项及其原因。用于评分结果中明确标识「不全 / 已跳过」。
struct SourceSkip: Sendable, Codable, Equatable {
    /// 被跳过的数据类别。
    var source: MetricSource
    /// 跳过原因。
    var reason: ScoreSkipReason

    /// 供 UI 展示的短文案。系统判定用「数据不全」，手动标记额外强调「已跳过」。
    var displayText: String {
        switch reason {
        case .incomplete: return "\(source.label)数据不全"
        case .manual: return "\(source.label)已标记不全，已跳过"
        }
    }
}

struct ReadinessResult: Sendable, Equatable {
    var score: Double?
    var components: ReadinessComponents
    var completeness: Int
    var missing: [MetricSource]
    var confidence: ScoreConfidence
    var baselineDays: Int
    /// 被跳过的评分项（系统判定不全 + 用户手动标记），带原因。
    var skipped: [SourceSkip] = []
}

struct StressResult: Sendable, Equatable {
    var score: Double?
    var level: StressLevel?
    var components: StressComponents
    var completeness: Int
    var missing: [MetricSource]
    var confidence: ScoreConfidence
    var baselineDays: Int
    /// 被跳过的评分项（系统判定不全 + 用户手动标记），带原因。
    var skipped: [SourceSkip] = []
}
