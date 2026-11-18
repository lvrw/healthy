import Foundation
import Testing

struct SleepTrendAggregatesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 12)) ?? .now
    }

    private func snapshot(
        offset: Int,
        totalH: Double? = 7.5,
        efficiency: Double? = 0.9,
        deepH: Double? = 1.5,
        remH: Double? = 1.8,
        bedtime: Double? = -60,
        midpoint: Double? = 180
    ) -> DailySnapshot {
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return DailySnapshot(
            dayKey: DayKey.key(for: date, calendar: calendar),
            date: date,
            sleepTotalH: totalH,
            sleepEfficiency: efficiency,
            deepH: deepH,
            remH: remH,
            sleepMidpointMinutes: midpoint,
            sleepBedtimeMinutes: bedtime
        )
    }

    @Test func qualityScoreCombinesEfficiencyAndRestorative() {
        // 0.5×90 + 0.5×90（ratio 0.405 → 展示分 90）
        #expect(SleepTrendAggregates.qualityScore(efficiency: 0.9, restorativeRatio: 0.405) == 90)
        #expect(SleepTrendAggregates.qualityScore(efficiency: 0.9, restorativeRatio: nil) == 90)
        #expect(SleepTrendAggregates.qualityScore(efficiency: nil, restorativeRatio: 0.33) == 80)
        #expect(SleepTrendAggregates.qualityScore(efficiency: nil, restorativeRatio: nil) == nil)
    }

    @Test func daySummaryFlagsLateBedtime() {
        let late = SleepTrendAggregates.daySummary(snapshot(offset: 0, bedtime: -30), lateThresholdMinutes: -60)
        #expect(late.isLateBedtime)
        #expect(late.restorativeRatio == 0.44)
        let early = SleepTrendAggregates.daySummary(snapshot(offset: 0, bedtime: -90), lateThresholdMinutes: -60)
        #expect(!early.isLateBedtime)
        let noThreshold = SleepTrendAggregates.daySummary(snapshot(offset: 0, bedtime: -30), lateThresholdMinutes: nil)
        #expect(!noThreshold.isLateBedtime)
    }

    @Test func lateThresholdUses28DayMedianPlusMargin() {
        let history = [
            snapshot(offset: -1, bedtime: -60),
            snapshot(offset: -2, bedtime: -60),
            snapshot(offset: -3, bedtime: -60),
            snapshot(offset: -4, bedtime: -30),
            snapshot(offset: -5, bedtime: -90),
        ]
        // 中位数 −60 + 60 分钟宽限 = 0
        let threshold = SleepTrendAggregates.lateThreshold(
            history: history,
            today: snapshot(offset: 0, bedtime: 120),
            calendar: calendar
        )
        #expect(threshold == 0)
    }

    @Test func lateThresholdRequiresThreeValuesAndIgnoresOldDays() {
        let short = [snapshot(offset: -1, bedtime: -60), snapshot(offset: -2, bedtime: -60)]
        #expect(SleepTrendAggregates.lateThreshold(history: short, today: snapshot(offset: 0), calendar: calendar) == nil)
        let old = [
            snapshot(offset: -40, bedtime: -60),
            snapshot(offset: -41, bedtime: -60),
            snapshot(offset: -42, bedtime: -60),
        ]
        #expect(SleepTrendAggregates.lateThreshold(history: old, today: snapshot(offset: 0), calendar: calendar) == nil)
    }

    @Test func streakCountsConsecutiveDaysEndingAtLatest() {
        let summaries = [
            SleepTrendAggregates.daySummary(snapshot(offset: -3), lateThresholdMinutes: nil),
            SleepTrendAggregates.daySummary(snapshot(offset: -1), lateThresholdMinutes: nil),
            SleepTrendAggregates.daySummary(snapshot(offset: 0), lateThresholdMinutes: nil),
        ]
        // 最新日 11-04 有数据，11-03 有，11-02 缺失 → 连续 2 天
        #expect(SleepTrendAggregates.streak(summaries, calendar: calendar) == 2)
    }

    @Test func streakIsZeroWhenLatestDayMissing() {
        let summaries = [
            SleepTrendAggregates.daySummary(snapshot(offset: -2), lateThresholdMinutes: nil),
            SleepTrendAggregates.daySummary(snapshot(offset: -1), lateThresholdMinutes: nil),
            SleepTrendAggregates.daySummary(snapshot(offset: 0, totalH: nil), lateThresholdMinutes: nil),
        ]
        #expect(SleepTrendAggregates.streak(summaries, calendar: calendar) == 0)
    }

    @Test func periodStatsAggregateAveragesAndValidity() {
        let summaries = [
            SleepTrendAggregates.daySummary(snapshot(offset: -6, totalH: 6, efficiency: 0.8, bedtime: -30), lateThresholdMinutes: -60),
            SleepTrendAggregates.daySummary(snapshot(offset: -5, totalH: 8, efficiency: 1.0, bedtime: -90), lateThresholdMinutes: -60),
            SleepTrendAggregates.daySummary(snapshot(offset: -4, totalH: nil, efficiency: nil, bedtime: nil), lateThresholdMinutes: -60),
        ]
        let stats = SleepTrendAggregates.periodStats(summaries)
        #expect(stats.averageTotalH == 7)
        #expect(stats.validRatio == 2.0 / 3.0)
        #expect(stats.lateCount == 1)
        #expect(stats.midpointSD == nil)
    }

    @Test func weekIntervalStartsOnMonday() throws {
        let interval = try #require(SleepTrendAggregates.weekInterval(containing: now, calendar: calendar))
        let start = calendar.dateComponents([.year, .month, .day], from: interval.start)
        #expect(start.month == 11)
        #expect(start.day == 2)
        #expect(interval.duration == 7 * 24 * 3600)
    }
}

// configured by qoder