import HealthKit

enum HealthKitTypes {
    static var hrv: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    static var hrvRMSSD: HKQuantityType? {
        if #available(iOS 27.0, *) {
            return HKQuantityType(.heartRateVariabilityRMSSD)
        }
        return nil
    }
    static var restingHeartRate: HKQuantityType { HKQuantityType(.restingHeartRate) }
    static var heartRate: HKQuantityType { HKQuantityType(.heartRate) }
    static var walkingHeartRate: HKQuantityType { HKQuantityType(.walkingHeartRateAverage) }
    static var respiratoryRate: HKQuantityType { HKQuantityType(.respiratoryRate) }
    static var oxygenSaturation: HKQuantityType { HKQuantityType(.oxygenSaturation) }
    static var wristTemperature: HKQuantityType { HKQuantityType(.appleSleepingWristTemperature) }
    static var stepCount: HKQuantityType { HKQuantityType(.stepCount) }
    /// 健身 App 活动圆环的官方数据源：系统按天合成的活动摘要（含用户设置的圆环目标）。
    /// 活动 / 锻炼 / 站立与官方圆环对齐必须用它，普通统计查询与圆环存在已知的口径差。
    static var activitySummary: HKActivitySummaryType { HKObjectType.activitySummaryType() }
    static var activeEnergy: HKQuantityType { HKQuantityType(.activeEnergyBurned) }
    /// Apple Watch 记录/估算的静息能量，即健康 App 里的「基础代谢」日累计值。
    static var basalEnergy: HKQuantityType { HKQuantityType(.basalEnergyBurned) }
    static var exerciseTime: HKQuantityType { HKQuantityType(.appleExerciseTime) }
    static var standTime: HKQuantityType { HKQuantityType(.appleStandTime) }
    static var sleepAnalysis: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    static var vo2Max: HKQuantityType { HKQuantityType(.vo2Max) }
    static var walkingSpeed: HKQuantityType { HKQuantityType(.walkingSpeed) }
    static var walkingStepLength: HKQuantityType { HKQuantityType(.walkingStepLength) }
    static var walkingAsymmetry: HKQuantityType { HKQuantityType(.walkingAsymmetryPercentage) }
    static var walkingSteadiness: HKQuantityType { HKQuantityType(.appleWalkingSteadiness) }
    static var flightsClimbed: HKQuantityType { HKQuantityType(.flightsClimbed) }
    static var distanceWalkingRunning: HKQuantityType { HKQuantityType(.distanceWalkingRunning) }

    static var timeInDaylight: HKQuantityType { HKQuantityType(.timeInDaylight) }
    static var environmentalAudioExposure: HKQuantityType { HKQuantityType(.environmentalAudioExposure) }
    static var mindfulSession: HKCategoryType { HKCategoryType(.mindfulSession) }
    static var stateOfMind: HKStateOfMindType { HKObjectType.stateOfMindType() }

    static var bodyMass: HKQuantityType { HKQuantityType(.bodyMass) }
    static var bodyFatPercentage: HKQuantityType { HKQuantityType(.bodyFatPercentage) }
    static var leanBodyMass: HKQuantityType { HKQuantityType(.leanBodyMass) }
    static var bodyMassIndex: HKQuantityType { HKQuantityType(.bodyMassIndex) }
    static var waistCircumference: HKQuantityType { HKQuantityType(.waistCircumference) }

    /// 个人特征（出生日期 / 性别）来自健康 App 的健康档案。
    /// 这类 HKCharacteristicType 不会弹系统授权界面，但必须先在
    /// requestAuthorization 的 read 集合里声明，否则 dateOfBirthComponents() /
    /// biologicalSex() 会抛 HKError.errorAuthorizationNotDetermined。
    static var dateOfBirth: HKCharacteristicType { HKCharacteristicType(.dateOfBirth) }
    static var biologicalSex: HKCharacteristicType { HKCharacteristicType(.biologicalSex) }
    static var characteristicTypes: Set<HKObjectType> { [dateOfBirth, biologicalSex] }

    /// 该错误的 localizedDescription 是英文 "Authorization is not determined"，
    /// 需要单独识别后转成中文提示，不能原样透出到界面。
    static func isAuthorizationNotDetermined(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == HKErrorDomain
            && nsError.code == HKError.errorAuthorizationNotDetermined.rawValue
    }

    static var bloodPressureSystolic: HKQuantityType { HKQuantityType(.bloodPressureSystolic) }
    static var bloodPressureDiastolic: HKQuantityType { HKQuantityType(.bloodPressureDiastolic) }
    static var bloodGlucose: HKQuantityType { HKQuantityType(.bloodGlucose) }

    // MARK: - 饮水与饮食
    /// 双向同步的喝水量类型：既从健康 App 读，也把本 App 打卡写回。
    static var dietaryWater: HKQuantityType { HKQuantityType(.dietaryWater) }
    static var dietaryEnergy: HKQuantityType { HKQuantityType(.dietaryEnergyConsumed) }
    static var dietaryCarbs: HKQuantityType { HKQuantityType(.dietaryCarbohydrates) }
    static var dietaryProtein: HKQuantityType { HKQuantityType(.dietaryProtein) }
    static var dietaryFat: HKQuantityType { HKQuantityType(.dietaryFatTotal) }
    static var dietaryFiber: HKQuantityType { HKQuantityType(.dietaryFiber) }
    static var dietarySugar: HKQuantityType { HKQuantityType(.dietarySugar) }
    static var dietarySodium: HKQuantityType { HKQuantityType(.dietarySodium) }
    static var dietaryCaffeine: HKQuantityType { HKQuantityType(.dietaryCaffeine) }

    /// 需要申请写入权限的类型：喝水、咖啡因、饮品附带的碳蛋脂，
    /// 以及食物识别写回的能量 / 膳食纤维 / 糖 / 钠。
    /// 一杯美式 / 拿铁会一次写入 4 类样本；一顿饭会一次写入 9 类样本
    ///（7 类膳食 + 水 + 咖啡因），缺任何一类写权限整批保存都会失败。
    static var writeTypes: Set<HKSampleType> {
        [
            dietaryWater, dietaryCaffeine,
            dietaryCarbs, dietaryProtein, dietaryFat,
            dietaryEnergy, dietaryFiber, dietarySugar, dietarySodium,
            // 感受记录回写健康 App 的「心理状态」（iOS 18+）。
            stateOfMind,
        ]
    }

    /// 食物识别写回需要的 7 类膳食样本类型（与 NutritionMetric 一一对应）。
    static var mealWriteTypes: [HKQuantityType] {
        [dietaryEnergy, dietaryCarbs, dietaryProtein, dietaryFat, dietaryFiber, dietarySugar, dietarySodium]
    }

    /// 一顿饭写回健康 App 的完整样本类型：7 类膳食营养 + 水 + 咖啡因。
    /// 饮食记录里匹配到的咖啡 / 饮料要把含水量与咖啡因一起带出去，
    /// 编辑或删除该条饮食记录时也按同一组类型重写 / 清理。
    static var mealSampleTypes: [HKQuantityType] {
        mealWriteTypes + [dietaryWater, dietaryCaffeine]
    }

    /// 膳食类型对应的读取 / 写回单位（千卡 / 毫升 / 克 / 毫克）。
    static func unit(for type: HKQuantityType) -> HKUnit {
        switch type {
        case dietaryEnergy: return .kilocalorie()
        case dietaryCarbs, dietaryProtein, dietaryFat, dietaryFiber, dietarySugar: return HealthKitTypes.gram
        case dietarySodium, dietaryCaffeine: return HealthKitTypes.milligram
        case dietaryWater: return HealthKitTypes.milliliter
        default: return HealthKitTypes.gram
        }
    }

    /// 饮水与饮食的读取单位（ml / kcal / g / mg）。
    static var milliliter: HKUnit { HKUnit.literUnit(with: .milli) }
    static var gram: HKUnit { HKUnit.gram() }
    static var milligram: HKUnit { HKUnit.gramUnit(with: .milli) }

    static var vo2MaxUnit: HKUnit {
        HKUnit.literUnit(with: .milli)
            .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
    }

    static var meterPerSecond: HKUnit {
        HKUnit.meter().unitDivided(by: HKUnit.second())
    }

    static var milligramsPerDeciliter: HKUnit {
        HKUnit.gramUnit(with: .milli).unitDivided(by: HKUnit.literUnit(with: .deci))
    }

    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            hrv, restingHeartRate, heartRate, walkingHeartRate,
            respiratoryRate, oxygenSaturation, wristTemperature,
            stepCount, activeEnergy, basalEnergy, exerciseTime, standTime,
            sleepAnalysis,
            vo2Max, walkingSpeed, walkingStepLength, walkingAsymmetry,
            walkingSteadiness, flightsClimbed, distanceWalkingRunning,
            timeInDaylight, mindfulSession, stateOfMind,
            environmentalAudioExposure,
            bodyMass, bodyFatPercentage, leanBodyMass, bodyMassIndex, waistCircumference,
            bloodPressureSystolic, bloodPressureDiastolic, bloodGlucose,
            dietaryWater, dietaryEnergy, dietaryCarbs, dietaryProtein, dietaryFat,
            dietaryFiber, dietarySugar, dietarySodium, dietaryCaffeine,
            activitySummary,
            HKObjectType.workoutType(),
        ]
        types.formUnion(characteristicTypes)
        if let hrvRMSSD {
            types.insert(hrvRMSSD)
        }
        return types
    }

    static var dailyAverageTypes: [(HKQuantityType, HKUnit)] {
        [
            (hrv, .secondUnit(with: .milli)),
            (restingHeartRate, .count().unitDivided(by: .minute())),
            (heartRate, .count().unitDivided(by: .minute())),
            (walkingHeartRate, .count().unitDivided(by: .minute())),
            (respiratoryRate, .count().unitDivided(by: .minute())),
            (oxygenSaturation, .percent()),
            (vo2Max, vo2MaxUnit),
            (walkingSpeed, meterPerSecond),
            (walkingStepLength, .meter()),
            (walkingAsymmetry, .percent()),
            (walkingSteadiness, .percent()),
            (environmentalAudioExposure, .decibelAWeightedSoundPressureLevel()),
            (bodyMass, .gramUnit(with: .kilo)),
            (bodyFatPercentage, .percent()),
            (leanBodyMass, .gramUnit(with: .kilo)),
            (bodyMassIndex, .count()),
            (waistCircumference, .meter()),
            (bloodPressureSystolic, .millimeterOfMercury()),
            (bloodPressureDiastolic, .millimeterOfMercury()),
            (bloodGlucose, milligramsPerDeciliter),
        ]
    }

    static var dailySumTypes: [(HKQuantityType, HKUnit)] {
        [
            (stepCount, .count()),
            (activeEnergy, .kilocalorie()),
            (basalEnergy, .kilocalorie()),
            (exerciseTime, .minute()),
            (standTime, .minute()),
            (flightsClimbed, .count()),
            (distanceWalkingRunning, .meter()),
            (timeInDaylight, .minute()),
        ]
    }
}

/// 逐类型读取的饮水/饮食指标。这里用样本遍历而不是 HKStatisticsCollectionQuery：
/// 喝水必须按 sample.sourceRevision 排除本 App 回写的样本，统计查询无法在结果里
/// 反查单条来源，样本遍历才能保证两侧不重复计数。
enum NutritionMetric: CaseIterable, Sendable {
    case water
    case energy
    case carbs
    case protein
    case fat
    case fiber
    case sugar
    case sodium
    case caffeine

    var type: HKQuantityType {
        switch self {
        case .water: return HealthKitTypes.dietaryWater
        case .energy: return HealthKitTypes.dietaryEnergy
        case .carbs: return HealthKitTypes.dietaryCarbs
        case .protein: return HealthKitTypes.dietaryProtein
        case .fat: return HealthKitTypes.dietaryFat
        case .fiber: return HealthKitTypes.dietaryFiber
        case .sugar: return HealthKitTypes.dietarySugar
        case .sodium: return HealthKitTypes.dietarySodium
        case .caffeine: return HealthKitTypes.dietaryCaffeine
        }
    }

    var unit: HKUnit {
        switch self {
        case .water: return HealthKitTypes.milliliter
        case .energy: return .kilocalorie()
        case .carbs, .protein, .fat, .fiber, .sugar: return HealthKitTypes.gram
        case .sodium, .caffeine: return HealthKitTypes.milligram
        }
    }

    /// 把一条样本的值累加到当日汇总。
    func add(_ value: Double, to day: inout NutritionDay) {
        func accumulate(_ path: WritableKeyPath<NutritionDay, Double?>) {
            day[keyPath: path] = (day[keyPath: path] ?? 0) + value
        }
        switch self {
        case .water: accumulate(\.externalWaterMl)
        case .energy: accumulate(\.energyKcal)
        case .carbs: accumulate(\.carbsG)
        case .protein: accumulate(\.proteinG)
        case .fat: accumulate(\.fatG)
        case .fiber: accumulate(\.fiberG)
        case .sugar: accumulate(\.sugarG)
        case .sodium: accumulate(\.sodiumMg)
        case .caffeine: accumulate(\.caffeineMg)
        }
    }
}
