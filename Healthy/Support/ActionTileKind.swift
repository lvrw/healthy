import Foundation
import SwiftUI

enum ActionTileKind: String, CaseIterable, Identifiable, Sendable {
    case daylight
    case mindful
    case steps
    case noise
    case water
    case caffeine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: return "晒太阳"
        case .mindful: return "呼吸正念"
        case .steps: return "步数"
        case .noise: return "环境音量"
        case .water: return "喝水"
        case .caffeine: return "咖啡因"
        }
    }

    var icon: String {
        switch self {
        case .daylight: return "sun.max.fill"
        case .mindful: return "wind"
        case .steps: return "figure.walk"
        case .noise: return "speaker.wave.3.fill"
        case .water: return "drop.fill"
        case .caffeine: return "mug.fill"
        }
    }

    var color: Color {
        switch self {
        case .daylight: return Color.yellow
        case .mindful: return Color.teal
        case .steps: return Color.green
        case .noise: return Color.purple
        case .water: return Color.blue
        case .caffeine: return Color.brown
        }
    }

    var isManual: Bool { self == .water || self == .caffeine }

    /// 详情页主色：跟随行动页标签图标色（日照黄 / 呼吸浅蓝 / 步数绿 / 音量紫 / 喝水深蓝 / 咖啡褐）。
    /// 6 个标签直接取 color；仅出现在洞察「关键行动」的分析项按同类标签取色。
    static func tint(for action: InsightAction) -> Color {
        if let kind = allCases.first(where: { $0.insightAction == action }) {
            return kind.color
        }
        switch action {
        case .sleep7h, .sleepEfficiency90, .shortSleep6h: return .purple
        case .daylight20, .lowDaylight5: return .yellow
        case .steps8000, .flights10, .lowSteps3000: return .green
        default: return .green
        }
    }

    /// 映射到「智能建议 / 详情」分析用的 InsightAction（按阈值细分）。
    /// 让底部 6 个标签都能进入同一套「查看详情」页（压力关联 / 逐日日历 / 等级分布）。
    var insightAction: InsightAction {
        switch self {
        case .daylight: return .daylight20
        case .mindful: return .mindful5
        case .steps: return .steps8000
        case .noise: return .quietUnder55
        case .water: return .water1500
        case .caffeine: return .caffeineModerate
        }
    }

    /// 手动打卡单位说明。
    var manualUnit: String {
        switch self {
        case .water: return "毫升"
        case .caffeine: return "毫克"
        default: return ""
        }
    }

    static let defaultOrder: [ActionTileKind] = [.daylight, .mindful, .steps, .noise, .water, .caffeine]

    static func storedOrder(defaults: UserDefaults = .standard) -> [ActionTileKind] {
        let keys = defaults.stringArray(forKey: orderKey) ?? []
        let restored = keys.compactMap(ActionTileKind.init(rawValue:))
        let missing = defaultOrder.filter { !restored.contains($0) }
        return restored + missing
    }

    static func store(_ order: [ActionTileKind], defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: orderKey)
    }

    private static let orderKey = "healthy.actionTileOrder"
}

/// 行动页 3 列格子里的指标：原来的 4 个标签（锻炼已升为全宽「健身」概览卡）。
/// 这些格子长按即可拖动排序，顺序存 UserDefaults。
enum ActionGridTile: String, CaseIterable, Identifiable, Sendable {
    case daylight
    case mindful
    case steps
    case noise

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight: return ActionTileKind.daylight.title
        case .mindful: return ActionTileKind.mindful.title
        case .steps: return ActionTileKind.steps.title
        case .noise: return ActionTileKind.noise.title
        }
    }

    var icon: String {
        switch self {
        case .daylight: return ActionTileKind.daylight.icon
        case .mindful: return ActionTileKind.mindful.icon
        case .steps: return ActionTileKind.steps.icon
        case .noise: return ActionTileKind.noise.icon
        }
    }

    var color: Color {
        switch self {
        case .daylight: return ActionTileKind.daylight.color
        case .mindful: return ActionTileKind.mindful.color
        case .steps: return ActionTileKind.steps.color
        case .noise: return ActionTileKind.noise.color
        }
    }

    /// 点进详情时使用的分析项：步数直接用「每日 8000 步」的行动分析。
    var insightAction: InsightAction {
        switch self {
        case .steps: return .steps8000
        case .daylight: return ActionTileKind.daylight.insightAction
        case .mindful: return ActionTileKind.mindful.insightAction
        case .noise: return ActionTileKind.noise.insightAction
        }
    }

    /// 默认顺序与用户指定的模块顺序一致：睡眠 → 健身 → 饮食 → 饮水 → 咖啡因 → 其余 4 项。
    static let defaultOrder: [ActionGridTile] = [.daylight, .mindful, .steps, .noise]

    /// 读回用户拖过的顺序；新增 / 缺失的项按默认顺序补齐，不会丢格子。
    static func storedOrder(defaults: UserDefaults = .standard) -> [ActionGridTile] {
        let keys = defaults.stringArray(forKey: orderKey) ?? []
        let restored = keys.compactMap(ActionGridTile.init(rawValue:))
        let missing = defaultOrder.filter { !restored.contains($0) }
        return restored + missing
    }

    static func store(_ order: [ActionGridTile], defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: orderKey)
    }

    private static let orderKey = "healthy.actionGridOrder"
}

// configured by qoder