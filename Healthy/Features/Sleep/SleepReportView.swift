import SwiftUI

struct SleepReportView: View {
    let metrics: [DailyMetrics]

    enum Mode: String, CaseIterable, Identifiable {
        case day = "天"
        case week = "周"
        case month = "月"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .day
    @State private var anchor: Date = .now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { .current }
    private var snapshots: [DailySnapshot] { metrics.map(\.snapshot) }
    private var anchorKey: String { DayKey.key(for: anchor, calendar: calendar) }
    private var isAtToday: Bool {
        calendar.startOfDay(for: anchor) >= calendar.startOfDay(for: .now)
    }

    private var daySnapshot: DailySnapshot? {
        snapshots.first { $0.dayKey == anchorKey }
    }

    private var historyBeforeAnchor: [DailySnapshot] {
        snapshots.filter { $0.dayKey < anchorKey }
    }

    private var periodInterval: DateInterval? {
        switch mode {
        case .day: return nil
        case .week: return SleepTrendAggregates.weekInterval(containing: anchor, calendar: calendar)
        case .month: return calendar.dateInterval(of: .month, for: anchor)
        }
    }

    private var navigationLabel: String {
        switch mode {
        case .day:
            return anchor.formatted(.dateTime.month(.wide).day().weekday(.wide))
        case .week:
            guard let interval = periodInterval else { return "" }
            let end = interval.end.addingTimeInterval(-24 * 3600)
            return "\(interval.start.formatted(.dateTime.month().day())) – \(end.formatted(.dateTime.month().day()))"
        case .month:
            return anchor.formatted(.dateTime.year().month(.wide))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("范围", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Button {
                        shift(-1)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    Spacer()
                    Text(navigationLabel)
                        .font(.subheadline.weight(.semibold))
                        .contentTransition(.opacity)
                    Spacer()
                    Button {
                        shift(1)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                    }
                    .disabled(isAtToday)
                }
                .padding(.horizontal, 4)

                Group {
                    switch mode {
                    case .day:
                        if let daySnapshot {
                            SleepDayView(snapshot: daySnapshot, history: historyBeforeAnchor)
                        } else {
                            emptyDay
                        }
                    case .week, .month:
                        if let interval = periodInterval {
                            SleepPeriodView(
                                interval: interval,
                                mode: mode,
                                snapshots: snapshots
                            )
                        }
                    }
                }
                .transition(.opacity)

                VStack(alignment: .leading, spacing: 12) {
                    AppSectionHeader(title: "睡眠小知识", icon: "questionmark.circle.fill", tint: .indigo)
                    FAQListView(topic: .sleep)
                }
                .appCard()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppScreenBackground(tone: .lavender))
        .navigationTitle("睡眠报告")
        .navigationBarTitleDisplayMode(.inline)
        .animation(reduceMotion ? nil : .snappy, value: mode)
        .animation(reduceMotion ? nil : .snappy, value: anchor)
    }

    private var emptyDay: some View {
        VStack(spacing: 8) {
            Image(systemName: "moon.zzz")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("这一天没有睡眠数据")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("佩戴手表入睡后会自动记录。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .appCard()
    }

    private func shift(_ direction: Int) {
        let next: Date
        switch mode {
        case .day:
            next = DayKey.addingDays(direction, to: anchor, calendar: calendar)
        case .week:
            next = DayKey.addingDays(7 * direction, to: anchor, calendar: calendar)
        case .month:
            next = calendar.date(byAdding: .month, value: direction, to: anchor) ?? anchor
        }
        anchor = min(next, .now)
    }
}

// configured by qoder