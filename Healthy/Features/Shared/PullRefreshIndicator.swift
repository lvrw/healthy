import SwiftUI

/// 给 ScrollView 套上 **iOS 标准** 的顶部下拉刷新：系统原生 `.refreshable` 旋转圈。
///
/// 不做任何自定义反馈——之前加过自定义圈（与原生 spinner 重叠）、
/// 手动 feedback generator 与 .sensoryFeedback（松手时阻塞主线程），
/// 反复造成「圈重叠」和「卡两下」。标准样式交给系统，最稳。
@MainActor
private struct PullRefreshModifier: ViewModifier {
    /// 页面各自的刷新逻辑。
    let work: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.refreshable {
            await work()
        }
    }
}

extension View {
    /// 顶部下拉刷新：work 为页面自定义刷新动作，视觉与交互完全走系统原生。
    @MainActor
    func withPullToRefresh(
        work: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(PullRefreshModifier(work: work))
    }
}
