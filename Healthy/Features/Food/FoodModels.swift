import Foundation

/// 一份的「数值 + 实际单位」。单位取自内置库 / AI 返回的份量文本（如 g、ml），
/// 只跟随食物实际来源，UI 里只改数值。
struct PortionValue: Sendable, Equatable {
    var amount: Double
    var unit: String
}

/// 一次识别出的「单样食物」。数量直接记为「数值 + 单位」（如 300g），
/// 营养对应该数量；用户改数量时营养等比缩放，不再有「份数」这一层。
/// 可编解码：保存记录时把每样食物写入 `ActionCheckIn.mealItemsJSON`，
/// 之后在记录编辑页就能逐项改数量并等比改营养（旧记录没有分项数据，仍走聚合编辑）。
struct MealItem: Identifiable, Sendable, Codable {
    var id = UUID().uuidString
    /// 食物名称（AI 返回的或本地库匹配到的）。
    var name: String
    /// 这份食物的数量数值（UI 里可改；如 300g 中的 300）。
    var portionAmount: Double
    /// 数量单位（只允许 g / kg / ml / L；模糊单位在构造与保存前统一归一）。
    var portionUnit: String
    /// 当前数量对应的营养。改 portionAmount 时按 新/旧 等比例缩放。
    var perPortion: IntakeNutrition
    /// 官网产品图片 URL，匹配到本地库时从 FoodItem / CustomFood 继承；AI 原生返回的为 nil。
    var imageURL: String?

    /// 解码时对新增字段做兜底（旧 JSON 缺字段不至于整条解析失败）。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        let measured = Self.measured(
            try c.decodeIfPresent(Double.self, forKey: .portionAmount) ?? 100,
            unit: try c.decodeIfPresent(String.self, forKey: .portionUnit) ?? "g"
        )
        portionAmount = measured.amount
        portionUnit = measured.unit
        perPortion = try c.decodeIfPresent(IntakeNutrition.self, forKey: .perPortion) ?? .zero
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
    }

    init(id: String = UUID().uuidString, name: String, portionAmount: Double,
         portionUnit: String, perPortion: IntakeNutrition, imageURL: String? = nil) {
        self.id = id
        self.name = name
        let measured = Self.measured(portionAmount, unit: portionUnit)
        self.portionAmount = measured.amount
        self.portionUnit = measured.unit
        self.perPortion = perPortion
        self.imageURL = imageURL
    }

    /// 构造 / 解码时的统一换算：kg → g、L → ml（数值同步放大，营养不变），
    /// 模糊单位（份 / 个 / 碗 / 杯）按克。这样 App 内所有数量都只有「克 / 毫升」两种单位。
    static func measured(_ amount: Double, unit: String) -> (amount: Double, unit: String) {
        switch normalizeUnit(unit) {
        case "kg": return (amount * 1000, "g")
        case "L": return (amount * 1000, "ml")
        case "ml": return (amount, "ml")
        default: return (amount, "g")
        }
    }

    /// 这一样食物的营养 = 当前数量对应的营养（数量变化时已等比缩放）。
    var total: IntakeNutrition { perPortion }

    /// 质量 / 体积单位才算「已按实际计量记录」，其余（份 / 个 / 碗 / 杯 / 块）都算模糊单位。
    static let measuredUnits = ["g", "kg", "ml", "L"]

    /// 单位归一：只保留质量 / 体积单位。
    /// 「份 / 个 / 碗 / 杯 / 块 / 片」这类无法从名称反推重量的单位一律按克处理，
    /// 保证每条新增记录都以「多少克 / 多少毫升」落库，而不是「一份」。
    static func normalizeUnit(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch key {
        case "g", "克", "gram", "grams": return "g"
        case "kg", "千克", "公斤": return "kg"
        case "ml", "毫升", "milliliter", "milliliters": return "ml"
        case "l", "升", "liter", "liters": return "L"
        default: return "g"
        }
    }

    /// 当前单位是否已是实际计量单位（g / kg / ml / L）。
    var isMeasured: Bool { Self.measuredUnits.contains(portionUnit) }

    /// 数量是否有效：必须是大于 0 的实际计量。用于保存前校验，禁止「一份」这类空数量落库。
    var hasValidAmount: Bool { isMeasured && portionAmount > 0 }

    /// 编辑用归一：kg → g、L → ml（数值同步放大，营养不变，仍是同一份食物），
    /// 其余模糊单位一律按克。编辑页只提供「克 / 毫升」两个选项，避免又绕回「份」。
    var normalizedForEditing: MealItem {
        var copy = self
        switch copy.portionUnit {
        case "kg":
            copy.portionAmount *= 1000
            copy.portionUnit = "g"
        case "L":
            copy.portionAmount *= 1000
            copy.portionUnit = "ml"
        case "g", "ml":
            break
        default:
            copy.portionUnit = "g"
        }
        return copy
    }

    /// 数量展示串（数字 + 实际单位，如 150g / 330ml）：整数不带小数，小数保留一位。
    var portionText: String {
        Self.formatAmount(portionAmount) + portionUnit
    }

    /// 数量数值格式化：整数不带小数，小数保留一位。
    static func formatAmount(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    /// 修改数量数值，同时把营养按 新/旧 等比例缩放。单位不变。
    /// 用当前 perPortion 作基准（而非识别时的原始值），这样用户手动改过营养后再改数量，
    /// 也会基于改动后的营养等比变化；连续输入中间态的连乘比例会抵消，结果恒等于 最终/初始。
    mutating func updatePortionAmount(to newValue: Double) {
        let clamped = max(1, newValue)
        let old = portionAmount
        guard old > 0, clamped != old else {
            portionAmount = clamped
            return
        }
        perPortion = perPortion.scaled(by: clamped / old)
        portionAmount = clamped
    }
}

/// 饮食备注的结构化拆装：编辑页把「名称」与「数量 + 单位」拆成两个可编辑字段；
/// 兼容历史记录里的「×N份」写法，统一在保存时写成「名称 数字+单位」。
struct MealNoteParts: Equatable, Sendable {
    var name: String
    var amount: String
    var unit: String

    /// 末尾数量片段：兼容 `×10份`、`300g`、`330 ml`、`1.5L` 等写法。
    private static let quantityPattern = #"(?:\s*[×xX*]\s*)?([0-9]+(?:\.[0-9]+)?)\s*(份|克|千克|毫升|升|kg|g|ml|L)\s*$"#

    /// 把备注拆成名称 / 数量 / 单位。旧「份」按数值保留、单位归一为 g，供用户核对修改。
    static func parse(_ note: String) -> MealNoteParts {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: quantityPattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) else {
            return MealNoteParts(name: trimmed, amount: "", unit: "g")
        }
        let text = trimmed as NSString
        let name = text.substring(to: match.range.location)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let amount = text.substring(with: match.range(at: 1))
        let rawUnit = text.substring(with: match.range(at: 2))
        let unit: String
        switch rawUnit.lowercased() {
        case "份", "克", "g": unit = "g"
        case "千克", "kg": unit = "kg"
        case "毫升", "ml": unit = "ml"
        case "升", "l": unit = "L"
        default: unit = rawUnit
        }
        return MealNoteParts(name: name, amount: amount, unit: unit)
    }

    /// 保存时拼回备注；名称和数量任一为空时只写另一部分。
    var composed: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let a = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return a.isEmpty ? "" : a + u }
        if a.isEmpty { return n }
        return n + " " + a + u
    }

    /// 识别保存时按每样食物的「名称 + 数量+单位」拼备注，不再出现「×N份」。
    static func compose(_ items: [MealItem]) -> String? {
        let parts = items.compactMap { item -> String? in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }
            return name + " " + MealItem.formatAmount(item.portionAmount) + item.portionUnit
        }
        return parts.isEmpty ? nil : parts.joined(separator: "、")
    }
}

/// 一次识别的完整结果（可能含多种食物）。
struct RecognizedMeal: Sendable {
    var items: [MealItem]
    /// 来自 AI 还是本地营养库匹配。
    var source: MealSource
    /// 用户原始文字描述（用于回写备注）。
    var rawDescription: String
    /// 非致命提示（如「当前模型不支持图片，照片未参与识别」），UI 里展示给用户。
    var notice: String? = nil

    /// 全部食物的营养合计。
    var total: IntakeNutrition {
        items.map(\.total).reduce(.zero, +)
    }

    var isEmpty: Bool { items.isEmpty }
}

/// 识别来源，UI 里用来显示「AI 识别」或「本地营养库匹配」。
enum MealSource: String, Sendable {
    case ai
    case local
}

/// 食物识别相关的错误。
enum FoodRecognitionError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case notSupported

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "尚未配置 AI 服务的 API Key，请到「设置 → AI 服务」填写，或关闭 AI 识别改用本地营养库匹配。"
        case .invalidResponse:
            return "AI 返回的内容无法解析为营养数据，请换个说法或重试。"
        case .notSupported:
            return "当前模型不支持图片识别，请改用支持视觉的模型，或关闭 AI 识别改用本地营养库匹配。"
        }
    }
}
