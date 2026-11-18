import SwiftUI

extension StressLevel {
    /// 原型四档状态色：状态优秀绿 / 状态正常紫蓝 / 注意压力橙 / 压力过载粉。
    var tint: Color {
        switch self {
        case .low: return AppPalette.green
        case .moderateLow: return AppPalette.lav
        case .elevated: return AppPalette.orange
        case .high: return AppPalette.pink
        }
    }

    /// 原型可见文案。评分引擎与 AI 提示词仍使用内部语义 label（低/中低/偏高/高），
    /// 仅在 UI 展示层替换为截图中的四档名称，避免改动既有计算与测试契约。
    var displayName: String {
        switch self {
        case .low: return "状态优秀"
        case .moderateLow: return "状态正常"
        case .elevated: return "注意压力"
        case .high: return "压力过载"
        }
    }
}

/// 今日页状态条：原型从左到右为 压力过载 → 注意压力 → 状态正常 → 状态优秀，
/// 且四段宽度约为 1 : 1 : 1 : 2.4。
enum AppStatusScale {
    static let colors: [Color] = [
        AppPalette.pink.opacity(0.65),
        AppPalette.orange.opacity(0.65),
        AppPalette.lav.opacity(0.65),
        AppPalette.green,
    ]
    static let weights: [Double] = [1, 1, 1, 2.4]
}
