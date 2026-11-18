import Foundation
import Testing

struct SleepAnalysisEngineTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var midnight: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 2)) ?? .now
    }

    private func at(_ hour: Double, dayOffset: Int = 0) -> Date {
        let base = calendar.date(byAdding: .day, value: dayOffset, to: midnight) ?? midnight
        return base.addingTimeInterval(hour * 3600)
    }

    @Test func restorativeRatioCombinesDeepAndREM() {
        let ratio = SleepAnalysisEngine.restorativeRatio(deepH: 1.5, remH: 1.8, totalH: 7.5)
        #expect(ratio == 0.44)
    }

    @Test func restorativeRatioRequiresPositiveTotal() {
        #expect(SleepAnalysisEngine.restorativeRatio(deepH: 1, remH: 1, totalH: nil) == nil)
        #expect(SleepAnalysisEngine.restorativeRatio(deepH: 1, remH: 1, totalH: 0) == nil)
        #expect(SleepAnalysisEngine.restorativeRatio(deepH: nil, remH: nil, totalH: 7) == 0)
    }

    @Test func restorativeScoreMapsReferenceBand() {
        // 参考带 33%–48%：带下线性 0→80，带内 80→100，带上封顶 100（仅展示，不进总评分）。
        #expect(SleepAnalysisEngine.restorativeScore(ratio: 0) == 0)
        #expect(SleepAnalysisEngine.restorativeScore(ratio: 0.165) == 40)
        #expect(SleepAnalysisEngine.restorativeScore(ratio: 0.33) == 80)
        #expect(SleepAnalysisEngine.restorativeScore(ratio: 0.405) == 90)
        #expect(SleepAnalysisEngine.restorativeScore(ratio: 0.48) == 100)
        #expect(SleepAnalysisEngine.restorativeScore(ratio: 0.60) == 100)
    }

    @Test func sleepHeartRateLevels() {
        #expect(SleepAnalysisEngine.heartRateLevel(80) == .high)
        #expect(SleepAnalysisEngine.heartRateLevel(75) == .normal)
        #expect(SleepAnalysisEngine.heartRateLevel(60) == .normal)
        #expect(SleepAnalysisEngine.heartRateLevel(59.9) == .excellent)
        #expect(SleepAnalysisEngine.heartRateLevel(45) == .excellent)
    }

    @Test func daytimeHREstimateFromDailyAverage() {
        // (78×24 − 60×8) / (24−8) = 87
        let daytime = SleepAnalysisEngine.daytimeHR(avgHR: 78, sleepHR: 60, sleepHours: 8)
        #expect(daytime == 87)
        #expect(SleepAnalysisEngine.daytimeHR(avgHR: nil, sleepHR: 60, sleepHours: 8) == nil)
        #expect(SleepAnalysisEngine.daytimeHR(avgHR: 78, sleepHR: nil, sleepHours: 8) == nil)
        #expect(SleepAnalysisEngine.daytimeHR(avgHR: 78, sleepHR: 60, sleepHours: 24) == nil)
    }

    @Test func dipPercentFormula() {
        // (75 − 60) / 75 × 100 = 20
        #expect(SleepAnalysisEngine.dipPercent(daytimeHR: 75, sleepHR: 60) == 20)
        #expect(SleepAnalysisEngine.dipPercent(daytimeHR: nil, sleepHR: 60) == nil)
        #expect(SleepAnalysisEngine.dipPercent(daytimeHR: 0, sleepHR: 60) == nil)
    }

    @Test func dipLevels() {
        #expect(SleepAnalysisEngine.dipLevel(9.9) == .low)
        #expect(SleepAnalysisEngine.dipLevel(10) == .normal)
        #expect(SleepAnalysisEngine.dipLevel(20) == .normal)
        #expect(SleepAnalysisEngine.dipLevel(20.1) == .good)
    }

    @Test func dipPercentForDayHidesIncompleteToday() {
        let today = DayKey.key(for: .now)
        let yesterday = DayKey.key(for: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        let now = Date()
        // 当天、睡眠尚未结束（now < 睡眠结束时间）：avgHR 被睡眠段主导，应判为无数据，绝不出现「偏低」。
        #expect(
            SleepAnalysisEngine.dipPercentForDay(
                avgHR: 66, sleepHR: 66, sleepHours: 6.7, dayKey: today,
                sleepEnd: now.addingTimeInterval(3600)
            ) == nil
        )
        // 当天、已醒来（睡眠结束时间早于现在）：正常反推（daytimeHR=(72×24−60×7)/17≈76.9，dip≈22.0）。
        #expect(
            SleepAnalysisEngine.dipPercentForDay(
                avgHR: 72, sleepHR: 60, sleepHours: 7, dayKey: today,
                sleepEnd: now.addingTimeInterval(-3600)
            ).map { $0.rounded() } == 22
        )
        // 历史已完成的一天：正常反推（daytimeHR=(72×24−60×7)/17≈76.9，dip≈22.0）。
        #expect(
            SleepAnalysisEngine.dipPercentForDay(
                avgHR: 72, sleepHR: 60, sleepHours: 7, dayKey: yesterday
            ).map { $0.rounded() } == 22
        )
    }

    @Test func stageIntervalJSONRoundTrip() throws {
        let intervals = [
            SleepStageInterval(start: at(23, dayOffset: -1), end: at(23.75, dayOffset: -1), stage: .core),
            SleepStageInterval(start: at(23.75, dayOffset: -1), end: at(0.25), stage: .deep),
            SleepStageInterval(start: at(6), end: at(6.1), stage: .awake),
        ]
        let json = try #require(SleepStageCodec.encode(intervals))
        #expect(SleepStageCodec.decode(json) == intervals)
        #expect(SleepStageCodec.encode([]) == nil)
        #expect(SleepStageCodec.decode(nil).isEmpty)
        #expect(SleepStageCodec.decode("not json").isEmpty)
    }

    @Test func windowAggregationAssignsSamplesByDate() {
        // 睡眠窗口跨午夜：11-01 23:00 → 11-02 07:00，按醒来日归档。
        let window = DateInterval(start: at(23, dayOffset: -1), end: at(7))
        let stats = SleepAnalysisEngine.aggregate(
            heartRate: [
                TimedValue(date: at(23.5, dayOffset: -1), value: 55),
                TimedValue(date: at(3), value: 60),
                TimedValue(date: at(6.5), value: 65),
                TimedValue(date: at(8), value: 90),
            ],
            hrv: [TimedValue(date: at(3), value: 50)],
            respiratory: [TimedValue(date: at(4), value: 13)],
            spo2: [TimedValue(date: at(5), value: 97)],
            windows: ["2026-11-02": window]
        )
        let day = stats["2026-11-02"]
        #expect(day?.avgHR == 60)
        #expect(day?.minHR == 55)
        #expect(day?.maxHR == 65)
        #expect(day?.avgHRV == 50)
        #expect(day?.avgResp == 13)
        #expect(day?.avgSpo2 == 97)
    }

    @Test func windowWithoutSamplesKeepsNilFields() {
        let window = DateInterval(start: at(23, dayOffset: -1), end: at(7))
        let stats = SleepAnalysisEngine.aggregate(
            heartRate: [TimedValue(date: at(12), value: 80)],
            hrv: [],
            respiratory: [],
            spo2: [],
            windows: ["2026-11-02": window]
        )
        let day = stats["2026-11-02"]
        #expect(day?.avgHR == nil)
        #expect(day?.minHR == nil)
        #expect(day?.maxHR == nil)
        #expect(day?.avgHRV == nil)
    }

    @Test func sampleAtWindowEndIsExcluded() {
        let window = DateInterval(start: at(23, dayOffset: -1), end: at(7))
        let stats = SleepAnalysisEngine.aggregate(
            heartRate: [TimedValue(date: at(7), value: 88)],
            hrv: [],
            respiratory: [],
            spo2: [],
            windows: ["2026-11-02": window]
        )
        #expect(stats["2026-11-02"]?.avgHR == nil)
    }
}

// configured by qoder