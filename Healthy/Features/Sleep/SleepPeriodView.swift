import Charts
import SwiftUI

struct SleepPeriodView: View {
    let interval: DateInterval
    let mode: SleepReportView.Mode
    let snapshots: [DailySnapshot]

    enum ChartMetric: String, CaseIterable, Identifiable {
        case duration = "时长"
        case quality = "质量"
        var id: String { rawValue }
    }

    @State private var chartMetric: ChartMetric = .duration
    @State private var selectedKey: String?

    private var calendar: Calendar { .current }
    private var isMonth: Bool { mode == .month }

    private var days: [Date] {
        let today = calendar.startOfDay(for: .now)
        var result: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end && cursor <= today {
            result.append(cursor)
            cursor = DayKey.addingDays(1, to: cursor)
        }
        return result
    }

    private var summaries: [SleepDaySummary] {
        days.map { day in
            let key = DayKey.key(for: day, calendar: calendar)
            let snapshot = snapshots.first { $0.dayKey == key } ?? DailySnapshot(dayKey: key, date: day)
            let history = snapshots.filter { $0.dayKey < key }
            let threshold = SleepTrendAggregates.lateThreshold(history: history, today: snapshot, calendar: calendar)
            return SleepTrendAggregates.daySummary(snapshot, lateThresholdMinutes: threshold)
        }
    }

    private var stats: SleepPeriodStats {
        SleepTrendAggregates.periodStats(summaries)
    }

    private var streak: Int {
        SleepTrendAggregates.streak(summaries, calendar: calendar)
    }

    private var selectedSummary: SleepDaySummary? {
        guard let selectedKey else { return nil }
        return summaries.first { $0.dayKey == selectedKey }
    }

    private var barValue: (SleepDaySummary) -> Double? {
        switch chartMetric {
        case .duration: return { $0.totalH }
        case .quality: return { $0.qualityScore }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            statsCard
            chartCard
            calendarCard
            SleepVitalsTrendView(
                snapshots: snapshots,
                endDate: min(
                    interval.end.addingTimeInterval(-24 * 3600),
                    calendar.startOfDay(for: .now)
                )
            )
        }
    }

    private var statsCard: some View {
        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: isMonth ? "本月概览" : "本周概览", icon: "calendar.badge.clock", tint: .indigo)
            LazyVGrid(columns: columns, spacing: 10) {
                statTile("平均时长", stats.averageTotalH.map { String(format: "%.1f h", $0) } ?? "—")
                statTile("平均质量", stats.averageQuality.map { "\(Int($0.rounded())) 分" } ?? "—")
                statTile("规律性", stats.midpointSD.map { String(format: "±%.0f 分", $0) } ?? "—")
                statTile("连续记录", "\(streak) 天")
                statTile("有效占比", "\(Int((stats.validRatio * 100).rounded()))%")
                statTile("晚睡", "\(stats.lateCount) 天")
            }
            Text("质量 = 效率 + 恢复性展示合成；晚睡按各日前 28 天中位数 + 60 分钟判定，均为展示口径。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func statTile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "每日\(chartMetric.rawValue)", icon: "chart.bar.fill", tint: .indigo)
            Picker("图表", selection: $chartMetric) {
                ForEach(ChartMetric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            let bars = summaries.compactMap { summary -> (SleepDaySummary, Double)? in
                barValue(summary).map { (summary, $0) }
            }
            if bars.isEmpty {
                Text("这段时间还没有睡眠记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(bars, id: \.0.dayKey) { summary, value in
                        BarMark(
                            x: .value("日期", summary.date, unit: .day),
                            y: .value(chartMetric.rawValue, value)
                        )
                        .foregroundStyle(chartMetric == .duration
                            ? Color.indigo.opacity(summary.dayKey == selectedKey ? 1 : 0.7)
                            : Color.purple.opacity(summary.dayKey == selectedKey ? 1 : 0.7))
                        .cornerRadius(3)
                    }
                    if let selectedSummary, let value = barValue(selectedSummary) {
                        BarMark(
                            x: .value("日期", selectedSummary.date, unit: .day),
                            y: .value(chartMetric.rawValue, value)
                        )
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(3)
                    }
                    RuleMark(y: .value("参考", chartMetric == .duration ? 7.5 : 80))
                        .foregroundStyle(Color.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYScale(domain: chartMetric == .duration ? 0...10 : 0...100)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: isMonth ? 5 : 1)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day(), centered: true)
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
                                                let key = DayKey.key(for: date, calendar: calendar)
                                                withAnimation {
                                                    selectedKey = selectedKey == key ? nil : key
                                                }
                                            }
                                        }
                                )
                            if let selectedSummary,
                               let value = barValue(selectedSummary),
                               let plotFrame = proxy.plotFrame,
                               let x = proxy.position(forX: selectedSummary.date),
                               let y = proxy.position(forY: value) {
                                ChartCalloutOverlay(
                                    lines: [
                                        selectedSummary.date.formatted(.dateTime.month().day().weekday(.short)),
                                        chartMetric == .duration
                                            ? String(format: "%.1f 小时", value)
                                            : "\(Int(value.rounded())) 分",
                                    ],
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
        .appCard()
    }

    private var calendarCard: some View {
        let firstWeekday = calendar.firstWeekday
        let startWeekday = calendar.component(.weekday, from: interval.start)
        let blanks = (startWeekday - firstWeekday + 7) % 7
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        return VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "晚睡日历", icon: "moon.stars.fill", tint: .orange)
            LazyVGrid(columns: columns, spacing: 6) {
                if isMonth {
                    ForEach(0..<blanks, id: \.self) { _ in
                        Color.clear.frame(height: 40)
                    }
                }
                ForEach(summaries) { summary in
                    lateCell(summary)
                }
            }
            HStack(spacing: 12) {
                legendDot(.orange, "晚睡")
                legendDot(.green, "正常")
                legendDot(.gray, "无数据")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .appCard()
    }

    private func lateCell(_ summary: SleepDaySummary) -> some View {
        let tint: Color = summary.totalH == nil
            ? .gray
            : (summary.isLateBedtime ? .orange : .green)
        return VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: summary.date))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            Circle()
                .fill(tint.opacity(summary.totalH == nil ? 0.35 : 0.85))
                .frame(width: 7, height: 7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            Color(.systemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(selectedKey == summary.dayKey ? Color.accentColor : .clear, lineWidth: 1.5)
        )
        .onTapGesture {
            withAnimation {
                selectedKey = selectedKey == summary.dayKey ? nil : summary.dayKey
            }
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
}

// configured by qoder