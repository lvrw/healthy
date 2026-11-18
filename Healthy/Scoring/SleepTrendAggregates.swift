import Foundation

struct SleepDaySummary: Sendable, Equatable, Identifiable {
    var id: String { dayKey }
    var dayKey: String
    var date: Date
    var totalH: Double?
    var efficiency: Double?
    var deepH: Double?
    var remH: Double?
    var restorativeRatio: Double?
    var qualityScore: Double?
    var bedtimeMinutes: Double?
    var midpointMinutes: Double?
    var isLateBedtime: Bool
}

struct SleepPeriodStats: Sendable, Equatable {
    var averageTotalH: Double?
    var averageQuality: Double?
    var midpointSD: Double?
    var validRatio: Double
    var lateCount: Int
}

enum SleepTrendAggregates {
    static let lateMarginMinutes = 60.0
    static let minThresholdDays = 3
    static let minVariabilityDays = 3

    /// 质量环展示合成 = 0.5×效率×100 + 0.5×恢复性展示分；仅展示，不进 Readiness/Stress。
    static func qualityScore(efficiency: Double?, restorativeRatio: Double?) -> Double? {
        let efficiencyScore = efficiency.map { ScoreSupport.clampScore($0 * 100) }
        let restorativeScore = restorativeRatio.map { SleepAnalysisEngine.restorativeScore(ratio: $0) }
        return ScoreSupport.weightedAverage([
            (0.5, efficiencyScore),
            (0.5, restorativeScore),
        ])
    }

    static func daySummary(_ snapshot: DailySnapshot, lateThresholdMinutes: Double?) -> SleepDaySummary {
        let ratio = SleepAnalysisEngine.restorativeRatio(
            deepH: snapshot.deepH,
            remH: snapshot.remH,
            totalH: snapshot.sleepTotalH
        )
        let bedtime = MetricSanitizer.value(snapshot.sleepBedtimeMinutes, in: MetricRange.sleepBedtimeMinutes)
        return SleepDaySummary(
            dayKey: snapshot.dayKey,
            date: snapshot.date,
            totalH: snapshot.sleepTotalH,
            efficiency: snapshot.sleepEfficiency,
            deepH: snapshot.deepH,
            remH: snapshot.remH,
            restorativeRatio: ratio,
            qualityScore: qualityScore(efficiency: snapshot.sleepEfficiency, restorativeRatio: ratio),
            bedtimeMinutes: bedtime,
            midpointMinutes: snapshot.sleepMidpointMinutes,
            isLateBedtime: bedtime.flatMap { b in lateThresholdMinutes.map { b > $0 } } ?? false
        )
    }

    /// 晚睡阈值 = 过去 28 天入睡点中位数 + 60 分钟宽限（不含当天；展示口径，非评分）。
    static func lateThreshold(
        history: [DailySnapshot],
        today: DailySnapshot,
        calendar: Calendar,
        marginMinutes: Double = lateMarginMinutes
    ) -> Double? {
        let todayStart = calendar.startOfDay(for: today.date)
        let start = DayKey.addingDays(-28, to: todayStart, calendar: calendar)
        let values = history.compactMap { snapshot -> Double? in
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= start, day < todayStart else { return nil }
            return MetricSanitizer.value(snapshot.sleepBedtimeMinutes, in: MetricRange.sleepBedtimeMinutes)
        }
        guard values.count >= minThresholdDays else { return nil }
        return median(values) + marginMinutes
    }

    /// 从最新一天向前数连续有睡眠的天数；最新日无数据则为 0。
    static func streak(_ summaries: [SleepDaySummary], calendar: Calendar) -> Int {
        let sorted = summaries.sorted { $0.date < $1.date }
        guard let latest = sorted.last, latest.totalH != nil else { return 0 }
        var count = 1
        var expected = DayKey.addingDays(-1, to: calendar.startOfDay(for: latest.date), calendar: calendar)
        for summary in sorted.dropLast().reversed() {
            let day = calendar.startOfDay(for: summary.date)
            guard day == expected, summary.totalH != nil else { break }
            count += 1
            expected = DayKey.addingDays(-1, to: expected, calendar: calendar)
        }
        return count
    }

    static func periodStats(_ summaries: [SleepDaySummary]) -> SleepPeriodStats {
        let valid = summaries.filter { $0.totalH != nil }
        let midpoints = valid.compactMap(\.midpointMinutes)
        let sd: Double? = midpoints.count >= minVariabilityDays
            ? ScoreSupport.standardDeviation(midpoints)
            : nil
        return SleepPeriodStats(
            averageTotalH: ScoreSupport.mean(valid.compactMap(\.totalH)),
            averageQuality: ScoreSupport.mean(valid.compactMap(\.qualityScore)),
            midpointSD: sd,
            validRatio: summaries.isEmpty ? 0 : Double(valid.count) / Double(summaries.count),
            lateCount: summaries.filter(\.isLateBedtime).count
        )
    }

    static func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

// configured by qoder