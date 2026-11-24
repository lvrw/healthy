import Testing
import Foundation

/// 饮品水量 / 咖啡因兜底估算的回归测试。
/// 对应需求：饮食记录里匹配到咖啡和饮料时，要把水和咖啡因一并记录。
@Suite("DrinkIntakeEstimator 饮品水量与咖啡因估算")
struct DrinkIntakeEstimatorTests {

    /// 构造一样带份量的食物，营养默认全 0（模拟营养库里饮品只登记热量、水与咖啡因缺省的情况）。
    private func item(
        _ name: String,
        _ amount: Double,
        unit: String,
        waterMl: Double = 0,
        caffeineMg: Double = 0
    ) -> MealItem {
        MealItem(
            name: name,
            portionAmount: amount,
            portionUnit: unit,
            perPortion: IntakeNutrition(waterMl: waterMl, caffeineMg: caffeineMg)
        )
    }

    @Test("可乐按容量折算 90% 水量并按 0.10mg/ml 估算咖啡因")
    func colaEstimatesWaterAndCaffeine() {
        let cola = item("可口可乐（中）", 443, unit: "ml")
        #expect(DrinkIntakeEstimator.waterMl(for: cola) == 399) // 443 × 0.9 = 398.7 → 399
        #expect(DrinkIntakeEstimator.caffeineMg(for: cola) == 39.9) // 399 × 0.10
    }

    @Test("拿铁按 0.22mg/ml 估算咖啡因，水量取容量九成")
    func latteCaffeineProfile() {
        let latte = item("生椰拿铁", 450, unit: "ml")
        #expect(DrinkIntakeEstimator.waterMl(for: latte) == 405)
        #expect(DrinkIntakeEstimator.caffeineMg(for: latte) == 89.1)
    }

    @Test("美式咖啡因系数高于拿铁")
    func americanoHasHigherCaffeine() {
        let americano = item("冰美式", 450, unit: "ml")
        let latte = item("拿铁", 450, unit: "ml")
        #expect(DrinkIntakeEstimator.caffeineMg(for: americano)
                > DrinkIntakeEstimator.caffeineMg(for: latte))
    }

    @Test("纯水按 100% 容量补水且不含咖啡因")
    func plainWaterCountsFullVolume() {
        let water = item("农夫山泉", 550, unit: "ml")
        #expect(DrinkIntakeEstimator.waterMl(for: water) == 550)
        #expect(DrinkIntakeEstimator.caffeineMg(for: water) == 0)
    }

    @Test("果汁补水但不含咖啡因")
    func juiceHasWaterWithoutCaffeine() {
        let juice = item("美汁源100%苹果汁", 200, unit: "ml")
        #expect(DrinkIntakeEstimator.waterMl(for: juice) == 180)
        #expect(DrinkIntakeEstimator.caffeineMg(for: juice) == 0)
    }

    @Test("标注无咖啡因的饮品不再估算咖啡因")
    func decafHasNoCaffeine() {
        let decaf = item("无咖啡因拿铁", 300, unit: "ml")
        #expect(DrinkIntakeEstimator.caffeineMg(for: decaf) == 0)
        #expect(DrinkIntakeEstimator.waterMl(for: decaf) == 270)
    }

    @Test("固体食物不折算水量，菜名里的「水」不算饮品")
    func solidFoodHasNoWater() {
        #expect(DrinkIntakeEstimator.waterMl(for: item("水煮鱼", 300, unit: "g")) == 0)
        #expect(DrinkIntakeEstimator.waterMl(for: item("米饭", 150, unit: "g")) == 0)
        #expect(DrinkIntakeEstimator.caffeineMg(for: item("米饭", 150, unit: "g")) == 0)
    }

    @Test("浓缩咖啡等小容量配料不折算成一杯水")
    func espressoShotIsNotACupOfWater() {
        let shot = item("浓缩咖啡液", 30, unit: "ml")
        #expect(DrinkIntakeEstimator.waterMl(for: shot) == 0)
        #expect(DrinkIntakeEstimator.caffeineMg(for: shot) == 0)
    }

    @Test("已有真实水量 / 咖啡因的条目不被估算覆盖")
    func existingValuesArePreserved() {
        let luckin = item("标准美式", 450, unit: "ml", waterMl: 450, caffeineMg: 164.3)
        let filled = DrinkIntakeEstimator.applying(to: luckin)
        #expect(filled.perPortion.waterMl == 450)
        #expect(filled.perPortion.caffeineMg == 164.3)
    }

    @Test("只补空缺字段：有水量缺咖啡因时只补咖啡因")
    func fillsOnlyMissingField() {
        let partial = item("拿铁", 450, unit: "ml", waterMl: 400)
        let filled = DrinkIntakeEstimator.applying(to: partial)
        #expect(filled.perPortion.waterMl == 400)
        #expect(filled.perPortion.caffeineMg == 88) // 400 × 0.22
    }

    // MARK: - 营养库匹配 → 估算

    @Test("营养库匹配到的可乐经估算后带上水量与咖啡因")
    func matchedLibraryDrinkIsFilled() throws {
        // 模拟营养库里的可乐条目：只有热量 / 碳水 / 钠，水与咖啡因缺省为 0。
        let libraryCola = FoodItem(
            id: "mcd.cola.mid",
            name: "可口可乐（中）",
            keywords: ["可口可乐", "可乐"],
            portion: "1 杯（中） / 443ml",
            nutrition: IntakeNutrition(energyKcal: 147, carbsG: 36)
        )
        let matched = FoodDatabase.match("一瓶可乐", custom: [libraryCola])
        let food = try #require(matched.first)
        let portion = FoodDatabase.parsePortion(from: food.portion)
        #expect(portion.amount == 443)

        let items = DrinkIntakeEstimator.applying(to: [
            MealItem(
                name: food.name, portionAmount: portion.amount,
                portionUnit: portion.unit, perPortion: food.nutrition
            )
        ])
        #expect(items[0].perPortion.waterMl == 399)
        #expect(items[0].perPortion.caffeineMg == 39.9)
    }

    @Test("营养库匹配到的固体食物不会被补水量")
    func matchedSolidFoodKeepsZeroWater() throws {
        let libraryBurger = FoodItem(
            id: "mcd.burger",
            name: "汉堡包",
            keywords: ["汉堡包", "汉堡"],
            portion: "1 个 / 104g",
            nutrition: IntakeNutrition(energyKcal: 248, carbsG: 29)
        )
        let matched = FoodDatabase.match("一个汉堡", custom: [libraryBurger])
        let food = try #require(matched.first)
        let portion = FoodDatabase.parsePortion(from: food.portion)
        let items = DrinkIntakeEstimator.applying(to: [
            MealItem(
                name: food.name, portionAmount: portion.amount,
                portionUnit: portion.unit, perPortion: food.nutrition
            )
        ])
        #expect(items[0].perPortion.waterMl == 0)
        #expect(items[0].perPortion.caffeineMg == 0)
    }

    // MARK: - 只统计单独饮用的水

    @Test("按克记的饭菜即使名字含饮品词也不补水")
    func solidFoodWithDrinkKeywordDoesNotCountAsWater() {
        let cake = item("咖啡蛋糕", 120, unit: "g")
        #expect(DrinkIntakeEstimator.isDrink(cake) == false)
        #expect(DrinkIntakeEstimator.waterMl(for: cake) == 0)
        #expect(DrinkIntakeEstimator.applying(to: cake).perPortion.waterMl == 0)

        #expect(DrinkIntakeEstimator.waterMl(for: item("茶叶蛋", 60, unit: "g")) == 0)
        #expect(DrinkIntakeEstimator.waterMl(for: item("红酒炖牛肉", 250, unit: "g")) == 0)
    }

    @Test("食物营养里残留的含水量归零，不为食物水创建额外条目")
    func foodBorneWaterIsCleared() {
        let rice = item("米饭", 200, unit: "g", waterMl: 60)
        #expect(DrinkIntakeEstimator.applying(to: rice).perPortion.waterMl == 0)
    }

    @Test("纯水即使误按克记也计入；液体计量的饮品照常计入")
    func plainWaterAndMeasuredDrinksStillCount() {
        let byWeight = item("矿泉水", 500, unit: "g")
        #expect(DrinkIntakeEstimator.isDrink(byWeight) == true)
        #expect(DrinkIntakeEstimator.waterMl(for: byWeight) == 500)
        #expect(DrinkIntakeEstimator.waterMl(for: item("拿铁", 400, unit: "ml")) == 360)
    }

    @Test("整餐汇总只含饮品水，饭菜本身的水不重复统计")
    func mealTotalOnlyContainsDrinkWater() {
        let items = DrinkIntakeEstimator.applying(to: [
            item("米饭", 200, unit: "g", waterMl: 60),
            item("咖啡蛋糕", 100, unit: "g", waterMl: 30),
            item("可口可乐（中）", 443, unit: "ml"),
        ])
        let totalWater = items.reduce(0) { $0 + $1.perPortion.waterMl }
        #expect(totalWater == 399)
    }
}
