import Foundation
import Testing

/// 膳食对账口径回归：水与咖啡因必须参与「是否一致」的判断。
/// 否则编辑一条饮食记录只改了饮品容量 / 咖啡因时，健康 App 侧不会重写。
struct MealSyncWaterTests {
    private var date: Date {
        Date(timeIntervalSince1970: 1_763_000_000)
    }

    private func record(
        waterMl: Double = 405,
        caffeineMg: Double = 89.1,
        energyKcal: Double = 105,
        date: Date? = nil
    ) -> MealSyncRecord {
        MealSyncRecord(
            syncID: "meal-1",
            date: date ?? self.date,
            nutrition: IntakeNutrition(energyKcal: energyKcal, waterMl: waterMl, caffeineMg: caffeineMg)
        )
    }

    private func sample(
        waterMl: Double = 405,
        caffeineMg: Double = 89.1,
        energyKcal: Double = 105,
        date: Date? = nil
    ) -> MealSyncSample {
        MealSyncSample(
            syncID: "meal-1",
            uuids: ["u1"],
            date: date ?? self.date,
            nutrition: IntakeNutrition(energyKcal: energyKcal, waterMl: waterMl, caffeineMg: caffeineMg),
            syncVersion: 1
        )
    }

    @Test("九项一致时判定为相同")
    func identicalValuesMatch() {
        #expect(MealSyncReconciler.matches(sample(), record()))
    }

    @Test("只改水量也判定为不一致，需要重写健康 App")
    func waterChangeBreaksMatch() {
        #expect(!MealSyncReconciler.matches(sample(waterMl: 405), record(waterMl: 450)))
    }

    @Test("只改咖啡因也判定为不一致")
    func caffeineChangeBreaksMatch() {
        #expect(!MealSyncReconciler.matches(sample(caffeineMg: 89.1), record(caffeineMg: 164.3)))
    }

    @Test("水量 5ml / 咖啡因 1mg 以内按一致处理")
    func smallToleranceIsAccepted() {
        #expect(MealSyncReconciler.matches(sample(waterMl: 405, caffeineMg: 89.1),
                                            record(waterMl: 409, caffeineMg: 90)))
    }
}
