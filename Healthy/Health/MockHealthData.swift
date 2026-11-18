#if DEBUG
import Foundation

enum MockHealthData {
    static func dailyMetrics(
        days: Int = 118,
        endingAt endDate: Date = .now,
        calendar: Calendar = .current
    ) -> [DailyMetricsDTO] {
        var generator = SeededGenerator(seed: 0x5EED_2026)
        var rows: [DailyMetricsDTO] = []
        let end = DayKey.startOfDay(endDate, calendar: calendar)

        for offset in stride(from: days - 1, through: 0, by: -1) {
            let date = DayKey.addingDays(-offset, to: end, calendar: calendar)
            let dayKey = DayKey.key(for: date, calendar: calendar)
            let isToday = offset == 0
            let weekday = calendar.component(.weekday, from: date)

            var hrv: Double? = rounded(46 + 4 * sin(Double(weekday)) + Double.random(in: -5...5, using: &generator))
            if offset % 11 == 7 { hrv = nil }
            if isToday { hrv = 33.5 }

            let restingHR = rounded(58 - ((hrv ?? 46) - 46) * 0.18 + Double.random(in: -1.5...1.5, using: &generator) + (isToday ? 4 : 0))
            let avgHR = rounded(66 + Double.random(in: -5...5, using: &generator))
            let walkingHR = rounded(98 + Double.random(in: -8...8, using: &generator))
            let respiratoryRate = rounded(14.6 + Double.random(in: -0.7...0.7, using: &generator))
            let spo2 = rounded(97.5 + Double.random(in: -0.9...0.9, using: &generator))
            let wristTempC = rounded(36.15 + Double.random(in: -0.18...0.18, using: &generator))

            let sleepTotal = rounded(isToday ? 6.3 : 7.3 + Double.random(in: -1.0...0.9, using: &generator))
            let deep = rounded(max(0.4, sleepTotal * 0.16 + Double.random(in: -0.1...0.1, using: &generator)))
            let rem = rounded(max(0.5, sleepTotal * 0.21 + Double.random(in: -0.1...0.1, using: &generator)))
            let core = rounded(max(0, sleepTotal - deep - rem))
            let awake = rounded(0.15 + Double.random(in: 0...0.25, using: &generator))
            let inBed = rounded(sleepTotal + awake + 0.1)

            let steps = rounded(7500 + Double.random(in: -2800...2800, using: &generator))
            let activeEnergy = rounded(480 + Double.random(in: -130...130, using: &generator))
            let basalEnergyKcal = rounded(1_620 + Double.random(in: -40...40, using: &generator))
            let exerciseMinutes = rounded(max(0, 28 + Double.random(in: -18...18, using: &generator)))
            let standMinutes = rounded(max(180, (9 + Double.random(in: -2.5...2.5, using: &generator)) * 60))
            let workoutCount = Int.random(in: 0...2, using: &generator)
            let workoutMinutes: Double? = workoutCount == 0 ? nil : rounded(25 + Double.random(in: 0...40, using: &generator))
            // 演示用的训练心率区间分布（偏有氧/无氧），归一化到 workoutMinutes。
            let workoutZoneJSON: String? = workoutMinutes.flatMap { total in
                let weights = [0.15, 0.25, 0.35, 0.18, 0.07]
                let minutes = weights.map { rounded(total * $0) }
                return (try? JSONEncoder().encode(WorkoutZoneMinutes(minutes: minutes)))
                    .flatMap { String(data: $0, encoding: .utf8) }
            }

            let vo2Max: Double? = offset % 5 == 3
                ? nil
                : (isToday ? 40.2 : rounded(42 + Double.random(in: -2...2, using: &generator)))
            let walkingSpeed = rounded(1.35 + Double.random(in: -0.08...0.08, using: &generator))
            let walkingStepLength = rounded(72 + Double.random(in: -3...3, using: &generator))
            let walkingAsymmetry = rounded(2.5 + Double.random(in: -1...1, using: &generator))
            let walkingSteadiness = rounded(85 + Double.random(in: -5...5, using: &generator))
            let flights = rounded(8 + Double.random(in: -4...4, using: &generator))
            let distanceKm = rounded(5.5 + Double.random(in: -1.5...1.5, using: &generator))

            let daylight = isToday ? 15 : rounded(45 + Double.random(in: -20...20, using: &generator))
            let mindful = isToday ? 0 : rounded(max(0, Double.random(in: 0...15, using: &generator)))
            let valence: Double? = isToday
                ? -0.3
                : (offset % 3 == 0 ? rounded(Double.random(in: -0.6...0.8, using: &generator)) : nil)
            let midpoint = isToday ? 240 : rounded(180 + Double.random(in: -25...25, using: &generator))
            let bedtime = isToday ? -30 : rounded(-60 + Double.random(in: -30...30, using: &generator))
            let awakeCount = Int.random(in: 1...3, using: &generator)

            let onset = date.addingTimeInterval(bedtime * 60)
            var stages: [SleepStageInterval] = []
            var cursor = onset
            func appendStage(_ stage: SleepStageKind, hours: Double) {
                guard hours > 0 else { return }
                let end = cursor.addingTimeInterval(hours * 3600)
                stages.append(SleepStageInterval(start: cursor, end: end, stage: stage))
                cursor = end
            }
            appendStage(.core, hours: core * 0.5)
            appendStage(.deep, hours: deep * 0.7)
            appendStage(.core, hours: core * 0.3)
            appendStage(.rem, hours: rem * 0.4)
            appendStage(.awake, hours: awake * 0.5)
            appendStage(.deep, hours: deep * 0.3)
            appendStage(.core, hours: core * 0.2)
            appendStage(.rem, hours: rem * 0.6)
            appendStage(.awake, hours: awake * 0.5)
            let wake = cursor
            let sleepAvgHR = rounded(restingHR - 4 + Double.random(in: -2...2, using: &generator))

            let weight = isToday ? 70.4 : rounded(70 + Double.random(in: -0.3...0.3, using: &generator))
            let bodyFat = rounded(18 + Double.random(in: -0.4...0.4, using: &generator))
            let leanMass = rounded(57 + Double.random(in: -0.3...0.3, using: &generator))
            let bmiValue = rounded(22.5 + Double.random(in: -0.2...0.2, using: &generator))
            let waist = rounded(82 + Double.random(in: -0.5...0.5, using: &generator))

            // 示例数据也带上饮食与饮水，便于验证评分 / 身体年龄 / UI 展示链路。
            let externalWater = isToday ? 900.0 : rounded(1_000 + Double.random(in: -400...600, using: &generator))
            let energyKcal = rounded(2_100 + Double.random(in: -300...300, using: &generator))
            let carbsG = rounded(250 + Double.random(in: -50...50, using: &generator))
            let proteinG = isToday ? 52 : rounded(72 + Double.random(in: -18...18, using: &generator))
            let fatG = rounded(72 + Double.random(in: -18...18, using: &generator))
            let fiberG = isToday ? 16 : rounded(26 + Double.random(in: -8...8, using: &generator))
            let sugarG = isToday ? 68 : rounded(45 + Double.random(in: -15...20, using: &generator))
            let sodiumMg = isToday ? 2_700 : rounded(2_100 + Double.random(in: -500...400, using: &generator))
            let caffeineMg = rounded(120 + Double.random(in: -70...90, using: &generator))

            var flags = MetricSource.sleep.rawValue | MetricSource.activity.rawValue | MetricSource.vitals.rawValue
            flags |= MetricSource.circadian.rawValue | MetricSource.fitnessBody.rawValue
            flags |= MetricSource.nutrition.rawValue
            if hrv != nil { flags |= MetricSource.hrv.rawValue }
            flags |= MetricSource.restingHR.rawValue

            let hrvLatestAt = calendar.date(bySettingHour: 7, minute: 35, second: 0, of: date)

            rows.append(
                DailyMetricsDTO(
                    dayKey: dayKey,
                    date: date,
                    hrvSDNN: hrv,
                    hrvLatest: hrv.map { rounded($0 + Double.random(in: -2...2, using: &generator)) },
                    hrvLatestAt: hrvLatestAt,
                    restingHR: restingHR,
                    avgHR: avgHR,
                    walkingHR: walkingHR,
                    respiratoryRate: respiratoryRate,
                    spo2: spo2,
                    wristTempC: wristTempC,
                    sleepTotalH: sleepTotal,
                    deepH: deep,
                    remH: rem,
                    coreH: core,
                    awakeH: awake,
                    inBedH: inBed,
                    sleepEfficiency: rounded(sleepTotal / inBed),
                    steps: steps,
                    activeEnergy: activeEnergy,
                    basalEnergyKcal: basalEnergyKcal,
                    exerciseMinutes: exerciseMinutes,
                    standMinutes: standMinutes,
                    workoutCount: workoutCount,
                    workoutMinutes: workoutMinutes,
                    workoutZoneMinutesJSON: workoutZoneJSON,
                    sourceFlags: flags,
                    vo2Max: vo2Max,
                    walkingSpeedMps: walkingSpeed,
                    walkingStepLengthCm: walkingStepLength,
                    walkingAsymmetryPct: walkingAsymmetry,
                    walkingSteadinessPct: walkingSteadiness,
                    flightsClimbed: flights,
                    distanceWalkingKm: distanceKm,
                    daylightMinutes: daylight,
                    mindfulMinutes: mindful,
                    stateOfMindValence: valence,
                    stateOfMindCount: valence == nil ? nil : Int.random(in: 1...3, using: &generator),
                    sleepMidpointMinutes: midpoint,
                    sleepBedtimeMinutes: bedtime,
                    awakeCount: awakeCount,
                    sleepStagesJSON: SleepStageCodec.encode(stages),
                    sleepOnsetAt: onset,
                    sleepWakeAt: wake,
                    sleepAvgHR: sleepAvgHR,
                    sleepMinHR: rounded(sleepAvgHR - 6),
                    sleepMaxHR: rounded(sleepAvgHR + 9),
                    sleepAvgHRV: hrv.map { rounded($0 * 1.08) },
                    sleepAvgResp: rounded(respiratoryRate - 0.6),
                    sleepAvgSpo2: rounded(spo2 - 0.4),
                    environmentalNoiseDb: rounded(50 + Double.random(in: -8...14, using: &generator)),
                    bodyMassKg: weight,
                    bodyFatPct: bodyFat,
                    leanBodyMassKg: leanMass,
                    bmi: bmiValue,
                    waistCircumferenceCm: waist,
                    systolicBP: nil,
                    diastolicBP: nil,
                    bloodGlucoseMgDl: nil,
                    externalWaterMl: externalWater,
                    waterTotalMl: externalWater,
                    dietaryEnergyKcal: energyKcal,
                    dietaryCarbsG: carbsG,
                    dietaryProteinG: proteinG,
                    dietaryFatG: fatG,
                    dietaryFiberG: fiberG,
                    dietarySugarG: sugarG,
                    dietarySodiumMg: sodiumMg,
                    dietaryCaffeineMg: caffeineMg
                )
            )
        }
        return rows
    }

    private static func rounded(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif
