import Foundation

struct MoodPoint: Sendable, Equatable, Identifiable {
    var id: String { dayKey }
    var dayKey: String
    var date: Date
    var valence: Double
    var isLocal: Bool
}

enum MoodDisplay {
    /// 感受点阵展示层合并：同一天本地记录优先于健康 App 的心理状态；两侧都无值的天剔除。
    /// 注意：StressEngine.moodComponent 仍只使用 HealthKit 数据，评分口径不变。
    static func merge(
        healthKit: [(date: Date, valence: Double?)],
        local: [(date: Date, valence: Double)],
        calendar: Calendar
    ) -> [MoodPoint] {
        var points: [MoodPoint] = []
        var seen: Set<String> = []

        for entry in local {
            let key = DayKey.key(for: entry.date, calendar: calendar)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            points.append(
                MoodPoint(
                    dayKey: key,
                    date: calendar.startOfDay(for: entry.date),
                    valence: entry.valence,
                    isLocal: true
                )
            )
        }
        for entry in healthKit {
            let key = DayKey.key(for: entry.date, calendar: calendar)
            guard let valence = entry.valence, !seen.contains(key) else { continue }
            seen.insert(key)
            points.append(
                MoodPoint(
                    dayKey: key,
                    date: calendar.startOfDay(for: entry.date),
                    valence: valence,
                    isLocal: false
                )
            )
        }
        return points.sorted { $0.date < $1.date }
    }
}

// configured by qoder