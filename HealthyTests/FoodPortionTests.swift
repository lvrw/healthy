import Foundation
import Testing

/// 覆盖「一份的量」结构化：自由文本解析成「数值 + 实际单位」+ 改数值时营养等比例缩放。
struct FoodPortionTests {

    // MARK: - FoodDatabase.parsePortion

    @Test func parsePortionPrefersUnitValueOverCount() {
        // 「1 碗 / 150g」应取带单位的 150g，而不是数量词里的 1。
        #expect(FoodDatabase.parsePortion(from: "1 碗 / 150g") == PortionValue(amount: 150, unit: "g"))
        #expect(FoodDatabase.parsePortion(from: "1 根 / 120g") == PortionValue(amount: 120, unit: "g"))
        #expect(FoodDatabase.parsePortion(from: "1 个 / 50g") == PortionValue(amount: 50, unit: "g"))
    }

    @Test func parsePortionKeepsMilliliterUnit() {
        // 单位按实际来源，不做 g/ml 换算。
        #expect(FoodDatabase.parsePortion(from: "1 罐 / 330ml") == PortionValue(amount: 330, unit: "ml"))
        #expect(FoodDatabase.parsePortion(from: "1 杯 / 500ml") == PortionValue(amount: 500, unit: "ml"))
        #expect(FoodDatabase.parsePortion(from: "1 杯 / 250毫升") == PortionValue(amount: 250, unit: "ml"))
        #expect(FoodDatabase.parsePortion(from: "1 杯 / 240mL") == PortionValue(amount: 240, unit: "ml"))
    }

    @Test func parsePortionNormalizesAliases() {
        #expect(FoodDatabase.parsePortion(from: "100g") == PortionValue(amount: 100, unit: "g"))
        #expect(FoodDatabase.parsePortion(from: "300 g") == PortionValue(amount: 300, unit: "g"))
        #expect(FoodDatabase.parsePortion(from: "200克") == PortionValue(amount: 200, unit: "g"))
        #expect(FoodDatabase.parsePortion(from: "1.5L") == PortionValue(amount: 1.5, unit: "L"))
        #expect(FoodDatabase.parsePortion(from: "2升") == PortionValue(amount: 2, unit: "L"))
        #expect(FoodDatabase.parsePortion(from: "0.5kg") == PortionValue(amount: 0.5, unit: "kg"))
        #expect(FoodDatabase.parsePortion(from: "150.5g") == PortionValue(amount: 150.5, unit: "g"))
    }

    @Test func parsePortionFallsBackForBareNumberOrNoUnit() {
        // 纯数字但明显是份量时直接采用，单位默认 g。
        #expect(FoodDatabase.parsePortion(from: "180") == PortionValue(amount: 180, unit: "g"))
        // 只有数量词（≤10）时不当成份量，回退默认 100g。
        let fallback = FoodDatabase.defaultPortion
        #expect(fallback == PortionValue(amount: 100, unit: "g"))
        #expect(FoodDatabase.parsePortion(from: "1 份") == fallback)
        #expect(FoodDatabase.parsePortion(from: "2 块") == fallback)
        #expect(FoodDatabase.parsePortion(from: "") == fallback)
        #expect(FoodDatabase.parsePortion(from: "适量") == fallback)
    }

    @Test func builtInDrinksUseMilliliter() {
        // 内置单品库已移除，直接用 FoodItem 字面量测试 portion 解析单位。
        let colaPortion = "1 罐 / 330ml"
        #expect(FoodDatabase.parsePortion(from: colaPortion).unit == "ml")
        let milkPortion = "1 杯 / 250ml"
        #expect(FoodDatabase.parsePortion(from: milkPortion).unit == "ml")
        let ricePortion = "1 碗 / 150g"
        #expect(FoodDatabase.parsePortion(from: ricePortion).unit == "g")
    }

    // MARK: - MealItem.updatePortionAmount

    @Test func portionTextUsesActualUnit() {
        let grams = MealItem(name: "米饭", portionAmount: 150, portionUnit: "g", perPortion: .zero)
        #expect(grams.portionText == "150g")
        let drink = MealItem(name: "可乐", portionAmount: 330, portionUnit: "ml", perPortion: .zero)
        #expect(drink.portionText == "330ml")
        // 大于毫升的单位在构造时统一折算成毫升，App 内只保留「克 / 毫升」两种单位。
        let fractional = MealItem(name: "测试", portionAmount: 1.5, portionUnit: "L", perPortion: .zero)
        #expect(fractional.portionAmount == 1500)
        #expect(fractional.portionUnit == "ml")
        #expect(fractional.portionText == "1500ml")
    }

    @Test func changingAmountScalesNutritionProportionally() {
        // 一份 150g：热量 180 / 碳水 40 / 蛋白 4；改成 300g 应整体 ×2。
        var item = MealItem(
            name: "米饭",
            portionAmount: 150,
            portionUnit: "g",
            perPortion: IntakeNutrition(energyKcal: 180, carbsG: 40, proteinG: 4, fatG: 0.4, fiberG: 0.6, sugarG: 0.1, sodiumMg: 2)
        )
        item.updatePortionAmount(to: 300)
        #expect(item.portionAmount == 300)
        #expect(item.portionUnit == "g")  // 改数值不影响单位
        #expect(item.perPortion.energyKcal == 360)
        #expect(item.perPortion.carbsG == 80)
        #expect(item.perPortion.proteinG == 8)
        // 合计即当前数量对应的营养，应同步反映放大后的营养。
        #expect(item.total.energyKcal == 360)
    }

    @Test func scalingWorksForMilliliterItem() {
        // 饮品 ml 同样按数值等比缩放：330ml → 660ml，营养 ×2。
        var item = MealItem(name: "可乐", portionAmount: 330, portionUnit: "ml",
                            perPortion: IntakeNutrition(energyKcal: 140, carbsG: 35))
        item.updatePortionAmount(to: 660)
        #expect(item.portionText == "660ml")
        #expect(item.perPortion.energyKcal == 280)
        #expect(item.perPortion.carbsG == 70)
    }

    @Test func changingAmountRepeatedlyIsEquivalentToFinalOverInitial() {
        // 连续输入中间态（150→75→300）连乘比例会抵消，结果恒等于 最终/初始 = 2 倍。
        var item = MealItem(name: "测试", portionAmount: 150, portionUnit: "g",
                            perPortion: IntakeNutrition(energyKcal: 100, carbsG: 20))
        item.updatePortionAmount(to: 75)
        item.updatePortionAmount(to: 300)
        #expect(abs(item.perPortion.energyKcal - 200) < 1e-6)
        #expect(abs(item.perPortion.carbsG - 40) < 1e-6)
        #expect(item.total.energyKcal == item.perPortion.energyKcal)
    }

    @Test func changingAmountScalesManuallyEditedNutrition() {
        // 用户先手动把热量改成 300，再把 100 → 200，应基于改动后的值 ×2 = 600。
        var item = MealItem(name: "测试", portionAmount: 100, portionUnit: "g",
                            perPortion: IntakeNutrition(energyKcal: 150))
        item.perPortion.energyKcal = 300
        item.updatePortionAmount(to: 200)
        #expect(item.perPortion.energyKcal == 600)
    }

    @Test func amountIsClampedAndZeroSafe() {
        var item = MealItem(name: "测试", portionAmount: 100, portionUnit: "g",
                            perPortion: IntakeNutrition(energyKcal: 100))
        item.updatePortionAmount(to: 0)   // 不允许 0 或负数，钳到 1
        #expect(item.portionAmount == 1)
        #expect(abs(item.perPortion.energyKcal - 1) < 1e-6)
        item.updatePortionAmount(to: 100)
        #expect(item.portionAmount == 100)
        #expect(abs(item.perPortion.energyKcal - 100) < 1e-6)
    }

    @Test func sameAmountIsNoOp() {
        var item = MealItem(name: "测试", portionAmount: 150, portionUnit: "g",
                            perPortion: IntakeNutrition(energyKcal: 100))
        item.updatePortionAmount(to: 150)
        #expect(item.perPortion.energyKcal == 100)
    }

    // MARK: - MealNoteParts（饮食备注：去掉份数，统一数字 + 单位）

    @Test func noteParsesLegacyPortionCountIntoEditableQuantity() {
        // 旧记录「×10 份」拆成可编辑数量；数值保留、单位归一为 g 供用户核对。
        let parts = MealNoteParts.parse("满屋三明治（含生菜、番茄、调料）×10 份")
        #expect(parts.name == "满屋三明治（含生菜、番茄、调料）")
        #expect(parts.amount == "10")
        #expect(parts.unit == "g")
        #expect(parts.composed == "满屋三明治（含生菜、番茄、调料） 10g")
    }

    @Test func noteParsesQuantityWithActualUnit() {
        let grams = MealNoteParts.parse("米饭 300g")
        #expect(grams.name == "米饭")
        #expect(grams.amount == "300")
        #expect(grams.unit == "g")
        let ml = MealNoteParts.parse("可乐 330 ml")
        #expect(ml.amount == "330")
        #expect(ml.unit == "ml")
        #expect(MealNoteParts.parse("牛奶 250毫升").unit == "ml")
        #expect(MealNoteParts.parse("牛奶 1升").unit == "L")
    }

    @Test func noteWithoutQuantityKeepsNameAndDefaultsToGrams() {
        let parts = MealNoteParts.parse("未知食物")
        #expect(parts.name == "未知食物")
        #expect(parts.amount.isEmpty)
        #expect(parts.unit == "g")
        #expect(parts.composed == "未知食物")
    }

    @Test func composeItemsUsesQuantityInsteadOfPortionCount() {
        let items = [
            MealItem(name: "米饭", portionAmount: 300, portionUnit: "g", perPortion: .zero),
            MealItem(name: "可乐", portionAmount: 330, portionUnit: "ml", perPortion: .zero),
            MealItem(name: "  ", portionAmount: 100, portionUnit: "g", perPortion: .zero)
        ]
        #expect(MealNoteParts.compose(items) == "米饭 300g、可乐 330ml")
        #expect(MealNoteParts.compose([]) == nil)
    }

    // MARK: - 单位归一（新增记录禁止「一份」）

    @Test func fuzzyUnitsAreNormalizedToGrams() {
        // 份 / 个 / 碗 / 杯 / 块这类无法反推重量的单位一律按克。
        #expect(MealItem.normalizeUnit("份") == "g")
        #expect(MealItem.normalizeUnit("个") == "g")
        #expect(MealItem.normalizeUnit("碗") == "g")
        #expect(MealItem.normalizeUnit("杯") == "g")
        #expect(MealItem.normalizeUnit("块") == "g")
        #expect(MealItem.normalizeUnit("") == "g")
        // 真实计量单位保留，别名归一。
        #expect(MealItem.normalizeUnit("克") == "g")
        #expect(MealItem.normalizeUnit("G") == "g")
        #expect(MealItem.normalizeUnit("毫升") == "ml")
        #expect(MealItem.normalizeUnit("ML") == "ml")
        #expect(MealItem.normalizeUnit("kg") == "kg")
        #expect(MealItem.normalizeUnit("升") == "L")
    }

    @Test func itemConstructionConvertsToGramOrMilliliter() {
        // kg → g、L → ml，数值同步放大，营养不变（还是同一份食物）。
        let kilo = MealItem(name: "牛排", portionAmount: 0.3, portionUnit: "kg",
                            perPortion: IntakeNutrition(energyKcal: 600))
        #expect(kilo.portionAmount == 300)
        #expect(kilo.portionUnit == "g")
        #expect(kilo.perPortion.energyKcal == 600)

        let liter = MealItem(name: "牛奶", portionAmount: 1, portionUnit: "L",
                             perPortion: IntakeNutrition(energyKcal: 640))
        #expect(liter.portionAmount == 1000)
        #expect(liter.portionUnit == "ml")

        // 「一份」不再是可接受单位：按克记录，数量原样保留供用户核对。
        let portion = MealItem(name: "三明治", portionAmount: 1, portionUnit: "份",
                               perPortion: IntakeNutrition(energyKcal: 300))
        #expect(portion.portionUnit == "g")
        #expect(portion.portionText == "1g")
    }

    @Test func validAmountRequiresMeasuredQuantity() {
        let valid = MealItem(name: "米饭", portionAmount: 150, portionUnit: "g", perPortion: .zero)
        #expect(valid.hasValidAmount)
        #expect(valid.isMeasured)
        let zero = MealItem(name: "米饭", portionAmount: 0, portionUnit: "g", perPortion: .zero)
        #expect(!zero.hasValidAmount)
    }

    @Test func normalizedForEditingKeepsGramOrMilliliterOnly() {
        // 编辑页只给克 / 毫升：kg 折算成克、L 折算成毫升。
        let kilo = MealItem(name: "米饭", portionAmount: 1, portionUnit: "kg",
                            perPortion: IntakeNutrition(energyKcal: 1160))
        let edited = kilo.normalizedForEditing
        #expect(edited.portionAmount == 1000)
        #expect(edited.portionUnit == "g")
        #expect(edited.perPortion.energyKcal == 1160)

        let liter = MealItem(name: "水", portionAmount: 2, portionUnit: "L",
                             perPortion: IntakeNutrition(waterMl: 2000))
        #expect(liter.normalizedForEditing.portionUnit == "ml")
        #expect(liter.normalizedForEditing.portionAmount == 2000)
    }

    // MARK: - 分项持久化（记录里逐样食物）

    @Test func mealItemsRoundTripThroughJSON() throws {
        // 保存到 ActionCheckIn.mealItemsJSON 后要能原样还原（名称 / 数量 / 单位 / 营养）。
        let items = [
            MealItem(name: "米饭", portionAmount: 300, portionUnit: "g",
                     perPortion: IntakeNutrition(energyKcal: 360, carbsG: 80, proteinG: 8)),
            MealItem(name: "可乐", portionAmount: 330, portionUnit: "ml",
                     perPortion: IntakeNutrition(energyKcal: 140, carbsG: 35, sugarG: 35))
        ]
        let data = try JSONEncoder().encode(items)
        let decoded = try JSONDecoder().decode([MealItem].self, from: data)
        #expect(decoded.count == 2)
        #expect(decoded[0].name == "米饭")
        #expect(decoded[0].portionAmount == 300)
        #expect(decoded[0].portionUnit == "g")
        #expect(decoded[0].perPortion.energyKcal == 360)
        #expect(decoded[1].name == "可乐")
        #expect(decoded[1].portionUnit == "ml")
        #expect(decoded[1].perPortion.carbsG == 35)
    }

    @Test func legacyItemJSONWithoutNewFieldsStillDecodes() throws {
        // 兼容旧 JSON：缺 id / imageURL 也不应整条失败，单位缺省按克。
        let json = #"[{"name":"米饭","portionAmount":200,"portionUnit":"份","perPortion":{"energyKcal":232}}]"#
        let decoded = try JSONDecoder().decode([MealItem].self, from: Data(json.utf8))
        #expect(decoded.count == 1)
        #expect(decoded[0].name == "米饭")
        #expect(decoded[0].portionAmount == 200)
        #expect(decoded[0].portionUnit == "g")
        #expect(decoded[0].perPortion.energyKcal == 232)
        #expect(!decoded[0].id.isEmpty)
    }

    @Test func multiItemTotalSumsEveryItem() {
        // 多食物合计 = 各样按当前数量算出的营养之和。
        let rice = MealItem(name: "米饭", portionAmount: 150, portionUnit: "g",
                            perPortion: IntakeNutrition(energyKcal: 180, carbsG: 40, proteinG: 4))
        var chicken = MealItem(name: "鸡胸肉", portionAmount: 100, portionUnit: "g",
                               perPortion: IntakeNutrition(energyKcal: 133, proteinG: 24, fatG: 2.5))
        chicken.updatePortionAmount(to: 200)  // 200g → 营养 ×2
        let meal = RecognizedMeal(items: [rice, chicken], source: .ai, rawDescription: "米饭 + 鸡胸肉")
        #expect(meal.total.energyKcal == 180 + 266)
        #expect(meal.total.proteinG == 4 + 48)
        #expect(meal.total.carbsG == 40)
    }

    // MARK: - MealNoteParts.splitTitleAndRemark（饮食记录标题 / 备注拆分）

    @Test func splitNoteSeparatesDescriptionFromFoodList() {
        // 有备注：第一个「；」前是用户描述，之后是食物清单（核心标题）。
        let split = MealNoteParts.splitTitleAndRemark("今天吃得清淡；米饭 150g、青菜 100g")
        #expect(split.title == "米饭 150g、青菜 100g")
        #expect(split.remark == "今天吃得清淡")
    }

    @Test func splitNoteWithNoDescriptionKeepsWholeTitle() {
        // 无备注：整段都是核心名称，备注为 nil。
        let split = MealNoteParts.splitTitleAndRemark("米饭 150g、青菜 100g")
        #expect(split.title == "米饭 150g、青菜 100g")
        #expect(split.remark == nil)
    }

    @Test func splitNoteWithEmptyOrNilReturnsEmpty() {
        // 空串 / nil：返回空标题，不产生备注。
        let empty = MealNoteParts.splitTitleAndRemark("")
        #expect(empty.title.isEmpty)
        #expect(empty.remark == nil)
        let none = MealNoteParts.splitTitleAndRemark(nil)
        #expect(none.title.isEmpty)
        #expect(none.remark == nil)
    }

    @Test func splitNoteTrimsWhitespaceAndHandlesEmptySegments() {
        // 空格裁剪；备注为空时降级为 nil；标题为空的异常数据退回用备注作标题。
        let blankRemark = MealNoteParts.splitTitleAndRemark("   ；  米饭 150g  ")
        #expect(blankRemark.title == "米饭 150g")
        #expect(blankRemark.remark == nil)
        let emptyTitle = MealNoteParts.splitTitleAndRemark("仅有描述；   ")
        #expect(emptyTitle.title == "仅有描述")
        #expect(emptyTitle.remark == nil)
    }

    @Test func composedNoteRoundTripsThroughSplit() {
        // compose 产出经 split 还原：食物清单完整保留为标题、无备注。
        let items = [
            MealItem(name: "米饭", portionAmount: 150, portionUnit: "g", perPortion: .zero),
            MealItem(name: "鸡胸肉", portionAmount: 200, portionUnit: "g", perPortion: .zero)
        ]
        let note = MealNoteParts.compose(items)
        let split = MealNoteParts.splitTitleAndRemark(note)
        #expect(split.title == "米饭 150g、鸡胸肉 200g")
        #expect(split.remark == nil)
    }
}
