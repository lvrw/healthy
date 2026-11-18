import Charts
import SwiftData
import SwiftUI
import UIKit

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var appModel
    @Query(sort: \DailyScore.dayKey, order: .reverse) private var scores: [DailyScore]
    @Query(sort: \DailyMetrics.dayKey, order: .reverse) private var metrics: [DailyMetrics]
    @Query(sort: \DailyReport.dayKey, order: .reverse) private var reports: [DailyReport]
    @State private var isGeneratingBriefing = false
    @State private var briefingError: String?
    @State private var didAttemptAutoGenerate = false
    @State private var currentSnapshot: CurrentStateSnapshot?
    @State private var isRefreshingCurrent = false
    @State private var currentError: String?
    @State private var currentUpdatedAt: Date?
    @State private var intradaySummary: IntradaySummary = .empty
    @State private var intradayError: String?
    @State private var showStressInfo = false
    /// 详情页入口：HRV 曲线进 HRV 详情，压力曲线 / 状态简介进压力详情。
    @State private var detailMode: DayDetailMode?
    @State private var showShare = false
    @State private var showBriefingDetail = false
    /// 设置入口已从底部菜单栏移到今日页右上角。
    @State private var showSettings = false
    /// 首页刷新按钮：一次拉取健康数据、重算此刻状态与日内压力。
    @State private var isRefreshingAll = false

    private var todayScore: DailyScore? { scores.first }
    private var todayMetrics: DailyMetrics? { metrics.first }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        heroHeader(topInset: proxy.safeAreaInsets.top)
                        if todayMetrics == nil {
                            emptyState
                        } else {
                            VStack(spacing: 16) {
                                trendCard
                                adviceCard
                                sectionTitle("指标详情")
                                componentCards
                                completenessFootnote
                                groupCards
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 24)
                        }
                    }
                }
                // 顶部下拉刷新：iOS 标准原生 spinner，与「刷新健康数据」按钮走同一套逻辑。
                .withPullToRefresh {
                    await pullToRefresh()
                }
                .background(AppScreenBackground(tone: .white))
            }
            // 头图延伸到状态栏下方；GeometryReader 忽略安全区后才能读到真实的状态栏高度，
            // 用于给右上角悬浮按钮留出位置。
            .ignoresSafeArea(edges: .top)
            // 首页改为沉浸式插画头图，隐藏系统导航栏；子页面 push 后仍保留各自的返回栏。
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showShare) {
                ShareCardView(score: todayScore, metrics: todayMetrics)
            }
            .sheet(isPresented: $showSettings) {
                // SettingsView 自带 NavigationStack，用 sheet 呈现避免导航栈嵌套。
                SettingsView()
                    .presentationDragIndicator(.visible)
            }
            .task {
                await loadBriefingIfNeeded()
            }
            .task {
                if currentSnapshot == nil {
                    refreshCurrentState()
                }
            }
            .sheet(isPresented: $showStressInfo) {
                StressSourceInfoView()
            }
            .sheet(item: $detailMode) { mode in
                DayDetailSheet(
                    mode: mode,
                    score: todayScore,
                    metrics: metrics,
                    intradaySummary: intradaySummary,
                    currentSnapshot: currentSnapshot,
                    isRefreshingCurrent: isRefreshingCurrent,
                    currentError: currentError,
                    currentUpdatedAt: currentUpdatedAt,
                    intradayError: intradayError,
                    onRefreshCurrent: refreshCurrentState
                )
            }
            .sheet(isPresented: $showBriefingDetail) {
                briefingDetail
            }
            .sensoryFeedback(.success, trigger: currentUpdatedAt)
            .sensoryFeedback(.warning, trigger: currentError != nil)
        }
    }

    // MARK: - 顶部 Hero

    /// 参考图布局：整宽插画 + 弧形下沿，状态文案与四段状态条居中排在插画下方。
    private func heroHeader(topInset: CGFloat) -> some View {
        // 某些被安全区裁剪过的坐标系里 GeometryProxy 会退化成 0，
        // 用 keyWindow 的真实状态栏高度兜底，避免悬浮按钮钻进状态栏。
        let inset = max(topInset, windowTopSafeInset)
        return VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HeroAuroraArt()
                    .frame(maxWidth: .infinity)
                    .frame(height: 250)
                    .clipped()
                    .mask(HeroBottomCurve())
                    .accessibilityHidden(true)
                heroActions
                    .padding(.top, inset + 8)
                    .padding(.trailing, 16)
            }
            StatusBannerView(
                stress: todayScore?.stress,
                readiness: todayScore?.readiness,
                confidenceRaw: todayScore?.confidenceRaw,
                onInfo: { showStressInfo = true },
                showsChevron: true,
                style: .hero
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                if todayScore != nil {
                    detailMode = .stress
                }
            }
            .accessibilityHint("轻点查看今日压力详情")
        }
    }

    /// 备用读数：keyWindow 的真实顶部安全区，机型 / 方向变化时也能取到。
    @MainActor
    private var windowTopSafeInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .safeAreaInsets.top ?? 0
    }

    private var heroActions: some View {
        HStack(spacing: 10) {
            heroActionButton(
                systemName: "arrow.clockwise",
                label: "刷新健康数据",
                isLoading: isRefreshingAll,
                action: refreshAll
            )
            heroActionButton(
                systemName: "square.and.arrow.up",
                label: "分享",
                action: { showShare = true }
            )
            heroActionButton(
                systemName: "gearshape",
                label: "设置",
                action: { showSettings = true }
            )
        }
    }

    private func heroActionButton(
        systemName: String,
        label: String,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.92))
                    .overlay(
                        Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppPalette.ink)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppPalette.ink)
                }
            }
            .frame(width: 34, height: 34)
            .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(label)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.slash")
                .font(.system(size: 30))
                .foregroundStyle(AppPalette.ink4)
            Text("还没有健康数据")
                .font(.headline)
            Text("去「设置」授权 HealthKit，或载入示例数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("去设置") { showSettings = true }
                    .buttonStyle(.borderedProminent)
                Button("刷新") { refreshAll() }
                    .buttonStyle(.bordered)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: 24)
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    // MARK: - 核心概览卡

    /// 核心曲线卡：只放 HRV / 压力两条近 7 天曲线，整块可点进「此刻与日内」。
    private var trendCard: some View {
        HStack(alignment: .top, spacing: 14) {
            trendMetric(
                title: "HRV 曲线",
                value: hrvToday,
                unit: "ms",
                noteText: hrvNoteText,
                noteSymbol: hrvNoteSymbol,
                noteTint: hrvNoteTint,
                values: recentHRVValues,
                tint: AppPalette.teal,
                mode: .hrv
            )
            Divider().frame(height: 112)
            trendMetric(
                title: "压力曲线",
                value: stressToday,
                unit: "分",
                noteText: stressNoteText,
                noteSymbol: stressNoteSymbol,
                noteTint: stressNoteTint,
                values: recentStressValues,
                tint: stressTint,
                mode: .stress
            )
        }
        .appCard()
        .cardScrollEffect()
    }

    /// 建议 + 解读卡：与曲线分开成独立卡片，不再和图表连在一起。
    private var adviceCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            adviceRow
            summaryBody
            Text(updateText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Divider()
            summaryFooter
        }
        .appCard()
        .cardScrollEffect()
    }

    private func trendMetric(
        title: String,
        value: Double?,
        unit: String,
        noteText: String,
        noteSymbol: String?,
        noteTint: Color,
        values: [Double],
        tint: Color,
        mode: DayDetailMode
    ) -> some View {
        Button {
            detailMode = mode
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(AppType.display(30))
                        .monospacedDigit()
                        .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 3) {
                    if let noteSymbol {
                        Image(systemName: noteSymbol)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(noteTint)
                    }
                    Text(noteText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                trendChart(values: values, tint: tint)
                    .frame(height: 48)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("轻点查看此刻与日内")
    }

    /// 近 7 天曲线：面积渐变 + 折线 + 最新点，不画坐标轴。
    private func trendChart(values: [Double], tint: Color) -> some View {
        Chart {
            ForEach(values.indices, id: \.self) { index in
                AreaMark(
                    x: .value("天", index),
                    y: .value("值", values[index])
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.24), tint.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("天", index),
                    y: .value("值", values[index])
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            }
            if let last = values.indices.last {
                PointMark(
                    x: .value("天", last),
                    y: .value("值", values[last])
                )
                .foregroundStyle(tint)
                .symbolSize(22)
            }
        }
        .chartYScale(domain: sparkDomain(values))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(maxWidth: .infinity)
        .opacity(values.count > 1 ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func sparkDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.25, 1)
        return (min - padding)...(max + padding)
    }

    private var adviceRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppPalette.greenDeep)
                .frame(width: 22, height: 22)
                .background(Color(.secondarySystemGroupedBackground), in: Circle())
            Text(adviceText)
                .font(.footnote)
                .foregroundStyle(AppPalette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            AppPalette.greenSoft,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var adviceText: String {
        guard let stress = todayScore?.stress else {
            return "继续佩戴手表，积累更多数据后给出更贴合你的建议。"
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

    /// AI 解读：有缓存就展示摘要，没有时按配置 / 基线状态给出对应入口。
    @ViewBuilder
    private var summaryBody: some View {
        if isGeneratingBriefing {
            HStack(spacing: 8) {
                ProgressView()
                Text("正在生成解读…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else if let briefingError {
            VStack(alignment: .leading, spacing: 6) {
                Text(briefingError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                Button("重试") {
                    generateBriefing(force: true)
                }
                .font(.footnote.weight(.medium))
            }
        } else if let report = cachedBriefing {
            Text(report.summary)
                .font(.footnote)
                .foregroundStyle(AppPalette.ink2)
                .lineLimit(4)
                .truncationMode(.tail)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if !BriefingService.isConfigured() {
            Text("还没有配置 AI 服务，可在「设置 → AI 服务」填入 API Key 后生成解读。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if let score = todayScore, score.baselineDays < 3 {
            Text("个人基线还在积累，至少 3 天后可生成 AI 解读。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            Button {
                generateBriefing(force: false)
            } label: {
                Label("生成智能评分", systemImage: "sparkles")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private var summaryFooter: some View {
        HStack(spacing: 0) {
            Button {
                showBriefingDetail = true
            } label: {
                Text("详细解读")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            Divider().frame(height: 16)
            NavigationLink {
                ChatView(dayKey: todayKey)
            } label: {
                Text("问问 AI")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(AppPalette.greenDeep)
        .padding(.top, 2)
    }

    private var updateText: String {
        let date = todayReportRow?.generatedAt ?? todayMetrics?.updatedAt
        guard let date else { return "数据尚未更新" }
        return "数据更新于 \(date.formatted(date: .omitted, time: .shortened))"
    }

    // MARK: - 核心指标数据

    private var stressToday: Double? {
        todayScore?.stress
    }

    private var hrvToday: Double? {
        todayMetrics?.hrvSDNN ?? todayMetrics?.hrvLatest
    }

    /// 近 7 天（含今天）的压力值与日均 HRV，用于列平均与曲线。
    private var recentStressValues: [Double] {
        Array(scores.prefix(7).reversed()).compactMap(\.stress)
    }

    private var recentHRVValues: [Double] {
        Array(metrics.prefix(7).reversed()).compactMap { $0.hrvSDNN ?? $0.hrvLatest }
    }

    private var stressTint: Color {
        TodayStatusPresentation.make(stress: stressToday).level?.tint ?? AppPalette.orange
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var stressNoteText: String {
        guard let avg = average(recentStressValues) else { return "7 天暂无数据" }
        return "7 天均值 \(Int(avg.rounded())) 分"
    }

    private var stressNoteSymbol: String? {
        guard let avg = average(recentStressValues), let today = stressToday else { return nil }
        // 压力越低越好，方向与 HRV 相反。
        if today < avg - 1 { return "arrow.down" }
        if today > avg + 1 { return "arrow.up" }
        return "arrow.right"
    }

    private var stressNoteTint: Color {
        guard let avg = average(recentStressValues), let today = stressToday else { return .secondary }
        if today < avg - 1 { return AppPalette.greenDeep }
        if today > avg + 1 { return AppPalette.orange }
        return .secondary
    }

    private var hrvNoteText: String {
        guard let avg = average(recentHRVValues) else { return "7 天暂无数据" }
        return "7 天均值 \(Int(avg.rounded()))ms"
    }

    private var hrvNoteSymbol: String? {
        guard let avg = average(recentHRVValues), let today = hrvToday else { return nil }
        if today > avg + 1 { return "arrow.up" }
        if today < avg - 1 { return "arrow.down" }
        return "arrow.right"
    }

    private var hrvNoteTint: Color {
        guard let avg = average(recentHRVValues), let today = hrvToday else { return .secondary }
        if today > avg + 1 { return AppPalette.greenDeep }
        if today < avg - 1 { return AppPalette.orange }
        return .secondary
    }

    // MARK: - 页面结构

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppPalette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
            .padding(.top, 4)
    }

    @ViewBuilder
    private var componentCards: some View {
        if let metrics = todayMetrics, let score = todayScore {
            let readiness = decodeReadiness(score)
            let sleepGroup = MetricGroup(
                title: "睡眠",
                icon: "moon.zzz.fill",
                tint: .indigo,
                rows: SleepCardView.detailRows(metrics),
                footnote: "恢复性分为展示指标，不参与状态 / 压力评分；dip 由全天平均心率推算。"
            )
            let autonomicGroup = MetricGroup(
                title: "心率变异性 / 静息心率",
                icon: "waveform.path.ecg",
                tint: .pink,
                rows: autonomicRows(metrics),
                footnote: "HRV 与静息心率均相对 28 天个人基线评估，数值缺失时沿用最近一次读数。"
            )
            let activityGroup = MetricGroup(
                title: "活动",
                icon: "figure.walk",
                tint: .green,
                rows: activityRows(metrics),
                footnote: "活动负荷取近 7 天与近 28 天均值之比，数据来自健康 App。"
            )
            let vitalsGroup = MetricGroup(
                title: "生命体征",
                icon: "thermometer.medium",
                tint: .teal,
                rows: vitalRows(metrics),
                footnote: "血压 / 血糖没有设备时，可在健康 App 手动记录；异常值仅作提示，非医疗诊断。"
            )
            VStack(spacing: 12) {
                metricCardLink(group: sleepGroup, score: readiness?.sleep) {
                    SleepCardView(
                        metrics: metrics,
                        componentScore: readiness?.sleep,
                        showsDetail: true
                    )
                }
                metricCardLink(group: autonomicGroup, score: readiness?.autonomic) {
                    ComponentCard(
                        title: autonomicGroup.title,
                        icon: autonomicGroup.icon,
                        tint: autonomicGroup.tint,
                        score: readiness?.autonomic,
                        rows: autonomicGroup.rows,
                        footnote: autonomicGroup.footnote,
                        showsDetail: true
                    )
                }
                metricCardLink(group: activityGroup, score: readiness?.load) {
                    ComponentCard(
                        title: activityGroup.title,
                        icon: activityGroup.icon,
                        tint: activityGroup.tint,
                        score: readiness?.load,
                        rows: activityGroup.rows,
                        footnote: activityGroup.footnote,
                        showsDetail: true
                    )
                }
                metricCardLink(group: vitalsGroup, score: readiness?.vitals) {
                    ComponentCard(
                        title: vitalsGroup.title,
                        icon: vitalsGroup.icon,
                        tint: vitalsGroup.tint,
                        score: readiness?.vitals,
                        rows: vitalsGroup.rows,
                        footnote: vitalsGroup.footnote,
                        showsDetail: true
                    )
                }
            }
        }
    }

    /// 「指标详情」区共用的整卡跳转：点卡片 push 到指标分组详情页。
    /// 卡片内部不再放 NavigationLink，避免嵌套导航链接抢手势。
    private func metricCardLink<Card: View>(
        group: MetricGroup,
        score: Double?,
        @ViewBuilder card: () -> Card
    ) -> some View {
        NavigationLink {
            MetricGroupDetailView(group: group, score: score, metrics: self.metrics)
        } label: {
            card()
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    /// 数据源完整度并入拆解区脚注，不再单独占一张卡片。
    @ViewBuilder
    private var completenessFootnote: some View {
        if let score = todayScore {
            VStack(alignment: .leading, spacing: 4) {
                Text(dataCoverageText(score))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if score.confidenceRaw == ScoreConfidence.insufficient.rawValue {
                    Text("正在积累个人基线：已有 \(score.baselineDays) 天，还需约 \(max(0, 7 - score.baselineDays)) 天才能稳定评分。")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func dataCoverageText(_ score: DailyScore) -> String {
        var text = "\(score.completeness)/\(MetricSource.allCases.count) 数据源可用 · 基线 \(score.baselineDays) 天"
        if !score.missing.isEmpty {
            text += " · 缺失：\(score.missing)"
        }
        return text
    }

    @ViewBuilder
    private var groupCards: some View {
        // 饮食与饮水只在「行动」页维护，首页指标详情不再重复展示。
        let groups = MetricGroupFactory.groups(metrics: metrics)
            .filter { $0.title != "饮食与饮水" }
        if groups.isEmpty {
            Text("指标详情暂无更多数据。体重来自智能秤，血压 / 血糖需要在健康 App 或设备中记录。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(padding: 14)
        } else {
            let readiness = todayScore.flatMap(decodeReadiness)
            VStack(spacing: 12) {
                ForEach(groups, id: \.title) { group in
                    metricCardLink(
                        group: group,
                        score: groupScore(title: group.title, components: readiness)
                    ) {
                        MetricGroupCard(
                            title: group.title,
                            icon: group.icon,
                            tint: group.tint,
                            rows: group.rows,
                            footnote: group.footnote,
                            score: groupScore(title: group.title, components: readiness),
                            showsDetail: true
                        )
                    }
                }
            }
        }
    }

    /// 分组卡与评分引擎的分项对应关系：心肺体能 → fitnessBody，生活节律 → circadian，
    /// 饮食与饮水 → nutrition，身体成分 → bodyComposition（仅展示，不并入综合评分）。
    /// 数据不足时引擎会给 nil，对应分组就不显示评分角标。
    private func groupScore(title: String, components: ReadinessComponents?) -> Double? {
        switch title {
        case "心肺体能": return components?.fitnessBody
        case "生活节律": return components?.circadian
        case "饮食与饮水": return components?.nutrition
        case "身体成分": return components?.bodyComposition
        default: return nil
        }
    }

    // MARK: - 数据刷新

    /// 首页刷新按钮：先刷新此刻 / 日内信号，再拉一次健康数据并重算评分。
    private func refreshAll() {
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        Task { @MainActor in
            let perfToken = PerformanceTrace.shared.begin("页面 · 今日 · 全部刷新", category: .page)
            defer { PerformanceTrace.shared.end(perfToken) }
            await appModel.pullToRefresh { await pullToRefresh() }
            isRefreshingAll = false
        }
    }

    /// 顶部下拉刷新与刷新按钮共用的实际动作：此刻 / 日内信号 + 健康数据同步。
    private func pullToRefresh() async {
        await refreshCurrentStateNow()
        await appModel.sync()
        if case let .failed(message) = appModel.phase {
            currentError = message
        }
    }

    private func refreshCurrentState() {
        Task { await refreshCurrentStateNow() }
    }

    private func refreshCurrentStateNow() async {
        guard !isRefreshingCurrent else { return }
        let perfToken = PerformanceTrace.shared.begin("页面 · 今日 · 刷新此刻状态", category: .page)
        defer { PerformanceTrace.shared.end(perfToken) }
        isRefreshingCurrent = true
        currentError = nil
        intradayError = nil

        let todaySnapshot = todayMetrics?.snapshot ?? DailySnapshot(dayKey: todayKey, date: .now)
        let history = metrics.dropFirst().map(\.snapshot)
        let service = HealthKitService()

        // 先把两路信号都取回、算好，最后一次性提交状态。
        // 之前每个 do 块各带一个 withAnimation(.snappy)，松手后连续触发两次
        // 整棵首页树（含 Charts）动画重绘，是「卡两下」的根因；合并为一次事务。
        var nextSnapshot: CurrentStateSnapshot?
        var nextIntraday: IntradaySummary?
        var nextUpdatedAt: Date?
        var nextCurrentError: String?
        var nextIntradayError: String?

        do {
            let signals = try await service.fetchCurrentSignals()
            nextSnapshot = CurrentStateEngine.evaluate(
                today: todaySnapshot,
                history: history,
                readiness: todayScore?.readiness,
                signals: signals
            )
            nextUpdatedAt = .now
        } catch {
            nextCurrentError = error.localizedDescription
        }

        do {
            let signals = try await service.fetchIntradaySignals()
            nextIntraday = IntradayStressEngine.evaluate(
                today: todaySnapshot,
                history: history,
                signals: signals
            )
        } catch {
            nextIntradayError = error.localizedDescription
        }

        let transaction = Transaction(animation: reduceMotion ? nil : .snappy)
        withTransaction(transaction) {
            if let nextSnapshot { currentSnapshot = nextSnapshot }
            if let nextUpdatedAt { currentUpdatedAt = nextUpdatedAt }
            if let nextIntraday { intradaySummary = nextIntraday }
            currentError = nextCurrentError
            intradayError = nextIntradayError
            isRefreshingCurrent = false
        }
    }

    // MARK: - 晨报生成

    private var todayKey: String {
        DayKey.key(for: .now)
    }

    /// 当天报告行，不按状态过滤。
    /// `BriefingService.generate(force: true)` 会先把同一行改成 pending，
    /// 但 payloadJSON 仍保留上一次成功内容；只认 status == .success 会让
    /// 详情页在点击「重新生成」的瞬间变成空白 sheet（白屏）。
    private var todayReportRow: DailyReport? {
        reports.first { $0.dayKey == todayKey }
    }

    private var cachedBriefing: BriefingReport? {
        guard let json = todayReportRow?.payloadJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BriefingReport.self, from: json)
    }

    private func loadBriefingIfNeeded() async {
        guard !didAttemptAutoGenerate else { return }
        didAttemptAutoGenerate = true
        if let existing = todayReportRow {
            switch existing.status {
            case .success:
                if cachedBriefing == nil {
                    briefingError = "已保存的评分报告无法读取，请重新生成。"
                }
            case .failed:
                briefingError = existing.errorMessage ?? "上次生成失败，请手动重试。"
            case .pending:
                briefingError = "上次生成没有完成（可能被中断），点击重试。"
            }
            return
        }
        guard BriefingService.isConfigured(),
              let score = todayScore,
              score.baselineDays >= 3
        else { return }
        generateBriefing(force: false)
    }

    private func generateBriefing(force: Bool) {
        guard !isGeneratingBriefing else { return }
        guard AISmartScoringSettings.isEnabled else {
            briefingError = "已在设置中关闭「智能评分」AI 功能。"
            return
        }
        isGeneratingBriefing = true
        briefingError = nil
        Task { @MainActor in
            let perfToken = PerformanceTrace.shared.begin("页面 · 今日 · 生成晨报", category: .page)
            defer { PerformanceTrace.shared.end(perfToken) }
            do {
                let service = BriefingService(context: context)
                _ = try await service.generate(dayKey: todayKey, force: force)
            } catch {
                briefingError = error.localizedDescription
            }
            isGeneratingBriefing = false
        }
    }

    @ViewBuilder
    private var briefingDetail: some View {
        if let report = cachedBriefing {
            BriefingDetailSheet(
                report: report,
                readiness: todayScore?.readiness,
                stress: todayScore?.stress,
                baselineDays: todayScore?.baselineDays ?? 0,
                updatedAt: todayReportRow?.generatedAt,
                isGenerating: isGeneratingBriefing,
                errorMessage: briefingError,
                onRegenerate: { generateBriefing(force: true) }
            )
        } else {
            briefingPlaceholder
        }
    }

    /// sheet 的兜底内容：首次生成、生成中、生成失败且没有历史报告时都有可见界面，
    /// 绝不给 EmptyView，否则用户只会看到一片白。
    private var briefingPlaceholder: some View {
        NavigationStack {
            VStack(spacing: 14) {
                if isGeneratingBriefing {
                    ProgressView()
                    Text("正在生成智能评分…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: briefingError == nil ? "sparkles" : "exclamationmark.triangle")
                        .font(.system(size: 30))
                        .foregroundStyle(briefingError == nil ? .orange : .red)
                    Text(briefingError ?? "暂时还没有可显示的智能评分。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("重新生成") {
                        generateBriefing(force: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppScreenBackground(tone: .lavender))
            .navigationTitle("智能评分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showBriefingDetail = false }
                }
            }
        }
    }

    // MARK: - 展示辅助

    private func decodeReadiness(_ score: DailyScore) -> ReadinessComponents? {
        guard let json = score.readinessComponentsJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadinessComponents.self, from: json)
    }

    private func autonomicRows(_ metrics: DailyMetrics) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let hrv = metrics.hrvLatest ?? metrics.hrvSDNN {
            var value = "\(Int(hrv.rounded())) ms"
            if let measuredAt = metrics.hrvLatestAt {
                value += " · \(measuredAt.formatted(.relative(presentation: .named)))"
            }
            rows.append(InfoRow(label: "HRV", value: value))
        } else {
            rows.append(InfoRow(label: "HRV", value: "—"))
        }
        rows.append(InfoRow(label: "静息心率", value: metrics.restingHR.map { "\(Int($0.rounded())) 次/分" } ?? "—"))
        return rows
    }

    private func activityRows(_ metrics: DailyMetrics) -> [InfoRow] {
        [
            InfoRow(label: "步数", value: metrics.steps.map { "\(Int($0.rounded()))" } ?? "—"),
            InfoRow(label: "活动能量", value: metrics.activeEnergy.map { "\(Int($0.rounded())) 千卡" } ?? "—"),
            InfoRow(label: "锻炼", value: metrics.exerciseMinutes.map { "\(Int($0.rounded())) 分钟" } ?? "—"),
        ]
    }

    private func vitalRows(_ metrics: DailyMetrics) -> [InfoRow] {
        var rows: [InfoRow] = [
            InfoRow(label: "呼吸频率", value: metrics.respiratoryRate.map { String(format: "%.1f 次/分", $0) } ?? "—"),
            InfoRow(label: "血氧", value: metrics.spo2.map { String(format: "%.0f%%", $0) } ?? "—"),
        ]
        if let wrist = latestWristTemperature() {
            rows.append(InfoRow(label: "手腕温度", value: wrist))
        } else {
            rows.append(InfoRow(label: "手腕温度", value: "—"))
        }
        return rows
    }

    private func latestWristTemperature() -> String? {
        guard let latest = metrics.first(where: { $0.wristTempC != nil }),
              let temperature = latest.wristTempC
        else { return nil }
        let suffix = latest.dayKey == todayKey
            ? ""
            : " · \(latest.date.formatted(.dateTime.month().day()))"
        return String(format: "%.1f℃%@", temperature, suffix)
    }
}

/// 首页插画的下沿弧形裁切：左右两端收高，中间向下鼓出，衔接下方白色内容区。
private struct HeroBottomCurve: Shape {
    var dip: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .zero)
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - dip))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: rect.maxY - dip),
            control: CGPoint(x: rect.midX, y: rect.maxY + dip)
        )
        path.closeSubpath()
        return path
    }
}

/// 首页头图：抽象的「晨光 + 节律线」——柔和的薄荷 / 淡紫光斑，
/// 加一条压力律动曲线。浅色是清晨青绿，深色压成深夜森林，避免亮白断层。
private struct HeroAuroraArt: View {
    /// 顶部主色：浅色薄荷，深色墨绿。
    private static let topTint = AppPalette.adaptive(
        light: (0.851, 0.949, 0.890),
        dark: (0.047, 0.106, 0.078)
    )
    /// 中部过渡色：浅色接近页面白，深色压到近黑。
    private static let midTint = AppPalette.adaptive(
        light: (0.961, 0.984, 0.973),
        dark: (0.055, 0.075, 0.063)
    )

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Self.topTint,
                    Self.midTint,
                    Color(uiColor: .systemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottom
            )

            // 左上薄荷 + 右侧淡紫 + 底部天蓝三团柔光，深色下调透明度避免发灰。
            RadialGradient(
                colors: [AppPalette.green.opacity(0.34), .clear],
                center: UnitPoint(x: 0.14, y: 0.18),
                startRadius: 8,
                endRadius: 240
            )
            RadialGradient(
                colors: [AppPalette.lav.opacity(0.24), .clear],
                center: UnitPoint(x: 0.92, y: 0.38),
                startRadius: 8,
                endRadius: 220
            )
            RadialGradient(
                colors: [AppPalette.sky.opacity(0.20), .clear],
                center: UnitPoint(x: 0.34, y: 0.96),
                startRadius: 8,
                endRadius: 190
            )

            // 右上角三层柔光圆环，与悬浮按钮错开，增加层次。
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
                    .frame(width: 96, height: 96)
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    .frame(width: 156, height: 156)
                Circle()
                    .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                    .frame(width: 222, height: 222)
            }
            .offset(x: 132, y: -72)

            // 主律动线 + 一条错位的淡淡副线，模拟一天的呼吸感。
            VStack {
                Spacer()
                ZStack {
                    HeroRhythmLine(phase: 1.6)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppPalette.teal.opacity(0.10),
                                    AppPalette.teal.opacity(0.22)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round)
                        )
                        .offset(y: 14)
                    HeroRhythmLine()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    AppPalette.teal.opacity(0.35),
                                    AppPalette.greenDeep.opacity(0.75)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                        )
                }
                .frame(height: 62)
                .padding(.horizontal, 26)
                .padding(.bottom, 52)
            }
        }
    }
}

/// 装饰用的平滑律动曲线：两端收敛、中间起伏，模拟一天的节律感。
private struct HeroRhythmLine: Shape {
    /// 相位偏移，用于叠一条错位的副线。
    var phase: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let steps = 160
        func point(at t: CGFloat) -> CGPoint {
            let envelope = 0.3 + 0.7 * sin(t * .pi)
            let y = rect.midY + sin(t * .pi * 3.4 + 0.4 + phase) * rect.height * 0.34 * envelope
            return CGPoint(x: rect.minX + rect.width * t, y: y)
        }
        path.move(to: point(at: 0))
        for step in 1...steps {
            path.addLine(to: point(at: CGFloat(step) / CGFloat(steps)))
        }
        return path
    }
}

struct ConfidenceBadge: View {
    let raw: String

    private var text: String {
        switch raw {
        case ScoreConfidence.full.rawValue: return "数据完整"
        case ScoreConfidence.low.rawValue: return "低置信度"
        default: return "基线积累中"
        }
    }

    private var tint: Color {
        switch raw {
        case ScoreConfidence.full.rawValue: return .green
        case ScoreConfidence.low.rawValue: return .orange
        default: return .gray
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
            .foregroundStyle(tint)
    }
}

#Preview {
    let container = try! ModelContainer(
        for: DailyMetrics.self, DailyScore.self, DailyReport.self, ChatSession.self, ActionCheckIn.self, MoodEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TodayView()
        .environment(AppModel(context: container.mainContext))
        .modelContainer(container)
}
