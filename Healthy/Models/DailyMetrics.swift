import Foundation
import SwiftData

@Model
final class DailyMetrics {
    @Attribute(.unique) var dayKey: String
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
    /// 健康 App 的静息能量当日累计（千卡），用于「健康」页基础代谢。
    var basalEnergyKcal: Double?
    var exerciseMinutes: Double?
    var standMinutes: Double?
    /// 健身 App 当天活动圆环目标（千卡），来自 HKActivitySummary；nil 用 500 常量回退。
    var activeEnergyGoal: Double?
    /// 健身 App 当天锻炼圆环目标（分钟），nil 用 30 常量回退。
    var exerciseGoalMinutes: Double?
    /// 健身 App 当天站立圆环目标（小时），nil 用 12 常量回退。
    var standGoalHours: Double?
    var workoutCount: Int?
    var workoutMinutes: Double?
    /// 近 7 日 workouts 心率区间累计分钟（Z1–Z5）的 JSON 编码，缺数据为 nil。
    var workoutZoneMinutesJSON: String?
    var sourceFlags: Int
    var updatedAt: Date

    var vo2Max: Double?
    var walkingSpeedMps: Double?
    var walkingStepLengthCm: Double?
    var walkingAsymmetryPct: Double?
    var walkingSteadinessPct: Double?
    var flightsClimbed: Double?
    var distanceWalkingKm: Double?

    var daylightMinutes: Double?
    var mindfulMinutes: Double?
    var stateOfMindValence: Double?
    var stateOfMindCount: Int?
    var sleepMidpointMinutes: Double?
    var sleepBedtimeMinutes: Double?
    var awakeCount: Int?
    var sleepStagesJSON: String?
    var sleepOnsetAt: Date?
    var sleepWakeAt: Date?
    var sleepAvgHR: Double?
    var sleepMinHR: Double?
    var sleepMaxHR: Double?
    var sleepAvgHRV: Double?
    var sleepAvgResp: Double?
    var sleepAvgSpo2: Double?
    var environmentalNoiseDb: Double?

    var bodyMassKg: Double?
    var bodyFatPct: Double?
    var leanBodyMassKg: Double?
    var bmi: Double?
    var waistCircumferenceCm: Double?

    var systolicBP: Double?
    var diastolicBP: Double?
    var basalBodyTempC: Double?
    var bloodGlucoseMgDl: Double?

    /// 健康 App / 第三方 App 记录的喝水量（毫升），不含本 App 回写的样本。
    var externalWaterMl: Double?
    /// 本 App 当天喝水打卡累计（毫升）。
    var localWaterMl: Double?
    /// 两侧合并后的当日总喝水量（毫升）。
    var waterTotalMl: Double?
    /// 膳食热量（千卡）。
    var dietaryEnergyKcal: Double?
    /// 碳水化合物（克）。
    var dietaryCarbsG: Double?
    /// 蛋白质（克）。
    var dietaryProteinG: Double?
    /// 总脂肪（克）。
    var dietaryFatG: Double?
    /// 膳食纤维（克）。
    var dietaryFiberG: Double?
    /// 糖（克）。
    var dietarySugarG: Double?
    /// 钠（毫克）。
    var dietarySodiumMg: Double?
    /// 两侧合并后的当日咖啡因总量（毫克）。
    var dietaryCaffeineMg: Double?
    /// 健康 App 同步来的外部咖啡因（毫克）。
    var externalCaffeineMg: Double?
    /// 本 App 咖啡因打卡累计（毫克）。
    var localCaffeineMg: Double?

    /// 本 App 食物识别打卡累计的膳食营养（当天）。写回健康 App 的 7 类样本也在本地合并，
    /// 保证评分 / AI / 展示读到的是合并后的总量；删除打卡后重新合并会清掉本地量。
    var localMealEnergyKcal: Double?
    var localMealCarbsG: Double?
    var localMealProteinG: Double?
    var localMealFatG: Double?
    var localMealFiberG: Double?
    var localMealSugarG: Double?
    var localMealSodiumMg: Double?

    /// 当日规律饮食评分（0–100）。由 WaterMerge 依据本 App 的餐次打卡计算；
    /// 没有任何饮食记录时为 nil，评分层会自动跳过该维度，不影响既有分值。
    var mealRegularityScore: Double?
    /// 当日所有餐次健康评分的平均值（0–100），用于分组卡与详情页展示。
    var mealAverageScore: Double?
    /// 当日饮食打卡条数。
    var mealCount: Int?
    /// 当日覆盖到的主餐数（早餐/午餐/晚餐，0–3）。
    var mealCoveredMainMeals: Int?

    init(dayKey: String, date: Date) {
        self.dayKey = dayKey
        self.date = date
        self.sourceFlags = 0
        self.updatedAt = .now
    }

    /// 解码当日训练心率区间（Z1–Z5 分钟），无 JSON 或解码失败时为 nil。
    var workoutZones: WorkoutZoneMinutes? {
        guard let json = workoutZoneMinutesJSON, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(WorkoutZoneMinutes.self, from: data)
    }

    func apply(_ dto: DailyMetricsDTO) {
        dayKey = dto.dayKey
        date = dto.date
        hrvSDNN = dto.hrvSDNN
        hrvLatest = dto.hrvLatest
        hrvLatestAt = dto.hrvLatestAt
        restingHR = dto.restingHR
        avgHR = dto.avgHR
        walkingHR = dto.walkingHR
        respiratoryRate = dto.respiratoryRate
        spo2 = dto.spo2
        wristTempC = dto.wristTempC
        sleepTotalH = dto.sleepTotalH
        deepH = dto.deepH
        remH = dto.remH
        coreH = dto.coreH
        awakeH = dto.awakeH
        inBedH = dto.inBedH
        sleepEfficiency = dto.sleepEfficiency
        steps = dto.steps
        activeEnergy = dto.activeEnergy
        basalEnergyKcal = dto.basalEnergyKcal
        exerciseMinutes = dto.exerciseMinutes
        standMinutes = dto.standMinutes
        activeEnergyGoal = dto.activeEnergyGoal
        exerciseGoalMinutes = dto.exerciseGoalMinutes
        standGoalHours = dto.standGoalHours
        workoutCount = dto.workoutCount
        workoutMinutes = dto.workoutMinutes
        workoutZoneMinutesJSON = dto.workoutZoneMinutesJSON
        sourceFlags = dto.sourceFlags

        vo2Max = dto.vo2Max
        walkingSpeedMps = dto.walkingSpeedMps
        walkingStepLengthCm = dto.walkingStepLengthCm
        walkingAsymmetryPct = dto.walkingAsymmetryPct
        walkingSteadinessPct = dto.walkingSteadinessPct
        flightsClimbed = dto.flightsClimbed
        distanceWalkingKm = dto.distanceWalkingKm

        daylightMinutes = dto.daylightMinutes
        mindfulMinutes = dto.mindfulMinutes
        stateOfMindValence = dto.stateOfMindValence
        stateOfMindCount = dto.stateOfMindCount
        sleepMidpointMinutes = dto.sleepMidpointMinutes
        sleepBedtimeMinutes = dto.sleepBedtimeMinutes
        awakeCount = dto.awakeCount
        sleepStagesJSON = dto.sleepStagesJSON
        sleepOnsetAt = dto.sleepOnsetAt
        sleepWakeAt = dto.sleepWakeAt
        sleepAvgHR = dto.sleepAvgHR
        sleepMinHR = dto.sleepMinHR
        sleepMaxHR = dto.sleepMaxHR
        sleepAvgHRV = dto.sleepAvgHRV
        sleepAvgResp = dto.sleepAvgResp
        sleepAvgSpo2 = dto.sleepAvgSpo2
        environmentalNoiseDb = dto.environmentalNoiseDb

        bodyMassKg = dto.bodyMassKg
        bodyFatPct = dto.bodyFatPct
        leanBodyMassKg = dto.leanBodyMassKg
        bmi = dto.bmi
        waistCircumferenceCm = dto.waistCircumferenceCm

        systolicBP = dto.systolicBP
        diastolicBP = dto.diastolicBP
        basalBodyTempC = dto.basalBodyTempC
        bloodGlucoseMgDl = dto.bloodGlucoseMgDl

        externalWaterMl = dto.externalWaterMl
        // 本地打卡量由 SyncCoordinator 在 apply 之后重新合并，DTO 中始终为 nil。
        localWaterMl = dto.localWaterMl
        waterTotalMl = dto.waterTotalMl
        dietaryEnergyKcal = dto.dietaryEnergyKcal
        dietaryCarbsG = dto.dietaryCarbsG
        dietaryProteinG = dto.dietaryProteinG
        dietaryFatG = dto.dietaryFatG
        dietaryFiberG = dto.dietaryFiberG
        dietarySugarG = dto.dietarySugarG
        dietarySodiumMg = dto.dietarySodiumMg
        dietaryCaffeineMg = dto.dietaryCaffeineMg
        externalCaffeineMg = dto.externalCaffeineMg
        localCaffeineMg = dto.localCaffeineMg

        updatedAt = .now
    }

    /// 同步把「纯外部营养量」写入 dietary* 后调用：清掉上一轮本地 meal 快照。
    /// WaterMerge 用「存储值 − 上一轮本地量 + 本轮本地量」重算总量，若不清理，
    /// 外部量会被再扣一次，本 App 食物打卡的热量可能被抵消成 0。
    func clearLocalMealSnapshot() {
        localMealEnergyKcal = nil
        localMealCarbsG = nil
        localMealProteinG = nil
        localMealFatG = nil
        localMealFiberG = nil
        localMealSugarG = nil
        localMealSodiumMg = nil
    }

    var snapshot: DailySnapshot {
        DailySnapshot(
            dayKey: dayKey,
            date: date,
            hrvSDNN: hrvSDNN,
            restingHR: restingHR,
            respiratoryRate: respiratoryRate,
            spo2: spo2,
            wristTempC: wristTempC,
            sleepTotalH: sleepTotalH,
            sleepEfficiency: sleepEfficiency,
            deepH: deepH,
            remH: remH,
            steps: steps,
            activeEnergy: activeEnergy,
            basalEnergyKcal: basalEnergyKcal,
            exerciseMinutes: exerciseMinutes,
            workoutZoneMinutes: workoutZones?.minutes,
            avgHR: avgHR,
            vo2Max: vo2Max,
            walkingSpeedMps: walkingSpeedMps,
            walkingStepLengthCm: walkingStepLengthCm,
            walkingAsymmetryPct: walkingAsymmetryPct,
            walkingSteadinessPct: walkingSteadinessPct,
            flightsClimbed: flightsClimbed,
            distanceWalkingKm: distanceWalkingKm,
            daylightMinutes: daylightMinutes,
            mindfulMinutes: mindfulMinutes,
            stateOfMindValence: stateOfMindValence,
            sleepMidpointMinutes: sleepMidpointMinutes,
            sleepBedtimeMinutes: sleepBedtimeMinutes,
            awakeCount: awakeCount,
            sleepStagesJSON: sleepStagesJSON,
            sleepOnsetAt: sleepOnsetAt,
            sleepWakeAt: sleepWakeAt,
            sleepAvgHR: sleepAvgHR,
            sleepMinHR: sleepMinHR,
            sleepMaxHR: sleepMaxHR,
            sleepAvgHRV: sleepAvgHRV,
            sleepAvgResp: sleepAvgResp,
            sleepAvgSpo2: sleepAvgSpo2,
            environmentalNoiseDb: environmentalNoiseDb,
            bodyMassKg: bodyMassKg,
            bodyFatPct: bodyFatPct,
            leanBodyMassKg: leanBodyMassKg,
            bmi: bmi,
            waistCircumferenceCm: waistCircumferenceCm,
            systolicBP: systolicBP,
            diastolicBP: diastolicBP,
            basalBodyTempC: basalBodyTempC,
            bloodGlucoseMgDl: bloodGlucoseMgDl,
            externalWaterMl: externalWaterMl,
            localWaterMl: localWaterMl,
            waterTotalMl: waterTotalMl,
            dietaryEnergyKcal: dietaryEnergyKcal,
            dietaryCarbsG: dietaryCarbsG,
            dietaryProteinG: dietaryProteinG,
            dietaryFatG: dietaryFatG,
            dietaryFiberG: dietaryFiberG,
            dietarySugarG: dietarySugarG,
            dietarySodiumMg: dietarySodiumMg,
            dietaryCaffeineMg: dietaryCaffeineMg,
            externalCaffeineMg: externalCaffeineMg,
            localCaffeineMg: localCaffeineMg,
            mealRegularityScore: mealRegularityScore,
            mealAverageScore: mealAverageScore,
            mealCount: mealCount,
            mealCoveredMainMeals: mealCoveredMainMeals
        )
    }
}
