import Foundation

enum SleepStageKind: String, Codable, Sendable {
    case inBed
    case awake
    case core
    case deep
    case rem
}

struct SleepStageInterval: Codable, Sendable, Equatable {
    var start: Date
    var end: Date
    var stage: SleepStageKind
}

enum SleepStageCodec {
    static func encode(_ intervals: [SleepStageInterval]) -> String? {
        guard !intervals.isEmpty,
              let data = try? JSONEncoder().encode(intervals)
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> [SleepStageInterval] {
        guard let json, let data = json.data(using: .utf8),
              let intervals = try? JSONDecoder().decode([SleepStageInterval].self, from: data)
        else { return [] }
        return intervals.sorted { $0.start < $1.start }
    }
}

struct SleepWindowStats: Sendable, Equatable {
    var avgHR: Double? = nil
    var minHR: Double? = nil
    var maxHR: Double? = nil
    var avgHRV: Double? = nil
    var avgResp: Double? = nil
    var avgSpo2: Double? = nil
}

/// 主睡眠区间 = 最长的一段连续睡眠（合并间隔 < mergeGapMinutes 的片段）。
/// 用于入睡点 / 睡眠中点 / 醒来点，自动忽略远离夜间的午睡等短时片段，
/// 否则午睡会拉偏 firstAsleepStart / lastAsleepEnd，使中点计算严重偏差。
///
/// - Parameters:
///   - stages: 已筛选出的 asleep 片段（core/deep/rem），不含 awake/inBed。
///   - mergeGapMinutes: 相邻睡眠片段间隔小于该值即视为同一段（默认 240，
///     足以桥接夜间短暂清醒，又不会把下午午睡并入夜睡）。
/// - Returns: 主睡眠的 (start, end)；无任何睡眠片段时返回 nil。
func mainSleepSpan(
    from stages: [SleepStageInterval],
    mergeGapMinutes: Double = 240
) -> (start: Date, end: Date)? {
    let sorted = stages.sorted { $0.start < $1.start }
    guard !sorted.isEmpty else { return nil }
    let gap = mergeGapMinutes * 60
    var merged: [DateInterval] = []
    for iv in sorted {
        if let last = merged.last, iv.start <= last.end + gap {
            merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, iv.end))
        } else {
            merged.append(DateInterval(start: iv.start, end: iv.end))
        }
    }
    guard let longest = merged.max(by: { $0.duration < $1.duration }) else { return nil }
    return (start: longest.start, end: longest.end)
}

struct TimedValue: Sendable, Equatable {
    var date: Date
    var value: Double
}

// configured by qoder