import HealthKit

/// watchOS 端使用到的 HealthKit 类型与单位，是 iOS 端 HealthKitTypes 的子集。
enum WatchHealthTypes {
    static var hrv: HKQuantityType { HKQuantityType(.heartRateVariabilitySDNN) }
    static var heartRate: HKQuantityType { HKQuantityType(.heartRate) }
    static var dietaryWater: HKQuantityType { HKQuantityType(.dietaryWater) }
    static var dietaryCaffeine: HKQuantityType { HKQuantityType(.dietaryCaffeine) }

    static var milliliter: HKUnit { HKUnit.literUnit(with: .milli) }
    static var milligram: HKUnit { HKUnit.gramUnit(with: .milli) }
    /// HRV(SDNN) 在 HealthKit 中以秒存储，读取时换算为毫秒展示。
    static var hrvUnit: HKUnit { HKUnit.secondUnit(with: .milli) }

    static var readTypes: Set<HKObjectType> {
        [hrv, heartRate, dietaryWater, dietaryCaffeine]
    }

    static var writeTypes: Set<HKSampleType> {
        [dietaryWater, dietaryCaffeine]
    }
}
