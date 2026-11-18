import Foundation
import SwiftData

/// 本地营养库的分组（如「麦当劳早餐」「瑞幸咖啡」）。分组下挂载若干自定义食物（CustomFood.groupID）。
///
/// 分组分两类：
/// - **用户分组**（isBuiltin = false）：用户手动创建，可随意增删 / 重命名 / 删除。
/// - **系统分组**（isBuiltin = true）：首次启动时由 FoodSeed 预置（如麦当劳菜单、瑞幸咖啡），
///   相当于品牌官方的营养库，用户只能查看和用于识别匹配，**不允许**增删其中食物、
///   重命名分组、删除分组、把食物移出分组，避免用户数据被系统同步覆盖或误改。
@Model
final class FoodGroup {
    var id: String
    var name: String
    /// 排序权重，越小越靠前。
    var sortOrder: Int
    /// 是否为系统预置的品牌分组（麦当劳 / 瑞幸）。true 时整个分组只读。
    var isBuiltin: Bool
    var createdAt: Date

    init(id: String = UUID().uuidString, name: String, sortOrder: Int = 0, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.isBuiltin = isBuiltin
        self.createdAt = .now
    }
}
