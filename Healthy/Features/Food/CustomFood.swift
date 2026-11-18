import Foundation
import SwiftData

/// 用户自定义的常吃食物，存于本地（SwiftData），可在「设置 → 本地营养库」里增删改。
/// 关闭 AI 识别时，这些食物会和内置营养库一起参与文字匹配，优先命中用户常吃的菜。
@Model
final class CustomFood {
    var id: String
    var name: String
    /// 别名 / 关键词（JSON 编码的 [String]），文字描述里出现任一即视为命中。
    var keywordsJSON: String
    /// 数量描述，如「150g / 330ml」。
    var portion: String
    /// 该数量对应的营养（JSON 编码的 IntakeNutrition）。
    var nutritionJSON: String
    /// 所属分组 ID（FoodGroup.id）；为 nil 表示未分组（归「我的常吃食物」）。
    var groupID: String?
    /// 官网产品图片 URL（远程），nil 表示无图。
    var imageURL: String?
    var createdAt: Date

    init(name: String, keywords: [String], portion: String, nutrition: IntakeNutrition, groupID: String? = nil, imageURL: String? = nil) {
        self.id = UUID().uuidString
        self.name = name
        self.keywordsJSON = (try? JSONEncoder().encode(keywords))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        self.portion = portion
        self.nutritionJSON = (try? JSONEncoder().encode(nutrition))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        self.groupID = groupID
        self.imageURL = imageURL
        self.createdAt = .now
    }

    var keywords: [String] {
        (keywordsJSON.data(using: .utf8))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    var nutrition: IntakeNutrition {
        (nutritionJSON.data(using: .utf8))
            .flatMap { try? JSONDecoder().decode(IntakeNutrition.self, from: $0) } ?? .zero
    }

    /// 转成内置库统一的 FoodItem，便于和 FoodDatabase.all 一起参与匹配。
    var foodItem: FoodItem {
        FoodItem(id: id, name: name, keywords: keywords, portion: portion, nutrition: nutrition, imageURL: imageURL)
    }
}
