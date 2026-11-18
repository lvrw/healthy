import SwiftData
import SwiftUI
import UIKit

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("healthy.onboarded") private var onboarded = false
    @State private var tabState = AppTabState()
    /// 独立的 ➕ 悬浮按钮展开的记录菜单是否可见。
    @State private var showAddMenu = false
    /// 菜单选中的记录类型；非 nil 时呈现对应的原有记录页。
    @State private var activeRecord: AddRecordItem?
    /// 运行时读到的窗口底部安全区高度：不同机型 / 横竖屏 / iPad 各不相同，
    /// ➕ 与菜单的垂直位置由它推导，不再写死针对某一台真机的校准偏移。
    @State private var bottomSafeInset: CGFloat = 0
    /// 从系统菜单栏真实 frame 量出的「菜单栏底边距屏幕底」距离；
    /// 读不到（私有层级变化 / 首帧未布局）时回退到 21pt／62pt 的实测常量。
    @State private var measuredBarBottomGap: CGFloat?
    /// 量到的浮动胶囊高度（真机 / 模拟器实测都是 62pt），用于把 ➕ 垂直居中。
    @State private var measuredBarHeight: CGFloat?

    /// 悬浮圆按钮直径；菜单浮在它上方 10pt。
    private let addButtonSize: CGFloat = 58
    /// 圆按钮底边相对安全区底部的基准距离。
    private let addButtonBottomInset: CGFloat = 8
    /// 菜单与圆按钮之间的间距。
    private let addMenuSpacing: CGFloat = 10
    /// 菜单宽度；相对上一版稍微放大，让 4 行内容更舒展。
    private let addMenuWidth: CGFloat = 268

    /// iOS 26+ 浮动菜单栏底边距屏幕底部的距离。
    /// 优先用 UIKit 层级里系统菜单栏的真实 frame，避免按机型猜系数：
    /// 同一套「安全区 * 系数」在 iOS 26.5 真机与 iOS 27.2 模拟器上差了十几 pt，
    /// 正是之前「偏低 → 偏高」来回摆动的原因。
    /// 两代系统实测都是 **21pt**（iPhone 15 Pro Max / iOS 26.5、
    /// iPhone 18 Pro Max / iOS 27.2），所以首帧读不到时直接用它，不再用猜的系数。
    private var floatingBarBottomGap: CGFloat {
        measuredBarBottomGap ?? 21
    }

    /// 系统浮动菜单栏（胶囊）高度；实测两代系统都是 62pt。
    private var floatingBarHeight: CGFloat {
        measuredBarHeight ?? 62
    }

    /// ➕ 相对安全区底边需要下移多少才能与浮动菜单栏**垂直居中**。
    /// ZStack 的 bottom 对齐点就在安全区底边，`padding(.bottom, 8)` 已先上抬 8pt。
    /// 底边齐平会让 58pt 的圆比 62pt 的胶囊整体低 4pt，看起来像「陷入胶囊」；
    /// 改成中心对齐后上下各留 2pt，视觉上真正平齐。
    private var addButtonAlignmentOffset: CGFloat {
        let verticalCentering = (floatingBarHeight - addButtonSize) / 2
        return max(0, bottomSafeInset + addButtonBottomInset - floatingBarBottomGap - verticalCentering)
    }

    /// 备用读数：某些被安全区裁剪过的坐标系里 GeometryProxy.safeAreaInsets 会退化成 0，
    /// 用 keyWindow 的真实 inset 兜底，保证机型 / 方向差异不会丢失。
    @MainActor
    private var windowBottomSafeInset: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }

    @MainActor
    private var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    /// 遍历 UIKit 视图层级找出系统浮动菜单栏，返回「底边距屏幕底的距离 + 胶囊高度」。
    /// 用类名含 TabBar / Platter、宽度介于 60%~97% 屏宽的视图作为目标；
    /// 私有类名换了就返回 nil，由 21pt / 62pt 的实测常量兜底。
    @MainActor
    private func measureFloatingBar() -> (gap: CGFloat, height: CGFloat)? {
        guard let window = keyWindow else { return nil }
        let shouldLog = ProcessInfo.processInfo.arguments.contains("-LogTabBar")
        var best: CGRect?
        func walk(_ view: UIView) {
            let name = String(describing: type(of: view))
            if name.contains("TabBar") || name.contains("Platter") {
                let rect = view.convert(view.bounds, to: window)
                if shouldLog {
                    NSLog("[TabBarProbe] %@ %@", name, NSCoder.string(for: rect))
                }
                // iOS 26+ 的层级里同时存在「贴底全宽容器」(UITabBar / _UIBottomTabBarGroupView)
                // 和真正的浮动胶囊 (_UITabBarItemPlatterView，左右各留约 21pt 边距)。
                // 只认宽度小于屏宽的胶囊；否则会读到 maxY == 屏高，gap 变成 0，
                // ➕ 直接贴到屏幕最底边。
                if rect.width > window.bounds.width * 0.6,
                   rect.width < window.bounds.width * 0.97,
                   rect.height > 20, rect.height < 160,
                   rect.maxY <= window.bounds.height + 1,
                   rect.maxY > (best?.maxY ?? 0) {
                    best = rect
                }
            }
            for subview in view.subviews { walk(subview) }
        }
        walk(window)
        guard let rect = best else {
            if shouldLog { NSLog("[TabBarProbe] no platter candidate") }
            return nil
        }
        let gap = max(0, window.bounds.height - rect.maxY)
        if shouldLog {
            NSLog("[TabBarProbe] gap=%.2f height=%.2f windowH=%.2f", gap, rect.height, window.bounds.height)
        }
        return (gap, rect.height)
    }

    var body: some View {
        Group {
            if onboarded {
                // 系统 TabView 标签栏：各标签页保留自己的 NavigationStack
                // 与滚动/导航状态。➕ 是叠在标签栏之上的独立悬浮按钮，不占标签位。
                mainStack
            } else {
                OnboardingView()
            }
        }
        .task {
            // 调试用：`-startTab actions` 直接进入指定主标签。
            // 无 UI 自动化的环境里（辅助功能未授权）靠它把某个子页拉到最前面做验证。
            applyStartTabArgumentIfNeeded()
            applyOpenCheckInArgumentIfNeeded()
            await appModel.syncIfNeeded()
        }
    }

    /// 解析 `-startTab <rawValue>` 启动参数；没传或值非法时保持默认「今日」。
    private func applyStartTabArgumentIfNeeded() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-startTab"),
              arguments.count > index + 1,
              let tab = AppTab(rawValue: arguments[index + 1]),
              AppTab.visibleTabs.contains(tab) else { return }
        tabState.selection = tab
    }

    /// 调试用：`-openCheckIn <diet|water|caffeine|mood>` 启动后直接弹出对应记录页，
    /// 便于无 UI 自动化时截图核对打卡页布局 / 样式。
    private func applyOpenCheckInArgumentIfNeeded() {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "-openCheckIn"),
              arguments.count > index + 1,
              let item = AddRecordItem(rawValue: arguments[index + 1]) else { return }
        // 延后一帧，等根视图完成首屏布局再呈现 sheet。
        Task { @MainActor in activeRecord = item }
    }

    private var mainStack: some View {
        ZStack(alignment: .bottomTrailing) {
            // 菜单展开时由 overlay 里的原生模糊层糊住页面与菜单栏；FAB 叠在模糊层之上保持清晰。
            Group {
                TabView(
                    selection: Binding(
                        get: { tabState.selection },
                        set: { newTab in
                            if newTab == .add {
                                // 最右侧空白占位格被点到时也展开菜单，selection 保持原值。
                                withAnimation(addMenuAnimation) { showAddMenu = true }
                                return
                            }
                            guard newTab != tabState.selection else { return }
                            // 记录 Tab 切换耗时：目标页出现时由 .perfPage 结算。
                            PerformanceTrace.shared.beginPageSwitch(to: newTab.title)
                            tabState.selection = newTab
                            if showAddMenu { closeAddMenu() }
                        }
                    )
                ) {
                    ForEach(AppTab.visibleTabs) { tab in
                        tabContent(tab)
                            .tabItem {
                                Label(tab.title, systemImage: tab.symbol)
                            }
                            .tag(tab)
                    }
                    // 只占位、不显示图标文字：把菜单栏最右一格让给独立的 ➕ 圆按钮。
                    Color.clear
                        .tabItem {
                            Text("")
                        }
                        .tag(AppTab.add)
                }
                .environment(tabState)
            }
            // 不再对整棵 TabView 加 animated .blur：逐帧插值高斯模糊半径会重绘
            // 整个页面层级，真机上明显掉帧。模糊改由 overlay 里的系统原生 blur view 承担。

            // overlay 常驻视图树，让 scale / offset / opacity 随 showAddMenu 平滑插值；
            // 若用 if + transition，收起时视图被移除会打断动画。
            addRecordOverlay

            // 圆按钮叠在模糊层之上：菜单展开时仍然清晰可见，并切换成 ✕ 作为关闭入口，
            // 否则按钮被整屏模糊糊掉，看起来像是消失了。
            addButton
                .padding(.trailing, 14)
                .padding(.bottom, addButtonBottomInset)
                .offset(y: addButtonAlignmentOffset)
        }
        // 只做测量的透明层，不参与主视图布局，避免改变 TabView 的安全区行为。
        // 几何读数与窗口读数取较大值：前者能反映方向变化，后者防止读数被裁成 0。
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(
                        key: BottomSafeInsetKey.self,
                        value: max(proxy.safeAreaInsets.bottom, windowBottomSafeInset)
                    )
            }
        )
        .onPreferenceChange(BottomSafeInsetKey.self) { inset in
            guard inset != bottomSafeInset else { return }
            bottomSafeInset = inset
            // 方向 / 机型变化后按新的布局重新量一次菜单栏。
            measuredBarBottomGap = nil
            measuredBarHeight = nil
            scheduleFloatingBarMeasurement()
        }
        // 首帧系统菜单栏还没挂进视图层级（真机实测要等约 1s），
        // 用几次短重试逐步拿真实值；拿到后就不再遍历层级。
        .task { scheduleFloatingBarMeasurement() }
        .sheet(item: $activeRecord) { item in
            recordSheet(item)
        }
    }

    /// 菜单展开 / 收起用的弹性动画；比背景模糊略带一点回弹，观感更接近系统弹层。
    private let addMenuAnimation: Animation = .spring(response: 0.34, dampingFraction: 0.82)

    /// 分几次短重试量系统浮动菜单栏：首帧它还没挂进层级，一次读不到就永远读不到。
    /// 拿到值后立即停止（后续重试发现已有值直接返回），菜单动画期间不再遍历 UIKit 层级。
    private func scheduleFloatingBarMeasurement() {
        Task { @MainActor in
            for delay in [0.05, 0.2, 0.5, 1.0, 1.8] {
                try? await Task.sleep(for: .seconds(delay))
                if measuredBarBottomGap != nil, measuredBarHeight != nil { return }
                if let measured = measureFloatingBar() {
                    measuredBarBottomGap = measured.gap
                    measuredBarHeight = measured.height
                }
            }
        }
    }

    /// 独立的悬浮 ➕ 按钮：不进 tabItem，也不跟 4 个业务标签均分宽度。
    /// 配色走原型色板的绿色（今日 / 行动 / 趋势 / 健康各页都以绿为强调色），不再用橙色。
    private var addButton: some View {
        Button {
            withAnimation(addMenuAnimation) { showAddMenu.toggle() }
        } label: {
            Image(systemName: showAddMenu ? "xmark" : "plus")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(showAddMenu ? 90 : 0))
                .frame(width: addButtonSize, height: addButtonSize)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [AppPalette.green, AppPalette.greenDeep],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
                .shadow(color: AppPalette.greenDeep.opacity(0.32), radius: 12, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showAddMenu ? "关闭记录菜单" : "添加记录")
    }

    /// 原生模糊层 + 透明点击层 + 从 ➕ 上方靠右展开的记录列表。
    /// 模糊不再由 SwiftUI 逐帧插值 radius，改为 UIVisualEffectView 的 effect 渐变，
    /// 由系统 GPU 合成，页面本身不重绘。
    private var addRecordOverlay: some View {
        ZStack(alignment: .bottomTrailing) {
            BlurBackdrop(isActive: showAddMenu)
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            // 模糊之上再压一层极淡的渐变暗色：上浅下深带来一点纵深，
            // 让白色菜单卡自然浮起，不靠描边 / 大阴影也能和背景分开。
            LinearGradient(
                colors: [.black.opacity(0.04), .black.opacity(0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(showAddMenu ? 1 : 0)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.26), value: showAddMenu)
            Color.clear
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { closeAddMenu() }
            addRecordMenu
                .frame(width: addMenuWidth)
                .padding(.trailing, 14)
                // FAB 的下移量随机型变化，菜单用同一个自适应值保持 10pt 间距。
                .padding(
                    .bottom,
                    addButtonBottomInset + addButtonSize + addMenuSpacing - addButtonAlignmentOffset
                )
                // 展开时卡片立即就位、不给它自己的动画，避免外层事务干扰
                // 内部逐行的 delay 错峰；收起时整体快速缩回 ➕。
                .opacity(showAddMenu ? 1 : 0)
                .scaleEffect(showAddMenu ? 1 : 0.9, anchor: .bottomTrailing)
                .animation(
                    showAddMenu ? nil : .easeOut(duration: 0.14),
                    value: showAddMenu
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 收起后整层不再拦截点击，避免盖住 TabView 与页面内容。
        .allowsHitTesting(showAddMenu)
    }

    /// 4 类记录入口；点击后复用既有记录页面，不新建页面。
    /// 展开时从最下面一行开始，逐行向上冒出（轻微上浮 + 淡入），收起时一起快速淡出。
    private var addRecordMenu: some View {
        VStack(spacing: 0) {
            ForEach(Array(AddRecordItem.allCases.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    if index > 0 {
                        Divider().padding(.leading, 60)
                    }
                    Button {
                        closeAddMenu()
                        // 让菜单收起的过渡先提交，再呈现 sheet，避免同一事务里
                        // overlay 移除与 sheet 呈现互相打断。
                        Task { @MainActor in activeRecord = item }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(item.tint)
                                .frame(width: 32, height: 32)
                                .background(
                                    item.tint.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            Text(item.title)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        // 整行都可点：默认只有图标/文字/箭头这些实际内容区域响应，
                        // Spacer 的留白不会触发 Button；contentShape 把命中区扩到整行矩形。
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .opacity(showAddMenu ? 1 : 0)
                .offset(y: showAddMenu ? 0 : 16)
                .scaleEffect(showAddMenu ? 1 : 0.96, anchor: .bottom)
                .animation(
                    showAddMenu
                        ? addMenuAnimation.delay(
                            Double(AddRecordItem.allCases.count - 1 - index) * 0.055
                        )
                        : .easeOut(duration: 0.12),
                    value: showAddMenu
                )
            }
        }
        // 参考图样式：极淡的半透明玻璃卡，不描边、不加大阴影。
        // 背景已模糊且轻压暗，卡片用系统卡片色浮起，深浅色模式都成立。
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.94))
        )
        .shadow(color: .black.opacity(0.08), radius: 28, x: 0, y: 12)
    }

    private func closeAddMenu() {
        withAnimation(addMenuAnimation) { showAddMenu = false }
    }

    /// 记录页全部复用既有实现，日期取今天。
    @ViewBuilder
    private func recordSheet(_ item: AddRecordItem) -> some View {
        let date = DayKey.startOfDay(.now)
        switch item {
        case .diet: FoodRecognitionView(date: date)
        case .water: ActionCheckInSheet(kind: .water, date: date)
        case .caffeine: ActionCheckInSheet(kind: .caffeine, date: date)
        case .mood: MoodRecordSheet(date: date)
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab) -> some View {
        content(for: tab)
            // 统一挂页面性能埋点：结算 Tab 切换耗时 + 捕捉首帧主线程阻塞。
            .perfPage(tab.title)
    }

    @ViewBuilder
    private func content(for tab: AppTab) -> some View {
        switch tab {
        case .today: TodayView()
        case .actions: ActionHubView()
        case .trends: TrendsView()
        case .health: HealthProfileView()
        // 设置已从底部菜单栏移到今日页右上角，此分支仅保留枚举穷举。
        case .settings: SettingsView()
        case .add: EmptyView()
        }
    }
}

/// 独立 ➕ 按钮展开的 4 类记录：饮食、饮水、咖啡因、当前感受。
enum AddRecordItem: String, CaseIterable, Identifiable, Sendable {
    case diet
    case water
    case caffeine
    case mood

    var id: String { rawValue }

    var title: String {
        switch self {
        case .diet: return "饮食"
        case .water: return "饮水"
        case .caffeine: return "咖啡因"
        case .mood: return "当前感受"
        }
    }

    var icon: String {
        switch self {
        case .diet: return "fork.knife"
        case .water: return "drop.fill"
        case .caffeine: return "mug.fill"
        case .mood: return "face.smiling"
        }
    }

    var tint: Color {
        switch self {
        case .diet: return .green
        case .water: return .blue
        case .caffeine: return .brown
        case .mood: return .purple
        }
    }
}

/// 测量层回传的布局数据：底部安全区 + 系统菜单栏真实 frame 推出的底边间距。
/// 把窗口底部安全区高度从测量层传回 RootView；随机型 / 方向变化自动更新。
private struct BottomSafeInsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// 系统原生渐进模糊层：只在开 / 关切换时对 UIVisualEffectView.effect 做一次动画，
/// 由系统 GPU 合成，不逐帧重绘后面的 SwiftUI 页面（原先 animated .blur 的卡顿来源）。
private struct BlurBackdrop: UIViewRepresentable {
    let isActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: nil)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        guard context.coordinator.isActive != isActive else { return }
        context.coordinator.isActive = isActive
        UIView.animate(
            withDuration: 0.26,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            uiView.effect = isActive ? UIBlurEffect(style: .systemThinMaterial) : nil
        }
    }

    final class Coordinator {
        var isActive = false
    }
}

#Preview {
    let container = try! ModelContainer(
        for: DailyMetrics.self, DailyScore.self, DailyReport.self, ChatSession.self, ActionCheckIn.self, MoodEntry.self, CustomFood.self, FrequentFood.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return RootView()
        .environment(AppModel(context: container.mainContext))
        .modelContainer(container)
}
