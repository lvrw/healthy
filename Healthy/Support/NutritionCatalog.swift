import Foundation

/// 苹果健康 App「营养摄入」页面的完整指标清单（40 项）。
///
/// 顺序与命名完全对齐健康 App 中文界面：前 26 项为「水 / 饱和脂肪 / … / 膳食胆固醇」，
/// 后 14 项为「生物素 / 铁 / … / 叶酸」；「酒精摄入量」对应 HealthKit 的
/// `numberOfAlcoholicBeverages`（标准杯），其余 39 项都有对应的 `dietary*` 数量类型。
/// 每一项同时给出：JSON 字段（也是 IntakeNutrition 的属性名）、中文名、单位、
/// 以及指向 IntakeNutrition 的 keyPath，供 AI 提示词、解析、UI 编辑和缩放/求和统一驱动。
enum NutritionField: CaseIterable, Sendable {
    case water
    case fatSaturated
    case protein
    case sodium
    case energy
    case sugar
    case carbs
    case fiber
    case fatTotal
    case caffeine
    case fatMonounsaturated
    case iodine
    case fatPolyunsaturated
    case pantothenicAcid
    case calcium
    case chromium
    case riboflavin
    case potassium
    case alcohol
    case phosphorus
    case thiamin
    case chloride
    case magnesium
    case manganese
    case molybdenum
    case cholesterol
    case biotin
    case iron
    case copper
    case vitaminA
    case vitaminB6
    case vitaminB12
    case vitaminC
    case vitaminD
    case vitaminE
    case vitaminK
    case selenium
    case zinc
    case niacin
    case folate

    /// JSON 字段名，同时也是 IntakeNutrition 的属性名（保证编解码与 AI 输出一致）。
    var jsonKey: String {
        switch self {
        case .water: return "waterMl"
        case .fatSaturated: return "saturatedFatG"
        case .protein: return "proteinG"
        case .sodium: return "sodiumMg"
        case .energy: return "energyKcal"
        case .sugar: return "sugarG"
        case .carbs: return "carbsG"
        case .fiber: return "fiberG"
        case .fatTotal: return "fatG"
        case .caffeine: return "caffeineMg"
        case .fatMonounsaturated: return "monounsaturatedFatG"
        case .iodine: return "iodineMcg"
        case .fatPolyunsaturated: return "polyunsaturatedFatG"
        case .pantothenicAcid: return "pantothenicAcidMg"
        case .calcium: return "calciumMg"
        case .chromium: return "chromiumMcg"
        case .riboflavin: return "riboflavinMg"
        case .potassium: return "potassiumMg"
        case .alcohol: return "alcoholServings"
        case .phosphorus: return "phosphorusMg"
        case .thiamin: return "thiaminMg"
        case .chloride: return "chlorideMg"
        case .magnesium: return "magnesiumMg"
        case .manganese: return "manganeseMg"
        case .molybdenum: return "molybdenumMcg"
        case .cholesterol: return "cholesterolMg"
        case .biotin: return "biotinMcg"
        case .iron: return "ironMg"
        case .copper: return "copperMg"
        case .vitaminA: return "vitaminAMcg"
        case .vitaminB6: return "vitaminB6Mg"
        case .vitaminB12: return "vitaminB12Mcg"
        case .vitaminC: return "vitaminCMg"
        case .vitaminD: return "vitaminDMcg"
        case .vitaminE: return "vitaminEMg"
        case .vitaminK: return "vitaminKMcg"
        case .selenium: return "seleniumMcg"
        case .zinc: return "zincMg"
        case .niacin: return "niacinMg"
        case .folate: return "folateMcg"
        }
    }

    /// 健康 App 中文指标名。
    var displayName: String {
        switch self {
        case .water: return "水"
        case .fatSaturated: return "饱和脂肪"
        case .protein: return "蛋白质"
        case .sodium: return "钠"
        case .energy: return "膳食能量"
        case .sugar: return "膳食糖"
        case .carbs: return "碳水化合物"
        case .fiber: return "纤维"
        case .fatTotal: return "总脂肪"
        case .caffeine: return "咖啡因"
        case .fatMonounsaturated: return "单元不饱和脂肪"
        case .iodine: return "碘"
        case .fatPolyunsaturated: return "多元不饱和脂肪"
        case .pantothenicAcid: return "泛酸"
        case .calcium: return "钙"
        case .chromium: return "铬"
        case .riboflavin: return "核黄素"
        case .potassium: return "钾"
        case .alcohol: return "酒精摄入量"
        case .phosphorus: return "磷"
        case .thiamin: return "硫胺"
        case .chloride: return "氯化物"
        case .magnesium: return "镁"
        case .manganese: return "锰"
        case .molybdenum: return "钼"
        case .cholesterol: return "膳食胆固醇"
        case .biotin: return "生物素"
        case .iron: return "铁"
        case .copper: return "铜"
        case .vitaminA: return "维生素A"
        case .vitaminB6: return "维生素B6"
        case .vitaminB12: return "维生素B12"
        case .vitaminC: return "维生素C"
        case .vitaminD: return "维生素D"
        case .vitaminE: return "维生素E"
        case .vitaminK: return "维生素K"
        case .selenium: return "硒"
        case .zinc: return "锌"
        case .niacin: return "烟酸"
        case .folate: return "叶酸"
        }
    }

    /// UI 与 AI 输出使用的单位缩写。
    var unit: String {
        switch self {
        case .water: return "ml"
        case .energy: return "kcal"
        case .alcohol: return "杯"
        case .fatSaturated, .protein, .sugar, .carbs, .fiber, .fatTotal,
             .fatMonounsaturated, .fatPolyunsaturated: return "g"
        case .iodine, .chromium, .molybdenum, .biotin, .vitaminA, .vitaminB12,
             .vitaminD, .vitaminK, .selenium, .folate: return "µg"
        default: return "mg"
        }
    }

    /// 指向 IntakeNutrition 对应字段的读写路径，保证「新增指标」不需要改缩放/求和逻辑。
    var keyPath: WritableKeyPath<IntakeNutrition, Double> {
        switch self {
        case .water: return \.waterMl
        case .fatSaturated: return \.saturatedFatG
        case .protein: return \.proteinG
        case .sodium: return \.sodiumMg
        case .energy: return \.energyKcal
        case .sugar: return \.sugarG
        case .carbs: return \.carbsG
        case .fiber: return \.fiberG
        case .fatTotal: return \.fatG
        case .caffeine: return \.caffeineMg
        case .fatMonounsaturated: return \.monounsaturatedFatG
        case .iodine: return \.iodineMcg
        case .fatPolyunsaturated: return \.polyunsaturatedFatG
        case .pantothenicAcid: return \.pantothenicAcidMg
        case .calcium: return \.calciumMg
        case .chromium: return \.chromiumMcg
        case .riboflavin: return \.riboflavinMg
        case .potassium: return \.potassiumMg
        case .alcohol: return \.alcoholServings
        case .phosphorus: return \.phosphorusMg
        case .thiamin: return \.thiaminMg
        case .chloride: return \.chlorideMg
        case .magnesium: return \.magnesiumMg
        case .manganese: return \.manganeseMg
        case .molybdenum: return \.molybdenumMcg
        case .cholesterol: return \.cholesterolMg
        case .biotin: return \.biotinMcg
        case .iron: return \.ironMg
        case .copper: return \.copperMg
        case .vitaminA: return \.vitaminAMcg
        case .vitaminB6: return \.vitaminB6Mg
        case .vitaminB12: return \.vitaminB12Mcg
        case .vitaminC: return \.vitaminCMg
        case .vitaminD: return \.vitaminDMcg
        case .vitaminE: return \.vitaminEMg
        case .vitaminK: return \.vitaminKMcg
        case .selenium: return \.seleniumMcg
        case .zinc: return \.zincMg
        case .niacin: return \.niacinMg
        case .folate: return \.folateMcg
        }
    }

    /// HealthKit 数量类型标识（rawValue）。酒精摄入量不属于 dietary 家族，
    /// 对应 `numberOfAlcoholicBeverages`（标准杯）；其余 39 项与 SDK 一一对应。
    /// TODO: 目前新增指标只在 App 内留档，尚未申请这些类型的写权限并回写健康 App。
    var healthKitIdentifier: String {
        switch self {
        case .water: return "HKQuantityTypeIdentifierDietaryWater"
        case .fatSaturated: return "HKQuantityTypeIdentifierDietaryFatSaturated"
        case .protein: return "HKQuantityTypeIdentifierDietaryProtein"
        case .sodium: return "HKQuantityTypeIdentifierDietarySodium"
        case .energy: return "HKQuantityTypeIdentifierDietaryEnergyConsumed"
        case .sugar: return "HKQuantityTypeIdentifierDietarySugar"
        case .carbs: return "HKQuantityTypeIdentifierDietaryCarbohydrates"
        case .fiber: return "HKQuantityTypeIdentifierDietaryFiber"
        case .fatTotal: return "HKQuantityTypeIdentifierDietaryFatTotal"
        case .caffeine: return "HKQuantityTypeIdentifierDietaryCaffeine"
        case .fatMonounsaturated: return "HKQuantityTypeIdentifierDietaryFatMonounsaturated"
        case .iodine: return "HKQuantityTypeIdentifierDietaryIodine"
        case .fatPolyunsaturated: return "HKQuantityTypeIdentifierDietaryFatPolyunsaturated"
        case .pantothenicAcid: return "HKQuantityTypeIdentifierDietaryPantothenicAcid"
        case .calcium: return "HKQuantityTypeIdentifierDietaryCalcium"
        case .chromium: return "HKQuantityTypeIdentifierDietaryChromium"
        case .riboflavin: return "HKQuantityTypeIdentifierDietaryRiboflavin"
        case .potassium: return "HKQuantityTypeIdentifierDietaryPotassium"
        case .alcohol: return "HKQuantityTypeIdentifierNumberOfAlcoholicBeverages"
        case .phosphorus: return "HKQuantityTypeIdentifierDietaryPhosphorus"
        case .thiamin: return "HKQuantityTypeIdentifierDietaryThiamin"
        case .chloride: return "HKQuantityTypeIdentifierDietaryChloride"
        case .magnesium: return "HKQuantityTypeIdentifierDietaryMagnesium"
        case .manganese: return "HKQuantityTypeIdentifierDietaryManganese"
        case .molybdenum: return "HKQuantityTypeIdentifierDietaryMolybdenum"
        case .cholesterol: return "HKQuantityTypeIdentifierDietaryCholesterol"
        case .biotin: return "HKQuantityTypeIdentifierDietaryBiotin"
        case .iron: return "HKQuantityTypeIdentifierDietaryIron"
        case .copper: return "HKQuantityTypeIdentifierDietaryCopper"
        case .vitaminA: return "HKQuantityTypeIdentifierDietaryVitaminA"
        case .vitaminB6: return "HKQuantityTypeIdentifierDietaryVitaminB6"
        case .vitaminB12: return "HKQuantityTypeIdentifierDietaryVitaminB12"
        case .vitaminC: return "HKQuantityTypeIdentifierDietaryVitaminC"
        case .vitaminD: return "HKQuantityTypeIdentifierDietaryVitaminD"
        case .vitaminE: return "HKQuantityTypeIdentifierDietaryVitaminE"
        case .vitaminK: return "HKQuantityTypeIdentifierDietaryVitaminK"
        case .selenium: return "HKQuantityTypeIdentifierDietarySelenium"
        case .zinc: return "HKQuantityTypeIdentifierDietaryZinc"
        case .niacin: return "HKQuantityTypeIdentifierDietaryNiacin"
        case .folate: return "HKQuantityTypeIdentifierDietaryFolate"
        }
    }

    /// 参与评分 / 身体年龄计算的白名单：饱和脂肪、碳水、蛋白质、总脂肪、糖、纤维、水、咖啡因。
    /// 饱和脂肪与纤维在单餐评分中生效；每日同步的汇总里没有这两项，由总脂肪与其余字段覆盖。
    /// 其余 32 项只做记录与展示，后续要放开时只改这里。
    static let scoringFields: [NutritionField] = [
        .fatSaturated, .carbs, .protein, .fatTotal, .sugar, .fiber, .water, .caffeine,
    ]

    /// 编辑页默认展示的主要指标（原有 7 项 + 水 / 咖啡因）。
    static let primaryFields: [NutritionField] = [
        .energy, .carbs, .protein, .fatTotal, .fiber, .sugar, .sodium, .water, .caffeine,
    ]

    /// 折叠区里的其余苹果健康指标；按清单顺序，缺数据一律为 0。
    static var extendedFields: [NutritionField] {
        let primary = Set(primaryFields.map(\.jsonKey))
        return allCases.filter { !primary.contains($0.jsonKey) }
    }

    /// AI 提示词里给模型的字段模板：所有 40 项都必须出现，未知填 0。
    static var aiJSONTemplate: String {
        let fields = allCases.map { "\"\($0.jsonKey)\":0" }.joined(separator: ",")
        return "{\"items\":[{\"name\":\"食物名\",\"portion\":\"份量，如 150g / 330ml\",\(fields)}]}"
    }

    /// 按单位分组的字段说明，避免 prompt 里重复 40 行单位。
    static var aiUnitDescription: String {
        func joined(_ unit: String) -> String {
            allCases.filter { $0.unit == unit }.map(\.jsonKey).joined(separator: "、")
        }
        return [
            "千卡：\(joined("kcal"))",
            "毫升：\(joined("ml"))",
            "标准杯：\(joined("杯"))",
            "克：\(joined("g"))",
            "毫克：\(joined("mg"))",
            "微克：\(joined("µg"))",
        ].joined(separator: "；")
    }
}

/// 动态 JSON key，供 IntakeNutrition 与 AI 返回按字段名容错解码。
struct NutritionCodingKey: CodingKey, Sendable {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ key: String) { stringValue = key }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
