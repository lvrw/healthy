import SwiftUI

/// 页面性能埋点修饰器。
///
/// 两个作用：
/// 1. 页面出现时结算由 TabView 选择触发的「切换耗时」计时（见 PerformanceTrace.beginPageSwitch）。
/// 2. 捕捉「首帧阻塞」：从 onAppear 到主线程下一次空闲的间隔。若页面 body 计算 / 布局很重，
///    主队列的 async 回调会被推迟，这个间隔就大——正是用户感知到的「切过去卡一下」。
///    小于 8ms 的抖动不记录，避免噪声淹没统计。
struct PerfPageModifier: ViewModifier {
    let name: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                let appeared = Date()
                PerformanceTrace.shared.endPageSwitchIfNeeded(pageName: name)
                DispatchQueue.main.async {
                    let blockedMs = -appeared.timeIntervalSinceNow * 1000
                    if blockedMs >= 8 {
                        PerformanceTrace.shared.record(
                            "\(name) · 首帧阻塞",
                            category: .page,
                            durationMs: blockedMs,
                            start: appeared,
                            detail: "onAppear → 主线程空闲"
                        )
                    }
                }
            }
    }
}

extension View {
    /// 给页面挂上性能埋点；name 要与 TabView 切换时传入的目标名一致。
    func perfPage(_ name: String) -> some View {
        modifier(PerfPageModifier(name: name))
    }
}
