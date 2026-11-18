import Foundation
import Testing

struct TrendAggregatesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .now
    }

    @Test func weekdayAveragesGroupByWeekdaySymbol() {
        // 2026-11-02 是周一（weekday symbol = 2）
        let points: [(date: Date, value: Double)] = [
            (day(2026, 11, 2), 40),
            (day(2026, 11, 9), 60),
            (day(2026, 11, 4), 50),
        ]
        let averages = TrendAggregates.weekdayAverages(points: points, calendar: calendar)
        #expect(averages.count == 7)
        let monday = averages.first { $0.weekday == 2 }
        #expect(monday?.average == 50)
        #expect(monday?.count == 2)
        let wednesday = averages.first { $0.weekday == 4 }
        #expect(wednesday?.average == 50)
        let tuesday = averages.first { $0.weekday == 3 }
        #expect(tuesday?.average == nil)
        #expect(tuesday?.count == 0)
    }

    @Test func levelDistributionCountsUseTierBoundaries() {
        let values = [29.9, 30.0, 49.9, 50.0, 69.9, 70.0, 100.0]
        let counts = TrendAggregates.levelDistribution(stressValues: values, config: ScoringConfig())
        #expect(counts.count == 4)
        #expect(counts[0].level == .low)
        #expect(counts[0].count == 1)
        #expect(counts[1].count == 2)
        #expect(counts[2].count == 2)
        #expect(counts[3].count == 2)
        #expect(counts[3].level == .high)
        #expect(abs(counts.map(\.fraction).reduce(0, +) - 1.0) < 0.0001)
    }

    @Test func emptyDistributionKeepsFourZeroTiers() {
        let counts = TrendAggregates.levelDistribution(stressValues: [], config: ScoringConfig())
        #expect(counts.count == 4)
        #expect(counts.allSatisfy { $0.count == 0 && $0.fraction == 0 })
    }

    @Test func monthlyAveragesBucketAndSort() {
        let points: [(date: Date, value: Double)] = [
            (day(2026, 11, 30), 70),
            (day(2026, 11, 10), 50),
            (day(2026, 12, 2), 80),
            (day(2026, 9, 15), 40),
        ]
        let buckets = TrendAggregates.monthlyAverages(points: points, calendar: calendar)
        #expect(buckets.count == 3)
        #expect(buckets[0].average == 40)
        #expect(buckets[1].average == 60)
        #expect(buckets[1].count == 2)
        #expect(buckets[2].average == 80)
        #expect(buckets.map { calendar.component(.month, from: $0.monthStart) } == [9, 11, 12])
    }

    @Test func monthlyAveragesIgnoresMissingValues() {
        let points: [(date: Date, value: Double)] = [(day(2026, 11, 1), 60)]
        let buckets = TrendAggregates.monthlyAverages(points: points, calendar: calendar)
        #expect(buckets.count == 1)
        #expect(buckets[0].count == 1)
    }
}

// configured by qoder
