import Charts
import SwiftUI

/// 卡片内可展示的区块：HRV 与压力可单独展示，避免 HRV 详情页混入压力内容（反之亦然）。
struct StressInsightSections: OptionSet {
    let rawValue: Int

    static let hrv = StressInsightSections(rawValue: 1 << 0)
    static let stress = StressInsightSections(rawValue: 1 << 1)
    static let all: StressInsightSections = [.hrv, .stress]
}

struct StressInsightsCard: View {
    let summary: IntradaySummary
    let isLoading: Bool
    let error: String?
    let onRefresh: () -> Void
    let onOpenReading: (IntradayReading) -> Void
    let onOpenAll: () -> Void
    let onInfo: () -> Void
    /// 只展示指定区块；默认两者都展示。
    var sections: StressInsightSections = .all

    @State private var selectedBucketDate: Date?
    @State private var selectedReadingDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsHRV: Bool { sections.contains(.hrv) }
    private var showsStress: Bool { sections.contains(.stress) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHRV {
                AppSectionHeader(
                    title: "今日 HRV 趋势",
                    icon: "waveform.path.ecg",
                    tint: .pink,
                    trailing: AnyView(
                        HStack(spacing: 8) {
                            if isLoading {
                                ProgressView()
                            }
                            Button {
                                onInfo()
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    )
                )
                hrvChart
                if selectedReading != nil {
                    readingSelectionPanel
                }
                legend
                latestReading
            }
            if showsHRV, showsStress {
                Divider()
            }
            if showsStress {
                AppSectionHeader(
                    title: "今日压力时间线",
                    icon: "bolt.heart.fill",
                    tint: .orange,
                    trailing: AnyView(
                        Text("选择柱形可查看当日详情")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    )
                )
                stressChart
                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            Divider()
            HStack {
                Button {
                    onRefresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                Spacer()
                if showsHRV {
                    Button("全部记录") {
                        onOpenAll()
                    }
                    .font(.subheadline)
                }
            }
        }
        .appCard()
        .sensoryFeedback(.selection, trigger: selectedBucketDate)
        .sensoryFeedback(.selection, trigger: selectedReadingDate)
    }

    @ViewBuilder
    private var hrvChart: some View {
        if summary.readings.isEmpty {
            emptyHint("今天还没有 HRV 读数。Apple Watch 会在静息和正念时记录 HRV。")
        } else {
            Chart {
                ForEach(summary.readings) { reading in
                    if let sdnn = reading.sdnn {
                        LineMark(
                            x: .value("时间", reading.date),
                            y: .value("HRV", sdnn)
                        )
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("时间", reading.date),
                            y: .value("HRV", sdnn)
                        )
                        .foregroundStyle(levelColor(reading.level))
                        .symbolSize(selectedReading?.date == reading.date ? 110 : 46)
                        .shadow(color: levelColor(reading.level).opacity(0.35), radius: 4)
                    }
                }
                ForEach(summary.readings) { reading in
                    if let rmssd = reading.rmssd {
                        LineMark(
                            x: .value("时间", reading.date),
                            y: .value("RMSSD", rmssd)
                        )
                        .foregroundStyle(.purple.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .interpolationMethod(.catmullRom)
                    }
                }
                if let baseline = summary.baselineHRVms {
                    RuleMark(y: .value("基线", baseline))
                        .foregroundStyle(.gray.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let reading = selectedReading {
                    RuleMark(x: .value("选中", reading.date))
                        .foregroundStyle(levelColor(reading.level).opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
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
                                                selectedReadingDate = date
                                            }
                                        }
                                    }
                            )
                        if let reading = selectedReading,
                           let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: reading.date),
                           let y = proxy.position(forY: reading.sdnn ?? reading.rmssd ?? 0) {
                            ChartCalloutOverlay(
                                lines: readingCalloutLines(reading),
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

    private var legend: some View {
        HStack(spacing: 8) {
            legendChip("SDNN", color: .secondary)
            if summary.readings.contains(where: { $0.rmssd != nil }) {
                legendChip("RMSSD", color: .purple)
            }
            legendChip("28 天基线", color: .gray.opacity(0.6), dashed: true)
            Spacer()
        }
    }

    private func legendChip(_ text: String, color: Color, dashed: Bool = false) -> some View {
        HStack(spacing: 4) {
            Capsule()
                .fill(color)
                .frame(width: 14, height: dashed ? 1.5 : 6)
            Text(text)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stressChart: some View {
        if summary.buckets.isEmpty {
            emptyHint("今天还没有心率数据。")
        } else {
            Chart {
                if let sleepWindow = summary.sleepWindow {
                    RectangleMark(
                        xStart: .value("入睡", sleepWindow.start),
                        xEnd: .value("起床", sleepWindow.end)
                    )
                    .foregroundStyle(.purple.opacity(0.12))
                }
                ForEach(summary.buckets) { bucket in
                    BarMark(
                        xStart: .value("开始", bucket.start),
                        xEnd: .value("结束", bucket.end),
                        y: .value("压力", barHeight(bucket))
                    )
                    .foregroundStyle(bucketColor(bucket))
                    .cornerRadius(2)
                    .opacity(selectedBucket?.start == bucket.start ? 1 : 0.88)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.hour())
                }
            }
            .frame(height: 170)
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
                                                selectedBucketDate = date
                                            }
                                        }
                                    }
                            )
                        if let bucket = selectedBucket,
                           let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: bucket.start.addingTimeInterval(TimeInterval(bucket.minutes * 30))),
                           let y = proxy.position(forY: barHeight(bucket)) {
                            ChartCalloutOverlay(
                                lines: bucketCalloutLines(bucket),
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
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    legendChip("不计入时段", color: .gray.opacity(0.3))
                    Spacer()
                }
                Text("按 15 分钟平均心率 vs 28 天日均心率估算；紫色为睡眠时段，运动、明显活动时段不计入，只留灰色矮柱。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var readingSelectionPanel: some View {
        if let reading = selectedReading {
            HStack(spacing: 10) {
                Circle()
                    .fill(levelColor(reading.level))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reading.date.formatted(date: .omitted, time: .shortened)) · \(hrvText(reading)) · \(levelText(reading.level))")
                        .font(.caption.weight(.semibold))
                    Text("偏离基线 \(reading.zScore.map { String(format: "%+.2f", $0) } ?? "—")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("详情") {
                    onOpenReading(reading)
                }
                .font(.caption)
            }
            .padding(10)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    @ViewBuilder
    private var latestReading: some View {
        if let reading = summary.latestReading {
            Button {
                onOpenReading(reading)
            } label: {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(reading.date.formatted(date: .omitted, time: .shortened))（最近一次）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(levelColor(reading.level))
                                .frame(width: 10, height: 10)
                            Text(hrvText(reading))
                                .font(AppType.display(20))
                                .contentTransition(.numericText())
                            Text(levelText(reading.level))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(levelColor(reading.level))
                        }
                        Text(explanation(reading))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            .buttonStyle(.plain)
        } else {
            emptyHint("还没有可展示的 HRV 读数。")
        }
    }

    private var selectedBucket: IntradayBucket? {
        guard let selectedBucketDate else { return nil }
        return summary.buckets.min {
            abs($0.start.addingTimeInterval(TimeInterval($0.minutes * 30)).timeIntervalSince(selectedBucketDate))
                < abs($1.start.addingTimeInterval(TimeInterval($1.minutes * 30)).timeIntervalSince(selectedBucketDate))
        }
    }

    private var selectedReading: IntradayReading? {
        guard let selectedReadingDate else { return nil }
        return summary.readings.min {
            abs($0.date.timeIntervalSince(selectedReadingDate))
                < abs($1.date.timeIntervalSince(selectedReadingDate))
        }
    }

    private func timeRange(_ bucket: IntradayBucket) -> String {
        let startText = bucket.start.formatted(date: .omitted, time: .shortened)
        let endText = bucket.end.formatted(date: .omitted, time: .shortened)
        return "\(startText)–\(endText)"
    }

    private func readingCalloutLines(_ reading: IntradayReading) -> [String] {
        var lines = [
            "\(reading.date.formatted(date: .omitted, time: .shortened)) · \(levelText(reading.level))",
            hrvText(reading),
        ]
        if let rmssd = reading.rmssd, reading.sdnn != nil {
            lines.append("RMSSD \(Int(rmssd.rounded())) ms")
        }
        return lines
    }

    private func barHeight(_ bucket: IntradayBucket) -> Double {
        bucket.stress ?? (bucket.context == .noHeartRate ? 0 : 5)
    }

    private func bucketCalloutLines(_ bucket: IntradayBucket) -> [String] {
        var lines = [timeRange(bucket)]
        switch bucket.context {
        case .workout:
            lines.append("运动时段 · 不计入压力")
        case .sleeping:
            lines.append("睡眠时段 · 不计入压力")
        case .activity:
            lines.append("明显活动 · 心率远高于日均基线")
        case .noBaseline:
            lines.append("日均心率基线积累中")
        case .noHeartRate:
            lines.append("无有效心率")
        case .normal:
            if let stress = bucket.stress {
                lines.append(
                    "压力 \(Int(stress.rounded())) · \(levelText(StressEngine.level(for: stress, config: ScoringConfig())))"
                )
            }
        }
        if let heartRate = bucket.heartRate {
            lines.append("平均心率 \(Int(heartRate.rounded())) bpm")
        }
        if let baseline = summary.baselineAverageHR {
            lines.append("日均基线 \(Int(baseline.rounded())) bpm")
        }
        return lines
    }

    private func hrvText(_ reading: IntradayReading) -> String {
        if let sdnn = reading.sdnn {
            return "\(Int(sdnn.rounded())) ms"
        }
        if let rmssd = reading.rmssd {
            return "RMSSD \(Int(rmssd.rounded())) ms"
        }
        return "—"
    }

    private func levelText(_ level: StressLevel?) -> String {
        switch level {
        case .low: return "放松"
        case .moderateLow: return "中低压力"
        case .elevated: return "压力偏高"
        case .high: return "压力过载"
        case nil: return "仅展示"
        }
    }

    private func explanation(_ reading: IntradayReading) -> String {
        guard let z = reading.zScore else {
            return "当前只有 RMSSD 读数，暂无 28 天基线，不参与压力评分。"
        }
        if z < -1 {
            return "HRV 明显低于 28 天基线，可能与疲劳、压力或睡眠不足有关；运动后短时下降属正常。"
        }
        if z > 1 {
            return "HRV 高于个人基线，恢复状态较好。"
        }
        return "HRV 接近个人基线，状态平稳。"
    }

    private func levelColor(_ level: StressLevel?) -> Color {
        switch level {
        case .low: return .teal
        case .moderateLow: return .blue
        case .elevated: return .orange
        case .high: return .red
        case nil: return .gray
        }
    }

    private func bucketColor(_ bucket: IntradayBucket) -> Color {
        guard let stress = bucket.stress, bucket.context == .normal else {
            return .gray.opacity(bucket.context == .noHeartRate ? 0.12 : 0.25)
        }
        return levelColor(StressEngine.level(for: stress, config: ScoringConfig()))
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
    }
}
