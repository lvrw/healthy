import Charts
import SwiftUI

struct RestingHRIntradayChart: View {
    let buckets: [IntradayBucket]
    let sleepWindow: DateInterval?
    let mean60d: Double?

    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct HRPoint: Identifiable {
        var id: Date { date }
        var date: Date
        var heartRate: Double
    }

    private var points: [HRPoint] {
        buckets.compactMap { bucket in
            bucket.heartRate.map {
                HRPoint(date: bucket.start.addingTimeInterval(TimeInterval(bucket.minutes * 30)), heartRate: $0)
            }
        }
    }

    private var selectedPoint: HRPoint? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.heartRate)
        if let mean60d {
            values.append(mean60d)
        }
        let lower = (values.min() ?? 40) - 8
        let upper = (values.max() ?? 100) + 8
        return lower...upper
    }

    var body: some View {
        if points.isEmpty {
            Text("今天还没有心率数据。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .center)
        } else {
            Chart {
                if let sleepWindow {
                    RectangleMark(
                        xStart: .value("入睡", sleepWindow.start),
                        xEnd: .value("起床", sleepWindow.end)
                    )
                    .foregroundStyle(.purple.opacity(0.12))
                }
                ForEach(points) { point in
                    AreaMark(
                        x: .value("时间", point.date),
                        y: .value("心率", point.heartRate)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.orange.opacity(0.25), .orange.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("时间", point.date),
                        y: .value("心率", point.heartRate)
                    )
                    .foregroundStyle(.orange.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.catmullRom)
                }
                if let mean60d {
                    RuleMark(y: .value("60 天均值", mean60d))
                        .foregroundStyle(.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                if let selectedPoint {
                    RuleMark(x: .value("选中", selectedPoint.date))
                        .foregroundStyle(.orange.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(
                        x: .value("时间", selectedPoint.date),
                        y: .value("心率", selectedPoint.heartRate)
                    )
                    .foregroundStyle(.orange)
                    .symbolSize(80)
                }
            }
            .chartYScale(domain: yDomain)
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
                                                selectedDate = date
                                            }
                                        }
                                    }
                            )
                        if let sleepWindow,
                           let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: sleepWindow.start.addingTimeInterval(sleepWindow.duration / 2)),
                           x >= 0, x <= geometry[plotFrame].width {
                            Label("睡眠", systemImage: "bed.double.fill")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.purple)
                                .position(
                                    x: geometry[plotFrame].origin.x + x,
                                    y: geometry[plotFrame].origin.y + 10
                                )
                        }
                        if let selectedPoint,
                           let plotFrame = proxy.plotFrame,
                           let x = proxy.position(forX: selectedPoint.date),
                           let y = proxy.position(forY: selectedPoint.heartRate) {
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
            Text("按小时平均心率估算；紫色为睡眠时段，虚线为近 60 天静息心率均值（展示统计，非评分基线）。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func calloutLines(_ point: HRPoint) -> [String] {
        var lines = [
            point.date.formatted(date: .omitted, time: .shortened),
            "心率 \(Int(point.heartRate.rounded())) 次/分",
        ]
        if let sleepWindow, sleepWindow.contains(point.date) {
            lines.append("睡眠时段")
        }
        return lines
    }
}

// configured by qoder