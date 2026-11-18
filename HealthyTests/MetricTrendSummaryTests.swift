import Foundation
import Testing

struct MetricTrendSummaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)) ?? .now
    }

    private func snapshot(offset: Int, value: Double?) -> DailySnapshot {
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return DailySnapshot(
            dayKey: DayKey.key(for: date, calendar: calendar),
            date: date,
            restingHR: value
        )
    }

    @Test func deltaComparesTodayAgainstPriorWeek() {
        let history = (1...7).map { snapshot(offset: -$0, value: 60) }
        let summary = MetricTrendSummary.make(
            history: history,
            today: snapshot(offset: 0, value: 67),
            calendar: calendar
        ) { $0.restingHR }
        #expect(summary.latest == 67)
        #expect(summary.recentAverage == 60)
        #expect(summary.delta == 7)
    }

    @Test func averageWindowExcludesOlderDays() {
        let history = (1...10).map { snapshot(offset: -$0, value: $0 <= 7 ? 60 : 100) }
        let summary = MetricTrendSummary.make(
            history: history,
            today: snapshot(offset: 0, value: 67),
            calendar: calendar
        ) { $0.restingHR }
        #expect(summary.recentAverage == 60)
    }

    @Test func missingTodayValueLeavesDeltaNil() {
        let history = (1...7).map { snapshot(offset: -$0, value: 60) }
        let summary = MetricTrendSummary.make(
            history: history,
            today: snapshot(offset: 0, value: nil),
            calendar: calendar
        ) { $0.restingHR }
        #expect(summary.latest == nil)
        #expect(summary.recentAverage == 60)
        #expect(summary.delta == nil)
    }

    @Test func emptyHistoryLeavesAverageNil() {
        let summary = MetricTrendSummary.make(
            history: [],
            today: snapshot(offset: 0, value: 60),
            calendar: calendar
        ) { $0.restingHR }
        #expect(summary.latest == 60)
        #expect(summary.recentAverage == nil)
        #expect(summary.delta == nil)
        #expect(summary.series.count == 1)
    }

    @Test func seriesIsSortedAndWindowed() {
        let history = (1...20).map { snapshot(offset: -$0, value: 50) }
        let summary = MetricTrendSummary.make(
            history: history,
            today: snapshot(offset: 0, value: 60),
            calendar: calendar
        ) { $0.restingHR }
        #expect(summary.series.count == 14)
        #expect(summary.series.map(\.date) == summary.series.map(\.date).sorted())
        let start = calendar.date(byAdding: .day, value: -13, to: calendar.startOfDay(for: now)) ?? now
        #expect(summary.series.first?.date == start)
        #expect(summary.series.last?.value == 60)
    }

    @Test func sixtyDayAverageUsesWindowParameter() {
        var history = [snapshot(offset: -61, value: 100)]
        history += (1...60).map { snapshot(offset: -$0, value: 60) }
        let summary = MetricTrendSummary.make(
            history: history,
            today: snapshot(offset: 0, value: 60),
            calendar: calendar,
            averageWindowDays: 60
        ) { $0.restingHR }
        #expect(summary.recentAverage == 60)
    }
}

// configured by qoder