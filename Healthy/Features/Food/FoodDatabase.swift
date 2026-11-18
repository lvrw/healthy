import Foundation

/// 本地营养库里的一条食物记录。营养值为「portion」标注的那一份的含量。
/// 数值为常见参考值（千卡 / 克 / 毫克），用于本地营养库匹配（无 AI）时的关键词匹配回填。
struct FoodItem: Identifiable, Codable, Sendable {
    var id: String
    var name: String
    /// 别名 / 关键词，文字描述里出现任一即视为命中（例如「米饭」命中「白饭」）。
    var keywords: [String]
    /// 这一份的量描述，如「1 碗 / 150g」。
    var portion: String
    var nutrition: IntakeNutrition
    /// 官网产品图片 URL（远程），用于食物展示和 AI 识别记录。nil 表示无图。
    var imageURL: String?
}

/// 内置本地食物营养库 + 文字匹配。纯 Foundation 实现，便于单元测试，
/// 也避免引入资源打包流程。关闭 AI 识别时，用户用文字描述食物，
/// 系统按名称 / 关键词匹配并回填营养（拍照无 AI 时退化为文字匹配）。
enum FoodDatabase {
    /// 通用内置单品库（米饭 / 鸡蛋 / 牛奶 等）已从 UI 中移除。
    /// 现在统一由「品牌预置组」（FoodSeed 里的麦当劳 / 瑞幸）和用户自定义食物组成
    /// 本地营养库，匹配时通过 FoodRecognitionService 传入 custom 参数完成。
    static let all: [FoodItem] = []

    /// 按文字描述匹配命中的食物（不区分大小写）。命中规则：描述里出现食物名或任一关键词。
    /// 内置库在前，用户自定义食物（custom）追加在后一起参与匹配；未命中返回空数组。
    static func match(_ text: String, custom: [FoodItem] = []) -> [FoodItem] {
        let lowered = text.lowercased()
        guard !lowered.isEmpty else { return [] }
        return (all + custom).filter { food in
            let name = food.name.lowercased()
            if lowered.contains(name), !name.isEmpty { return true }
            return food.keywords.contains { keyword in
                let k = keyword.lowercased()
                return !k.isEmpty && lowered.contains(k)
            }
        }
    }

    /// 搜索框用：返回名称或关键词包含查询词的食物，供用户点选。
    static func search(_ query: String, custom: [FoodItem] = []) -> [FoodItem] {
        match(query, custom: custom)
    }

    /// 份量解析不到有效「数值 + 单位」时的默认值。
    static let defaultPortion = PortionValue(amount: 100, unit: "g")

    /// 中英文单位别名 → 统一展示符号。覆盖内置库与 AI 常见写法。
    private static let unitAliases: [String: String] = [
        "g": "g", "克": "g", "gram": "g", "grams": "g",
        "kg": "kg", "千克": "kg", "公斤": "kg",
        "mg": "mg", "毫克": "mg",
        "ml": "ml", "毫升": "ml", "milliliter": "ml", "milliliters": "ml",
        "l": "L", "升": "L", "liter": "L", "liters": "L",
        "oz": "oz", "盎司": "oz",
    ]

    /// 从内置库 / AI 返回的自由文本份量里解析出「数值 + 实际单位」。
    /// 单位跟随食物实际来源（固体 g、饮品 ml、大瓶装 L 等），不做 g/ml 换算。
    /// 例：「1 碗 / 150g」→(150,"g")，「1 罐 / 330ml」→(330,"ml")，「100g」→(100,"g")。
    /// 取最后一个「数字 + 已知单位」匹配（份量说明通常在斜杠后，避免把「1 碗」的 1 当份量）。
    static func parsePortion(from text: String) -> PortionValue {
        let lowered = text.lowercased()
        // 长单位放前面，避免 ml/kg/mg 被 l/g 抢占；中文单位同样优先长词。
        let unit = #"(?:milliliters?|liters?|grams?|毫升|毫克|千克|公斤|盎司|ml|kg|mg|oz|l|升|克|g)"#
        let pattern = "([0-9]+(?:\\.[0-9]+)?)\\s*(" + unit + ")"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return defaultPortion }
        let matches = regex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
        if let match = matches.last,
           match.numberOfRanges > 2,
           let numberRange = Range(match.range(at: 1), in: lowered),
           let unitRange = Range(match.range(at: 2), in: lowered),
           let amount = Double(lowered[numberRange]), amount > 0 {
            let raw = String(lowered[unitRange])
            return PortionValue(amount: amount, unit: unitAliases[raw] ?? raw)
        }
        // 没有带单位的数字时，退而取文本里最后一个纯数字（如 AI 只回「150」），单位默认 g。
        // 太小的数（≤10，如「1 份」「2 块」）视为份数而非份量，忽略并用默认值。
        let digitPattern = #"[0-9]+(?:\.[0-9]+)?"#
        guard let digitRegex = try? NSRegularExpression(pattern: digitPattern) else { return defaultPortion }
        let digitMatches = digitRegex.matches(in: lowered, range: NSRange(lowered.startIndex..., in: lowered))
        if let match = digitMatches.last,
           let range = Range(match.range, in: lowered),
           let amount = Double(lowered[range]), amount > 10 {
            return PortionValue(amount: amount, unit: defaultPortion.unit)
        }
        return defaultPortion
    }
}
