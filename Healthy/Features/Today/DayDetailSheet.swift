import Charts
import SwiftData
import SwiftUI

/// 详情页入口类型：HRV 曲线只进 HRV 详情，压力曲线只进压力详情。
enum DayDetailMode: String, Identifiable {
    case hrv
    case stress

    var id: String { rawValue }

    var navigationTitle: String {
        switch self {
        case .hrv: return "HRV 详情"
        case .stress: return "压力详情"
        }
    }
}

struct DayDetailSheet: View {
    let mode: DayDetailMode
    let score: DailyScore?
    let metrics: [DailyMetrics]
    let intradaySummary: IntradaySummary
    /// 「此刻」实时卡片的数据与刷新入口：由首页传入，详情页不再单独拉数据。
    var currentSnapshot: CurrentStateSnapshot? = nil
    var isRefreshingCurrent: Bool = false
    var currentError: String? = nil
    var currentUpdatedAt: Date? = nil
    var intradayError: String? = nil
    var onRefreshCurrent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var selectedReading: IntradayReading?
    @State private var showAllReadings = false
    @State private var showStressInfo = false

    private var todaySnapshot: DailySnapshot? { metrics.first?.snapshot }
    private var history: [DailySnapshot] { metrics.dropFirst().map(\.snapshot) }

    private var hrvTrend: MetricTrendSummary {
        trend { MetricSanitizer.value($0.hrvSDNN, in: MetricRange.hrv) }
    }

    private var restingHRTrend: MetricTrendSummary {
        trend { MetricSanitizer.value($0.restingHR, in: MetricRange.restingHR) }
    }

    private var rhr60Mean: Double? {
        guard let todaySnapshot else { return nil }
        return MetricTrendSummary.make(
            history: history,
            today: todaySnapshot,
            calendar: .current,
            averageWindowDays: 60
        ) { MetricSanitizer.value($0.restingHR, in: MetricRange.restingHR) }.recentAverage
    }

    private func trend(_ extract: (DailySnapshot) -> Double?) -> MetricTrendSummary {
        guard let todaySnapshot else {
            return MetricTrendSummary(latest: nil, recentAverage: nil, delta: nil, series: [])
        }
        return MetricTrendSummary.make(
            history: history,
            today: todaySnapshot,
            calendar: .current,
            extract: extract
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    CurrentStateCard(
                        snapshot: currentSnapshot,
                        isRefreshing: isRefreshingCurrent,
                        error: currentError,
                        updatedAt: currentUpdatedAt,
                        onRefresh: onRefreshCurrent,
                        mode: mode
                    )
                    .cardScrollEffect()
                    if mode == .stress {
                        StatusBannerView(stress: score?.stress, readiness: score?.readiness)
                        StressInsightsCard(
                            summary: intradaySummary,
                            isLoading: isRefreshingCurrent,
                            error: intradayError,
                            onRefresh: onRefreshCurrent,
                            onOpenReading: { selectedReading = $0 },
                            onOpenAll: { showAllReadings = true },
                            onInfo: { showStressInfo = true },
                            sections: .stress
                        )
                        .cardScrollEffect()
                        stressSummaryCard
                            .cardScrollEffect()
                    } else {
                        AutonomicSummaryCard(hrv: hrvTrend, restingHR: restingHRTrend)
                            .cardScrollEffect()
                        StressInsightsCard(
                            summary: intradaySummary,
                            isLoading: isRefreshingCurrent,
                            error: intradayError,
                            onRefresh: onRefreshCurrent,
                            onOpenReading: { selectedReading = $0 },
                            onOpenAll: { showAllReadings = true },
                            onInfo: { showStressInfo = true },
                            sections: .hrv
                        )
                        .cardScrollEffect()
                        hrvBaselineCard
                            .cardScrollEffect()
                        todayHeartRateCard
                            .cardScrollEffect()
                    }
                    faqCard
                        .cardScrollEffect()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppScreenBackground())
            .navigationTitle(mode.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $selectedReading) { reading in
                NavigationStack {
                    StressReadingDetailView(
                        reading: reading,
                        summary: intradaySummary,
                        moodValence: metrics.first?.stateOfMindValence
                    )
                }
            }
            .sheet(isPresented: $showAllReadings) {
                NavigationStack {
                    StressReadingListView(
                        summary: intradaySummary,
                        moodValence: metrics.first?.stateOfMindValence
                    )
                }
            }
            .sheet(isPresented: $showStressInfo) {
                StressSourceInfoView()
            }
        }
    }

    private var hrvBaselineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "HRV 与 28 天基线", icon: "waveform.path.ecg", tint: .pink)
            HRVBaselineChart(metrics: metrics, baseline: intradaySummary.baselineHRVms)
            Text("折线为每日平均 SDNN；虚线为过去 28 天基线（对数均值还原）。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private var todayHeartRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "今日心率", icon: "heart.fill", tint: .orange)
            RestingHRIntradayChart(
                buckets: intradaySummary.buckets,
                sleepWindow: intradaySummary.sleepWindow,
                mean60d: rhr60Mean
            )
        }
        .appCard()
    }

    private var stressSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "压力总结", icon: "text.alignleft", tint: .blue)
            Text(stressSummaryText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .appCard()
    }

    private var faqCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "常见问题", icon: "questionmark.circle", tint: .teal)
            FAQListView(topics: mode == .hrv ? [.hrv, .baseline] : [.stress, .baseline])
        }
        .appCard()
    }

    private var stressSummaryText: String {
        guard let score else {
            return "基线还在积累，暂时没有压力评分。继续佩戴手表，数据越多评分越稳。"
        }
        var parts: [String] = []
        if let stress = score.stress {
            let level = StressEngine.level(for: stress, config: ScoringConfig())
            parts.append("今日压力 \(Int(stress.rounded())) 分（\(level.label)）")
        }
        parts.append("个人基线 \(score.baselineDays) 天，数据源 \(score.completeness)/\(MetricSource.allCases.count)")
        return parts.joined(separator: "；") + "。评分相对个人基线计算，仅供日常参考。"
    }
}

private struct HRVBaselineChart: View {
    let metrics: [DailyMetrics]
    let baseline: Double?

    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct HRVPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var value: Double
    }

    private var points: [HRVPoint] {
        metrics.prefix(28).reversed().compactMap { row in
            MetricSanitizer.value(row.hrvSDNN, in: MetricRange.hrv).map {
                HRVPoint(date: row.date, value: $0)
            }
        }
    }

    private var selectedPoint: HRVPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        if points.isEmpty {
            Text("还没有 HRV 历史数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(.pink.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("日期", point.date),
                        y: .value("HRV", point.value)
                    )
                    .foregroundStyle(.pink)
                    .symbolSize(selectedPoint?.date == point.date ? 90 : 30)
                }
                if let baseline {
                    RuleMark(y: .value("基线", baseline))
                        .foregroundStyle(.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let selectedPoint {
                    RuleMark(x: .value("选中", selectedPoint.date))
                        .foregroundStyle(.pink.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day())
                }
            }
            .frame(height: 160)
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
                                                selectedDate = date
                                            }
                                        }
                                    }
                            )
                        if let selectedPoint,
                           let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: selectedPoint.date),
                           let y = proxy.position(forY: selectedPoint.value) {
                            ChartCalloutOverlay(
                                lines: calloutLines(selectedPoint),
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
        }
    }

    private func calloutLines(_ point: HRVPoint) -> [String] {
        var lines = [
            point.date.formatted(.dateTime.month().day()),
            "HRV \(Int(point.value.rounded())) ms",
        ]
        if let baseline {
            lines.append("基线 \(Int(baseline.rounded())) ms")
        }
        return lines
    }
}

// configured by qoder