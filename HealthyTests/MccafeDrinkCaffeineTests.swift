import Testing
@testable import Healthy

/// 饮食记录里的麦咖啡必须同时记录水与咖啡因（此前只补了水，咖啡因为 0）。
struct MccafeDrinkCaffeineTests {
    private func item(_ name: String, amount: Double = 340, water: Double = 300) -> MealItem {
        MealItem(
            name: name,
            portionAmount: amount,
            portionUnit: "ml",
            perPortion: IntakeNutrition(
                energyKcal: 148, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 77, waterMl: water
            )
        )
    }

    @Test("麦咖啡估算与打卡页口径一致：奶铁按杯型、无咖啡饮品为 0")
    func dedicatedEstimate() {
        #expect(MccafeCaffeineEstimate.estimatedMg(for: "冰奶铁（小）") == 75)
        #expect(MccafeCaffeineEstimate.estimatedMg(for: "冰奶铁（中）") == 110)
        #expect(MccafeCaffeineEstimate.estimatedMg(for: "热奶铁（大）") == 150)
        #expect(MccafeCaffeineEstimate.estimatedMg(for: "鲜萃咖啡") == 110)
        #expect(MccafeCaffeineEstimate.estimatedMg(for: "抹茶阿芙佳朵") == 15)
        #expect(MccafeCaffeineEstimate.estimatedMg(for: "冰牛奶（中）") == 0)
    }

    @Test("饮食记录补齐：奶铁同时保留水并补上咖啡因")
    func fillsBothWaterAndCaffeine() {
        let filled = DrinkIntakeEstimator.applying(to: item("冰奶铁（中）"))
        #expect(filled.perPortion.waterMl == 300)
        #expect(filled.perPortion.caffeineMg == 110)
    }

    @Test("饮食记录补齐：其它麦咖啡专属命名也能补咖啡因")
    func fillsOtherExclusiveNames() {
        #expect(DrinkIntakeEstimator.applying(to: item("鲜萃咖啡")).perPortion.caffeineMg == 110)
        // 与打卡页现有口径一致：抹茶判断优先于雪冰，给 60mg。
        #expect(DrinkIntakeEstimator.applying(to: item("浓浓抹茶雪冰（大）")).perPortion.caffeineMg == 60)
        #expect(DrinkIntakeEstimator.applying(to: item("咖啡阿芙佳朵")).perPortion.caffeineMg == 45)
    }

    @Test("已有真实咖啡因不被估算覆盖")
    func keepsExistingCaffeine() {
        var original = item("冰奶铁（中）")
        original.perPortion.caffeineMg = 95
        #expect(DrinkIntakeEstimator.applying(to: original).perPortion.caffeineMg == 95)
    }

    @Test("无咖啡因饮品不会凭空产生咖啡因")
    func milkStaysDecaf() {
        #expect(DrinkIntakeEstimator.applying(to: item("冰牛奶（中）")).perPortion.caffeineMg == 0)
    }

    @Test("本地营养库识别麦咖啡时，识别结果里已带水与咖啡因")
    func localRecognitionFillsMccafe() throws {
        // FoodDatabase.all 已清空，内置库由 FoodSeed 安装为 FoodGroup；这里直接构造同形态的食物。
        let food = FoodItem(
            id: "mcd.287.330", name: "冰奶铁（中）", keywords: ["冰奶铁", "奶铁", "拿铁"],
            portion: "1 杯（中） / 340ml",
            nutrition: IntakeNutrition(
                energyKcal: 148, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 77, waterMl: 300
            ),
            imageURL: nil
        )
        let meal = FoodRecognitionService.recognizeLocal(text: "冰奶铁", custom: [food])
        let latte = try #require(meal.items.first { $0.name.contains("奶铁") })
        #expect(latte.perPortion.waterMl == 300)
        #expect(latte.perPortion.caffeineMg == 110)
    }
}
