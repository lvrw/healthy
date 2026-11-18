import Charts
import SwiftData
import SwiftUI

/// 「洞察」页所有昂贵派生数据的一次性快照。
/// 原先 `summary`（`ActionImpactEngine.evaluate`，对 60 天做相关性）、`moodPoints`、
/// `manualByDay`、`actionDays` 都是 body 里的 computed property，SwiftUI 每次求值、
/// 每次滚动帧、每次选中态变化都会重算；`summary` 还在多个卡片里各被读一遍。
/// 现在改为后台算一次，按数据版本失效，body 只读缓存，避免切页/滚动掉帧。
private struct InsightsDerived: Sendable {
    let recentMetrics: [InsightMetricInput]
    let scoreByKey: [String: Double]
    let manualByDay: [String: [String: Double]]
    let actionDays: [ActionDay]
    let summary: ActionImpactSummary
    let moodPoints: [MoodPoint]
}

/// 后台纯计算的输入：SwiftData @Model 不可跨并发域，先转成值类型。
private struct InsightMetricInput: Sendable {
    let dayKey: String
    let date: Date
    let snapshot: DailySnapshot
    let waterTotalMl: Double?
    let dietaryCaffeineMg: Double?
    let stateOfMindValence: Double?
}

private struct InsightScoreInput: Sendable {
    let dayKey: String
    let stress: Double?
}

private struct InsightCheckInInput: Sendable {
    let dayKey: String
    let kindRaw: String
    let amount: Double
}

private struct InsightMoodInput: Sendable {
    let dayKey: String
    let valence: Double
}

struct InsightsView: View {
    /// 由 ActionHubView 挂载时隐藏系统大标题，避免与原型「行动 / 洞察」标题式子页签重复。
    var showsNavigationTitle: Bool = true

    @Query(sort: \DailyMetrics.dayKey) private var metrics: [DailyMetrics]
    @Query private var scores: [DailyScore]
    @Query private var checkIns: [ActionCheckIn]
    @Query private var moodEntries: [MoodEntry]
    @Environment(\.openURL) private var openURL
    /// 实时摄入合计需要用 modelContext 补齐老打卡 syncID。
    @Environment(\.modelContext) private var context
    /// 全局数据同步入口：顶部下拉刷新时重新拉取 HealthKit 数据并重算评分。
    @Environment(AppModel.self) private var appModel
    @State private var selectedAction: InsightAction = .sleep7h
    @State private var selectedActionDate: Date?
    @State private var selectedMoodDate: Date?
    @State private var showInfo = false
    @State private var showMoodSheet = false
    @State private var derived: InsightsDerived?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 喝水目标与「喝水配置」共用同一组偏好：改了目标，关联分析的分组与标题一起变。
    @AppStorage(IntakeGoal.waterDefaultsKey) private var storedWaterTargetMl = IntakeGoal.defaultWaterTargetMl
    /// 咖啡因上限同理：改了上限，咖啡因行动的标题与符合判定一起变。
    @AppStorage(IntakeGoal.caffeineDefaultsKey) private var storedCaffeineLimitMg = IntakeGoal.defaultCaffeineLimitMg

    /// 生效的喝水目标（毫升），范围钳制后参与分组判定与标题展示。
    private var waterTargetMl: Double {
        IntakeGoal.clamp(storedWaterTargetMl, in: IntakeGoal.waterRange)
    }

    /// 生效的咖啡因上限（毫克），同上。
    private var caffeineLimitMg: Double {
        IntakeGoal.clamp(storedCaffeineLimitMg, in: IntakeGoal.caffeineRange)
    }

    /// 分析项标题：喝水 / 咖啡因按当前配置展示，其他行动是固定口径。
    private func displayTitle(_ action: InsightAction) -> String {
        action.title(waterTargetMl: waterTargetMl, caffeineLimitMg: caffeineLimitMg)
    }

    /// 数据版本：metrics/scores/checkIns/moodEntries 或喝水目标任一变化才重算派生数据。
    /// 滚动、选中态、图表点击等普通重绘直接复用缓存，不再重跑相关性分析。
    private var dataVersion: String {
        [
            "\(metrics.count)",
            metrics.first?.dayKey ?? "",
            "\(scores.count)",
            "\(scores.first?.computedAt.timeIntervalSince1970 ?? 0)",
            "\(checkIns.count)",
            "\(moodEntries.count)",
            "\(waterTargetMl)",
            "\(caffeineLimitMg)",
        ].joined(separator: "|")
    }

    /// 主线程取 SwiftData 值快照，纯计算放后台；结果写回 @State 后 body 只读缓存。
    @MainActor
    private func refreshDerived() async {
        let perfToken = PerformanceTrace.shared.begin("页面 · 洞察 · 派生数据重算", category: .page)
        defer { PerformanceTrace.shared.end(perfToken) }
        let cutoff = DayKey.addingDays(-59, to: DayKey.startOfDay(.now))
        let metricInputs: [InsightMetricInput] = metrics.map {
            InsightMetricInput(
                dayKey: $0.dayKey,
                date: $0.date,
                snapshot: $0.snapshot,
                waterTotalMl: $0.waterTotalMl,
                dietaryCaffeineMg: $0.dietaryCaffeineMg,
                stateOfMindValence: $0.stateOfMindValence
            )
        }
        let scoreInputs: [InsightScoreInput] = scores.map {
            InsightScoreInput(dayKey: $0.dayKey, stress: $0.stress)
        }
        let checkInInputs: [InsightCheckInInput] = checkIns.map {
            InsightCheckInInput(dayKey: $0.dayKey, kindRaw: $0.kindRaw, amount: $0.amount)
        }
        let moodInputs: [InsightMoodInput] = moodEntries.map {
            InsightMoodInput(dayKey: $0.dayKey, valence: $0.valence)
        }
        let calendar = Calendar.current
        // 喝水目标与咖啡因上限在主线程取定值后传入后台任务，避免后台读 UserDefaults。
        let waterTargetMl = self.waterTargetMl
        let caffeineLimitMg = self.caffeineLimitMg
        // 饮水 / 咖啡因用记录页同口径的实时合计覆盖快照（快照会排除孤儿回写样本），
        // 必须在主线程读健康数据，再作为值传入后台纯计算。
        let recentDates = metricInputs.filter { $0.date >= cutoff }.map(\.date)
        let liveTotals = await IntakeTotalsLoader.totals(
            for: recentDates,
            checkIns: checkIns,
            context: context
        )

        let result = await Task.detached(priority: .userInitiated) {
            Self.makeDerived(
                metricInputs: metricInputs,
                scoreInputs: scoreInputs,
                checkInInputs: checkInInputs,
                moodInputs: moodInputs,
                cutoff: cutoff,
                calendar: calendar,
                waterTargetMl: waterTargetMl,
                caffeineLimitMg: caffeineLimitMg,
                liveTotals: liveTotals
            )
        }.value

        derived = result
        // 仅在当前选中项已不在结果里时才回退到首个关联行动，避免覆盖用户手动选择。
        if !result.summary.positive.contains(where: { $0.action == selectedAction })
            && !result.summary.negative.contains(where: { $0.action == selectedAction }),
           let first = result.summary.positive.first ?? result.summary.negative.first {
            selectedAction = first.action
        }
    }

    /// 与原 computed property 完全相同的计算口径，只是集中执行一次。
    /// nonisolated：View 成员默认继承 MainActor，这里必须在后台线程可调用。
    private nonisolated static func makeDerived(
        metricInputs: [InsightMetricInput],
        scoreInputs: [InsightScoreInput],
        checkInInputs: [InsightCheckInInput],
        moodInputs: [InsightMoodInput],
        cutoff: Date,
        calendar: Calendar,
        waterTargetMl: Double,
        caffeineLimitMg: Double,
        liveTotals: [String: [String: Double]]
    ) -> InsightsDerived {
        let recentMetrics = metricInputs
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }

        var scoreByKey: [String: Double] = [:]
        for input in scoreInputs {
            if let stress = input.stress {
                scoreByKey[input.dayKey] = stress
            }
        }

        var manualByDay: [String: [String: Double]] = [:]
        for check in checkInInputs {
            manualByDay[check.dayKey, default: [:]][check.kindRaw, default: 0] += check.amount
        }
        // 喝水与咖啡因用「本 App 打卡 + 健康 App 同步」的合并总量，
        // 与行动页、评分层保持一致，避免洞察分析漏掉健康 App / 第三方记录。
        for metric in metricInputs {
            if let total = metric.waterTotalMl {
                manualByDay[metric.dayKey, default: [:]]["water"] = total
            }
            if let total = metric.dietaryCaffeineMg {
                manualByDay[metric.dayKey, default: [:]]["caffeine"] = total
            }
        }
        // 实时合计优先：与喝水 / 咖啡因记录页同口径，修掉详情页 250 / 记录页 850 的偏差。
        for (dayKey, totals) in liveTotals {
            for (kind, value) in totals {
                manualByDay[dayKey, default: [:]][kind] = value
            }
        }

        let actionDays: [ActionDay] = recentMetrics.compactMap { metric in
            guard let stress = scoreByKey[metric.dayKey] else { return nil }
            return ActionDay(
                date: metric.date,
                stress: stress,
                snapshot: metric.snapshot,
                manual: manualByDay[metric.dayKey] ?? [:]
            )
        }

        let summary = ActionImpactEngine.evaluate(
            days: actionDays,
            waterTargetMl: waterTargetMl,
            caffeineLimitMg: caffeineLimitMg
        )

        let moodPoints = MoodDisplay.merge(
            healthKit: recentMetrics.map { ($0.date, $0.stateOfMindValence) },
            local: moodInputs.compactMap { entry in
                DayKey.date(from: entry.dayKey, calendar: calendar).map { ($0, entry.valence) }
            },
            calendar: calendar
        )

        return InsightsDerived(
            recentMetrics: recentMetrics,
            scoreByKey: scoreByKey,
            manualByDay: manualByDay,
            actionDays: actionDays,
            summary: summary,
            moodPoints: moodPoints
        )
    }

    private var summary: ActionImpactSummary {
        derived?.summary ?? .empty
    }

    private var availableActions: [InsightAction] {
        let impacted = (summary.positive + summary.negative).map(\.action)
        return impacted.isEmpty ? InsightAction.allCases : impacted
    }

    private var selectedImpact: ActionImpact? {
        (summary.positive + summary.negative).first { $0.action == selectedAction }
    }

    private var trendPoints: [ActionTrendPoint] {
        guard let derived else { return [] }
        return ActionImpactEngine.trendPoints(
            action: selectedAction,
            days: Array(derived.actionDays.suffix(30)),
            waterTargetMl: waterTargetMl,
            caffeineLimitMg: caffeineLimitMg
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if derived == nil {
                        ProgressView("正在分析过去 60 天…")
                            .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        smartSummaryCard
                        actionChartCard
                        keyActionsCard
                        moodCard
                    }
                }
                .padding(16)
            }
            // 顶部下拉刷新：同步后数据版本变化会触发 .task(id: dataVersion) 重算派生数据。
            .withPullToRefresh {
                await appModel.sync()
            }
            .background(AppScreenBackground(tone: .mint))
            .navigationTitle(showsNavigationTitle ? "洞察" : "")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: dataVersion) {
                await refreshDerived()
            }
            .sheet(isPresented: $showInfo) {
                InsightInfoView()
            }
            .sheet(isPresented: $showMoodSheet) {
                MoodRecordSheet()
            }
            .sensoryFeedback(.selection, trigger: selectedAction)
            .sensoryFeedback(.selection, trigger: selectedActionDate)
            .sensoryFeedback(.selection, trigger: selectedMoodDate)
        }
    }

    private var smartSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(
                title: "智能建议",
                icon: "sparkles",
                tint: .orange,
                trailing: AnyView(
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                )
            )
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("过去 60 天 · \(summary.daysAnalyzed) 天有压力数据")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .contentTransition(.numericText())
        }
        .appCard()
        .cardScrollEffect()
    }

    private var summaryText: String {
        guard summary.daysAnalyzed >= ActionImpactEngine.minAnalysisDays else {
            let remaining = max(0, ActionImpactEngine.minAnalysisDays - summary.daysAnalyzed)
            return "还需要约 \(remaining) 天有压力数据，才能做行为和压力的关联分析。继续佩戴手表并保持授权即可。"
        }
        if summary.positive.isEmpty && summary.negative.isEmpty {
            return "过去 60 天没有发现明显的行为与压力关联。继续记录会让分析更稳定。"
        }

        var parts: [String] = []
        if let first = summary.positive.first {
            parts.append("「\(displayTitle(first.action))」的日子压力平均低 \(Int(abs(first.delta).rounded())) 分")
        }
        if summary.positive.count > 1 {
            let second = summary.positive[1]
            parts.append("「\(displayTitle(second.action))」也偏低 \(Int(abs(second.delta).rounded())) 分")
        }
        if let first = summary.negative.first {
            parts.append("需要留意「\(displayTitle(first.action))」：这些日子的压力平均高 \(Int(abs(first.delta).rounded())) 分")
        }
        return "过去 60 天里，" + parts.joined(separator: "；") + "。"
    }

    private var actionChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "行动 v.s. 压力趋势",
                icon: "chart.bar.xaxis",
                tint: .blue,
                trailing: AnyView(
                    Menu {
                        Picker("行为", selection: $selectedAction) {
                            ForEach(availableActions) { action in
                                Text(displayTitle(action)).tag(action)
                            }
                        }
                    } label: {
                        Label(displayTitle(selectedAction), systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.blue.opacity(0.1), in: Capsule())
                    }
                )
            )

            if let impact = selectedImpact {
                Text("符合 \(impact.daysMet) 天，平均压力 \(Int(impact.averageStressMet.rounded()))；不符合 \(impact.daysNotMet) 天，平均 \(Int(impact.averageStressNotMet.rounded()))。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("选择柱形可查看当日详情")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            if trendPoints.isEmpty {
                Text("这个行为还没有足够数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(trendPoints) { point in
                    BarMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("压力", point.stress)
                    )
                    .foregroundStyle(point.status == .met ? selectedColor : Color.gray.opacity(0.22))
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...100)
                .frame(height: 180)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let x = value.location.x - geometry[plotFrame].origin.x
                                            if let date = proxy.value(atX: x, as: Date.self) {
                                                withAnimation(reduceMotion ? nil : .snappy) {
                                                    selectedActionDate = date
                                                }
                                            }
                                        }
                                )
                            if let point = selectedActionPoint,
                               let plotFrame = proxy.plotFrame,
                               let x = proxy.position(forX: point.date),
                               let y = proxy.position(forY: point.stress) {
                                ChartCalloutOverlay(
                                    lines: actionCalloutLines(point),
                                    anchor: CGPoint(
                                        x: geometry[plotFrame].origin.x + x,
                                        y: geometry[plotFrame].origin.y + y
                                    ),
                                    containerSize: geometry.size
                                )
                            }
                        }
                    }
                }

                HStack(spacing: 14) {
                    Label("符合「\(displayTitle(selectedAction))」", systemImage: "square.fill")
                        .foregroundStyle(selectedColor)
                    Label("不符合", systemImage: "square.fill")
                        .foregroundStyle(.gray.opacity(0.45))
                }
                .font(.caption2)
            }
        }
        .appCard()
        .animation(.snappy, value: selectedAction)
    }

    private var keyActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "关键行动",
                icon: "list.bullet.clipboard",
                tint: .green,
                trailing: AnyView(
                    Button {
                        showInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                )
            )

            if summary.positive.isEmpty && summary.negative.isEmpty {
                Text("数据积累后会在这里列出与压力关联最明显的行动。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                actionSection("积极行动", impacts: Array(summary.positive.prefix(4)), tint: .green)
                if !summary.negative.isEmpty {
                    Divider()
                    actionSection("消极行动", impacts: Array(summary.negative.prefix(4)), tint: .orange)
                }
            }
        }
        .appCard()
        .cardScrollEffect()
    }

    private func actionSection(_ title: String, impacts: [ActionImpact], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(impacts) { impact in
                NavigationLink {
                    ActionDetailView(action: impact.action, days: derived?.actionDays ?? [])
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: impact.action.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 30, height: 30)
                            .background(tint.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(displayTitle(impact.action))
                                .font(.subheadline)
                            Text("\(impact.daysMet) 天 · 压力\(impact.delta > 0 ? "低" : "高") \(Int(abs(impact.delta).rounded())) 分")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("影响 \(impact.impact.label)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(tint.opacity(0.12), in: Capsule())
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var moodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(
                title: "感受趋势",
                icon: "face.smiling",
                tint: .purple
            )

            if derived?.moodPoints.isEmpty ?? true {
                Text("过去 60 天里，你记录了 0 天感受。可以在健康 App 的「心理状态」或这里本地记录，之后会显示趋势。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("打开健康 App") {
                        openHealthApp()
                    }
                    Spacer()
                    Button("本地记录") {
                        showMoodSheet = true
                    }
                }
                .font(.footnote)
            } else {
                Text("过去 60 天记录了 \(derived?.moodPoints.count ?? 0) 天感受 · 选择数据点可查看当日详情")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Chart(derived?.moodPoints ?? []) { point in
                    LineMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("心情", point.valence)
                    )
                    .foregroundStyle(.purple)
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("心情", point.valence)
                    )
                    .foregroundStyle(.purple)
                    .symbolSize(selectedMoodPoint?.id == point.id ? 90 : 36)
                }
                .chartYScale(domain: -1...1)
                .frame(height: 140)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        ZStack {
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .gesture(
                                    SpatialTapGesture()
                                        .onEnded { value in
                                            guard let plotFrame = proxy.plotFrame else { return }
                                            let x = value.location.x - geometry[plotFrame].origin.x
                                            if let date = proxy.value(atX: x, as: Date.self) {
                                                withAnimation(reduceMotion ? nil : .snappy) {
                                                    selectedMoodDate = date
                                                }
                                            }
                                        }
                                )
                            if let point = selectedMoodPoint,
                               let plotFrame = proxy.plotFrame,
                               let x = proxy.position(forX: point.date),
                               let y = proxy.position(forY: point.valence) {
                                ChartCalloutOverlay(
                                    lines: moodCalloutLines(point),
                                    anchor: CGPoint(
                                        x: geometry[plotFrame].origin.x + x,
                                        y: geometry[plotFrame].origin.y + y
                                    ),
                                    containerSize: geometry.size
                                )
                            }
                        }
                    }
                }
                HStack {
                    Text("消极")
                    Spacer()
                    Text("中性")
                    Spacer()
                    Text("积极")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
        .appCard()
    }

    private var selectedColor: Color {
        if let impact = selectedImpact {
            return impact.isPositive ? .teal : .orange
        }
        return .blue
    }

    private var selectedActionPoint: ActionTrendPoint? {
        guard let selectedActionDate else { return nil }
        return trendPoints.min {
            abs($0.date.timeIntervalSince(selectedActionDate))
                < abs($1.date.timeIntervalSince(selectedActionDate))
        }
    }

    private var selectedMoodPoint: MoodPoint? {
        guard let selectedMoodDate else { return nil }
        guard let points = derived?.moodPoints else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedMoodDate))
                < abs($1.date.timeIntervalSince(selectedMoodDate))
        }
    }

    private func actionCalloutLines(_ point: ActionTrendPoint) -> [String] {
        let date = point.date.formatted(.dateTime.month().day())
        let status = point.status == .met ? "符合" : "不符合"
        return [date, "压力 \(Int(point.stress.rounded())) · \(status)"]
    }

    private func moodCalloutLines(_ point: MoodPoint) -> [String] {
        let date = point.date.formatted(.dateTime.month().day())
        let source = point.isLocal ? "本地" : "健康 App"
        return [date, "心情 \(String(format: "%+.2f", point.valence)) · \(moodLabel(point.valence))", source]
    }

    private func moodLabel(_ valence: Double) -> String {
        if valence <= -0.2 { return "消极" }
        if valence < 0.2 { return "中性" }
        return "积极"
    }

    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        openURL(url)
    }
}

struct InsightInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section(
                        "怎么算",
                        "对每个行动，比较「符合」和「不符合」的日子里平均压力的差值。少于 5 天的组不参与；差值小于 2 分视为没有明显关联。影响程度：<7 分小、7–15 分中、≥15 分大。"
                    )
                    section(
                        "积极 / 消极",
                        "符合某个行动时压力更低，列为积极行动；更高则列为消极行动。阈值不是固定的，会随你的个人基线变化。"
                    )
                    section(
                        "相关性不是因果",
                        "这是基于过去 60 天的统计关联，不代表某个行动一定导致压力变化。睡眠、日照、活动之间也会互相影响，建议结合自己的感受判断。"
                    )
                    section(
                        "数据来源",
                        "行为数据来自 HealthKit 的睡眠、步数、日照、正念、爬楼等指标；压力分来自本 App 的本地评分。数据太少时会显示「还需要 N 天」。"
                    )
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("关于洞察")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
