import Foundation

struct WeekdayAverage: Sendable, Equatable, Identifiable {
    var id: Int { weekday }
    var weekday: Int
    var average: Double?
    var count: Int
}

struct StressTierCount: Sendable, Equatable, Identifiable {
    var id: StressLevel { level }
    var level: StressLevel
    var count: Int
    var fraction: Double
}

struct MonthBucket: Sendable, Equatable, Identifiable {
    var id: Date { monthStart }
    var monthStart: Date
    var average: Double
    var count: Int
}

/// 趋势页展示统计（星期均值 / 四档分布 / 月度降采样），不参与评分口径。
enum TrendAggregates {
    static func weekdayAverages(points: [(date: Date, value: Double)], calendar: Calendar) -> [WeekdayAverage] {
        var buckets: [Int: [Double]] = [:]
        for point in points {
            buckets[calendar.component(.weekday, from: point.date), default: []].append(point.value)
        }
        return (1...7).map { weekday in
            let values = buckets[weekday] ?? []
            return WeekdayAverage(
                weekday: weekday,
                average: values.isEmpty ? nil : ScoreSupport.mean(values),
                count: values.count
            )
        }
    }

    static func levelDistribution(stressValues: [Double], config: ScoringConfig = ScoringConfig()) -> [StressTierCount] {
        let tiers = StressTierPresentation.tiers(config: config)
        let total = stressValues.count
        return tiers.map { tier in
            let count = stressValues.filter { StressEngine.level(for: $0, config: config) == tier.level }.count
            return StressTierCount(
                level: tier.level,
                count: count,
                fraction: total > 0 ? Double(count) / Double(total) : 0
            )
        }
    }

    static func monthlyAverages(points: [(date: Date, value: Double)], calendar: Calendar) -> [MonthBucket] {
        var buckets: [Date: [Double]] = [:]
        for point in points {
            guard let monthStart = calendar.dateInterval(of: .month, for: point.date)?.start else { continue }
            buckets[monthStart, default: []].append(point.value)
        }
        return buckets
            .map { start, values in
                MonthBucket(
                    monthStart: start,
                    average: values.reduce(0, +) / Double(values.count),
                    count: values.count
                )
            }
            .sorted { $0.monthStart < $1.monthStart }
    }
}

// configured by qoder
