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

    // MARK: - 数据不全 / 手动跳过

    /// 手动标记某项后，对应分量直接跳过（即使历史数据齐全也不兜底），
    /// 其余完整分量不受影响，并在结果中标识为手动跳过。
    @Test func manualIncompleteSkipsComponentWithoutAffectingOthers() {
        let history = history(days: 10, steps: 8000, energy: 500)
        let today = snapshot(offset: 0, steps: 8000, energy: 500)
        let baseline = ReadinessEngine.evaluate(today: today, history: history, calendar: calendar)
        let marked = ReadinessEngine.evaluate(
            today: today, history: history, calendar: calendar,
            manualIncomplete: [.activity]
        )
        #expect(baseline.components.load != nil)
        #expect(marked.components.load == nil)
        #expect(marked.components.sleep == baseline.components.sleep)
        #expect(marked.components.autonomic == baseline.components.autonomic)
        #expect(marked.components.vitals == baseline.components.vitals)
        #expect(marked.score != nil)
        #expect(marked.skipped.contains(where: { $0.source == .activity && $0.reason == .manual }))
        #expect(marked.completeness == baseline.completeness - 1)
    }

    /// 系统判定数据不全的项被明确标识为 incomplete。
    @Test func autoMissingIsIdentifiedAsIncomplete() {
        let history = history(days: 10)
        let today = snapshot(offset: 0, sleep: nil, efficiency: nil, deep: nil, rem: nil)
        let result = ReadinessEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(result.components.sleep == nil)
        #expect(result.skipped.contains(where: { $0.source == .sleep && $0.reason == .incomplete }))
    }

    /// 体能身体属于稀疏读数：今天没测，但近 28 天有体重记录时不应判为数据不全。
    @Test func sparseFitnessBodyReadingsCountAsAvailable() {
        let history = [
            snapshot(offset: -3, weight: 70),
            snapshot(offset: -2),
            snapshot(offset: -1),
        ]
        let result = ReadinessEngine.evaluate(
            today: snapshot(offset: 0), history: history, calendar: calendar
        )
        #expect(!result.missing.contains(.fitnessBody))
    }

    /// 超出 28 天窗口的旧读数不参与可用性判定。
    @Test func staleFitnessBodyReadingsStillMissing() {
        var history = (1...30).map { snapshot(offset: -$0) }
        history.append(snapshot(offset: -40, weight: 70))
        let result = ReadinessEngine.evaluate(
            today: snapshot(offset: 0), history: history, calendar: calendar
        )
        #expect(result.missing.contains(.fitnessBody))
    }

    /// 用户手动标记优先于系统判定，跳过原因展示为 manual。
    @Test func manualMarkTakesPrecedenceOverAutoMissing() {
        let history = history(days: 10)
        let today = snapshot(offset: 0, hrv: nil)
        let result = ReadinessEngine.evaluate(
            today: today, history: history, calendar: calendar,
            manualIncomplete: [.hrv]
        )
        #expect(result.skipped.contains(where: { $0.source == .hrv && $0.reason == .manual }))
        #expect(!result.skipped.contains(where: { $0.source == .hrv && $0.reason == .incomplete }))
    }

    /// 压力评分同样支持跳过对应分量，且只影响该项。
    @Test func stressManualIncompleteSkipsHRVOnly() {
        let history = history(days: 10)
        let today = snapshot(offset: 0)
        let baseline = StressEngine.evaluate(today: today, history: history, calendar: calendar)
        let marked = StressEngine.evaluate(
            today: today, history: history, calendar: calendar,
            manualIncomplete: [.hrv]
        )
        #expect(baseline.components.hrv != nil)
        #expect(marked.components.hrv == nil)
        #expect(marked.components.restingHR == baseline.components.restingHR)
        #expect(marked.skipped.contains(where: { $0.source == .hrv && $0.reason == .manual }))
    }

    /// 全部数据源被跳过时无法评分：总分 nil、完成度 0、跳过清单覆盖所有类别。
    @Test func allSourcesSkippedYieldsNilScore() {
        let history = history(days: 10)
        let today = snapshot(offset: 0)
        let result = ReadinessEngine.evaluate(
            today: today, history: history, calendar: calendar,
            manualIncomplete: Set(MetricSource.allCases)
        )
        #expect(result.score == nil)
        #expect(result.completeness == 0)
        #expect(result.skipped.count == MetricSource.allCases.count)
    }

    /// 跳过原因可编码进 DailyScore.skippedJSON 并原样还原。
    @Test func sourceSkipRoundTripsThroughJSON() {
        let skips = [
            SourceSkip(source: .sleep, reason: .incomplete),
            SourceSkip(source: .nutrition, reason: .manual),
        ]
        let data = try? JSONEncoder().encode(skips)
        let decoded = data.flatMap { try? JSONDecoder().decode([SourceSkip].self, from: $0) }
        #expect(decoded == skips)
    }

    /// 手动标记按 dayKey 隔离，取消标记后不再影响评分。
    @Test func incompleteMarkerIsIsolatedByDayKey() {
        let day = "2099-01-01"
        let otherDay = "2099-01-02"
        let source = MetricSource.activity
        IncompleteSourceMarker.clear(dayKey: day)
        defer { IncompleteSourceMarker.clear(dayKey: day) }

        IncompleteSourceMarker.set(source, marked: true, dayKey: day)
        #expect(IncompleteSourceMarker.isMarked(source, dayKey: day))
        #expect(!IncompleteSourceMarker.isMarked(source, dayKey: otherDay))

        IncompleteSourceMarker.set(source, marked: false, dayKey: day)
        #expect(!IncompleteSourceMarker.isMarked(source, dayKey: day))
    }

    /// 配置历史日期的不全标记后，只有该日评分受影响，今天与其他历史日保持不变。
    @Test func historicalDayMarkDoesNotAffectToday() {
        let history = history(days: 10, steps: 8000, energy: 500)
        let today = snapshot(offset: 0, steps: 8000, energy: 500)
        let past = history[0]
        IncompleteSourceMarker.clear(dayKey: past.dayKey)
        defer { IncompleteSourceMarker.clear(dayKey: past.dayKey) }
        IncompleteSourceMarker.set(.activity, marked: true, dayKey: past.dayKey)

        let pastResult = ReadinessEngine.evaluate(
            today: past, history: Array(history.dropFirst()), calendar: calendar,
            manualIncomplete: IncompleteSourceMarker.markedSources(for: past.dayKey)
        )
        let todayResult = ReadinessEngine.evaluate(
            today: today, history: history, calendar: calendar,
            manualIncomplete: IncompleteSourceMarker.markedSources(for: today.dayKey)
        )

        #expect(pastResult.components.load == nil)
        #expect(pastResult.skipped.contains(where: { $0.source == .activity && $0.reason == .manual }))
        #expect(todayResult.components.load != nil)
        #expect(!todayResult.skipped.contains(where: { $0.reason == .manual }))
    }
}
