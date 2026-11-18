import Charts
import SwiftUI

struct SleepVitalsTrendView: View {
    let snapshots: [DailySnapshot]
    let endDate: Date

    enum Metric: String, CaseIterable, Identifiable {
        case heartRate = "心率"
        case hrv = "HRV"
        case resp = "呼吸"
        case spo2 = "血氧"
        case temp = "腕温"

        var id: String { rawValue }

        func value(from snapshot: DailySnapshot) -> Double? {
            switch self {
            case .heartRate: return snapshot.sleepAvgHR
            case .hrv: return snapshot.sleepAvgHRV
            case .resp: return snapshot.sleepAvgResp
            case .spo2: return ScoreSupport.spo2Percent(snapshot.sleepAvgSpo2)
            case .temp: return snapshot.wristTempC
            }
        }

        var unit: String {
            switch self {
            case .heartRate, .resp: return " 次/分"
            case .hrv: return " ms"
            case .spo2: return "%"
            case .temp: return "℃"
            }
        }
    }

    @State private var metric: Metric = .heartRate
    @State private var selectedDate: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Point: Identifiable, Equatable {
        var id: Date { date }
        var date: Date
        var value: Double
    }

    private var points: [Point] {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: endDate)
        let start = DayKey.addingDays(-13, to: end)
        return snapshots
            .filter { calendar.startOfDay(for: $0.date) >= start && calendar.startOfDay(for: $0.date) <= end }
            .compactMap { snapshot in
                metric.value(from: snapshot).map {
                    Point(date: calendar.startOfDay(for: snapshot.date), value: $0)
                }
            }
            .sorted { $0.date < $1.date }
    }

    private var selectedPoint: Point? {
        guard let selectedDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "近 14 天睡眠体征", icon: "waveform.path", tint: .teal)
            Picker("指标", selection: $metric.animation(reduceMotion ? nil : .snappy)) {
                ForEach(Metric.allCases) { metric in
                    Text(metric.rawValue).tag(metric)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            if points.count < 2 {
                Text("睡眠窗口体征数据不足（需要佩戴手表并同步）。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(points) { point in
                        LineMark(
                            x: .value("日期", point.date),
                            y: .value(metric.rawValue, point.value)
                        )
                        .foregroundStyle(Color.teal.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("日期", point.date),
                            y: .value(metric.rawValue, point.value)
                        )
                        .foregroundStyle(Color.teal)
                        .symbolSize(28)
                    }
                    if let selectedPoint {
                        RuleMark(x: .value("选中", selectedPoint.date))
                            .foregroundStyle(Color.teal.opacity(0.3))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 3)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                    }
                }
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
                                    lines: [
                                        selectedPoint.date.formatted(.dateTime.month().day().weekday(.short)),
                                        String(format: "%.1f%@", selectedPoint.value, metric.unit),
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
            Text("睡眠窗口内均值（腕温为当日均值）；仅展示，不参与评分。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }
}

// configured by qoder