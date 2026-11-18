import Foundation
import SwiftData
import Testing

/// 本地营养库分组管理 + AI 识别本地优先校准 的单元测试。
struct FoodGroupTests {

    // MARK: - 分组模型与 groupID

    @Test @MainActor func foodGroupAndCustomFoodGroupIDRoundTrip() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CustomFood.self, FoodGroup.self, configurations: config)
        let ctx = container.mainContext

        let group = FoodGroup(name: "麦当劳早餐")
        ctx.insert(group)
        let food = CustomFood(name: "吉士蛋麦满分", keywords: ["麦满分"], portion: "1 个 / 110g",
                             nutrition: IntakeNutrition(energyKcal: 341, carbsG: 30.2, proteinG: 17, fatG: 16.2, sodiumMg: 787),
                             groupID: group.id)
        ctx.insert(food)
        try ctx.save()

        let groups = try ctx.fetch(FetchDescriptor<FoodGroup>())
        #expect(groups.count == 1)
        let foods = try ctx.fetch(FetchDescriptor<CustomFood>())
        #expect(foods.count == 1)
        #expect(foods.first?.groupID == group.id)
    }

    @Test func customFoodDefaultsToUngrouped() {
        let food = CustomFood(name: "米饭", keywords: ["白饭"], portion: "1 碗 / 150g", nutrition: .zero)
        #expect(food.groupID == nil)
    }

    // MARK: - 预置分组数据

    @Test @MainActor func seedCreatesBuiltinGroupsWithFoodsAndIsIdempotent() throws {
        UserDefaults.standard.removeObject(forKey: "didSeedBuiltinFoodGroups")
        UserDefaults.standard.removeObject(forKey: "builtinLuckinSeedVersion")
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: CustomFood.self, FoodGroup.self, configurations: config)
        let ctx = container.mainContext

        FoodSeed.ensureBuiltinGroups(in: ctx)

        let groups = try ctx.fetch(FetchDescriptor<FoodGroup>())
        #expect(groups.count == 9) // 麦当劳 8 个分组 + 瑞幸咖啡
        #expect(groups.contains { $0.id == "group.luckin.coffee" && $0.name == "瑞幸咖啡" })

        let allFoods = try ctx.fetch(FetchDescriptor<CustomFood>())
        #expect(allFoods.count == 167) // 2026-11-18 官网核对补录浓缩咖啡 / 鲜萃咖啡
        #expect(allFoods.filter { $0.groupID == "group.mcd.breakfast" }.count == 18)
        #expect(allFoods.filter { $0.groupID == "group.luckin.coffee" }.count == LuckinCatalog.drinks.count)
        // 营养库与咖啡因快捷入口共用同一份瑞幸目录，份量文本不能各写一份。
        #expect(allFoods.filter { $0.groupID == "group.luckin.coffee" }
            .allSatisfy { food in
                LuckinCatalog.drinks.contains { $0.id == food.id && $0.portion == food.portion }
            })
        // 麦当劳官方六项营养齐全；瑞幸热量为官网公示值，碳蛋脂为按公开配方拆算的推算值。
        let pork = allFoods.first { $0.id == "mcd.15.43" }
        #expect(pork?.nutrition.energyKcal == 308)
        #expect(pork?.nutrition.proteinG == 16)
        let coconut = allFoods.first { $0.id == "lk.coconut" }
        #expect(coconut?.nutrition.energyKcal == 179)
        #expect(coconut?.nutrition.carbsG == 7.4) // 碳蛋脂为推算值（厚椰乳配方拆算）
        #expect(coconut?.portion == "咖啡因118.4mg · 1 大杯 / 450ml")
        #expect(FoodDatabase.parsePortion(from: coconut?.portion ?? "").unit == "ml")
        #expect(FoodDatabase.parsePortion(from: coconut?.portion ?? "").amount == 450)
        let butterAmericano = allFoods.first { $0.id == "lk.butteramericano" }
        #expect(butterAmericano?.nutrition.energyKcal == 173)
        #expect(butterAmericano?.portion.contains("咖啡因212mg") == true)
        let thai = allFoods.first { $0.id == "lk.thaiyuanyeung" }
        #expect(thai?.nutrition.proteinG == 6.5)
        #expect(thai?.nutrition.energyKcal == 300) // 热量为推算值（官网未公示）

        // 幂等：再次调用不应重复创建。
        FoodSeed.ensureBuiltinGroups(in: ctx)
        let groups2 = try ctx.fetch(FetchDescriptor<FoodGroup>())
        #expect(groups2.count == 9)
        let foods2 = try ctx.fetch(FetchDescriptor<CustomFood>())
        #expect(foods2.count == 167)

        // 老用户数据版本升级：重建瑞幸预置条目，但保留用户自行新增的条目。
        let userFood = CustomFood(name: "我的特调", keywords: ["特调"], portion: "1 杯 / 300ml",
                                  nutrition: IntakeNutrition(energyKcal: 42), groupID: "group.luckin.coffee")
        ctx.insert(userFood)
        let stale = foods2.first { $0.id == "lk.applec" }
        if let stale { ctx.delete(stale) }
        try ctx.save()
        UserDefaults.standard.set(1, forKey: "builtinLuckinSeedVersion")
        FoodSeed.ensureBuiltinGroups(in: ctx)
        let foods3 = try ctx.fetch(FetchDescriptor<CustomFood>())
        let luckinFoods = foods3.filter { $0.groupID == "group.luckin.coffee" }
        #expect(luckinFoods.count == 29) // 28 条预置 + 1 条用户自定义
        #expect(luckinFoods.contains { $0.id == "lk.applec" && $0.nutrition.energyKcal == 131 })
        #expect(luckinFoods.contains { $0.id == userFood.id })
        #expect(foods3.count == 168)
    }

    // MARK: - AI 识别本地优先校准

    private var localMcD: FoodItem {
        FoodItem(id: "mcd.eggcheese", name: "吉士蛋麦满分", keywords: ["麦满分"], portion: "1 个 / 110g",
                 nutrition: IntakeNutrition(energyKcal: 341, carbsG: 30.2, proteinG: 17, fatG: 16.2, fiberG: 0, sugarG: 0, sodiumMg: 787))
    }

    @Test func applyLocalAuthorityOverridesCustomMatch() {
        let aiItem = MealItem(name: "吉士蛋麦满分", portionAmount: 110, portionUnit: "g",
                             perPortion: IntakeNutrition(energyKcal: 999))
        let (items, overridden) = FoodRecognitionService.applyLocalAuthority(to: [aiItem], custom: [localMcD])
        #expect(overridden == 1)
        #expect(items[0].perPortion.energyKcal == 341)
        #expect(items[0].perPortion.proteinG == 17)
        #expect(items[0].portionAmount == 110) // 采用本地份量
    }

    @Test func applyLocalAuthorityLeavesUnmatchedUnchanged() {
        let aiItem = MealItem(name: "自创料理 XYZ", portionAmount: 200, portionUnit: "g",
                             perPortion: IntakeNutrition(energyKcal: 123))
        let (items, overridden) = FoodRecognitionService.applyLocalAuthority(to: [aiItem], custom: [localMcD])
        #expect(overridden == 0)
        #expect(items[0].perPortion.energyKcal == 123)
    }

    @Test func applyLocalAuthorityKeepsAIValueWhenBuiltInLibraryIsEmpty() {
        // 通用内置单品库已移除（FoodDatabase.all 为空），本地权威只来自用户自定义 / 预置分组；
        // 没有 custom 时不得改写 AI 的估算值。
        let aiItem = MealItem(name: "汉堡", portionAmount: 150, portionUnit: "g",
                             perPortion: IntakeNutrition(energyKcal: 777))
        let (items, overridden) = FoodRecognitionService.applyLocalAuthority(to: [aiItem], custom: [])
        #expect(overridden == 0)
        #expect(items[0].perPortion.energyKcal == 777)
    }

    @Test func applyLocalAuthorityPrefersCustomOverBuiltIn() {
        // 同名「汉堡」用户自定义一个不同数值，应优先采用自定义（本地权威）。
        let customBurger = FoodItem(id: "my.burger", name: "汉堡", keywords: [], portion: "1 个 / 150g",
                                   nutrition: IntakeNutrition(energyKcal: 420))
        let aiItem = MealItem(name: "汉堡", portionAmount: 150, portionUnit: "g",
                             perPortion: IntakeNutrition(energyKcal: 777))
        let (items, _) = FoodRecognitionService.applyLocalAuthority(to: [aiItem], custom: [customBurger])
        #expect(items[0].perPortion.energyKcal == 420)
    }

    @Test func applyLocalAuthorityMatchesByKeyword() {
        // AI 返回「麦当劳吉士蛋麦满分」，关键词「麦满分」应命中本地项。
        let aiItem = MealItem(name: "麦当劳吉士蛋麦满分", portionAmount: 110, portionUnit: "g",
                             perPortion: IntakeNutrition(energyKcal: 888))
        let (items, overridden) = FoodRecognitionService.applyLocalAuthority(to: [aiItem], custom: [localMcD])
        #expect(overridden == 1)
        #expect(items[0].perPortion.energyKcal == 341)
    }

    @Test func applyLocalAuthorityPicksLongestNameMatch() {
        // 瑞幸营养库里「拿铁」是「生椰拿铁」的子串，无论查询顺序如何都应命中更长的名称。
        let plainLatte = FoodItem(id: "lk.latte", name: "拿铁", keywords: [], portion: "1 大杯 / 450ml",
                                  nutrition: IntakeNutrition(energyKcal: 268))
        let coconutLatte = FoodItem(id: "lk.coconut", name: "生椰拿铁", keywords: [],
                                    portion: "咖啡因118.4mg · 1 大杯 / 450ml",
                                    nutrition: IntakeNutrition(energyKcal: 179))
        let aiItem = MealItem(name: "生椰拿铁", portionAmount: 450, portionUnit: "ml",
                              perPortion: IntakeNutrition(energyKcal: 999))
        for custom in [[plainLatte, coconutLatte], [coconutLatte, plainLatte]] {
            let (items, overridden) = FoodRecognitionService.applyLocalAuthority(to: [aiItem], custom: custom)
            #expect(overridden == 1)
            #expect(items[0].name == "生椰拿铁")
            #expect(items[0].perPortion.energyKcal == 179)
            // 份量说明末尾是容量，不能把咖啡因的 mg 当成份量单位。
            #expect(items[0].portionAmount == 450)
            #expect(items[0].portionUnit == "ml")
        }
    }
}
