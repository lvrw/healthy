import SwiftData
import SwiftUI

/// 行动页：周历日期切换 + 概览卡（睡眠 / 健身 / 饮食 / 饮水 / 咖啡因）+ 3 列指标格子。
///
/// 结构约定：
/// - 顶部周历可切换日期，页面内所有指标 / 评分 / 打卡 / 感受都按选中日期取数。
/// - 顺序固定为 概览 → 智能建议 → 睡眠 → 健身 → 饮食 → 饮水 → 咖啡因 → 感受记录 → 锻炼 → 晒太阳 / 呼吸正念 / 步数 / 环境音量。
/// - 五张概览卡统一为深色卡：标题行 + 三列指标 + 右侧进度环，整卡点进详情。
/// - 「记录 / 设置」入口不贴在外层卡片上，而是收进点进去之后的详情页顶部（`ActionEntryBar`）：
///   饮水 → 喝水记录 / 喝水配置，咖啡因 → 咖啡因记录 / 咖啡因配置，
///   饮食 → 饮食记录 / 饮食设置，步数 → 步数目标设置。
/// - 指标格子长按即可拖动排序（不再需要先点「排序」进入排序模式）；
///   排序按钮移到页面顶部（与「今日概览」同排），拖动时格子放大并带投影跟随手指。
/// - 身体成分已移到首页「指标详情」，行动页不再重复展示。
struct ActionView: View {
    /// 由 ActionHubView 挂载时隐藏系统大标题，避免与原型「行动 / 洞察」标题式子页签重复。
    var showsNavigationTitle: Bool = true
    /// 全局数据同步入口：顶部下拉刷新时重新拉取 HealthKit 数据并重算评分。
    @Environment(AppModel.self) private var appModel
    /// 实时摄入合计回写老打卡 syncID 时需要用到 modelContext。
    @Environment(\.modelContext) private var context

    /// 支持切换日期后，查询窗口放宽到近 60 天：页面只读取选中日期的具体数值，
    /// 不会为窗口内每一天解析 snapshot（只有选中当天的 snapshot 会被访问）。
    /// 描述符写成静态常量，保证实例稳定，避免 SwiftUI 重建视图时被当成新查询重新取数。
    @Query(ActionQuery.actionWindowMetrics) private var metrics: [DailyMetrics]
    @Query(ActionQuery.actionWindowScores) private var scores: [DailyScore]
    @Query private var checkIns: [ActionCheckIn]
    /// 选中日期的感受记录，以及健康 App 同步来的心理状态。
    @Query private var moodEntries: [MoodEntry]
    /// 智能建议优先展示该日已缓存的 AI 简报；没有缓存时回退到本机确定性文案。
    @Query private var reports: [DailyReport]

    /// 当前选中日期；默认今天，点周历或日历后切换，页面所有卡片跟着换数。
    @State private var selectedDate: Date = DayKey.startOfDay(.now)
    /// 日历选择器 sheet 的显隐。
    @State private var showsDatePicker = false
    /// 数据不全标记面板的显隐；标记目标为当前选中日期（可为历史日期）。
    @State private var showsIncompletePicker = false
    /// 感受记录 sheet 的显隐（记录日期跟随选中日期）。
    @State private var showsMoodSheet = false
    /// 3 列格子的顺序（锻炼 + 晒太阳 / 呼吸正念 / 步数 / 环境音量），长按拖动后写回偏好。
    @State private var gridOrder = ActionGridTile.storedOrder()
    /// 点击卡片后进入的详情页；饮食走营养指标详情，其余走行动分析详情。nil 表示未进入。
    @State private var detailRoute: ActionDetailRoute?
    /// 饮水 / 咖啡因的实时合计：与喝水记录页共用同一套取值 + 去重口径。
    /// 快照 waterTotalMl 在「本 App 回写但本地已删的孤儿样本」场景会被 nutritionByDay
    /// 一律排除，而记录页保留孤儿，导致两页数字不一致。这里直接按记录页口径实时读取。
    @State private var liveIntakeTotals: [String: Double] = [:]
    /// 实时读取是否成功。失败时回退到快照值，避免 HealthKit 暂时不可用导致卡片归零。
    @State private var liveIntakeLoaded = false
    /// 正在被拖动的格子 id：非 nil 时该格子放大 + 投影，做出「被拎起来」的拖动特效。
    @State private var draggingTileID: String?
    /// 拖动兜底计时：拖动被取消时系统不会回调 drop，用它把拖动态复原。
    @State private var dragResetTask: Task<Void, Never>?
    /// 顶部「排序」按钮的提示态：只控制提示文案与抓取手柄，长按拖动本身始终可用。
    @State private var showsReorderHint = false

    /// 目标 / 阈值全部用 @AppStorage 直接绑定 UserDefaults：配置页一保存，
    /// 本页立刻刷新。之前在 body 里裸读 UserDefaults 不产生 SwiftUI 依赖，
    /// 用户在打卡页把喝水目标改成 2000 后，行动页仍会一直显示旧的 1500。
    @AppStorage(IntakeGoal.waterDefaultsKey) private var waterTarget = IntakeGoal.defaultWaterTargetMl
    @AppStorage(IntakeGoal.caffeineDefaultsKey) private var caffeineLimit = IntakeGoal.defaultCaffeineLimitMg
    @AppStorage(ActionGoal.stepsDefaultsKey) private var stepsTarget = ActionGoal.defaultStepsTarget
    @AppStorage(ActionGoal.weeklyWeightLossDefaultsKey) private var weeklyLoss = ActionGoal.defaultWeeklyWeightLossKg

    /// 格子区固定 3 列等宽。
    private let columnCount = 3

    private var key: String { DayKey.key(for: selectedDate) }

    private var isToday: Bool { key == ActionQuery.todayKey }

    private var isFuture: Bool { selectedDate > DayKey.startOfDay(.now) }

    private var dayMetrics: DailyMetrics? {
        metrics.first { $0.dayKey == key }
    }

    /// 选中日期的状态分；窗口内没有这天时返回 nil，概览卡显示空态。
    private var dayScore: DailyScore? {
        scores.first { $0.dayKey == key }
    }

    /// 选中日期的摄入热量：优先取同步合并后的总量；若被旧版同步逻辑冲成 nil，
    /// 回退到 WaterMerge 存下的本 App 食物打卡能量，避免行动页饮食卡一直显示「—」。
    private var selectedDietEnergyKcal: Double? {
        dayMetrics?.dietaryEnergyKcal ?? dayMetrics?.localMealEnergyKcal
    }

    /// 选中日期之前的历史（按 dayKey 倒序，最多 7 天）：给身体成分 7 天差值与维持热量估算用。
    private var bodyHistory: [DailyMetrics] {
        Array(metrics.filter { $0.date < selectedDate }.prefix(7))
    }

    /// 选中日期的评分分项 JSON；饮食 / 身体成分卡片的评分都取这一份。
    private var readinessComponents: ReadinessComponents? {
        guard let json = dayScore?.readinessComponentsJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadinessComponents.self, from: data)
    }

    /// 喝水目标 / 咖啡因上限 / 步数目标，统一做一次范围钳制，避免配置里出现异常值。
    private var waterGoal: Double { IntakeGoal.clamp(waterTarget, in: IntakeGoal.waterRange) }
    private var caffeineGoal: Double { IntakeGoal.clamp(caffeineLimit, in: IntakeGoal.caffeineRange) }
    private var stepsGoal: Double { ActionGoal.clamp(stepsTarget, in: ActionGoal.stepsRange) }

    /// 近 8 天里每天的「静息能量 + 活动能量」：给维持热量估算用，缺数据的日子自动跳过。
    private var bodyHistoryEnergies: [Double] {
        bodyHistory.compactMap {
            ActionGoal.dailyEnergy(basal: $0.basalEnergyKcal, active: $0.activeEnergy)
        }
    }

    private var selectedEnergy: Double? {
        ActionGoal.dailyEnergy(basal: dayMetrics?.basalEnergyKcal, active: dayMetrics?.activeEnergy)
    }

    /// 维持热量：近 7 个完整日健康 App 能量均值，无数据时给默认值。
    private var maintenanceKcal: Double {
        ActionGoal.estimatedMaintenanceKcal(
            historyEnergies: bodyHistoryEnergies,
            todayEnergy: selectedEnergy
        ) ?? ActionGoal.defaultMaintenanceKcal
    }

    /// 由减肥目标推导的每日卡路里摄入阈值。
    private var calorieThreshold: Double {
        ActionGoal.calorieThreshold(maintenanceKcal: maintenanceKcal, weeklyLossKg: weeklyLoss)
    }

    /// 完成度展示值：DailyScore.completeness 存的是有效数据源类别数（0–8），不是百分数，
    /// 直接拼 % 会让 8 类齐全的一天只显示「8%」。这里换算成真实百分比。
    private var completenessPercent: Int {
        CompletenessPresentation.percent(sourceCount: sourceCount)
    }

    private var sourceCount: Int { dayScore?.completeness ?? 0 }

    /// 选中日期被跳过的评分项；历史日期配置后同样从该日评分记录读取。
    private var skippedSources: [SourceSkip] {
        guard let json = dayScore?.skippedJSON?.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([SourceSkip].self, from: json)) ?? []
    }

    /// 系统根据选中日期原始快照判定为不全的数据源；仅供标记面板提示。
    private var incompleteSourcesDetected: Set<MetricSource> {
        guard let snapshot = dayMetrics?.snapshot else { return [] }
        let history = metrics
            .filter { $0.date < snapshot.date }
            .map(\.snapshot)
        return Set(ScoreSupport.availableSources(snapshot, history: history).missing)
    }

    /// 标记面板标题用的日期标签，便于确认正在配置的是哪一天。
    private var selectedDateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: selectedDate)
    }

    /// 手动标记变更后重算全部日期评分；ScoreStore 会合并短时间内的重复请求。
    private func recomputeScores() {
        Task { @MainActor in
            try? await ScoreStore.recomputeAll(in: context)
        }
    }

    /// 只合并选中日期的打卡与指标总量，给饮水 / 咖啡因卡片用。
    /// 语义：先累加当日打卡，再用指标里的合并总量（waterTotalMl / dietaryCaffeineMg
    /// 已含本地打卡）覆盖，避免本地打卡被重复计入。
    private var manualForSelectedDay: [String: Double] {
        var result: [String: Double] = [:]
        for check in checkIns where check.dayKey == key {
            result[check.kindRaw, default: 0] += check.amount
        }
        if let metric = dayMetrics {
            if let total = metric.waterTotalMl { result["water"] = total }
            if let total = metric.dietaryCaffeineMg { result["caffeine"] = total }
        }
        // 实时合计优先：与喝水 / 咖啡因记录页完全同源。HealthKit 读取失败时
        // liveIntakeLoaded 保持 false，继续用上面的快照值兜底。
        if liveIntakeLoaded {
            if let total = liveIntakeTotals["water"] { result["water"] = total }
            if let total = liveIntakeTotals["caffeine"] { result["caffeine"] = total }
        }
        return result
    }

    /// 按喝水记录页的同一口径实时读取选中日期的饮水 / 咖啡因合计：
    /// HealthKit 当日全量样本 + 本 App 本地打卡，按 syncID 去重后求和。
    /// 这样行动页卡片与点进去的记录页永远显示同一个数。
    @MainActor
    private func loadLiveIntakeTotals() async {
        let byKind = await IntakeTotalsLoader.totals(
            for: [selectedDate],
            checkIns: checkIns,
            context: context
        )
        guard let totals = byKind[key], !totals.isEmpty else { return }
        liveIntakeTotals = totals
        liveIntakeLoaded = true
    }

    // MARK: - 饮食 / 饮水 / 咖啡因 概览卡

    /// 三张卡与睡眠 / 健身卡同款：深色卡 + 标题行 + 三列指标 + 右侧进度环。
    private static let dietGreen = Color(red: 0.522, green: 0.851, blue: 0.306)
    private static let dietOrange = Color(red: 1.0, green: 0.416, blue: 0.302)
    private static let dietSky = Color(red: 0.337, green: 0.780, blue: 0.910)
    private static let teaBrown = Color(red: 0.741, green: 0.549, blue: 0.396)
    private static let mutedLabel = Color(red: 0.624, green: 0.663, blue: 0.643)

    private var dietVitalsCard: some View {
        let energy = selectedDietEnergyKcal
        let threshold = calorieThreshold
        let score = readinessComponents?.nutrition
        return ActionVitalsCard(
            title: "饮食",
            icon: "fork.knife",
            iconColor: Self.dietGreen,
            linkTitle: score.map { "饮食评分 \(Int($0.rounded())) 分" },
            metrics: [
                .init(label: "摄入", labelColor: Self.dietGreen,
                      value: energy.map { "\(Int($0.rounded())) 千卡" } ?? "—"),
                .init(label: "今日目标", labelColor: Self.dietSky,
                      value: "\(Int(threshold.rounded())) 千卡"),
            ],
            indicator: .rings(
                colors: [Self.dietGreen],
                progresses: [energy.map { min(1, max(0, $0 / threshold)) } ?? 0]
            )
        ) {
            detailRoute = .diet
        }
    }

    private var waterVitalsCard: some View {
        let current = manualForSelectedDay["water"]
        let goal = waterGoal
        return ActionVitalsCard(
            title: "饮水",
            icon: "drop.fill",
            iconColor: AppPalette.sky,
            linkTitle: nil,
            metrics: [
                .init(label: "已喝", labelColor: AppPalette.sky,
                      value: current.map { "\(Int($0.rounded())) 毫升" } ?? "—"),
                .init(label: "目标", labelColor: Color(red: 0.482, green: 0.482, blue: 0.969),
                      value: "\(Int(goal.rounded())) 毫升"),
            ],
            indicator: .glass(
                progress: current.map { min(1, max(0, $0 / goal)) } ?? 0,
                tint: AppPalette.sky
            )
        ) {
            detailRoute = .insight(.water1500)
        }
    }

    private var caffeineVitalsCard: some View {
        let current = manualForSelectedDay["caffeine"]
        let goal = caffeineGoal
        return ActionVitalsCard(
            title: "咖啡因",
            icon: "mug.fill",
            iconColor: Self.teaBrown,
            linkTitle: nil,
            metrics: [
                .init(label: "摄入", labelColor: Self.teaBrown,
                      value: current.map { "\(Int($0.rounded())) 毫克" } ?? "—"),
                .init(label: "上限", labelColor: Color(red: 0.482, green: 0.482, blue: 0.969),
                      value: "\(Int(goal.rounded())) 毫克"),
            ],
            indicator: .bean(
                progress: current.map { min(1, max(0, $0 / goal)) } ?? 0,
                tint: Self.teaBrown
            )
        ) {
            detailRoute = .insight(.caffeineModerate)
        }
    }

    // MARK: - 3 列格子数据

    private struct MetricTile: Identifiable {
        let id: String
        let title: String
        let icon: String
        let tint: Color
        let primary: String
        let secondary: String
        let progress: Double?
        let detail: ActionDetailRoute
    }

    private var gridItems: [MetricTile] {
        let snapshot = dayMetrics?.snapshot
        return gridOrder.map { tile in
            switch tile {
            case .daylight:
                let minutes = snapshot?.daylightMinutes
                return MetricTile(
                    id: tile.rawValue,
                    title: tile.title,
                    icon: tile.icon,
                    tint: tile.color,
                    primary: minutes.map { "\(Int($0.rounded())) / 20 分" } ?? "—",
                    secondary: "目标 20 分",
                    progress: minutes.map { min(1, max(0, $0 / 20)) },
                    detail: .insight(tile.insightAction)
                )
            case .mindful:
                let minutes = snapshot?.mindfulMinutes
                return MetricTile(
                    id: tile.rawValue,
                    title: tile.title,
                    icon: tile.icon,
                    tint: tile.color,
                    primary: minutes.map { "\(Int($0.rounded())) / 5 分" } ?? "—",
                    secondary: "目标 5 分",
                    progress: minutes.map { min(1, max(0, $0 / 5)) },
                    detail: .insight(tile.insightAction)
                )
            case .steps:
                let steps = snapshot?.steps
                let goal = Int(stepsGoal.rounded())
                return MetricTile(
                    id: tile.rawValue,
                    title: tile.title,
                    icon: tile.icon,
                    tint: tile.color,
                    primary: steps.map { "\(Int($0.rounded())) / \(goal)" } ?? "— / \(goal)",
                    secondary: "目标 \(goal) 步",
                    progress: steps.map { min(1, max(0, $0 / stepsGoal)) },
                    detail: .insight(tile.insightAction)
                )
            case .noise:
                return MetricTile(
                    id: tile.rawValue,
                    title: tile.title,
                    icon: tile.icon,
                    tint: tile.color,
                    primary: NoisePresentation.tileValue(snapshot?.environmentalNoiseDb),
                    secondary: NoisePresentation.tileCaption,
                    progress: nil,
                    detail: .insight(tile.insightAction)
                )
            }
        }
    }

    /// 逐行切分，用确定性 HStack 排布，避免懒加载网格高度估算错位。
    private var gridRows: [[MetricTile]] {
        let all = gridItems
        return stride(from: 0, to: all.count, by: columnCount).map { start in
            Array(all[start..<min(start + columnCount, all.count)])
        }
    }

    // MARK: - Body

    var body: some View {
        // 计算属性在 body 里会被多处引用，先取到局部只求值一次，
        // 否则每次访问都要重新解析 snapshot / 合并打卡，单帧开销被放大。
        let rows = gridRows
        return NavigationStack {
            ScrollView {
                // 惰性容器：只构建进入视口的行，避免一次性构建全部卡片（每张带阴影）拖慢切页。
                LazyVStack(spacing: 12) {
                    dateSwitcher
                    if dayMetrics == nil && dayScore == nil {
                        emptyDayNotice
                    }
                    overviewCard()
                    suggestionCard
                    sleepVitalsCard
                    fitnessVitalsCard
                    dietVitalsCard
                    waterVitalsCard
                    caffeineVitalsCard
                    moodCard
                    ForEach(rows.indices, id: \.self) { row in
                        HStack(spacing: 12) {
                            ForEach(rows[row]) { item in
                                gridCell(item)
                                    .frame(maxWidth: .infinity)
                            }
                            // 末排不足 3 个时用透明占位保持列宽一致。
                            ForEach(0..<(columnCount - rows[row].count), id: \.self) { _ in
                                Color.clear.frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
                // 拖动重排时让格子位置变化平滑动画。
                .animation(.spring(response: 0.3, dampingFraction: 0.75), value: gridOrder)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                // iOS 26 浮动标签栏会盖住最后一排，留出可滚动空间。
                .padding(.bottom, 72)
            }
            // 顶部下拉刷新：拉一次健康数据并重算评分，再按记录页口径重读当日摄入合计。
            .withPullToRefresh {
                await appModel.sync()
                await loadLiveIntakeTotals()
            }
            .background(AppScreenBackground(tone: .mint))
            .navigationTitle(showsNavigationTitle ? "行动" : "")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $detailRoute) { route in
                switch route {
                case .insight(let action):
                    ActionDetailHost(action: action)
                case .diet:
                    DietDetailHost()
                case .fitness:
                    FitnessDetailHost()
                }
            }
            .sheet(isPresented: $showsDatePicker) {
                datePickerSheet
            }
            .sheet(isPresented: $showsMoodSheet) {
                MoodRecordSheet(date: selectedDate)
            }
            .sheet(isPresented: $showsIncompletePicker) {
                IncompleteSourcePickerView(
                    dayKey: key,
                    autoMissing: incompleteSourcesDetected,
                    dateLabel: selectedDateLabel,
                    onChanged: recomputeScores
                )
                .presentationDragIndicator(.visible)
            }
            .task {
                // 进入页面先按记录页口径实时读一次，避免快照落后于健康 App。
                await loadLiveIntakeTotals()
                // 调试用：`-LogAction` 把行动页算出来的关键数值打到控制台，
                // 便于在没有 UI 自动化的环境里核对「配置值是否真的进了卡片」。
                if CommandLine.arguments.contains("-LogAction") {
                    logActionSnapshot()
                }
                // 调试用：`-openActionDetail <diet|InsightAction.rawValue>` 直接推入对应详情页，
                // 无 UI 自动化时用它核对详情页内部布局（入口条位置等）。
                if let route = Self.debugDetailRoute() {
                    detailRoute = route
                }
            }
            .onChange(of: key) { _, _ in
                // 切日期后旧合计已失效：先回退快照，再按新日期实时重读。
                liveIntakeTotals = [:]
                liveIntakeLoaded = false
                Task { await loadLiveIntakeTotals() }
            }
        }
    }

    /// 读取 `-openActionDetail <值>` 调试参数：`diet` 进饮食详情，
    /// 其余按 `InsightAction.rawValue` 解析；没有参数或值不合法时返回 nil。
    private static func debugDetailRoute() -> ActionDetailRoute? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "-openActionDetail"),
              args.index(after: index) < args.endIndex else { return nil }
        let value = args[args.index(after: index)]
        if value == "diet" { return .diet }
        guard let action = InsightAction(rawValue: value) else { return nil }
        return .insight(action)
    }

    /// 把行动页的取值链路打到控制台（仅 `-LogAction` 启动时执行）。
    private func logActionSnapshot() {
        let total = MetricSource.allCases.count
        print("[ActionPage] 日期=\(key) 今天=\(isToday) 完成度 sources=\(sourceCount)/\(total) percent=\(completenessPercent)%")
        print("[ActionPage] 阈值 维持热量=\(Int(maintenanceKcal)) 每周减重=\(weeklyLoss) 摄入阈值=\(Int(calorieThreshold)) 步数目标=\(Int(stepsGoal))")
        print("[ActionPage] 饮食 摄入=\(selectedDietEnergyKcal.map { Int($0.rounded()) } ?? -1) 千卡 阈值=\(Int(calorieThreshold))")
        print("[ActionPage] 饮水=\(manualForSelectedDay["water"].map { Int($0.rounded()) } ?? -1) / \(Int(waterGoal)) ml")
        print("[ActionPage] 咖啡因=\(manualForSelectedDay["caffeine"].map { Int($0.rounded()) } ?? -1) / \(Int(caffeineGoal)) mg")
        for item in gridItems {
            print("[ActionPage] 格子 \(item.title): \(item.primary) | \(item.secondary)")
        }
        // 记录 / 设置入口现在挂在各自详情页顶部，这里把映射打出来便于核对归属。
        for action in InsightAction.allCases {
            let labels = ActionCardSheet.entries(for: action).map(\.label)
            if !labels.isEmpty {
                print("[ActionDetail] \(action.title) 详情页入口=\(labels)")
            }
        }
        print("[ActionDetail] 饮食 详情页入口=\([ActionCardSheet.dietRecords, .dietSettings].map(\.label))")
        // 环境音量：格子与行动详情日历必须读同一条链路（snapshot.environmentalNoiseDb），
        // 这里把两边的取值一起打出来，便于核对「同一天两处数值一致」。
        let tileNoise = NoisePresentation.tileValue(dayMetrics?.snapshot.environmentalNoiseDb)
        let calendarNoise = dayMetrics
            .flatMap { InsightAction.quietUnder55.metricValue($0.snapshot) }
            .map(NoisePresentation.detailValue) ?? "nil"
        print("[ActionPage] 环境音量 格子=\(tileNoise) 日历同源值=\(calendarNoise)")
        print("[ActionPage] 顺序 \(gridOrder.map(\.rawValue))")
    }

    // MARK: - 日期切换

    /// 选中日期所在周（周一 → 周日，固定以周一为首日）。
    private var weekDates: [Date] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        // Gregorian weekday：1=周日、2=周一…7=周六；先回退到本周周一。
        let offsetToMonday = (weekday + 5) % 7
        let monday = DayKey.addingDays(-offsetToMonday, to: DayKey.startOfDay(selectedDate))
        return (0..<7).map { DayKey.addingDays($0, to: monday) }
    }

    private func weekdayLabel(for date: Date) -> String {
        if DayKey.key(for: date) == ActionQuery.todayKey { return "今" }
        let weekday = Calendar.current.component(.weekday, from: date)
        return ["日", "一", "二", "三", "四", "五", "六"][weekday - 1]
    }

    /// 日期文案，如「11月14日 周六」。
    private var dateLabel: String {
        Self.dateLabelFormatter.string(from: selectedDate)
    }

    private static let dateLabelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    /// 顶部周历条：点任意一天切换整页数据，右侧日历可跳到近 60 天内的其它日期。
    private var dateSwitcher: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(weekDates, id: \.self) { date in
                    let dateKey = DayKey.key(for: date)
                    let isSelected = dateKey == key
                    let isTodayCell = dateKey == ActionQuery.todayKey
                    Button {
                        selectedDate = date
                    } label: {
                        VStack(spacing: 3) {
                            Text(weekdayLabel(for: date))
                                .font(.system(size: 11, weight: .medium))
                            Text("\(Calendar.current.component(.day, from: date))")
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(
                            isSelected || isTodayCell ? AppPalette.greenDeep : AppPalette.ink3
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? AppPalette.greenSoft : Color.clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Self.dateLabelFormatter.string(from: date))
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
                Rectangle()
                    .fill(AppPalette.line)
                    .frame(width: 1, height: 22)
                Button {
                    showsDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppPalette.ink2)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择日期")
            }
            HStack(alignment: .firstTextBaseline) {
                Text(dateLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.ink2)
                Spacer(minLength: 0)
                if !isToday {
                    Button("回到今天") {
                        selectedDate = DayKey.startOfDay(.now)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppPalette.greenDeep)
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .animation(.snappy(duration: 0.2), value: key)
    }

    /// 日历弹层：限制在行动页查询窗口内（近 60 天，不含未来）。
    private var datePickerSheet: some View {
        NavigationStack {
            DatePicker(
                "选择日期",
                selection: Binding(
                    get: { selectedDate },
                    set: { selectedDate = DayKey.startOfDay($0) }
                ),
                in: DayKey.addingDays(-59, to: DayKey.startOfDay(.now))...DayKey.startOfDay(.now),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("选择日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsDatePicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    /// 选中日期没有指标 / 评分时的提示卡，避免整页都是「—」却不知道原因。
    private var emptyDayNotice: some View {
        HStack(spacing: 10) {
            Image(systemName: isFuture ? "calendar.badge.clock" : "tray")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppPalette.ink3)
            Text(isFuture ? "这天还没到，暂无数据。" : "这天还没有健康数据，可能有手表未佩戴或尚未同步。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .appCard(padding: 14, background: AppPalette.actionCard)
    }

    // MARK: - 智能建议

    /// 选中日期的已缓存 AI 简报；没有缓存或解析失败时为 nil。
    private var dayBriefing: BriefingReport? {
        guard let json = reports.first(where: { $0.dayKey == key })?.payloadJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BriefingReport.self, from: data)
    }

    /// 智能建议正文：优先 AI 简报摘要，其次按当日压力 / 状态给确定性文案。
    private var suggestionText: String {
        if let summary = dayBriefing?.summary, !summary.isEmpty { return summary }
        if isFuture { return "这天还没到，先保持今天的节奏，等数据积累后再来看建议。" }
        guard let stress = dayScore?.stress else {
            guard let readiness = dayScore?.readiness else {
                return "这天还没有足够的健康数据，补充记录后可以生成更贴合的建议。"
            }
            return readiness >= 60
                ? "这天状态整体不错，保持规律作息与适量活动即可。"
                : "这天状态偏低，建议优先补觉、补水，减少高强度安排。"
        }
        switch StressEngine.level(for: stress, config: ScoringConfig()) {
        case .low:
            return "状态不错，试试接触一点自然光、活动几分钟，让身体保持良好的节奏。"
        case .moderateLow:
            return "整体平稳，注意适时起身活动，减少长时间静坐带来的疲劳。"
        case .elevated:
            return "压力略高，试着放慢节奏、做几组深呼吸，给身体留出恢复时间。"
        case .high:
            return "压力偏高，建议尽快休息，减少高强度安排，优先保证睡眠。"
        }
    }

    /// 智能建议卡：头部可直达 AI 对话，正文按选中日期展示。
    private var suggestionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.greenDeep)
                Text("智能建议")
                    .font(.headline)
                Spacer(minLength: 0)
                NavigationLink {
                    ChatView(dayKey: key)
                } label: {
                    HStack(spacing: 2) {
                        Text("问问AI")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppPalette.greenDeep)
                }
                .buttonStyle(.plain)
            }
            Text(suggestionText)
                .font(.footnote)
                .foregroundStyle(AppPalette.ink2)
                .lineLimit(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appCard(padding: 16, background: AppPalette.actionCard)
    }

    // MARK: - 感受记录

    private var moodEntry: MoodEntry? {
        moodEntries.first { $0.dayKey == key }
    }

    /// 感受文案：本地记录优先，其次健康 App 同步来的心理状态。
    private var moodSummary: String {
        if let entry = moodEntry {
            let label = moodLabel(entry.valence)
            let tags = entry.tags
            return tags.isEmpty
                ? "\(label) · \(String(format: "%+.1f", entry.valence))"
                : "\(label) · \(tags.joined(separator: " / "))"
        }
        if let valence = dayMetrics?.stateOfMindValence {
            return "健康 App 记录：\(moodLabel(valence))"
        }
        if isFuture { return "这天还没到，暂无感受记录。" }
        return isToday ? "你现在的感受如何？" : "这天没有感受记录。"
    }

    private func moodLabel(_ valence: Double) -> String {
        if valence <= -0.6 { return "很低落" }
        if valence <= -0.2 { return "有点消极" }
        if valence < 0.2 { return "比较平静" }
        if valence < 0.6 { return "还不错" }
        return "很棒"
    }

    /// 感受记录卡：记录日期跟随选中日期，保存后本卡立刻刷新。
    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "face.smiling")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppPalette.greenDeep)
                Text("感受记录")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    showsMoodSheet = true
                } label: {
                    HStack(spacing: 2) {
                        Text("新增")
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(AppPalette.greenDeep)
                }
                .buttonStyle(.plain)
            }
            Text(moodSummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appCard(padding: 16, background: AppPalette.actionCard)
    }

    // MARK: - 概览

    /// 概览卡：环形状态分 + 一句话解读 + 数据完整度 / 压力；
    /// 右上角是「排序」按钮（不再单独占一行）。
    private func overviewCard() -> some View {
        let readiness = dayScore?.readiness
        let stress = dayScore?.stress
        let scoreInt = readiness.map { Int($0.rounded()) }
        let ringFraction = readiness.map { CGFloat(min(1, max(0, $0 / 100))) } ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(isToday ? "今日概览" : "当日概览")
                    .font(.headline)
                Spacer(minLength: 0)
                Button(showsReorderHint ? "完成" : "排序") {
                    withAnimation(.snappy) { showsReorderHint.toggle() }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(AppPalette.greenDeep)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppPalette.greenSoft, in: Capsule())
            }
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(Color(.systemFill), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: ringFraction)
                        .stroke(AppPalette.green, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 1) {
                        Text(scoreInt.map(String.init) ?? "—")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("状态分")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    Text(overviewHeadline(readiness: readiness))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    HStack(spacing: 18) {
                        // 完整度可点按配置：选中日期可为历史日期，标记只影响该日评分。
                        VStack(alignment: .leading, spacing: 2) {
                            Button {
                                showsIncompletePicker = true
                            } label: {
                                HStack(spacing: 3) {
                                    Text("\(completenessPercent)%")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isFuture || dayMetrics == nil)
                            Text("数据完整度 · 可配置")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        overviewStat("压力", stress.map { "\(Int($0.rounded()))" } ?? "—")
                    }
                    if !skippedSources.isEmpty {
                        Text("已跳过：" + skippedSources.map(\.displayText).joined(separator: "、"))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            if showsReorderHint {
                Text("长按下方任意格子即可拖动排序，松手后自动保存。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .appCard(padding: 16, background: AppPalette.actionCard)
    }

    private func overviewHeadline(readiness: Double?) -> String {
        let total = MetricSource.allCases.count
        let coverage = "数据源 \(sourceCount)/\(total)"
        guard let readiness else {
            if isFuture { return "这天还没到，暂无状态数据。" }
            if !isToday { return "这天没有状态评分（\(coverage)），换一天再看看。" }
            return "今日数据还在收集中（\(coverage)），先去右上角记录一下吧。"
        }
        let level: String
        switch readiness {
        case ..<40: level = "偏低"
        case ..<60: level = "一般"
        case ..<80: level = "较好"
        default: level = "很好"
        }
        return "身体状态\(level)，\(coverage) 已就绪。"
    }

    private func overviewStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 睡眠 / 健身 概览卡

    private var sleepVitalsCard: some View {
        let hours = dayMetrics?.sleepTotalH
        let efficiency = dayMetrics?.sleepEfficiency
        return ActionVitalsCard(
            title: "睡眠",
            icon: "bed.double.fill",
            iconColor: Color(red: 0.482, green: 0.420, blue: 1.0),
            linkTitle: "看睡眠报告",
            metrics: [
                .init(label: "时长", labelColor: Color(red: 0.482, green: 0.482, blue: 0.969),
                      value: hours.map(Self.sleepDurationText) ?? "—"),
                .init(label: "质量", labelColor: Color(red: 0.306, green: 0.616, blue: 1.0),
                      value: Self.sleepQualityText(efficiency)),
                .init(label: "平均心率", labelColor: Color(red: 0.624, green: 0.663, blue: 0.643),
                      value: dayMetrics?.sleepAvgHR.map { "\(Int($0.rounded())) 次/分" } ?? "—"),
            ],
            indicator: .rings(
                colors: [Color(red: 0.482, green: 0.420, blue: 1.0)],
                progresses: [hours.map { $0 / ActionGoal.sleepTargetHours } ?? 0]
            )
        ) {
            detailRoute = .insight(.sleep7h)
        }
    }

    private var fitnessVitalsCard: some View {
        let active = dayMetrics?.activeEnergy
        let exercise = dayMetrics?.exerciseMinutes
        let standHours = dayMetrics?.standMinutes.map { $0 / 60 }
        // 圆环分母优先用健身 App 里用户设置的真实目标；摘要缺失才回退 500 卡 / 30 分 / 12 小时。
        // 目标为 0 时用极小值兜底，避免除零。
        let activeGoal = max(dayMetrics?.activeEnergyGoal ?? 500, 1)
        let exerciseGoal = max(dayMetrics?.exerciseGoalMinutes ?? 30, 1)
        let standGoal = max(dayMetrics?.standGoalHours ?? 12, 1)

        // 主值只放当前值，目标值走 detail 小字，避免长字符串把主值压缩变小。
        let activeMetric = ActionVitalsCard.Metric(
            label: "活动",
            labelColor: Color(red: 1.0, green: 0.416, blue: 0.302),
            value: active.map { "\(Int($0.rounded()))" } ?? "—",
            detail: active == nil ? nil : "/ \(Int(activeGoal)) 卡"
        )
        let exerciseMetric = ActionVitalsCard.Metric(
            label: "锻炼",
            labelColor: Color(red: 0.522, green: 0.851, blue: 0.306),
            value: exercise.map { "\(Int($0.rounded()))" } ?? "—",
            detail: exercise == nil ? nil : "/ \(Int(exerciseGoal)) 分"
        )
        let standMetric = ActionVitalsCard.Metric(
            label: "站立",
            labelColor: Color(red: 0.337, green: 0.780, blue: 0.910),
            value: standHours.map { "\(Int($0.rounded()))" } ?? "—",
            detail: standHours == nil ? nil : "/ \(Int(standGoal)) 小时"
        )
        return ActionVitalsCard(
            title: "健身",
            icon: "flame.fill",
            iconColor: Color(red: 1.0, green: 0.353, blue: 0.235),
            linkTitle: nil,
            metrics: [activeMetric, exerciseMetric, standMetric],
            indicator: .rings(
                colors: [
                    Color(red: 1.0, green: 0.231, blue: 0.361),
                    Color(red: 0.549, green: 0.878, blue: 0.310),
                    Color(red: 0.333, green: 0.784, blue: 0.918),
                ],
                progresses: [
                    active.map { min(1, max(0, $0 / activeGoal)) } ?? 0,
                    exercise.map { min(1, max(0, $0 / exerciseGoal)) } ?? 0,
                    standHours.map { min(1, max(0, $0 / standGoal)) } ?? 0,
                ]
            )
        ) {
            detailRoute = .fitness
        }
    }

    private static func sleepDurationText(_ hours: Double) -> String {
        let minutes = Int((hours * 60).rounded())
        return "\(minutes / 60)小时\(minutes % 60)分钟"
    }

    private static func sleepQualityText(_ efficiency: Double?) -> String {
        guard let efficiency else { return "—" }
        switch efficiency {
        case ..<0.75: return "偏差"
        case ..<0.85: return "一般"
        case ..<0.9: return "正常"
        default: return "优秀"
        }
    }

    // MARK: - 3 列格子

    /// 3 列格子：长按即进入拖动（带放大 + 投影），松手落到目标格即重排；
    /// 步数目标设置收进点进详情后的页面，格子右上角不再挂齿轮。
    private func gridCell(_ item: MetricTile) -> some View {
        let isDragging = draggingTileID == item.id
        let cell = VStack(spacing: 8) {
            iconBadge(item)
            Text(item.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
            Text(item.primary)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(item.secondary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .appCard(padding: 12, background: AppPalette.actionCard)

        return Button {
            detailRoute = item.detail
        } label: {
            cell
        }
        .buttonStyle(.plain)
        // 拖动时放大 + 投影，做出「卡片被拎起来跟着手指走」的效果。
        .scaleEffect(isDragging ? 1.06 : 1)
        .shadow(color: .black.opacity(isDragging ? 0.18 : 0), radius: 14, y: 8)
        .zIndex(isDragging ? 1 : 0)
        .animation(.snappy(duration: 0.2), value: isDragging)
        .overlay(alignment: .topTrailing) {
            if showsReorderHint, !isDragging {
                Image(systemName: "line.3.horizontal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(6)
            }
        }
        // 长按即拖：不需要先点「排序」，也不需要额外的排序模式。
        .onDrag {
            beginDrag(item.id)
            return NSItemProvider(object: item.id as NSString)
        } preview: {
            dragPreview(item)
        }
        .onDrop(
            of: [.text],
            delegate: GridDropDelegate(
                targetID: item.id,
                order: $gridOrder,
                draggingID: $draggingTileID
            )
        )
    }

    /// 格子图标：有进度的指标（步数 / 晒太阳 / 正念）把进度画成图标外的圆环，
    /// 不再在文字下方单独占一条进度条。
    private func iconBadge(_ item: MetricTile) -> some View {
        ZStack {
            Circle()
                .fill(item.tint.opacity(0.14))
            if let progress = item.progress {
                Circle()
                    .stroke(item.tint.opacity(0.22), lineWidth: 3)
                    .padding(1.5)
                Circle()
                    .trim(from: 0, to: min(1, max(0, progress)))
                    .stroke(item.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(1.5)
            }
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.tint)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

    /// 起拖：标记被拖动的格子并起一个兜底计时（拖动被取消时系统不会回调 drop，
    /// 没有兜底的话格子会一直保持放大 + 投影的状态）。
    private func beginDrag(_ id: String) {
        draggingTileID = id
        dragResetTask?.cancel()
        dragResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            draggingTileID = nil
        }
    }

    /// 拖动时跟着手指走的小卡片（系统用它做 drag preview）。
    private func dragPreview(_ item: MetricTile) -> some View {
        VStack(spacing: 6) {
            Image(systemName: item.icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(item.tint)
            Text(item.title)
                .font(.caption.weight(.semibold))
            Text(item.primary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .frame(width: 110, height: 110)
        .background(AppPalette.actionCard, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 10)
    }

}

/// 行动页概览卡（睡眠 / 健身 / 饮食 / 饮水 / 咖啡因共用）：
/// 深色卡片，左侧标题 + 三列指标，右侧按主题显示进度环 / 水杯 / 咖啡豆。
private struct ActionVitalsCard: View {
    struct Metric {
        let label: String
        let labelColor: Color
        let value: String
        /// 可选次级信息（如目标值）：用小字号展示，避免主值因过长被压缩变小。
        var detail: String? = nil
    }

    /// 右侧指示器：睡眠 / 健身 / 饮食用同心圆环，饮水用水杯，咖啡因用咖啡豆。
    enum Indicator {
        case rings(colors: [Color], progresses: [Double])
        case glass(progress: Double, tint: Color)
        case bean(progress: Double, tint: Color)
    }

    let title: String
    let icon: String
    let iconColor: Color
    let linkTitle: String?
    let metrics: [Metric]
    let indicator: Indicator
    let action: () -> Void

    // 概览卡在浅色模式回到白卡 + 深色文字，深色模式保持原来的深绿黑卡。
    private let cardBackground = AppPalette.adaptive(
        light: (0.980, 0.984, 0.980),
        dark: (0.106, 0.133, 0.118)
    )
    private let titleColor = AppPalette.adaptive(
        light: (0.176, 0.212, 0.192),
        dark: (0.867, 0.902, 0.882)
    )
    private let linkColor = AppPalette.adaptive(
        light: (0.529, 0.576, 0.549),
        dark: (0.576, 0.631, 0.604)
    )
    private let valueColor = AppPalette.adaptive(
        light: (0.098, 0.118, 0.106),
        dark: (0.953, 0.969, 0.957)
    )

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(iconColor)
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(titleColor)
                    Spacer(minLength: 6)
                    HStack(spacing: 3) {
                        if let linkTitle {
                            Text(linkTitle)
                                .font(.system(size: 11, weight: .regular))
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(linkColor)
                }
                HStack(alignment: .center, spacing: 10) {
                    // 只有两个指标时列间距与首列宽度都放大一点，避免第二列贴得太紧。
                    HStack(alignment: .top, spacing: metrics.count == 2 ? 34 : 26) {
                        ForEach(metrics.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(metrics[index].label)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(metrics[index].labelColor)
                                // 主值与其他卡片同字号；目标值等次级信息用 11pt 灰字跟在基线上。
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Text(metrics[index].value)
                                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                        .foregroundStyle(valueColor)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.6)
                                    if let detail = metrics[index].detail {
                                        Text(detail)
                                            .font(.system(size: 11, weight: .medium))
                                            .monospacedDigit()
                                            .foregroundStyle(linkColor)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                    }
                                }
                            }
                            .frame(
                                width: index < metrics.count - 1 ? (metrics.count == 2 ? 96 : 86) : nil,
                                alignment: .leading
                            )
                        }
                    }
                    Spacer(minLength: 0)
                    indicatorView
                        .frame(width: 58, height: 58)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case let .rings(colors, progresses):
            ActionRingStack(colors: colors, progresses: progresses)
        case let .glass(progress, tint):
            IntakeGlassView(progress: progress, tint: tint)
                .frame(width: 36, height: 52)
        case let .bean(progress, tint):
            CoffeeBeanFillView(
                progress: progress,
                tint: tint,
                // 浅色白卡上用米色豆身 + 灰描边，深色卡上保持白色低透明度。
                emptyColor: AppPalette.adaptive(
                    light: UIColor(red: 0.886, green: 0.867, blue: 0.839, alpha: 1),
                    dark: UIColor.white.withAlphaComponent(0.10)
                ),
                emptyCrease: AppPalette.adaptive(
                    light: UIColor.gray.withAlphaComponent(0.25),
                    dark: UIColor.white.withAlphaComponent(0.06)
                ),
                trackColor: AppPalette.adaptive(
                    light: UIColor(red: 0.929, green: 0.918, blue: 0.898, alpha: 1),
                    dark: UIColor.white.withAlphaComponent(0.05)
                ),
                creaseColor: AppPalette.adaptive(
                    light: UIColor.brown.withAlphaComponent(0.28),
                    dark: UIColor.white.withAlphaComponent(0.22)
                )
            )
            .frame(width: 42, height: 52)
        }
    }
}

/// 同心圆进度环：第 1 圈最大，向内依次缩进，深色轨道 + 圆头彩色进度。
private struct ActionRingStack: View {
    let colors: [Color]
    let progresses: [Double]

    var body: some View {
        ZStack {
            ForEach(colors.indices, id: \.self) { index in
                ring(at: index)
            }
        }
    }

    private func ring(at index: Int) -> some View {
        let lineWidth: CGFloat = colors.count > 1 ? 6.5 : 9
        let progress = min(1, max(0, index < progresses.count ? progresses[index] : 0))
        return ZStack {
            Circle()
                .stroke(
                    AppPalette.adaptive(
                        light: (0.878, 0.898, 0.882),
                        dark: (0.169, 0.204, 0.184)
                    ),
                    lineWidth: lineWidth
                )
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        colors: [colors[index].opacity(0.72), colors[index], colors[index]],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[index].opacity(0.35), radius: 3)
        }
        .padding(CGFloat(index) * 9)
    }
}

/// 行动页拖动落点代理：只在 3 列格子之间重排，并把拖动态清空。
private struct GridDropDelegate: DropDelegate {
    let targetID: String
    @Binding var order: [ActionGridTile]
    @Binding var draggingID: String?

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [.text]).first else {
            draggingID = nil
            return false
        }
        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let draggedID = object as? String else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    reorder(draggedID: draggedID, targetID: targetID)
                }
                draggingID = nil
            }
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal {
        DropProposal(operation: .move)
    }

    private func reorder(draggedID: String, targetID: String) {
        guard draggedID != targetID,
              let dragged = ActionGridTile(rawValue: draggedID),
              let target = ActionGridTile(rawValue: targetID) else { return }
        var next = order
        next.removeAll { $0 == dragged }
        if let index = next.firstIndex(of: target) {
            next.insert(dragged, at: index)
        }
        order = next
        ActionGridTile.store(next)
    }
}

/// 行动页与详情页的查询描述符。
/// 全部写成静态常量：`@Query` 拿到的是同一个描述符实例，SwiftUI 重建视图结构时
/// 不会被当成新查询而重新取数（此前把描述符建在 `init` 里，导致每次 body 都重新取全表，越改越卡）。
enum ActionQuery {
    /// 当天 key。周历里的「今天」高亮与详情页的今日口径都以此为准。
    static let todayKey = DayKey.key(for: DayKey.startOfDay(.now))

    /// 行动页窗口：近 60 天（不含未来），按 dayKey 倒序。
    /// 页面按 `selectedDate` 从窗口里挑当天这一行，窗口内其它行只做身体成分 / 热量均值参考，
    /// 不解析 snapshot，因此不会像「逐日构建详情数据」那样付出 60 次 JSON 解码成本。
    static let actionWindowMetrics: FetchDescriptor<DailyMetrics> = {
        let cutoff = DayKey.key(for: DayKey.addingDays(-59, to: DayKey.startOfDay(.now)))
        let end = todayKey
        return FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.dayKey >= cutoff && $0.dayKey <= end },
            sortBy: [SortDescriptor(\DailyMetrics.dayKey, order: .reverse)]
        )
    }()

    static let actionWindowScores: FetchDescriptor<DailyScore> = {
        let cutoff = DayKey.key(for: DayKey.addingDays(-59, to: DayKey.startOfDay(.now)))
        let end = todayKey
        return FetchDescriptor<DailyScore>(
            predicate: #Predicate { $0.dayKey >= cutoff && $0.dayKey <= end },
            sortBy: [SortDescriptor(\DailyScore.dayKey, order: .reverse)]
        )
    }()

    static let todayScores: FetchDescriptor<DailyScore> = {
        let key = todayKey
        return FetchDescriptor<DailyScore>(predicate: #Predicate { $0.dayKey == key })
    }()

    /// 详情页窗口：含今天在内的近 60 天，按 dayKey 升序便于直接算趋势。
    static let recentMetrics: FetchDescriptor<DailyMetrics> = {
        let cutoff = DayKey.key(for: DayKey.addingDays(-59, to: DayKey.startOfDay(.now)))
        return FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.dayKey >= cutoff },
            sortBy: [SortDescriptor(\DailyMetrics.dayKey)]
        )
    }()

    static let recentScores: FetchDescriptor<DailyScore> = {
        let cutoff = DayKey.key(for: DayKey.addingDays(-59, to: DayKey.startOfDay(.now)))
        return FetchDescriptor<DailyScore>(predicate: #Predicate { $0.dayKey >= cutoff })
    }()

    /// 饮食详情窗口：近 60 天、按 dayKey 倒序（今天在前）。
    /// 与今日页分组详情口径一致，趋势卡片只取前 30 条再反转成时间正序。
    static let recentMetricsDescending: FetchDescriptor<DailyMetrics> = {
        let cutoff = DayKey.key(for: DayKey.addingDays(-59, to: DayKey.startOfDay(.now)))
        return FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.dayKey >= cutoff },
            sortBy: [SortDescriptor(\DailyMetrics.dayKey, order: .reverse)]
        )
    }()
}

/// 行动详情页的惰性宿主：只有真正点进某张卡片时才查询并构造近 60 天的历史数据。
///
/// 之前 `actionDays` 直接写在 `navigationDestination` 的参数里，
/// 而 `actionDays` 会为 60 天各解析一次 `metric.snapshot`（其中 `workoutZones` 要 JSON 解码）、
/// 并合并全部打卡，属于「为可能永远不会打开的详情提前买单」。
/// 现在历史数据由详情页自己查（窗口 60 天）、在 `task` 里按需计算：进入行动页时零成本。
private struct ActionDetailHost: View {
    let action: InsightAction
    /// 近 60 天的历史只在点进卡片后才会取，行动页的查询因此可以收窄到「今天」。
    @Query(ActionQuery.recentMetrics) private var metrics: [DailyMetrics]
    @Query(ActionQuery.recentScores) private var scores: [DailyScore]
    @Query private var checkIns: [ActionCheckIn]
    /// 实时合计需要用 modelContext 补齐老打卡 syncID。
    @Environment(\.modelContext) private var context

    /// nil 表示还在准备数据；准备好后再渲染真正的详情页。
    @State private var days: [ActionDay]?

    /// 占位帧的标题也要跟着喝水目标走，与详情页正文用同一个值，避免先闪一下「1500」。
    @AppStorage(IntakeGoal.waterDefaultsKey) private var storedWaterTargetMl = IntakeGoal.defaultWaterTargetMl

    private var loadingTitle: String {
        action.title(
            waterTargetMl: IntakeGoal.clamp(storedWaterTargetMl, in: IntakeGoal.waterRange)
        )
    }

    var body: some View {
        Group {
            if let days {
                // 记录 / 设置入口由行动类型决定，挂在详情页顶部；纯自动行动没有入口。
                // 睡眠详情额外带上近 60 天指标，供页面顶部的「睡眠报告」入口使用。
                ActionDetailView(
                    action: action,
                    days: days,
                    entries: ActionCardSheet.entries(for: action),
                    sleepMetrics: action == .sleep7h ? metrics : nil
                )
            } else {
                // 计算只有几十毫秒，用与详情页相同的底色兜住这一帧，避免白闪。
                AppScreenBackground(tone: .mint)
                    .navigationTitle(loadingTitle)
            }
        }
        .task {
            guard days == nil else { return }
            let trace = PerformanceTrace.shared.begin(
                "详情页 · 准备\(action.title)数据", category: .page,
                detail: "metrics=\(metrics.count) checks=\(checkIns.count)"
            )
            var built = Self.buildDays(metrics: metrics, scores: scores, checkIns: checkIns)
            // 饮水 / 咖啡因详情与记录页同口径：用实时合计覆盖快照，
            // 否则外层卡片已是 850、点进详情又是快照 250。
            if action == .water1500 || action == .caffeineModerate {
                let live = await IntakeTotalsLoader.totals(
                    for: built.map(\.date),
                    checkIns: checkIns,
                    context: context
                )
                for index in built.indices {
                    let dayKey = DayKey.key(for: built[index].date)
                    guard let totals = live[dayKey] else { continue }
                    for (kind, value) in totals {
                        built[index].manual[kind] = value
                    }
                }
            }
            PerformanceTrace.shared.end(trace)
            days = built
        }
    }

    /// 把「指标 + 评分 + 打卡」合并成详情页需要的逐日数据。
    /// 口径与原 `actionDays` 一致：近 60 天、必须有评分、饮水 / 咖啡因取合并总量。
    private static func buildDays(
        metrics: [DailyMetrics],
        scores: [DailyScore],
        checkIns: [ActionCheckIn]
    ) -> [ActionDay] {
        let scoreByKey = Dictionary(scores.map { ($0.dayKey, $0) }, uniquingKeysWith: { first, _ in first })

        var manualByDay: [String: [String: Double]] = [:]
        for check in checkIns {
            manualByDay[check.dayKey, default: [:]][check.kindRaw, default: 0] += check.amount
        }
        // 喝水与咖啡因都用合并后的总量（本 App 打卡 + 健康 App 同步），
        // 让行动页数值、洞察与今日状态评分口径一致。
        for metric in metrics {
            if let total = metric.waterTotalMl {
                manualByDay[metric.dayKey, default: [:]]["water"] = total
            }
            if let total = metric.dietaryCaffeineMg {
                manualByDay[metric.dayKey, default: [:]]["caffeine"] = total
            }
        }

        let cutoff = DayKey.addingDays(-59, to: DayKey.startOfDay(.now))
        return metrics
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .compactMap { metric in
                guard let stress = scoreByKey[metric.dayKey]?.stress else { return nil }
                return ActionDay(
                    date: metric.date,
                    stress: stress,
                    snapshot: metric.snapshot,
                    manual: manualByDay[metric.dayKey] ?? [:]
                )
            }
    }
}

/// 行动页卡片的详情路由：饮食走营养指标详情，健身走健身环详情，其余走既有行动分析详情。
private enum ActionDetailRoute: Hashable, Identifiable {
    case insight(InsightAction)
    case diet
    case fitness

    var id: String {
        switch self {
        case .insight(let action): return action.rawValue
        case .diet: return "diet"
        case .fitness: return "fitness"
        }
    }
}

/// 健身详情宿主：点进健身卡片后才查询近 60 天指标；
/// 页面按健康 App 健身页口径展示活动 / 锻炼 / 站立三个环，日期条可切历史。
private struct FitnessDetailHost: View {
    @Query(ActionQuery.recentMetricsDescending) private var metrics: [DailyMetrics]
    @State private var selectedDate = DayKey.startOfDay(.now)

    var body: some View {
        VStack(spacing: 0) {
            ActionDayStrip(
                selectedDate: $selectedDate,
                tint: Color(red: 1.0, green: 0.231, blue: 0.361)
            )
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 2)
            FitnessRingDetailView(metrics: selectedMetrics, date: selectedDate)
        }
        .background(AppScreenBackground(tone: .mint))
    }

    /// 选中日期对应的指标行；该日尚未同步健身数据时为 nil。
    private var selectedMetrics: DailyMetrics? {
        let key = DayKey.key(for: selectedDate)
        return metrics.first { $0.dayKey == key }
    }
}

/// 饮食详情宿主：只在点进饮食卡片后才查询近 60 天指标与当日评分。
/// 明细与近 30 天趋势复用今日页的 MetricGroupDetailView，保证同一套取值口径。
private struct DietDetailHost: View {
    @Query(ActionQuery.recentMetricsDescending) private var metrics: [DailyMetrics]
    @Query(ActionQuery.recentScores) private var scores: [DailyScore]
    /// 每日摄入阈值与行动页饮食卡共用同一套 @AppStorage 配置。
    @AppStorage(ActionGoal.weeklyWeightLossDefaultsKey) private var weeklyLoss = ActionGoal.defaultWeeklyWeightLossKg
    /// 详情页顶部日期切换条选中的日期，所有明细都跟随该日期。
    @State private var selectedDate = DayKey.startOfDay(.now)

    var body: some View {
        VStack(spacing: 0) {
            ActionDayStrip(selectedDate: $selectedDate, tint: AppPalette.greenDeep)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 2)
            MetricGroupDetailView(
                group: MetricGroupFactory.dietGroup(today: selectedMetrics),
                score: nutritionScore,
                metrics: metrics,
                // 饮食记录挂在详情页顶部，设置收进导航栏右上角齿轮。
                entries: [.dietRecords, .dietSettings],
                estimatedMaintenanceKcal: estimatedMaintenanceKcal,
                calorieSummary: calorieSummary,
                calorieOverageKcal: calorieOverageKcal,
                dayDate: selectedDate,
                dietWeightRelation: dietWeightRelation
            )
        }
        .background(AppScreenBackground(tone: .white))
    }

    /// 摄入与体重关系的数据：最近 7 天，窗口以详情页选中日期为终点，摄入口径与饮食卡一致。
    /// 体重是智能秤的稀疏采样，缺数据的日子在曲线上直接跳过，不补零。
    private var dietWeightRelation: DietWeightRelation {
        let days = metrics
            .filter { $0.date <= selectedDate }
            .map {
                DietWeightDay(
                    date: $0.date,
                    energyKcal: $0.dietaryEnergyKcal ?? $0.localMealEnergyKcal,
                    bodyMassKg: $0.bodyMassKg
                )
            }
        return DietWeightRelation.evaluate(days: days, thresholdKcal: calorieThreshold)
    }

    private var isToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: .now)
    }

    private var selectedDateKey: String {
        DayKey.key(for: selectedDate)
    }

    /// 自动估算的维持热量，无数据时默认 2000 kcal；与饮食设置页同一公式。
    private var calorieThreshold: Double {
        let maintenance = estimatedMaintenanceKcal ?? ActionGoal.defaultMaintenanceKcal
        return ActionGoal.calorieThreshold(maintenanceKcal: maintenance, weeklyLossKg: weeklyLoss)
    }

    /// 详情页头部展示的「摄入 / 阈值」，跟随所选日期，口径与行动页饮食卡完全一致。
    private var calorieSummary: String {
        let energy = selectedMetrics?.dietaryEnergyKcal ?? selectedMetrics?.localMealEnergyKcal
        let prefix = isToday ? "今日摄入" : "当日摄入"
        return "\(prefix) \(energy.map { String(Int($0.rounded())) } ?? "—") / \(Int(calorieThreshold.rounded())) kcal"
    }

    /// 当日摄入超出阈值的千卡数：与行动页饮食卡共用同一判定；未超限为 nil。
    private var calorieOverageKcal: Double? {
        guard let energy = selectedMetrics?.dietaryEnergyKcal ?? selectedMetrics?.localMealEnergyKcal,
              energy > calorieThreshold
        else { return nil }
        return energy - calorieThreshold
    }

    /// 维持热量估算：近 7 个完整日（不含今天）有「静息 + 活动」能量的日子取均值。
    /// 必须与行动页饮食卡 `bodyHistoryEnergies` 的窗口一致，否则会出现
    /// 「外层卡显示 1802、点进详情变 1403」这类两套阈值并存的问题。
    private var estimatedMaintenanceKcal: Double? {
        ActionGoal.estimatedMaintenanceKcal(
            historyEnergies: metrics
                .filter { $0.dayKey != ActionQuery.todayKey }
                .prefix(7)
                .compactMap { ActionGoal.dailyEnergy(basal: $0.basalEnergyKcal, active: $0.activeEnergy) },
            todayEnergy: todayMetrics.flatMap {
                ActionGoal.dailyEnergy(basal: $0.basalEnergyKcal, active: $0.activeEnergy)
            }
        )
    }

    /// 选中日期对应的指标行；该日尚未同步数据时传 nil，详情页显示空态提示。
    private var selectedMetrics: DailyMetrics? {
        metrics.first { $0.dayKey == selectedDateKey }
    }

    /// 今日明细仍取「今天」这一行，用于维持热量估算。
    private var todayMetrics: DailyMetrics? {
        metrics.first { $0.dayKey == ActionQuery.todayKey }
    }

    /// 饮食分项评分，取所选日期的 ReadinessComponents.nutrition；JSON 缺失 / 解码失败时为 nil。
    private var nutritionScore: Double? {
        guard let json = scores.first(where: { $0.dayKey == selectedDateKey })?.readinessComponentsJSON,
              let data = json.data(using: .utf8),
              let components = try? JSONDecoder().decode(ReadinessComponents.self, from: data)
        else { return nil }
        return components.nutrition
    }
}

// configured by qoder
