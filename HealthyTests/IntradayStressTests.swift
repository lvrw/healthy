import Foundation
import Testing

struct IntradayStressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12)) ?? .now
    }

    private func snapshot(
        offset: Int,
        hrv: Double = 45,
        rhr: Double = 58,
        avgHR: Double? = 78,
        bedtimeMinutes: Double? = nil,
        midpointMinutes: Double? = nil
    ) -> DailySnapshot {
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return DailySnapshot(
            dayKey: DayKey.key(for: date, calendar: calendar),
            date: date,
            hrvSDNN: hrv,
            restingHR: rhr,
            avgHR: avgHR,
            sleepMidpointMinutes: midpointMinutes,
            sleepBedtimeMinutes: bedtimeMinutes
        )
    }

    private func time(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    private func bucket(_ hour: Int, _ minute: Int = 0, average: Double) -> HeartRateBucket {
        HeartRateBucket(start: time(hour, minute), minutes: 15, average: average)
    }

    @Test func fifteenMinuteBucketsUseAverageHRBaseline() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = IntradaySignals(
            hrvPoints: [],
            heartRateBuckets: [
                bucket(10, average: 90),
                bucket(10, 15, average: 50),
            ],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        #expect(summary.buckets.count == 2)
        #expect(summary.buckets[0].start == time(10))
        #expect(summary.buckets[0].minutes == 15)
        #expect(summary.buckets[0].context == .normal)
        #expect(summary.buckets[0].stress == 77)
        #expect(summary.buckets[1].stress == 5)
        #expect(summary.baselineAverageHR == 78)
    }

    @Test func workoutOverlapMarksBucketNeutral() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let workout = WorkoutInterval(
            start: time(9, 30),
            end: time(10, 15)
        )
        let signals = IntradaySignals(
            hrvPoints: [],
            heartRateBuckets: [
                bucket(9, 30, average: 130),
                bucket(9, 45, average: 130),
                bucket(10, average: 130),
                bucket(10, 15, average: 78),
            ],
            workouts: [workout]
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        #expect(summary.buckets[0].context == .workout)
        #expect(summary.buckets[1].context == .workout)
        // 10:00–10:15 与运动区间完全重合
        #expect(summary.buckets[2].context == .workout)
        #expect(summary.buckets.allSatisfy { $0.stress == nil || $0.context == .normal })
        // 10:15 桶在运动结束之后
        #expect(summary.buckets[3].context == .normal)
        #expect(summary.buckets[3].stress == 50)
    }

    @Test func sleepBucketsUseHalfBucketOverlap() {
        // 入睡 = 前一天 23:00，中点 04:00 → 起床 = 2×240 − (−60) = 09:00
        let today = snapshot(offset: 0, bedtimeMinutes: -60, midpointMinutes: 240)
        let signals = IntradaySignals(
            hrvPoints: [],
            heartRateBuckets: [
                bucket(8, average: 55),
                bucket(8, 45, average: 55),
                bucket(9, 15, average: 78),
            ],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: today,
            history: (1...8).map { snapshot(offset: -$0) },
            signals: signals,
            calendar: calendar
        )
        #expect(summary.buckets[0].context == .sleeping)
        #expect(summary.buckets[0].heartRate == 55)
        // 08:45–09:00 整桶都在睡眠窗口内
        #expect(summary.buckets[1].context == .sleeping)
        #expect(summary.buckets[1].stress == nil)
        #expect(summary.buckets[2].context == .normal)
        #expect(summary.buckets[2].stress == 50)
    }

    @Test func activityBucketsAreExcluded() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = IntradaySignals(
            hrvPoints: [],
            heartRateBuckets: [bucket(18, average: 130)],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        #expect(summary.buckets[0].context == .activity)
        #expect(summary.buckets[0].stress == nil)
        #expect(summary.buckets[0].heartRate == 130)
    }

    @Test func missingAverageHRBaselineSuppressesBucketStress() {
        let history = (1...8).map { snapshot(offset: -$0, avgHR: nil) }
        let signals = IntradaySignals(
            hrvPoints: [],
            heartRateBuckets: [bucket(10, average: 90)],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0, avgHR: nil),
            history: history,
            signals: signals,
            calendar: calendar
        )
        #expect(summary.buckets[0].context == .noBaseline)
        #expect(summary.buckets[0].stress == nil)
        #expect(summary.baselineAverageHR == nil)
    }

    @Test func lowHRVProducesHighStress() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = IntradaySignals(
            hrvPoints: [HRVSamplePoint(date: time(9), sdnn: 25, rmssd: nil)],
            heartRateBuckets: [],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        let reading = summary.readings.first
        #expect((reading?.stress ?? 0) > 80)
        #expect(reading?.level == .high)
        #expect((summary.baselineHRVms ?? 0) > 40)
        #expect((summary.baselineHRVms ?? 0) < 50)
    }

    @Test func readingHeartRateComesFromContainingBucket() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = IntradaySignals(
            hrvPoints: [
                HRVSamplePoint(date: time(8), sdnn: 45, rmssd: 40),
                HRVSamplePoint(date: time(9), sdnn: 30, rmssd: 28),
            ],
            heartRateBuckets: [
                bucket(8, 30, average: 70),
                bucket(9, 15, average: 75),
            ],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        #expect(summary.latestReading?.date == time(9))
        #expect(summary.latestReading?.rmssd == 28)
        // 09:00 读数落在 09:00–09:15 之前一桶？9:00 < 9:15 start → 不落在 9:15 桶；8:30 桶覆盖 8:30–8:45 → 也不含 9:00
        #expect(summary.latestReading?.heartRate == nil)
        // 08:00 读数同样无覆盖桶
        #expect(summary.readings.first?.heartRate == nil)
    }

    @Test func readingUsesBucketCoveringItsTimestamp() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = IntradaySignals(
            hrvPoints: [HRVSamplePoint(date: time(9), sdnn: 30, rmssd: 28)],
            heartRateBuckets: [
                bucket(9, average: 75),
                bucket(9, 15, average: 80),
            ],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        // 09:00 落在 09:00–09:15 桶
        #expect(summary.latestReading?.heartRate == 75)
    }

    @Test func meanRRDerivedFromHeartRate() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = IntradaySignals(
            hrvPoints: [HRVSamplePoint(date: time(9), sdnn: 30, rmssd: 28)],
            heartRateBuckets: [bucket(9, average: 75)],
            workouts: []
        )
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            signals: signals,
            calendar: calendar
        )
        // Mean RR = 60000 / 75 = 800 ms
        #expect(summary.latestReading?.meanRRms == 800)
        #expect(IntradayReading(date: time(9), heartRate: nil).meanRRms == nil)
    }

    @Test func summaryExposesSleepWindow() throws {
        let today = snapshot(offset: 0, bedtimeMinutes: -60, midpointMinutes: 240)
        let summary = IntradayStressEngine.evaluate(
            today: today,
            history: (1...8).map { snapshot(offset: -$0) },
            signals: .empty,
            calendar: calendar
        )
        let window = try #require(summary.sleepWindow)
        let midnight = calendar.startOfDay(for: now)
        #expect(window.start == midnight.addingTimeInterval(-3600))
        #expect(window.end == time(9))
    }

    @Test func realOnsetWakeTakePriorityOverEstimate() {
        var today = snapshot(offset: 0, bedtimeMinutes: -60, midpointMinutes: 240)
        today.sleepOnsetAt = time(0)
        today.sleepWakeAt = time(7)
        let summary = IntradayStressEngine.evaluate(
            today: today,
            history: (1...8).map { snapshot(offset: -$0) },
            signals: .empty,
            calendar: calendar
        )
        #expect(summary.sleepWindow == DateInterval(start: time(0), end: time(7)))
    }

    @Test func invalidRealWindowFallsBackToEstimate() {
        var today = snapshot(offset: 0, bedtimeMinutes: -60, midpointMinutes: 240)
        today.sleepOnsetAt = time(8)
        today.sleepWakeAt = time(7)
        let summary = IntradayStressEngine.evaluate(
            today: today,
            history: (1...8).map { snapshot(offset: -$0) },
            signals: .empty,
            calendar: calendar
        )
        let midnight = calendar.startOfDay(for: now)
        #expect(summary.sleepWindow == DateInterval(
            start: midnight.addingTimeInterval(-3600),
            end: time(9)
        ))
    }

    @Test func missingSleepFieldsLeaveWindowNil() {
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: (1...8).map { snapshot(offset: -$0) },
            signals: .empty,
            calendar: calendar
        )
        #expect(summary.sleepWindow == nil)
    }

    @Test func emptySignalsProduceEmptySummary() {
        let summary = IntradayStressEngine.evaluate(
            today: snapshot(offset: 0),
            history: (1...8).map { snapshot(offset: -$0) },
            signals: .empty,
            calendar: calendar
        )
        #expect(summary.readings.isEmpty)
        #expect(summary.buckets.isEmpty)
        #expect(summary.latestReading == nil)
    }
}

// configured by qoder
