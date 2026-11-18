import SwiftUI

/// 主导航标签定义：今日 / 行动 / 趋势 / 健康（设置已移到今日页右上角）。
/// 底部导航使用系统 TabView 标签栏（用户要求），本文件只保留标签元数据与选中态。
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case actions
    case trends
    case health
    case settings
    /// 菜单栏最右侧的空白占位（tabItem 为 Text("")），把这一格让给独立的 ➕ 悬浮圆按钮。
    /// RootView 会拦截该 selection，选中态始终停留在原来的业务标签上。
    case add

    var id: String { rawValue }

    /// 底部菜单栏的 4 个业务标签；设置移到今日页右上角，➕ 单独作为占位标签。
    static let visibleTabs: [AppTab] = [.today, .actions, .trends, .health]

    var title: String {
        switch self {
        case .today: return "今日"
        case .actions: return "行动"
        case .trends: return "趋势"
        case .health: return "健康"
        case .settings: return "设置"
        case .add: return ""
        }
    }

    var symbol: String {
        switch self {
        case .today: return "heart.text.square"
        case .actions: return "figure.strengthtraining.traditional"
        case .trends: return "chart.xyaxis.line"
        case .health: return "cross.case.fill"
        case .settings: return "gearshape"
        case .add: return "plus"
        }
    }
}

/// 主标签选中态。放在环境中，便于需要的地方读取当前标签。
@Observable
final class AppTabState {
    var selection: AppTab = .today
}
