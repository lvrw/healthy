import Foundation
import SwiftData

/// 「常用饮食」：从拍照 / 文字识别并保存的食物里自动收集，与用户手动添加的「我的常吃食物」（CustomFood）区分开。
/// 同样会和内置库一起参与本地营养库匹配（按名称命中），并随保存次数累加，便于高频食物优先展示与去重。
@Model
final class FrequentFood {
    var id: String
    var name: String
    /// 数量描述，如「150g / 330ml」。
    var portion: String
    /// 该数量对应的营养（JSON 编码的 IntakeNutrition）。
    var nutritionJSON: String
    /// 官网产品图片 URL（远程），nil 表示无图。
    var imageURL: String?
    /// 被识别保存的次数，用于排序与去重累加。
    var useCount: Int
    var lastUsedAt: Date
    var createdAt: Date

    init(name: String, portion: String, nutrition: IntakeNutrition, imageURL: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.portion = portion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "100g"
            : portion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nutritionJSON = (try? JSONEncoder().encode(nutrition))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.imageURL = imageURL
        self.useCount = 1
        self.lastUsedAt = .now
        self.createdAt = .now
    }

    var nutrition: IntakeNutrition {
        (nutritionJSON.data(using: .utf8))
            .flatMap { try? JSONDecoder().decode(IntakeNutrition.self, from: $0) } ?? .zero
    }

    /// 转成内置库统一的 FoodItem，按名称匹配，便于和 FoodDatabase.all 一起参与匹配。
    var foodItem: FoodItem {
        FoodItem(id: id, name: name, keywords: [name], portion: portion, nutrition: nutrition, imageURL: imageURL)
    }
}
