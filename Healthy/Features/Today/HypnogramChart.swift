import Charts
import SwiftUI

struct HypnogramChart: View {
    let intervals: [SleepStageInterval]
    var showAxes: Bool = true
    var interactive: Bool = true

    @State private var selectedStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var visible: [SleepStageInterval] {
        intervals.filter { $0.stage != .inBed && $0.end > $0.start }
    }

    private var selectedInterval: SleepStageInterval? {
        guard let selectedStart else { return nil }
        return visible.first { $0.start == selectedStart }
    }

    private func level(_ stage: SleepStageKind) -> Double {
        switch stage {
        case .deep: return 0
        case .core: return 1
        case .rem: return 2
        case .awake: return 3
        case .inBed: return -1
        }
    }

    static func color(_ stage: SleepStageKind) -> Color {
        switch stage {
        case .deep: return .indigo
        case .core: return .blue
        case .rem: return .purple
        case .awake: return .orange
        case .inBed: return .gray
        }
    }

    static func label(_ stage: SleepStageKind) -> String {
        switch stage {
        case .deep: return "深睡"
        case .core: return "核心"
        case .rem: return "REM"
        case .awake: return "清醒"
        case .inBed: return "卧床"
        }
    }

    var body: some View {
        if visible.isEmpty {
            Text("无分期数据（需要佩戴手表入睡）。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: showAxes ? 80 : 44, alignment: .center)
        } else {
            Chart(visible, id: \.start) { interval in
                RectangleMark(
                    xStart: .value("开始", interval.start),
                    xEnd: .value("结束", interval.end),
                    yStart: .value("低", level(interval.stage) - 0.38),
                    yEnd: .value("高", level(interval.stage) + 0.38)
                )
                .foregroundStyle(Self.color(interval.stage).opacity(0.85))
                .opacity(selectedStart == nil || selectedStart == interval.start ? 1 : 0.45)
            }
            .chartYScale(domain: -0.7...3.7)
            .chartXScale(domain: (visible.first?.start ?? .now)...(visible.last?.end ?? .now))
            .chartYAxis {
                if showAxes {
                    AxisMarks(values: [0, 1, 2, 3]) { value in
                        AxisValueLabel {
                            if let level = value.as(Double.self) {
                                Text(Self.label(stage(forLevel: level)))
                                    .font(.caption2)
                            }
                        }
                    }
                }
            }
            .chartXAxis {
                if showAxes {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour().minute())
                    }
                }
            }
            .frame(height: showAxes ? 150 : 44)
            .chartOverlay { proxy in
                if interactive {
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
                                            if let date = proxy.value(atX: x, as: Date.self),
                                               let hit = visible.first(where: { $0.start <= date && date <= $0.end }) {
                                                withAnimation(reduceMotion ? nil : .snappy) {
                                                    selectedStart = selectedStart == hit.start ? nil : hit.start
                                                }
                                            }
                                        }
                                )
                            if let selectedInterval,
                               let plotFrame = proxy.plotFrame,
                               let x = proxy.position(forX: selectedInterval.start.addingTimeInterval(selectedInterval.end.timeIntervalSince(selectedInterval.start) / 2)),
                               let y = proxy.position(forY: level(selectedInterval.stage)) {
                                ChartCalloutOverlay(
                                    lines: calloutLines(selectedInterval),
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
    }

    private func stage(forLevel level: Double) -> SleepStageKind {
        switch Int(level.rounded()) {
        case 0: return .deep
        case 1: return .core
        case 2: return .rem
        default: return .awake
        }
    }

    private func calloutLines(_ interval: SleepStageInterval) -> [String] {
        let minutes = interval.end.timeIntervalSince(interval.start) / 60
        return [
            Self.label(interval.stage),
            "\(interval.start.formatted(date: .omitted, time: .shortened)) – \(interval.end.formatted(date: .omitted, time: .shortened))",
            String(format: "%.0f 分钟", minutes),
        ]
    }
}

// configured by qoder