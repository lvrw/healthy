import Foundation
import Testing

struct NutritionScoringTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var todayDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
    }

    private func date(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: todayDate)!
    }

    /// 具备全部 7 类原有数据源的快照，便于验证 nutrition 是「额外」的一维。
    private func baseSnapshot(_ offset: Int) -> DailySnapshot {
        let day = date(offset)
        return DailySnapshot(
            dayKey: DayKey.key(for: day, calendar: calendar),
            date: day,
            hrvSDNN: 46,
            restingHR: 58,
            respiratoryRate: 14.5,
            spo2: 97.5,
            wristTempC: 36.2,
            sleepTotalH: 7.5,
            sleepEfficiency: 0.93,
            deepH: 1.2,
            remH: 1.6,
            steps: 8_000,
            activeEnergy: 480,
            daylightMinutes: 45,
            sleepMidpointMinutes: 180,
            bodyMassKg: 70,
            bodyFatPct: 18
        )
    }

    private func balancedNutrition() -> NutritionValues {
        NutritionValues(
            waterTotalMl: 1_500,
            energyKcal: 2_100,
            carbsG: 250,
            proteinG: 70,
            fatG: 70,
            fiberG: 28,
            sugarG: 40,
            sodiumMg: 2_000,
            caffeineMg: 100
        )
    }

    // MARK: - NutritionEngine

    @Test func waterScoreFollowsTargetAndDoesNotPunishMildExcess() {
        #expect(NutritionEngine.waterScore(1_500) == 100)
        #expect(NutritionEngine.waterScore(nil) == nil)
        #expect(NutritionEngine.waterScore(0) == 40)
        // 2 倍目标只扣 12 分，超过 3 倍也封顶在 20 分。
        #expect(NutritionEngine.waterScore(3_000) == 88)
        #expect(NutritionEngine.waterScore(10_000) == 80)
    }

    @Test func balancedDietScoresAboveSugarAndSodiumHeavyDiet() {
        let balanced = NutritionEngine.dietScore(balancedNutrition())!
        let junk = NutritionEngine.dietScore(NutritionValues(
            energyKcal: 3_200,
            carbsG: 400,
            proteinG: 30,
            fatG: 140,
            fiberG: 6,
            sugarG: 130,
            sodiumMg: 5_000,
            caffeineMg: 450
        ))!
        #expect(balanced > 85)
        #expect(junk < balanced - 20)
    }

    @Test func missingNutritionLeavesScoreNil() {
        #expect(NutritionEngine.score(NutritionValues()) == nil)
        #expect(NutritionEngine.dietScore(NutritionValues()) == nil)
        #expect(NutritionEngine.combinedScore(NutritionValues(), regularity: nil) == nil)
    }

    /// 统一饮食评分：质量 70% + 规律 30%；缺任一分量时按剩余权重归一化。
    @Test func combinedScoreWeightsQualityAndRegularity() {
        let quality = NutritionEngine.dietScore(balancedNutrition())!
        let regularity = 80.0
        let both = NutritionEngine.combinedScore(balancedNutrition(), regularity: regularity)!
        #expect(abs(both - (quality * 0.7 + regularity * 0.3)) < 1e-9)

        // 只有饮食质量：归一化后应等于质量分本身，而不是被 0.7 折算。
        let qualityOnly = NutritionEngine.combinedScore(balancedNutrition(), regularity: nil)!
        #expect(abs(qualityOnly - quality) < 1e-9)

        // 只有规律饮食：归一化后应等于规律分本身。
        let regularityOnly = NutritionEngine.combinedScore(NutritionValues(), regularity: regularity)!
        #expect(abs(regularityOnly - regularity) < 1e-9)
    }

    @Test func waterAloneStillProducesANutritionScore() {
        let score = NutritionEngine.score(NutritionValues(waterTotalMl: 1_500))
        #expect(score != nil)
        #expect(NutritionEngine.dietScore(NutritionValues(waterTotalMl: 1_500)) == nil)
    }

    @Test func averageIgnoresMissingValues() {
        let average = NutritionValues.average([
            NutritionValues(waterTotalMl: 1_000, fiberG: 20),
            NutritionValues(waterTotalMl: 2_000),
            NutritionValues(),
        ])
        #expect(average.waterTotalMl == 1_500)
        #expect(average.fiberG == 20)
        #expect(average.energyKcal == nil)
    }

    // MARK: - 今日状态（Readiness）

    @Test func nutritionOnlyChangesReadinessWhenDataExists() {
        let history = (-30..<0).map { baseSnapshot($0) }
        let today = baseSnapshot(0)
        let plain = ReadinessEngine.evaluate(today: today, history: history, calendar: calendar)
        #expect(plain.components.nutrition == nil)
        #expect(plain.missing.contains(.nutrition))
        #expect(plain.score != nil)

        var enriched = today
        enriched.externalWaterMl = 600
        enriched.localWaterMl = 400
        enriched.waterTotalMl = 1_000
        enriched.dietaryEnergyKcal = 2_100
        enriched.dietaryCarbsG = 250
        enriched.dietaryProteinG = 70
        enriched.dietaryFatG = 70
        enriched.dietaryFiberG = 28
        enriched.dietarySugarG = 40
        enriched.dietarySodiumMg = 2_000
        enriched.dietaryCaffeineMg = 100
        let result = ReadinessEngine.evaluate(today: enriched, history: history, calendar: calendar)
        #expect(result.components.nutrition != nil)
        #expect(!result.missing.contains(.nutrition))
        #expect(result.completeness == plain.completeness + 1)
        #expect(result.score != plain.score)
    }

    @Test func externalAndLocalWaterAreCombinedNotDuplicated() {
        var snapshot = baseSnapshot(0)
        snapshot.externalWaterMl = 900
        snapshot.localWaterMl = 600
        snapshot.waterTotalMl = 1_500
        let values = NutritionValues.from(snapshot)
        #expect(values.waterTotalMl == 1_500)
        #expect(NutritionEngine.waterScore(values.waterTotalMl) == 100)
        #expect(values.hasData)
    }

    // MARK: - 身体年龄

    @Test func bodyAgeAddsNutritionFactorsOnlyWhenSyncedDataExists() {
        let norm = BodyAgeEngine.vo2Norm(age: 35, male: true)
        let base = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            vo2Max: norm,
            restingHR: 65,
            sleepHours: 7.5,
            weeklyExerciseMinutes: 150,
            leanBodyMassKg: nil
        )
        let plain = BodyAgeEngine.evaluate(base)
        #expect(plain.adjustments.count == 4)
        #expect(plain.adjustments.allSatisfy { $0.years == 0 })

        var enriched = base
        enriched.nutrition = balancedNutrition()
        let result = BodyAgeEngine.evaluate(enriched)
        #expect(result.adjustments.count == 6)
        #expect(result.adjustments.contains { $0.factor == .hydration })
        #expect(result.adjustments.contains { $0.factor == .dietQuality })
        #expect(result.adjustments.first { $0.factor == .hydration }?.years == 0)
    }

    @Test func lowWaterIntakeAddsYearsWithinCap() {
        var input = BodyAgeInput(chronologicalAge: 40, isMale: true)
        input.nutrition = NutritionValues(waterTotalMl: 200)
        let result = BodyAgeEngine.evaluate(input)
        let hydration = result.adjustments.first { $0.factor == .hydration }
        #expect(hydration != nil)
        #expect(hydration!.years > 0)
        #expect(hydration!.years <= 1.2)
        // 只有饮水、没有膳食数据时不应凭空生成饮食质量维度。
        #expect(!result.adjustments.contains { $0.factor == .dietQuality })
    }

    @Test func bodyAgeInputAveragesSevenDayNutrition() {
        let snapshots = (-6...0).map { offset -> DailySnapshot in
            var snapshot = baseSnapshot(offset)
            // 3 天 1000、3 天 2000、当天 1500 → 7 日均值恰好 1500。
            let water: Double = offset == 0
                ? 1_500
                : (offset.isMultiple(of: 2) ? 1_000 : 2_000)
            snapshot.externalWaterMl = water
            snapshot.waterTotalMl = water
            return snapshot
        }
        // 以「次日回看」的口径验证 7 日均值：asOf 已是完整日，不做日内折算。
        let nextDay = calendar.date(byAdding: .day, value: 1, to: todayDate)!
        let input = BodyAgeEngine.input(
            asOf: todayDate,
            snapshots: snapshots,
            chronologicalAge: 35,
            isMale: true,
            now: nextDay,
            calendar: calendar
        )
        #expect(input.nutrition.waterTotalMl == 1_500)
        #expect(!input.nutrition.hasDietData)
    }

    @Test func nutritionScoreUsesStagedTargetInsteadOfFullDayTarget() {
        // 20% 清醒窗口下 300 ml 恰好是 1500 ml 的阶段目标，应得满分。
        #expect(NutritionEngine.waterScore(300, progress: 0.2) == 100)
        // 仍在睡眠 / 进度太低时不评价累计量，避免刚起床就判「今日饮水偏低」。
        #expect(NutritionEngine.waterScore(0, progress: 0.05) == nil)
        #expect(NutritionEngine.score(NutritionValues(waterTotalMl: 0), progress: 0.05) == nil)
    }

    @Test func stressFollowsDietScoreDirection() {
        let history = (-30..<0).map { baseSnapshot($0) }
        let today = baseSnapshot(0)
        let plain = StressEngine.evaluate(today: today, history: history, calendar: calendar)
        func score(with nutrition: NutritionValues) -> Double? {
            var snapshot = today
            snapshot.dietaryCarbsG = nutrition.carbsG
            snapshot.dietaryProteinG = nutrition.proteinG
            snapshot.dietaryFatG = nutrition.fatG
            snapshot.dietaryFiberG = nutrition.fiberG
            snapshot.dietarySugarG = nutrition.sugarG
            return StressEngine.evaluate(today: snapshot, history: history, calendar: calendar).score
        }
        guard let plainScore = plain.score,
              let good = score(with: balancedNutrition()),
              let poor = score(with: NutritionValues(carbsG: 420, proteinG: 25, fatG: 130, fiberG: 4, sugarG: 130))
        else {
            Issue.record("压力评分基线不足")
            return
        }
        #expect(good < plainScore)
        #expect(poor > plainScore)
    }

    @Test func bodyAgeInputProratesUnfinishedTodayAndSkipsSleepHours() {
        let snapshots = (-6...0).map { offset -> DailySnapshot in
            var snapshot = baseSnapshot(offset)
            snapshot.externalWaterMl = 1_500
            snapshot.waterTotalMl = 1_500
            return snapshot
        }
        // 中午 12:00：清醒窗口只过了一部分，今日 1500 ml 折算为全天预估后
        // 7 日均值应高于 1500，而不是被当成已完成的全天值。
        let noon = BodyAgeEngine.input(
            asOf: todayDate, snapshots: snapshots,
            chronologicalAge: 35, isMale: true, now: todayDate, calendar: calendar
        )
        #expect(noon.nutrition.waterTotalMl! > 1_500)

        // 凌晨 3:00 仍在睡眠：今日累计量直接排除，只取过去 6 个完整日。
        let night = calendar.date(bySettingHour: 3, minute: 0, second: 0, of: todayDate)!
        let asleep = BodyAgeEngine.input(
            asOf: todayDate, snapshots: snapshots,
            chronologicalAge: 35, isMale: true, now: night, calendar: calendar
        )
        #expect(asleep.nutrition.waterTotalMl == 1_500)
    }
}
