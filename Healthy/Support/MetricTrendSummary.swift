import Foundation

struct MetricTrendSummary: Equatable, Sendable {
    struct Point: Equatable, Sendable, Identifiable {
        var id: Date { date }
        var date: Date
        var value: Double
    }

    var latest: Double?
    var recentAverage: Double?
    var delta: Double?
    var series: [Point]

    // 近 N 天均值不含当天；差值 = 当天值 − 近 N 天均值。
    static func make(
        history: [DailySnapshot],
        today: DailySnapshot,
        calendar: Calendar,
        averageWindowDays: Int = 7,
        seriesWindowDays: Int = 14,
        extract: (DailySnapshot) -> Double?
    ) -> MetricTrendSummary {
        let todayStart = calendar.startOfDay(for: today.date)
        let latest = extract(today)

        let averageStart = DayKey.addingDays(-averageWindowDays, to: todayStart, calendar: calendar)
        let averageValues = history.compactMap { snapshot -> Double? in
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= averageStart, day < todayStart else { return nil }
            return extract(snapshot)
        }
        let recentAverage = ScoreSupport.mean(averageValues)
        let delta = latest.flatMap { value in recentAverage.map { value - $0 } }

        let seriesStart = DayKey.addingDays(-(seriesWindowDays - 1), to: todayStart, calendar: calendar)
        var points: [Point] = []
        for snapshot in history {
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= seriesStart, day < todayStart, let value = extract(snapshot) else { continue }
            points.append(Point(date: day, value: value))
        }
        if let latest {
            points.append(Point(date: todayStart, value: latest))
        }
        points.sort { $0.date < $1.date }

        return MetricTrendSummary(latest: latest, recentAverage: recentAverage, delta: delta, series: points)
    }
}

// configured by qoder