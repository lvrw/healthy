import Foundation

enum SleepHRLevel: String, Sendable, Equatable {
    case excellent
    case normal
    case high

    var label: String {
        switch self {
        case .excellent: return "优秀"
        case .normal: return "正常"
        case .high: return "偏高"
        }
    }
}

enum DipLevel: String, Sendable, Equatable {
    case low
    case normal
    case good

    var label: String {
        switch self {
        case .low: return "偏低"
        case .normal: return "正常"
        case .good: return "优秀"
        }
    }
}

enum SleepAnalysisEngine {
    // 恢复性睡眠 = 深睡 + REM；参考带合计 33%–48%（深睡 13–23%、REM 20–25%）。
    static let restorativeLow = 0.33
    static let restorativeHigh = 0.48

    static func restorativeRatio(deepH: Double?, remH: Double?, totalH: Double?) -> Double? {
        guard let totalH, totalH > 0 else { return nil }
        return ((deepH ?? 0) + (remH ?? 0)) / totalH
    }

    /// 仅展示分：带下线性 0→80，带内 80→100，带上封顶；不参与 Readiness/Stress 加权。
    static func restorativeScore(ratio: Double) -> Double {
        let clamped = max(0, ratio)
        let score: Double
        if clamped < restorativeLow {
            score = 80 * clamped / restorativeLow
        } else if clamped <= restorativeHigh {
            score = 80 + 20 * (clamped - restorativeLow) / (restorativeHigh - restorativeLow)
        } else {
            score = 100
        }
        return score.rounded()
    }

    static func heartRateLevel(_ hr: Double) -> SleepHRLevel {
        if hr > 75 { return .high }
        if hr >= 60 { return .normal }
        return .excellent
    }

    /// 日间心率估算：(全天均值×24 − 睡眠心率×睡眠时长) / (24 − 睡眠时长)，非直接测量。
    static func daytimeHR(avgHR: Double?, sleepHR: Double?, sleepHours: Double?) -> Double? {
        guard let avgHR, let sleepHR, let sleepHours, sleepHours >= 0, sleepHours < 24 else { return nil }
        let daytime = (avgHR * 24 - sleepHR * sleepHours) / (24 - sleepHours)
        return daytime > 0 ? daytime : nil
    }

    static func dipPercent(daytimeHR: Double?, sleepHR: Double?) -> Double? {
        guard let daytimeHR, daytimeHR > 0, let sleepHR else { return nil }
        return (daytimeHR - sleepHR) / daytimeHR * 100
    }

    /// dip 仅在「睡眠已结束、当天数据足够完整」时有意义：当天仍在进行、且睡眠窗口尚未结束
    /// （now < 睡眠结束时间）时，全天均值几乎全由睡眠段构成，反推的日间心率失真，会被误判成
    /// 「偏低」，因此醒来前一律判为无数据（返回 nil）。历史日期的睡眠早已结束，正常计算；
    /// 当天但已醒来的，也正常计算。用 dayKey 与当天 key 比较，避免 date 时区/取整歧义。
    static func dipPercentForDay(
        avgHR: Double?,
        sleepHR: Double?,
        sleepHours: Double?,
        dayKey: String,
        sleepEnd: Date? = nil,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let daytime = daytimeHR(avgHR: avgHR, sleepHR: sleepHR, sleepHours: sleepHours)
        guard let daytime else { return nil }
        if dayKey == DayKey.key(for: now, calendar: calendar),
           let sleepEnd, now < sleepEnd {
            return nil
        }
        return dipPercent(daytimeHR: daytime, sleepHR: sleepHR)
    }

    static func dipLevel(_ dip: Double) -> DipLevel {
        if dip < 10 { return .low }
        if dip <= 20 { return .normal }
        return .good
    }

    /// 样本按日期落入 [start, end) 睡眠窗口归档；每类型一次全量查询后在代码内聚合。
    static func aggregate(
        heartRate: [TimedValue],
        hrv: [TimedValue],
        respiratory: [TimedValue],
        spo2: [TimedValue],
        windows: [String: DateInterval]
    ) -> [String: SleepWindowStats] {
        var result: [String: SleepWindowStats] = [:]
        for (key, window) in windows {
            func values(_ samples: [TimedValue]) -> [Double] {
                samples.compactMap { sample in
                    sample.date >= window.start && sample.date < window.end ? sample.value : nil
                }
            }
            let hrValues = values(heartRate)
            var stats = SleepWindowStats()
            stats.avgHR = ScoreSupport.mean(hrValues)
            stats.minHR = hrValues.min()
            stats.maxHR = hrValues.max()
            stats.avgHRV = ScoreSupport.mean(values(hrv))
            stats.avgResp = ScoreSupport.mean(values(respiratory))
            stats.avgSpo2 = ScoreSupport.mean(values(spo2))
            result[key] = stats
        }
        return result
    }
}

// configured by qoder