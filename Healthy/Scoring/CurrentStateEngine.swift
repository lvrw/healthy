import Foundation

enum CurrentStateEngine {
    static func evaluate(
        today: DailySnapshot,
        history: [DailySnapshot],
        readiness: Double?,
        signals: CurrentSignals,
        now: Date = .now,
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current
    ) -> CurrentStateSnapshot {
        let baseline = Baseline.compute(history: history, today: today, config: config, calendar: calendar)
        let hrAge = signals.heartRateAt.map { now.timeIntervalSince($0) }
        let workoutRecent = signals.lastWorkoutEndAt.map {
            now.timeIntervalSince($0) <= config.instantWorkoutCooldownMinutes * 60
        } ?? false

        var hrComponent: Double?
        var note: String?
        if let heartRate = MetricSanitizer.value(signals.heartRate, in: MetricRange.heartRate),
           let age = hrAge,
           age >= 0,
           age <= config.instantHRWindowHours * 3600,
           let average = baseline.averageHeartRate {
            let sd = max(average.sd, config.avgHRSDFloor)
            if workoutRecent {
                hrComponent = 50
                note = "运动后 30 分钟内，参考意义有限"
            } else if heartRate > average.mean + config.activityZThreshold * sd {
                note = "心率明显高于个人日均基线，可能正在活动，此刻压力暂不估算"
            } else {
                let z = (heartRate - average.mean) / sd
                hrComponent = ScoreSupport.clampScore(
                    50 + config.hourlyStressWeight * ScoreSupport.clampZ(z, config.zClamp)
                )
            }
        } else if signals.heartRate != nil,
                  let age = hrAge,
                  age >= 0,
                  age <= config.instantHRWindowHours * 3600 {
            note = "日均心率基线不足，此刻压力暂只参考 HRV"
        }

        var hrvComponent: Double?
        if let hrv = MetricSanitizer.value(signals.hrv, in: MetricRange.hrv),
           let age = signals.hrvAt.map({ now.timeIntervalSince($0) }),
           age >= 0,
           age <= config.instantHRVFreshHours * 3600,
           let z = baseline.zHRV(hrv) {
            hrvComponent = ScoreSupport.clampScore(50 - 16 * ScoreSupport.clampZ(z, config.zClamp))
        }

        let instantStress = ScoreSupport.weightedAverage([
            (config.instantHRWeight, hrComponent),
            (config.instantHRVWeight, hrvComponent),
        ])
        let instantLevel = instantStress.map { StressEngine.level(for: $0, config: config) }
        let currentState = ScoreSupport.weightedAverage([
            (config.instantStateReadinessWeight, readiness),
            (config.instantStateStressWeight, instantStress.map { 100 - $0 }),
        ])

        let confidence: CurrentStateConfidence
        if let age = hrAge, age >= 0, age <= config.instantHRWindowHours * 3600 {
            if workoutRecent {
                confidence = .fair
            } else if age <= config.instantHRFreshMinutes * 60 {
                confidence = .fresh
            } else if age <= config.instantHRAcceptableMinutes * 60 {
                confidence = .fair
            } else {
                confidence = .stale
                if note == nil {
                    note = "心率数据已超过 60 分钟"
                }
            }
        } else {
            confidence = .unavailable
            if note == nil {
                note = "近 6 小时没有心率数据"
            }
        }

        return CurrentStateSnapshot(
            instantStress: instantStress,
            instantStressLevel: instantLevel,
            currentState: currentState,
            heartRate: MetricSanitizer.value(signals.heartRate, in: MetricRange.heartRate),
            heartRateAt: signals.heartRateAt,
            confidence: confidence,
            note: note
        )
    }
}
