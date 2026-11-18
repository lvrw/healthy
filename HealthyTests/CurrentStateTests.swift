import Foundation
import Testing

struct CurrentStateTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12)) ?? .now
    }

    private func snapshot(
        offset: Int,
        hrv: Double? = 45,
        rhr: Double? = 58,
        avgHR: Double? = 78
    ) -> DailySnapshot {
        let date = calendar.date(byAdding: .day, value: offset, to: now) ?? now
        return DailySnapshot(
            dayKey: DayKey.key(for: date, calendar: calendar),
            date: date,
            hrvSDNN: hrv,
            restingHR: rhr,
            avgHR: avgHR
        )
    }

    @Test func elevatedHeartRateRaisesInstantStress() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(
            heartRate: 90,
            heartRateAt: now.addingTimeInterval(-300),
            hrv: nil,
            hrvAt: nil,
            lastWorkoutEndAt: nil
        )
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 70,
            signals: signals,
            now: now,
            calendar: calendar
        )
        #expect((result.instantStress ?? 0) > 60)
        #expect(result.confidence == .fresh)
        #expect(result.instantStressLevel == .high)
    }

    @Test func recentWorkoutNeutralizesHeartRate() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(
            heartRate: 130,
            heartRateAt: now.addingTimeInterval(-300),
            hrv: nil,
            hrvAt: nil,
            lastWorkoutEndAt: now.addingTimeInterval(-600)
        )
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 70,
            signals: signals,
            now: now,
            calendar: calendar
        )
        #expect(result.instantStress == 50)
        #expect(result.note?.contains("运动后") == true)
        #expect(result.confidence == .fair)
    }

    @Test func activeHeartRateWithoutWorkoutSuppressesStress() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(
            heartRate: 130,
            heartRateAt: now.addingTimeInterval(-300),
            hrv: nil,
            hrvAt: nil,
            lastWorkoutEndAt: nil
        )
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 70,
            signals: signals,
            now: now,
            calendar: calendar
        )
        #expect(result.instantStress == nil)
        #expect(result.note?.contains("活动") == true)
        #expect(result.confidence == .fresh)
        #expect(result.currentState == 70)
    }

    @Test func staleHeartRateMarksConfidence() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(
            heartRate: 65,
            heartRateAt: now.addingTimeInterval(-90 * 60),
            hrv: nil,
            hrvAt: nil,
            lastWorkoutEndAt: nil
        )
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 70,
            signals: signals,
            now: now,
            calendar: calendar
        )
        #expect(result.confidence == .stale)
        #expect(result.note != nil)
    }

    @Test func missingHeartRateLeavesInstantStressEmpty() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(heartRate: nil, heartRateAt: nil, hrv: nil, hrvAt: nil, lastWorkoutEndAt: nil)
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 70,
            signals: signals,
            now: now,
            calendar: calendar
        )
        #expect(result.instantStress == nil)
        #expect(result.confidence == .unavailable)
        #expect(result.currentState == 70)
    }

    @Test func lowHRVRaisesStressWithoutHeartRate() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(
            heartRate: nil,
            heartRateAt: nil,
            hrv: 25,
            hrvAt: now.addingTimeInterval(-3600),
            lastWorkoutEndAt: nil
        )
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 70,
            signals: signals,
            now: now,
            calendar: calendar
        )
        #expect((result.instantStress ?? 0) > 80)
        #expect(result.confidence == .unavailable)
    }

    @Test func currentStateBlendsReadinessAndStress() {
        let history = (1...8).map { snapshot(offset: -$0) }
        let signals = CurrentSignals(
            heartRate: 57,
            heartRateAt: now.addingTimeInterval(-60),
            hrv: nil,
            hrvAt: nil,
            lastWorkoutEndAt: nil
        )
        let result = CurrentStateEngine.evaluate(
            today: snapshot(offset: 0),
            history: history,
            readiness: 80,
            signals: signals,
            now: now,
            calendar: calendar
        )
        let stress = result.instantStress ?? 0
        let expected = 0.6 * 80 + 0.4 * (100 - stress)
        #expect(abs((result.currentState ?? 0) - expected) < 0.0001)
    }
}
