import Foundation

struct IntradayReading: Sendable, Equatable, Identifiable {
    var id: Date { date }
    var date: Date
    var sdnn: Double?
    var rmssd: Double?
    var stress: Double?
    var level: StressLevel?
    var zScore: Double?
    var heartRate: Double?

    /// Mean RR 由心率派生（60000/HR），HealthKit 不提供原始心搏间期。
    var meanRRms: Double? {
        heartRate.flatMap { hr in hr > 0 ? 60_000 / hr : nil }
    }
}

enum HourContext: Sendable, Equatable {
    case normal
    case workout
    case sleeping
    case activity
    case noHeartRate
    case noBaseline

    var isExcluded: Bool { self != .normal }
}

struct IntradayBucket: Sendable, Equatable, Identifiable {
    var id: Date { start }
    var start: Date
    var minutes: Int
    var stress: Double?
    var heartRate: Double?
    var context: HourContext

    var end: Date { start.addingTimeInterval(TimeInterval(minutes * 60)) }
}

struct IntradaySummary: Sendable, Equatable {
    var readings: [IntradayReading]
    var buckets: [IntradayBucket]
    var latestReading: IntradayReading?
    var baselineHRVms: Double?
    var baselineAverageHR: Double?
    var sleepWindow: DateInterval? = nil

    static let empty = IntradaySummary(
        readings: [],
        buckets: [],
        latestReading: nil,
        baselineHRVms: nil,
        baselineAverageHR: nil
    )
}

enum IntradayStressEngine {
    static func evaluate(
        today: DailySnapshot,
        history: [DailySnapshot],
        signals: IntradaySignals,
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current
    ) -> IntradaySummary {
        let baseline = Baseline.compute(history: history, today: today, config: config, calendar: calendar)
        let sleepWindow = sleepInterval(of: today, calendar: calendar)

        var readings: [IntradayReading] = []
        for point in signals.hrvPoints {
            let sdnn = MetricSanitizer.value(point.sdnn, in: MetricRange.hrv)
            let rmssd = MetricSanitizer.value(point.rmssd, in: MetricRange.hrv)
            let z = sdnn.flatMap { baseline.zHRV($0) }
            let stress = z.map { ScoreSupport.clampScore(50 - 16 * ScoreSupport.clampZ($0, config.zClamp)) }
            readings.append(
                IntradayReading(
                    date: point.date,
                    sdnn: sdnn,
                    rmssd: rmssd,
                    stress: stress,
                    level: stress.map { StressEngine.level(for: $0, config: config) },
                    zScore: z,
                    heartRate: signals.heartRateBuckets.first { $0.start <= point.date && point.date < $0.end }?.average
                )
            )
        }

        var buckets: [IntradayBucket] = []
        for point in signals.heartRateBuckets {
            let interval = point.start ..< point.end
            let heartRate = MetricSanitizer.value(point.average, in: MetricRange.heartRate)
            let context = hourContext(
                heartRate: heartRate,
                interval: interval,
                baseline: baseline.averageHeartRate,
                sleepWindow: sleepWindow,
                workouts: signals.workouts,
                config: config
            )
            var stress: Double?
            if context == .normal, let heartRate, let avg = baseline.averageHeartRate {
                let sd = max(avg.sd, config.avgHRSDFloor)
                let z = (heartRate - avg.mean) / sd
                stress = ScoreSupport.clampScore(
                    50 + config.hourlyStressWeight * ScoreSupport.clampZ(z, config.zClamp)
                )
            }
            buckets.append(
                IntradayBucket(
                    start: point.start,
                    minutes: point.minutes,
                    stress: stress,
                    heartRate: heartRate,
                    context: context
                )
            )
        }

        return IntradaySummary(
            readings: readings,
            buckets: buckets,
            latestReading: readings.last,
            baselineHRVms: baseline.hrvLog.map { exp($0.mean) - 1 },
            baselineAverageHR: baseline.averageHeartRate?.mean,
            sleepWindow: sleepWindow
        )
    }

    private static func hourContext(
        heartRate: Double?,
        interval: Range<Date>,
        baseline: BaselineStats?,
        sleepWindow: DateInterval?,
        workouts: [WorkoutInterval],
        config: ScoringConfig
    ) -> HourContext {
        guard let heartRate else { return .noHeartRate }
        guard let baseline else { return .noBaseline }
        if let sleepWindow {
            let bucketMinutes = interval.upperBound.timeIntervalSince(interval.lowerBound) / 60
            let threshold = min(config.sleepOverlapMinutes, bucketMinutes / 2)
            if overlapMinutes(between: sleepWindow, and: interval) >= threshold {
                return .sleeping
            }
        }
        if workouts.contains(where: { $0.start < interval.upperBound && $0.end > interval.lowerBound }) {
            return .workout
        }
        let sd = max(baseline.sd, config.avgHRSDFloor)
        if heartRate > baseline.mean + config.activityZThreshold * sd {
            return .activity
        }
        return .normal
    }

    /// 睡眠按「醒来日」归档：优先真实入睡/起床时间；缺失时用入睡点（相对当天 0 点可为负）+ 中点估算，起床点 = 2×中点 − 入睡点。
    private static func sleepInterval(of snapshot: DailySnapshot, calendar: Calendar) -> DateInterval? {
        if let onset = snapshot.sleepOnsetAt, let wake = snapshot.sleepWakeAt, wake > onset {
            return DateInterval(start: onset, end: wake)
        }
        guard
            let bedtime = MetricSanitizer.value(
                snapshot.sleepBedtimeMinutes,
                in: MetricRange.sleepBedtimeMinutes
            ),
            let midpoint = MetricSanitizer.value(
                snapshot.sleepMidpointMinutes,
                in: MetricRange.sleepMidpointMinutes
            )
        else { return nil }
        let midnight = calendar.startOfDay(for: snapshot.date)
        let onset = midnight.addingTimeInterval(bedtime * 60)
        let wake = midnight.addingTimeInterval((2 * midpoint - bedtime) * 60)
        guard wake > onset else { return nil }
        return DateInterval(start: onset, end: wake)
    }

    private static func overlapMinutes(between window: DateInterval, and interval: Range<Date>) -> Double {
        let start = max(window.start, interval.lowerBound)
        let end = min(window.end, interval.upperBound)
        return max(0, end.timeIntervalSince(start) / 60)
    }
}
