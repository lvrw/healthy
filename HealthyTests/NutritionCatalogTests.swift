import Foundation
import Testing

/// 苹果健康「营养摄入」40 项指标的元数据、编解码兼容、AI 识别容错与评分白名单回归测试。
struct NutritionCatalogTests {

    @Test func coversAllFortyHealthAppNutrients() {
        #expect(NutritionField.allCases.count == 40)
        #expect(Set(NutritionField.allCases.map(\.jsonKey)).count == 40)
        #expect(Set(NutritionField.allCases.map(\.displayName)).count == 40)
        #expect(NutritionField.primaryFields.count + NutritionField.extendedFields.count == 40)
        // 用户清单里的关键项（含截图下半段维生素 / 矿物质）都在。
        for name in ["水", "饱和脂肪", "膳食能量", "咖啡因", "单元不饱和脂肪", "碘", "泛酸",
                     "酒精摄入量", "氯化物", "钼", "膳食胆固醇", "生物素", "维生素B12", "叶酸"] {
            #expect(NutritionField.allCases.contains { $0.displayName == name })
        }
    }

    @Test func scoringWhitelistCoversCoreDeductionsAndQualityNutrients() {
        let names = NutritionField.scoringFields.map(\.displayName)
        #expect(names == ["饱和脂肪", "碳水化合物", "蛋白质", "总脂肪", "膳食糖", "纤维", "水", "咖啡因"])
    }

    @Test func oldEightFieldJSONStillDecodesWithZeros() throws {
        let json = #"{"energyKcal":308,"carbsG":24,"proteinG":16,"fatG":16,"fiberG":0,"sugarG":0,"sodiumMg":781,"waterMl":250}"#
        let nutrition = try JSONDecoder().decode(IntakeNutrition.self, from: Data(json.utf8))
        #expect(nutrition.energyKcal == 308)
        #expect(nutrition.carbsG == 24)
        #expect(nutrition.waterMl == 250)
        // 旧记录没有的字段一律 0，不能让整条记录解码失败。
        for field in NutritionField.extendedFields {
            #expect(nutrition[field] == 0)
        }
        #expect(nutrition.caffeineMg == 0)
    }

    @Test func everyFieldRoundTripsThroughJSON() throws {
        var original = IntakeNutrition()
        for (index, field) in NutritionField.allCases.enumerated() {
            original[field] = Double(index + 1)
        }
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(IntakeNutrition.self, from: data)
        #expect(decoded == original)
    }

    @Test func malformedOrMissingAIFieldsDefaultToZero() throws {
        // 只给了 4 项，碘用字符串，钠写成对象：其余全部按 0 处理。
        let json = """
        {"items":[{"name":"拿铁","portion":"330ml","carbsG":12,"proteinG":8,
                   "fatG":7,"caffeineMg":75,"iodineMcg":"12.5","sodiumMg":{"v":1}}]}
        """
        let items = try FoodRecognitionService.parseAIResponse(json)
        #expect(items.count == 1)
        let nutrition = items[0].perPortion
        #expect(items[0].portionAmount == 330)
        #expect(items[0].portionUnit == "ml")
        #expect(nutrition.carbsG == 12)
        #expect(nutrition.caffeineMg == 75)
        #expect(nutrition.iodineMcg == 12.5)
        #expect(nutrition.sodiumMg == 0)
        #expect(nutrition.folateMcg == 0)
        #expect(nutrition.alcoholServings == 0)
        #expect(NutritionField.extendedFields.allSatisfy { field in
            field.jsonKey == "iodineMcg" || nutrition[field] == 0
        })
    }

    @Test func aiPromptAsksForAllFortyFields() {
        let prompt = FoodRecognitionService.systemPrompt
        for field in NutritionField.allCases {
            #expect(prompt.contains(field.jsonKey))
            #expect(NutritionField.aiJSONTemplate.contains("\"\(field.jsonKey)\":0"))
        }
        #expect(prompt.contains("禁止省略字段"))
    }

    @Test func scalingAndSummationCoverNewNutrients() {
        var base = IntakeNutrition()
        base.calciumMg = 120
        base.vitaminCMg = 30
        base.caffeineMg = 80
        let doubled = base.scaled(by: 2)
        #expect(doubled.calciumMg == 240)
        #expect(doubled.vitaminCMg == 60)
        #expect(doubled.caffeineMg == 160)
        let sum = base + base
        #expect(sum.calciumMg == 240)
        #expect(sum.folateMcg == 0)
        // 只有水不算「有营养记录」；任一微量营养素非零则算。
        #expect(!IntakeNutrition(waterMl: 500).hasAny)
        #expect(IntakeNutrition(folateMcg: 1).hasAny)
    }

    @Test func nutritionScoreIgnoresEnergyAndSodiumButCountsSugarAndFiber() {
        let base = NutritionValues(
            waterTotalMl: 1_500, carbsG: 250, proteinG: 70, fatG: 70, caffeineMg: 100
        )
        let withExtras = NutritionValues(
            waterTotalMl: 1_500, energyKcal: 9_000, carbsG: 250, proteinG: 70, fatG: 70,
            sodiumMg: 15_000, caffeineMg: 100
        )
        #expect(NutritionEngine.score(base) == NutritionEngine.score(withExtras))
        #expect(NutritionEngine.dietScore(base) == NutritionEngine.dietScore(withExtras))
        // 糖是核心扣分项，高糖必须明显降分。
        let sugary = NutritionValues(
            waterTotalMl: 1_500, carbsG: 250, proteinG: 70, fatG: 70,
            sugarG: 400, caffeineMg: 100
        )
        #expect(NutritionEngine.dietScore(sugary)! < NutritionEngine.dietScore(base)!)
        // 只有能量 / 钠这类留档数据时，不应凭空产生饮食评分。
        let archivedOnly = NutritionValues(energyKcal: 2_100, sodiumMg: 2_000)
        #expect(NutritionEngine.dietScore(archivedOnly) == nil)
        #expect(!archivedOnly.hasData)
    }
}
