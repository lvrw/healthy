import Charts
import SwiftData
import SwiftUI

struct TrendsView: View {
    @Query(sort: \DailyScore.dayKey) private var scores: [DailyScore]
    @Query(sort: \DailyMetrics.dayKey) private var metrics: [DailyMetrics]
    @State private var range: TrendRange = .week
    @State private var moreMetric: MoreMetric = .weight
    @State private var selectedLevelDate: Date?
    /// 原型周视图顶部「如何理解压力趋势？」横幅，可关闭、可展开解读。
    @State private var showPromo = true
    @State private var showTrendGuide = false
    @State private var showShare = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 全局数据同步入口：顶部下拉刷新时重新拉取 HealthKit 数据并重算评分。
    @Environment(AppModel.self) private var appModel

    private var cutoff: Date {
        DayKey.addingDays(-(range.days - 1), to: DayKey.startOfDay(.now))
    }

    private var rangedScores: [DailyScore] {
        scores.filter { $0.date >= cutoff }
    }

    private var rangedMetrics: [DailyMetrics] {
        metrics.filter { $0.date >= cutoff }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    Picker("范围", selection: $range) {
                        ForEach(TrendRange.allCases) { range in
                            Text(range.title).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    dateRangeBar

                    if showPromo {
                        promoBanner
                    }

                    HStack {
                        Text("更多指标")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("更多指标", selection: $moreMetric) {
                            ForEach(MoreMetric.allCases) { metric in
                                Text(metric.title).tag(metric)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    if rangedScores.isEmpty && rangedMetrics.isEmpty {
                        ContentUnavailableView(
                            "暂无趋势数据",
                            systemImage: "chart.xyaxis.line",
                            description: Text("同步 HealthKit 或载入示例数据后展示趋势。")
                        )
                        .padding(.top, 60)
                    } else {
                        scoreChart
                        if range != .year {
                            levelBarsCard
                        }
                        distributionCard
                        hrvChart
                        restingHRChart
                        sleepChart
                        moreMetricChart
                        if range != .year {
                            dailyListCard
                        }
                    }
                }
                .padding(16)
            }
            // 顶部下拉刷新：拉一次健康数据并重算评分，@Query 驱动图表自动更新。
            .withPullToRefresh {
                await appModel.sync()
            }
            .background(AppScreenBackground(tone: .white))
            .navigationTitle("趋势")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showShare = true
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ShareCardView(score: scores.first, metrics: metrics.first)
            }
            .sheet(isPresented: $showTrendGuide) {
                StressTrendGuideView()
            }
            .animation(.snappy, value: range)
            .animation(.snappy, value: moreMetric)
        }
    }

    /// 原型周/月/年分段下方的日期范围条（上一周期按钮到边界时禁用）。
    private var dateRangeBar: some View {
        let calendar = Calendar.current
        let start = cutoff
        let end = DayKey.startOfDay(.now)
        let startText = "\(calendar.component(.month, from: start))月\(calendar.component(.day, from: start))日"
        let endText = "\(calendar.component(.month, from: end))月\(calendar.component(.day, from: end))日"
        return HStack(spacing: 10) {
            Button {
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
            }
            .disabled(true)
            .accessibilityLabel("上一周期（已到边界）")
            Text("\(startText) - \(endText)")
                .font(AppType.small.weight(.semibold))
                .foregroundStyle(AppPalette.greenDeep)
            Image(systemName: "chevron.down")
                .font(.system(size: 12))
                .foregroundStyle(AppPalette.greenDeep)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// 原型「如何理解压力趋势？」横幅：整块可点开解读，右侧按钮仅用于关闭。
    private var promoBanner: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                showTrendGuide = true
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("如何理解压力趋势？")
                            .font(AppType.cardTitle)
                        Text("了解每日压力状态的形成与解读方式")
                            .font(AppType.tiny)
                            .foregroundStyle(AppPalette.ink3)
                    }
                    Spacer()
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 30))
                        .foregroundStyle(AppPalette.green)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            Button {
                withAnimation { showPromo = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppPalette.ink3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭提示")
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var scoreChart: some View {
        card(range == .year ? "月度均值（降采样）" : "身体状态与压力") {
            if range == .year {
                let readinessPoints = rangedScores.compactMap { score -> (Date, Double)? in
                    score.readiness.map { (score.date, $0) }
                }
                let stressPoints = rangedScores.compactMap { score -> (Date, Double)? in
                    score.stress.map { (score.date, $0) }
                }
                if readinessPoints.isEmpty && stressPoints.isEmpty {
                    emptyHint
                } else {
                    Chart {
                        ForEach(TrendAggregates.monthlyAverages(points: readinessPoints, calendar: .current)) { bucket in
                            BarMark(
                                x: .value("月份", bucket.monthStart, unit: .month),
                                y: .value("状态均值", bucket.average)
                            )
                            .foregroundStyle(Color.green.opacity(0.75))
                            .position(by: .value("指标", "身体状态"))
                        }
                        ForEach(TrendAggregates.monthlyAverages(points: stressPoints, calendar: .current)) { bucket in
                            BarMark(
                                x: .value("月份", bucket.monthStart, unit: .month),
                                y: .value("压力均值", bucket.average)
                            )
                            .foregroundStyle(Color.orange.opacity(0.75))
                            .position(by: .value("指标", "压力"))
                        }
                    }
                    .chartForegroundStyleScale(["身体状态": Color.green, "压力": Color.orange])
                    .chartYScale(domain: 0...100)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.defaultDigits), centered: true)
                        }
                    }
                    .frame(height: 200)
                    Text("月内所有有评分日的算术平均；展示统计，不参与评分。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if rangedScores.contains(where: { $0.readiness != nil || $0.stress != nil }) {
                Chart {
                    ForEach(rangedScores) { score in
                        if let readiness = score.readiness {
                            LineMark(
                                x: .value("日期", score.date, unit: .day),
                                y: .value("分数", readiness)
                            )
                            .foregroundStyle(by: .value("指标", "身体状态"))
                            .interpolationMethod(.catmullRom)
                        }
                        if let stress = score.stress {
                            LineMark(
                                x: .value("日期", score.date, unit: .day),
                                y: .value("分数", stress)
                            )
                            .foregroundStyle(by: .value("指标", "压力"))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartForegroundStyleScale(["身体状态": Color.green, "压力": Color.orange])
                .chartYScale(domain: 0...100)
                .frame(height: 200)
            } else {
                emptyHint
            }
        }
    }

    private var stressDays: [(date: Date, stress: Double, level: StressLevel)] {
        rangedScores.compactMap { score in
            guard let stress = score.stress else { return nil }
            return (score.date, stress, StressEngine.level(for: stress, config: ScoringConfig()))
        }
    }

    private var levelBarsCard: some View {
        card("每日压力等级") {
            let days = stressDays
            if days.isEmpty {
                emptyHint
            } else {
                Chart(days, id: \.date) { day in
                    BarMark(
                        x: .value("日期", day.date, unit: .day),
                        y: .value("压力", day.stress)
                    )
                    .foregroundStyle(day.level.tint.opacity(0.85))
                    .cornerRadius(3)
                }
                .chartYScale(domain: 0...100)
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
                                                    selectedLevelDate = date
                                                }
                                            }
                                        }
                                )
                            if let selected = selectedLevelDay,
                               let plotFrame = proxy.plotFrame,
                               let x = proxy.position(forX: selected.date),
                               let y = proxy.position(forY: selected.stress) {
                                ChartCalloutOverlay(
                                    lines: levelCalloutLines(selected),
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
                HStack(spacing: 8) {
                    ForEach(StressLevel.allCases, id: \.self) { level in
                        legendChip(level.label, color: level.tint)
                    }
                    Spacer()
                }
                Text("柱形颜色对应四档压力等级（30 / 50 / 70 分为界）；选择柱形可查看当日详情。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var selectedLevelDay: (date: Date, stress: Double, level: StressLevel)? {
        guard let selectedLevelDate else { return nil }
        return stressDays.min {
            abs($0.date.timeIntervalSince(selectedLevelDate))
                < abs($1.date.timeIntervalSince(selectedLevelDate))
        }
    }

    private func levelCalloutLines(_ day: (date: Date, stress: Double, level: StressLevel)) -> [String] {
        let count = stressDays.filter { $0.level == day.level }.count
        let average = stressDays.map(\.stress).reduce(0, +) / Double(stressDays.count)
        return [
            day.date.formatted(.dateTime.month().day()),
            "压力 \(Int(day.stress.rounded())) · \(day.level.label)",
            "\(count) 天同档 · 比区间均值 \(day.stress >= average ? "+" : "")\(Int((day.stress - average).rounded()))",
        ]
    }

    private var distributionCard: some View {
        card("压力分布") {
            let counts = TrendAggregates.levelDistribution(
                stressValues: stressDays.map(\.stress),
                config: ScoringConfig()
            )
            if stressDays.isEmpty {
                emptyHint
            } else {
                GeometryReader { geometry in
                    HStack(spacing: 2) {
                        ForEach(counts) { entry in
                            if entry.fraction > 0 {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(entry.level.tint.opacity(0.85))
                                    .frame(width: max(0, CGFloat(entry.fraction) * (geometry.size.width - 6)))
                            }
                        }
                    }
                }
                .frame(height: 16)
                .clipShape(Capsule())
                ForEach(counts) { entry in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(entry.level.tint)
                            .frame(width: 7, height: 7)
                        Text(entry.level.label)
                            .font(.caption)
                        Spacer()
                        Text("\(entry.count) 天 · \(Int((entry.fraction * 100).rounded()))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("展示统计：按 StressEngine 日级压力四档划分。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var dailyListCard: some View {
        card("日列表") {
            let rows = rangedScores
                .sorted { $0.date > $1.date }
                .prefix(60)
            // 原先每行都对 118 天 metrics 做一次线性 first(where:)，
            // 60 行 × 118 天在每次 body 求值里重复执行。这里一次建索引。
            let metricsByKey = Dictionary(
                metrics.map { ($0.dayKey, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            if rows.isEmpty {
                emptyHint
            } else {
                ForEach(Array(rows)) { score in
                    if let metric = metricsByKey[score.dayKey] {
                        NavigationLink {
                            TrendDayDetailView(score: score, metrics: metric)
                        } label: {
                            dayRow(score, metric: metric)
                        }
                        .buttonStyle(.plain)
                    } else {
                        dayRow(score, metric: nil)
                    }
                }
            }
        }
    }

    private func dayRow(_ score: DailyScore, metric: DailyMetrics?) -> some View {
        HStack(spacing: 10) {
            Text(score.date.formatted(.dateTime.month(.defaultDigits).day().weekday(.abbreviated)))
                .font(.caption.monospacedDigit())
                .frame(width: 76, alignment: .leading)
            if let readiness = score.readiness {
                Text("\(Int(readiness.rounded()))")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.green)
            }
            if let stress = score.stress {
                let level = StressEngine.level(for: stress, config: ScoringConfig())
                Text("\(Int(stress.rounded())) · \(level.label)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(level.tint)
            }
            Spacer()
            Text(metric?.sleepTotalH.map { String(format: "%.1fh", $0) } ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    private func legendChip(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func weekdayStrip(points: [(date: Date, value: Double)], color: Color) -> some View {
        let averages = TrendAggregates.weekdayAverages(points: points, calendar: .current)
        return VStack(alignment: .leading, spacing: 4) {
            Chart(averages) { entry in
                BarMark(
                    x: .value("星期", weekdaySymbol(entry.weekday)),
                    y: .value("均值", entry.average ?? 0)
                )
                .foregroundStyle(color.opacity(entry.average == nil ? 0.12 : 0.55))
                .cornerRadius(3)
            }
            .frame(height: 70)
            Text("星期均值（展示统计，非评分基线）")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        let symbols = ["天", "一", "二", "三", "四", "五", "六"]
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
    }

    private var hrvChart: some View {
        card("HRV（ms）") {
            if rangedMetrics.contains(where: { $0.hrvSDNN != nil }) {
                Chart(rangedMetrics) { metric in
                    if let hrv = metric.hrvSDNN {
                        LineMark(
                            x: .value("日期", metric.date, unit: .day),
                            y: .value("HRV", hrv)
                        )
                        .foregroundStyle(.pink)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 160)
                weekdayStrip(
                    points: rangedMetrics.compactMap { metric in
                        metric.hrvSDNN.map { (metric.date, $0) }
                    },
                    color: .pink
                )
            } else {
                emptyHint
            }
        }
    }

    private var restingHRChart: some View {
        card("静息心率（次/分）") {
            if rangedMetrics.contains(where: { $0.restingHR != nil }) {
                Chart(rangedMetrics) { metric in
                    if let restingHR = metric.restingHR {
                        LineMark(
                            x: .value("日期", metric.date, unit: .day),
                            y: .value("静息心率", restingHR)
                        )
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 160)
                weekdayStrip(
                    points: rangedMetrics.compactMap { metric in
                        metric.restingHR.map { (metric.date, $0) }
                    },
                    color: .blue
                )
            } else {
                emptyHint
            }
        }
    }

    private var sleepChart: some View {
        card("睡眠分期（小时）") {
            let segments = sleepSegments
            if !segments.isEmpty {
                Chart(segments) { segment in
                    BarMark(
                        x: .value("日期", segment.date, unit: .day),
                        y: .value("小时", segment.hours)
                    )
                    .foregroundStyle(by: .value("分期", segment.kind))
                }
                .chartForegroundStyleScale([
                    "深睡": Color.indigo,
                    "REM": Color.purple,
                    "核心": Color.teal,
                ])
                .frame(height: 180)
            } else {
                emptyHint
            }
        }
    }

    private var moreMetricChart: some View {
        card(moreMetric.chartTitle) {
            if moreMetric == .bloodPressure {
                if rangedMetrics.contains(where: { $0.systolicBP != nil || $0.diastolicBP != nil }) {
                    Chart {
                        ForEach(rangedMetrics) { metric in
                            if let systolic = metric.systolicBP {
                                LineMark(
                                    x: .value("日期", metric.date, unit: .day),
                                    y: .value("收缩压", systolic)
                                )
                                .foregroundStyle(by: .value("类型", "收缩压"))
                                .interpolationMethod(.catmullRom)
                            }
                            if let diastolic = metric.diastolicBP {
                                LineMark(
                                    x: .value("日期", metric.date, unit: .day),
                                    y: .value("舒张压", diastolic)
                                )
                                .foregroundStyle(by: .value("类型", "舒张压"))
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    .chartForegroundStyleScale(["收缩压": Color.red, "舒张压": Color.blue])
                    .frame(height: 180)
                } else {
                    emptyHint
                }
            } else if rangedMetrics.contains(where: { moreMetric.value($0) != nil }) {
                Chart(rangedMetrics) { metric in
                    if let value = moreMetric.value(metric) {
                        LineMark(
                            x: .value("日期", metric.date, unit: .day),
                            y: .value(moreMetric.title, value)
                        )
                        .foregroundStyle(moreMetric.color)
                        .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 180)
            } else {
                emptyHint
            }
        }
    }

    private var emptyHint: some View {
        Text("暂无数据")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80)
    }

    private var sleepSegments: [SleepSegment] {
        rangedMetrics.flatMap { metric -> [SleepSegment] in
            var segments: [SleepSegment] = []
            if let deep = metric.deepH, deep > 0 {
                segments.append(SleepSegment(id: "\(metric.dayKey)-deep", date: metric.date, kind: "深睡", hours: deep))
            }
            if let rem = metric.remH, rem > 0 {
                segments.append(SleepSegment(id: "\(metric.dayKey)-rem", date: metric.date, kind: "REM", hours: rem))
            }
            if let core = metric.coreH, core > 0 {
                segments.append(SleepSegment(id: "\(metric.dayKey)-core", date: metric.date, kind: "核心", hours: core))
            }
            return segments
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .appCard()
        .cardScrollEffect()
    }
}

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7
    case month = 30
    case year = 365

    var id: Int { rawValue }
    var days: Int { rawValue }

    var title: String {
        switch self {
        case .week: return "7 天"
        case .month: return "30 天"
        case .year: return "1 年"
        }
    }
}

struct SleepSegment: Identifiable {
    let id: String
    let date: Date
    let kind: String
    let hours: Double
}

enum MoreMetric: String, CaseIterable, Identifiable {
    case weight
    case bodyFat
    case vo2Max
    case walkingSpeed
    case steadiness
    case daylight
    case mindful
    case sleepMidpoint
    case bloodPressure
    case glucose

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weight: return "体重"
        case .bodyFat: return "体脂率"
        case .vo2Max: return "VO2max"
        case .walkingSpeed: return "步行速度"
        case .steadiness: return "步行稳定性"
        case .daylight: return "日照"
        case .mindful: return "正念"
        case .sleepMidpoint: return "睡眠中点"
        case .bloodPressure: return "血压"
        case .glucose: return "血糖"
        }
    }

    var chartTitle: String {
        switch self {
        case .weight: return "体重（kg）"
        case .bodyFat: return "体脂率（%）"
        case .vo2Max: return "VO2max（ml/kg/min）"
        case .walkingSpeed: return "步行速度（km/h）"
        case .steadiness: return "步行稳定性（%）"
        case .daylight: return "日照（分钟）"
        case .mindful: return "正念（分钟）"
        case .sleepMidpoint: return "睡眠中点（时）"
        case .bloodPressure: return "血压（mmHg）"
        case .glucose: return "血糖（mg/dL）"
        }
    }

    var color: Color {
        switch self {
        case .weight: return .purple
        case .bodyFat: return .pink
        case .vo2Max: return .blue
        case .walkingSpeed: return .teal
        case .steadiness: return .green
        case .daylight: return .orange
        case .mindful: return .indigo
        case .sleepMidpoint: return .gray
        case .bloodPressure: return .red
        case .glucose: return .brown
        }
    }

    func value(_ metric: DailyMetrics) -> Double? {
        switch self {
        case .weight: return metric.bodyMassKg
        case .bodyFat: return metric.bodyFatPct
        case .vo2Max: return metric.vo2Max
        case .walkingSpeed: return metric.walkingSpeedMps.map { $0 * 3.6 }
        case .steadiness: return metric.walkingSteadinessPct
        case .daylight: return metric.daylightMinutes
        case .mindful: return metric.mindfulMinutes
        case .sleepMidpoint: return metric.sleepMidpointMinutes.map { $0 / 60 }
        case .bloodPressure: return nil
        case .glucose: return metric.bloodGlucoseMgDl
        }
    }
}

/// 「如何理解压力趋势？」横幅点开后的说明页。
private struct StressTrendGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guideCard(
                        "压力分怎么来",
                        "每日压力分（0–100）由 HRV（38%）、静息心率（15%）、睡眠（12%）、生命体征（10%）、作息规律（13%）与心情记录（12%）加权得出；缺失的分量按剩余权重归一化。分数越高表示压力越大。"
                    )
                    guideCard(
                        "四档颜色的含义",
                        "低 < 30 · 中低 30–50 · 偏高 50–70 · 高 > 70。每日压力等级柱形按这四档着色，用于快速识别连续偏高或偏低的时段。"
                    )
                    guideCard(
                        "两条曲线怎么看",
                        "身体状态分与压力分通常方向相反：状态下降、压力抬升常出现在睡眠不足或恢复不佳之后。单日波动可能是测量噪声，建议观察 7 天以上的走向，而不是某一天的绝对值。"
                    )
                    guideCard(
                        "当日尚未结束时",
                        "睡眠时段不会累积饮水、饮食、步数、运动、日照等数据。这些累计型指标按实际清醒 / 日光窗口的阶段目标评估，清晨的低数值不代表全天不足；建议看剩余时段还能做什么。"
                    )
                    VStack(alignment: .leading, spacing: 10) {
                        AppSectionHeader(title: "常见问题", icon: "questionmark.circle.fill", tint: .blue)
                        FAQListView(topic: .stress)
                    }
                    .appCard()
                }
                .padding(16)
            }
            .background(AppScreenBackground(tone: .white))
            .navigationTitle("如何理解压力趋势")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func guideCard(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }
}

#Preview {
    let container = try! ModelContainer(
        for: DailyMetrics.self, DailyScore.self, DailyReport.self, ChatSession.self, ActionCheckIn.self, MoodEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return TrendsView()
        .modelContainer(container)
}
