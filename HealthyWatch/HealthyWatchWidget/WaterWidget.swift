import SwiftUI
import WidgetKit

/// 纯动作小组件：只提供「点按记录一杯水」的入口，不展示今日饮水量。
/// 手机端打卡进度无法可靠同步到手表小组件（App Group 只在同一台设备内共享，
/// watchOS 的 HealthKit 库也不镜像 iPhone 上的数据），显示一个永远滞后的数字会误导用户。
struct WaterEntry: TimelineEntry {
    let date: Date
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry {
        WaterEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(WaterEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        // 视图内容是静态文案，无需按时间重载；记录动作由 AppIntent 直接写 HealthKit。
        completion(Timeline(entries: [WaterEntry(date: .now)], policy: .never))
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntry

    var body: some View {
        Button(intent: LogWaterIntent()) {
            content
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: "drop.fill")
                    .font(.body)
                    .widgetAccentable()
                Text("+\(Int(WaterShared.cupMl))")
                    .font(.caption2.weight(.semibold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        case .accessoryInline:
            Label("喝水 +\(Int(WaterShared.cupMl)) ml", systemImage: "drop.fill")
        default: // accessoryRectangular 及其他
            HStack(spacing: 8) {
                Image(systemName: "drop.fill")
                    .font(.title3)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 2) {
                    Text("喝水")
                        .font(.headline)
                    Text("点按记录 \(Int(WaterShared.cupMl)) ml")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

@main
struct HealthyWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WaterQuickWidget()
    }
}

struct WaterQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WaterShared.widgetKind, provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("喝水")
        .description("点一下记录一杯水（300 ml）")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline,
        ])
    }
}
