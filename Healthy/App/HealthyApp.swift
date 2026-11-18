import Combine
import SwiftData
import SwiftUI

@main
struct HealthyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    /// 基础设置里的夜间模式；system 时跟随系统外观。
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system
    private let container: ModelContainer
    @State private var appModel: AppModel
    /// App 长时间停留在前台时，也按时刻推进阶段目标（15 分钟一次本地重算）。
    private let dayProgressTimer = Timer.publish(every: 15 * 60, on: .main, in: .common).autoconnect()

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: DailyMetrics.self, DailyScore.self, DailyReport.self, ChatSession.self, ActionCheckIn.self, MoodEntry.self, CustomFood.self, FrequentFood.self, FoodGroup.self)
        } catch {
            fatalError("无法初始化本地数据库：\(error)")
        }
        self.container = container
        _appModel = State(initialValue: AppModel(context: container.mainContext))

        #if DEBUG
        if CommandLine.arguments.contains("-seedDemoData") {
            let context = container.mainContext
            _ = try? DemoDataInstaller.install(into: context)
        }
        #endif
        // 预置内置食物分组（麦当劳全菜单 / 瑞幸咖啡）；其它分组缺失才补，
        // 瑞幸按数据版本号同步官网菜单，用户自行新增的条目不受影响。
        FoodSeed.ensureBuiltinGroups(in: container.mainContext)
        // 激活与手表伴侣 App 的会话：激活成功后会立刻把当前喝水目标推过去，
        // 让手表不再用写死的 1500。
        WaterGoalWatchSync.shared.start()
        appLog(.info, "App", "启动 bundle=\(Bundle.main.bundleIdentifier ?? "?") tz=\(Calendar.current.timeZone.identifier)")
        // 累计型指标按当前时刻的清醒 / 日光窗口评分：冷启动时先按此刻重算一次，
        // 避免沿用上次退出时缓存的分数。重算在后台执行，不阻塞启动与首屏渲染。
        Task { try? await ScoreStore.recomputeAll(in: container.mainContext) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                // 基础设置里的夜间模式：跟随系统时写 .unspecified 交还系统，
                // 浅色 / 深色时强制为对应外观，页面与弹层一起切换。
                .appAppearance(appearance)
                // 页面底色、文字与卡片全部使用系统语义色，跟随系统浅色 / 深色模式。
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    appLog(.info, "App", "回到前台 key=\(DayKey.key(for: .now))")
                    // 每次回到前台按最新时刻重算评分；不依赖 HealthKit 同步节流。
                    // 重算已改为后台执行，主线程只承担 SwiftData 快照读取与差异落库。
                    Task {
                        try? await ScoreStore.recomputeAll(in: container.mainContext)
                        await appModel.syncIfNeeded()
                    }
                }
                .onReceive(dayProgressTimer) { _ in
                    Task { try? await ScoreStore.recomputeAll(in: container.mainContext) }
                }
        }
        .modelContainer(container)
    }
}
