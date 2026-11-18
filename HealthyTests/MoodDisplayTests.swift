import Foundation
import Testing

struct MoodDisplayTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var day0: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)) ?? .now
    }

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day0) ?? day0
    }

    @Test func localEntryOverridesSameDayHealthKit() {
        let points = MoodDisplay.merge(
            healthKit: [(day(0), -0.8), (day(-1), 0.4)],
            local: [(day(0), 0.6)],
            calendar: calendar
        )
        #expect(points.count == 2)
        let today = points.first { $0.dayKey == DayKey.key(for: day(0), calendar: calendar) }
        #expect(today?.valence == 0.6)
        #expect(today?.isLocal == true)
        let yesterday = points.first { $0.dayKey == DayKey.key(for: day(-1), calendar: calendar) }
        #expect(yesterday?.valence == 0.4)
        #expect(yesterday?.isLocal == false)
    }

    @Test func daysWithNoValueFromEitherSideAreExcluded() {
        let points = MoodDisplay.merge(
            healthKit: [(day(0), nil), (day(-1), 0.2)],
            local: [(day(-3), -0.5)],
            calendar: calendar
        )
        #expect(points.map(\.dayKey) == [
            DayKey.key(for: day(-3), calendar: calendar),
            DayKey.key(for: day(-1), calendar: calendar),
        ])
    }

    @Test func resultIsSortedAscendingByDate() {
        let points = MoodDisplay.merge(
            healthKit: [(day(2), 0.1), (day(-2), 0.3)],
            local: [(day(0), -0.2)],
            calendar: calendar
        )
        #expect(points.map(\.date) == [day(-2), day(0), day(2)])
    }

    @Test func emptyInputsProduceEmptyOutput() {
        #expect(MoodDisplay.merge(healthKit: [], local: [], calendar: calendar).isEmpty)
    }
}

// configured by qoder