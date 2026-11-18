import Charts
import SwiftUI

struct AutonomicSummaryCard: View {
    let hrv: MetricTrendSummary
    let restingHR: MetricTrendSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AppSectionHeader(title: "自主神经概览", icon: "waveform.path.ecg", tint: .pink)
            HStack(alignment: .top, spacing: 0) {
                metricColumn(
                    title: "今日平均 HRV",
                    summary: hrv,
                    unit: "ms",
                    tint: .pink,
                    higherIsBetter: true
                )
                Divider()
                    .frame(height: 96)
                    .padding(.horizontal, 12)
                metricColumn(
                    title: "静息心率",
                    summary: restingHR,
                    unit: "次/分",
                    tint: .orange,
                    higherIsBetter: false
                )
            }
        }
        .appCard()
    }

    private func metricColumn(
        title: String,
        summary: MetricTrendSummary,
        unit: String,
        tint: Color,
        higherIsBetter: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(summary.latest.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(AppType.display(22))
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            sparkline(summary.series, tint: tint)
                .frame(height: 30)
            deltaRow(summary.delta, higherIsBetter: higherIsBetter)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sparkline(_ points: [MetricTrendSummary.Point], tint: Color) -> some View {
        if points.count >= 2 {
            Chart {
                ForEach(points) { point in
                    LineMark(
                        x: .value("日期", point.date),
                        y: .value("数值", point.value)
                    )
                    .foregroundStyle(tint.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                    .interpolationMethod(.catmullRom)
                }
                if let last = points.last {
                    PointMark(
                        x: .value("日期", last.date),
                        y: .value("数值", last.value)
                    )
                    .foregroundStyle(tint)
                    .symbolSize(30)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.04))
        }
    }

    private func deltaRow(_ delta: Double?, higherIsBetter: Bool) -> some View {
        Group {
            if let delta {
                let rounded = Int(delta.rounded())
                let isGood = higherIsBetter ? delta >= 0 : delta <= 0
                HStack(spacing: 3) {
                    Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .bold))
                    Text("vs 近7天 \(rounded >= 0 ? "+" : "")\(rounded)")
                        .font(.caption2.weight(.medium))
                        .contentTransition(.numericText())
                }
                .foregroundStyle(isGood ? Color.green : Color.red)
            } else {
                Text("近 7 天均值 —")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// configured by qoder