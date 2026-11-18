import Foundation
import Testing

struct ScoringTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var todayDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12)) ?? .now
    }

    private func snapshot(
        offset: Int,
        hrv: Double? = 45,
        rhr: Double? = 58,
        sleep: Double? = 7.5,
        efficiency: Double? = 0.93,
        deep: Double? = 1.2,
        rem: Double? = 1.6,
        steps: Double? = 8000,
        energy: Double? = 500,
        resp: Double? = 14.5,
        spo2: Double? = 97.5,
        temp: Double? = 36.2,
        vo2: Double? = nil,
        speed: Double? = nil,
        steadiness: Double? = nil,
        distance: Double? = nil,
        flights: Double? = nil,
        daylight: Double? = nil,
        mindful: Double? = nil,
        valence: Double? = nil,
        midpoint: Double? = nil,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        lean: Double? = nil,
        systolic: Double? = nil,
        diastolic: Double? = nil,
        basalTemp: Double? = nil,
        glucose: Double? = nil
    ) -> DailySnapshot {
        let date = calendar.date(byAdding: .day, value: offset, to: todayDate) ?? todayDate
        return DailySnapshot(
            dayKey: DayKey.key(for: date, calendar: calendar),
            date: date,
            hrvSDNN: hrv,
            restingHR: rhr,
            respiratoryRate: resp,
            spo2: spo2,
            wristTempC: temp,
            sleepTotalH: sleep,
            sleepEfficiency: efficiency,
            deepH: deep,
            remH: rem,
            steps: steps,
            activeEnergy: energy,
            vo2Max: vo2,
            walkingSpeedMps: speed,
            walkingSteadinessPct: steadiness,
            flightsClimbed: flights,
            distanceWalkingKm: distance,
            daylightMinutes: daylight,
            mindfulMinutes: mindful,
            stateOfMindValence: valence,
            sleepMidpointMinutes: midpoint,
            bodyMassKg: weight,
            bodyFatPct: bodyFat,
            leanBodyMassKg: lean,
            systolicBP: systolic,
            diastolicBP: diastolic,
            basalBodyTempC: basalTemp,
            bloodGlucoseMgDl: glucose
        )
    }

    private func history(
        days: Int,
        hrv: Double? = 45,
        rhr: Double? = 58,
        sleep: Double? = 7.5,
        efficiency: Double? = 0.93,
        deep: Double? = 1.2,
        rem: Double? = 1.6,
        steps: Double? = 8000,
        energy: Double? = 500,
        resp: Double? = 14.5,
        spo2: Double? = 97.5,
        temp: Double? = 36.2,
        midpoint: Double? = nil,
        daylight: Double? = nil,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        lean: Double? = nil,
        systolic: Double? = nil,
        diastolic: Double? = nil,
        vo2: Double? = nil
    ) -> [DailySnapshot] {
        (1...days).map {
            snapshot(
                offset: -$0,
                hrv: hrv,
                rhr: rhr,
                sleep: sleep,
                efficiency: efficiency,
                deep: deep,
                rem: rem,
                steps: steps,
                energy: energy,
                resp: resp,
                spo2: spo2,
                temp: temp,
                vo2: vo2,
                daylight: daylight,
                midpoint: midpoint,
                weight: weight,
                bodyFat: bodyFat,
                lean: lean,
                systolic: systolic,
                diastolic: diastolic
            )
        }
    }

    @Test func baselineRequiresSevenDays() {
        let history = history(days: 6)
        let result = ReadinessEngine.evaluate(today: snapshot(offset: 0), history: history, calendar: calendar)
        #expect(result.baselineDays == 6)
        #expect(result.confidence == .low)
        #expect(result.score != nil)
    }

    @Test func insufficientBaselineYieldsPlaceholder() {
        let history = history(days: 2)
        let result = ReadinessEngine.evaluate(today: snapshot(offset: 0), history: history, calendar: calendar)
        #expect(result.baselineDays == 2)
        #expect(result.confidence == .insufficient)
        #expect(result.score == nil)
    }

    @Test func missingSourcesRenormalizeWeights() {
        let history = (1...8).map {
            snapshot(
                offset: -$0, hrv: nil, rhr: 58, sleep: nil, efficiency: nil, deep: nil, rem: nil,
                steps: nil, energy: nil, resp: nil, spo2: nil, temp: nil
            )
        }
        let today = snapshot(
            offset: 0, hrv: nil, rhr: nil, sleep: 7.5, efficiency: nil, deep: nil, rem: nil,
            steps: nil, energy: nil, resp: nil, spo2: nil, temp: nil
        )
        let result = ReadinessEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(result.completeness == 1)
        #expect(result.missing.contains(.hrv))
        #expect(result.missing.contains(.activity))
        #expect(result.components.autonomic == nil)
        #expect(result.components.load == nil)
        #expect(result.components.vitals == nil)
        #expect(result.components.circadian == nil)
        #expect(result.components.fitnessBody == nil)
        #expect(result.confidence == .low)
        #expect(abs((result.score ?? 0) - (result.components.sleep ?? -1)) < 0.0001)
    }

    @Test func shortSleepLowersReadiness() {
        let history = history(days: 8)
        let short = ReadinessEngine.evaluate(today: snapshot(offset: 0, sleep: 5.0), history: history, calendar: calendar)
        let normal = ReadinessEngine.evaluate(today: snapshot(offset: 0, sleep: 8.0), history: history, calendar: calendar)
        #expect((short.score ?? 0) < (normal.score ?? 0))
    }

    @Test func extremeHRVIsClamped() {
        let history = (1...8).map {
            snapshot(
                offset: -$0, hrv: 45, rhr: nil, sleep: nil, efficiency: nil, deep: nil, rem: nil,
                steps: nil, energy: nil, resp: nil, spo2: nil, temp: nil
            )
        }
        let today = snapshot(
            offset: 0, hrv: 5, rhr: nil, sleep: nil, efficiency: nil, deep: nil, rem: nil,
            steps: nil, energy: nil, resp: nil, spo2: nil, temp: nil
        )
        let result = ReadinessEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(result.components.autonomic != nil)
        #expect(abs((result.components.autonomic ?? -1) - 5) < 0.0001)
    }

    @Test func highStressScenarioMapsToHighLevel() {
        let history = history(days: 8)
        let today = snapshot(offset: 0, hrv: 5, sleep: 8.0)
        let result = StressEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(result.level == .high)
        #expect((result.score ?? 0) >= 70)
    }

    @Test func nanValuesAreIgnored() {
        let history = history(days: 8)
        let today = snapshot(
            offset: 0, hrv: .nan, rhr: nil, sleep: .infinity, efficiency: nil, deep: nil, rem: nil
        )
        let result = ReadinessEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(result.components.autonomic == nil)
        #expect(result.components.sleep == nil)
    }

    @Test func stressSleepNeedsThreeNights() {
        let history = (1...8).map { snapshot(offset: -$0, sleep: nil) }
        let today = snapshot(offset: 0, sleep: 8.0)
        let result = StressEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(result.components.sleep == nil)
    }

    @Test func dayKeyRoundTrips() {
        let key = DayKey.key(for: todayDate, calendar: calendar)
        #expect(key == "2026-10-30")
        #expect(DayKey.date(from: key, calendar: calendar) != nil)
    }

    @Test func daylightAndRegularityDriveCircadian() {
        let goodHistory = history(days: 8, midpoint: 180, daylight: 60)
        let good = ReadinessEngine.evaluate(
            today: snapshot(offset: 0, daylight: 60, midpoint: 180),
            history: goodHistory,
            calendar: calendar
        )
        let poor = ReadinessEngine.evaluate(
            today: snapshot(offset: 0, daylight: 0, midpoint: 320),
            history: goodHistory,
            calendar: calendar
        )
        #expect((good.components.circadian ?? 0) > (poor.components.circadian ?? 0))
    }

    @Test func irregularSleepMidpointRaisesStress() {
        let history = history(days: 8, midpoint: 180, daylight: 60)
        let regular = StressEngine.evaluate(
            today: snapshot(offset: 0, daylight: 60, midpoint: 180),
            history: history,
            calendar: calendar
        )
        let irregular = StressEngine.evaluate(
            today: snapshot(offset: 0, daylight: 0, midpoint: 320),
            history: history,
            calendar: calendar
        )
        #expect((irregular.components.circadian ?? 0) > (regular.components.circadian ?? 0))
    }

    @Test func weightChangeLowersFitnessBody() {
        let history = history(days: 8, weight: 70, bodyFat: 18, lean: 57)
        let stable = ReadinessEngine.evaluate(
            today: snapshot(offset: 0, weight: 70, bodyFat: 18, lean: 57),
            history: history,
            calendar: calendar
        )
        let changed = ReadinessEngine.evaluate(
            today: snapshot(offset: 0, weight: 74, bodyFat: 19, lean: 56),
            history: history,
            calendar: calendar
        )
        #expect((changed.components.fitnessBody ?? 100) < (stable.components.fitnessBody ?? 0))
    }

    @Test func highBloodPressureLowersVitals() {
        let history = history(days: 8, systolic: 115, diastolic: 75)
        let normal = ReadinessEngine.evaluate(
            today: snapshot(offset: 0, systolic: 115, diastolic: 75),
            history: history,
            calendar: calendar
        )
        let high = ReadinessEngine.evaluate(
            today: snapshot(offset: 0, systolic: 150, diastolic: 95),
            history: history,
            calendar: calendar
        )
        #expect((high.components.vitals ?? 100) < (normal.components.vitals ?? 0))
    }

    @Test func negativeMoodRaisesStressScore() {
        let history = history(days: 8)
        let negative = StressEngine.evaluate(
            today: snapshot(offset: 0, valence: -0.6),
            history: history,
            calendar: calendar
        )
        let positive = StressEngine.evaluate(
            today: snapshot(offset: 0, valence: 0.6),
            history: history,
            calendar: calendar
        )
        #expect((negative.components.mood ?? 0) > (positive.components.mood ?? 0))
    }

    @Test func sparseBaselineNeedsThreeValues() {
        let two = (1...2).map { snapshot(offset: -$0, vo2: 42) }
        let twoResult = Baseline.compute(history: two, today: snapshot(offset: 0), calendar: calendar)
        #expect(twoResult.vo2Max == nil)

        let three = (1...3).map { snapshot(offset: -$0, vo2: 42) }
        let threeResult = Baseline.compute(history: three, today: snapshot(offset: 0), calendar: calendar)
        #expect(threeResult.vo2Max != nil)
    }
}
