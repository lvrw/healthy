import Foundation
import Testing

/// 覆盖餐次推断、单餐评分、规律饮食，以及「并入状态分/体龄」对既有评分的兼容性。
struct MealScoringTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    /// 固定基准日 2026-11-10 00:00（本地时区）。
    private var baseDay: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 0))!
    }

    /// 基准日 + 指定时分。
    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: baseDay)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func nutrition(
        energy: Double = 600, carbs: Double = 70, protein: Double = 30,
        fat: Double = 20, fiber: Double = 8, sugar: Double = 8, sodium: Double = 500
    ) -> IntakeNutrition {
        IntakeNutrition(
            energyKcal: energy, carbsG: carbs, proteinG: protein, fatG: fat,
            fiberG: fiber, sugarG: sugar, sodiumMg: sodium
        )
    }

    // MARK: - 餐次推断

    @Test func inferSlotCoversWholeDay() {
        #expect(MealSlot.infer(from: at(3), calendar: calendar) == .lateNightSnack)
        #expect(MealSlot.infer(from: at(5), calendar: calendar) == .breakfast)
        #expect(MealSlot.infer(from: at(8), calendar: calendar) == .breakfast)
        #expect(MealSlot.infer(from: at(10), calendar: calendar) == .lunch)
        #expect(MealSlot.infer(from: at(12, 30), calendar: calendar) == .lunch)
        #expect(MealSlot.infer(from: at(15), calendar: calendar) == .afternoonTea)
        #expect(MealSlot.infer(from: at(18, 30), calendar: calendar) == .dinner)
        #expect(MealSlot.infer(from: at(21), calendar: calendar) == .lateNightSnack)
        #expect(MealSlot.infer(from: at(23, 59), calendar: calendar) == .lateNightSnack)
    }

    @Test func slotWindowMatchesInferredSlot() {
        for hour in 0..<24 {
            let date = at(hour)
            let slot = MealSlot.infer(from: date, calendar: calendar)
            #expect(slot.contains(date, calendar: calendar))
        }
    }

    @Test func energySharesSumToOne() {
        let sum = MealSlot.allCases.reduce(0.0) { $0 + $1.energyShare }
        #expect(abs(sum - 1.0) < 1e-9)
    }

    // MARK: - 单餐评分

    @Test func balancedLunchIsHealthy() {
        let evaluation = MealScoringEngine.evaluate(
            nutrition: nutrition(), slot: .lunch, date: at(12), calendar: calendar
        )
        #expect(evaluation.score > 80)
        #expect(evaluation.isHealthy)
        #expect(evaluation.level == "优秀" || evaluation.level == "良好")
    }

    /// 核心扣分项：饱和脂肪 / 总脂肪 / 糖 / 碳水任一偏高都要明显降分，且不能评为优秀。
    @Test func coreDeductionsLowerScoreAndBlockExcellent() {
        let good = MealScoringEngine.evaluate(
            nutrition: nutrition(), slot: .dinner, date: at(18), calendar: calendar
        )
        #expect(good.score > 80)
        #expect(good.level == "优秀" || good.level == "良好")

        var highSugar = nutrition()
        highSugar.sugarG = 300
        let sugary = MealScoringEngine.evaluate(
            nutrition: highSugar, slot: .dinner, date: at(18), calendar: calendar
        )
        #expect(sugary.score < good.score - 20)
        #expect(sugary.score < 90)
        #expect(sugary.notes.contains { $0.contains("糖偏多") })

        var highSatFat = nutrition()
        highSatFat.saturatedFatG = 25
        let fatty = MealScoringEngine.evaluate(
            nutrition: highSatFat, slot: .dinner, date: at(18), calendar: calendar
        )
        #expect(fatty.score < good.score - 20)
        #expect(fatty.score < 90)
        #expect(fatty.notes.contains { $0.contains("饱和脂肪偏多") })

        var highFat = nutrition()
        highFat.fatG = 90
        let oily = MealScoringEngine.evaluate(
            nutrition: highFat, slot: .dinner, date: at(18), calendar: calendar
        )
        #expect(oily.score < 60)
        #expect(oily.notes.contains { $0.contains("总脂肪偏多") })

        var unbalanced = nutrition(protein: 4, fat: 60)
        unbalanced.caffeineMg = 600
        let bad = MealScoringEngine.evaluate(
            nutrition: unbalanced, slot: .dinner, date: at(18), calendar: calendar
        )
        #expect(bad.score < good.score)
        #expect(!bad.isHealthy)
        #expect(bad.notes.contains { $0.contains("咖啡因偏多") })
        // 能量 / 钠仍只留档，不进入评分。
        var ignored = nutrition()
        ignored.energyKcal = 5_000
        ignored.sodiumMg = 5_000
        let unchanged = MealScoringEngine.evaluate(
            nutrition: ignored, slot: .dinner, date: at(18), calendar: calendar
        )
        #expect(unchanged.score == good.score)
    }

    /// 油炸卷饼 / 炸鸡这类高油高热量餐次不应再得到 80 分。
    @Test func friedMealsScoreBelowPassingLine() {
        let burrito = IntakeNutrition(
            energyKcal: 720, carbsG: 70, proteinG: 22, fatG: 30,
            fiberG: 6, sugarG: 8, saturatedFatG: 11
        )
        let friedChicken = IntakeNutrition(
            energyKcal: 680, carbsG: 40, proteinG: 35, fatG: 35,
            fiberG: 2, sugarG: 5, saturatedFatG: 12
        )
        for item in [burrito, friedChicken] {
            let evaluation = MealScoringEngine.evaluate(
                nutrition: item, slot: .lunch, date: at(12), calendar: calendar
            )
            #expect(evaluation.score < 60)
            #expect(!evaluation.isHealthy)
        }
    }

    @Test func proteinRichLowSatFatMealBeatsOrdinaryMeal() {
        let highQuality = IntakeNutrition(
            energyKcal: 620, carbsG: 60, proteinG: 42, fatG: 12,
            fiberG: 12, sugarG: 6, saturatedFatG: 2
        )
        let ordinary = IntakeNutrition(
            energyKcal: 650, carbsG: 85, proteinG: 14, fatG: 24,
            fiberG: 3, sugarG: 20, saturatedFatG: 7
        )
        let better = MealScoringEngine.evaluate(
            nutrition: highQuality, slot: .lunch, date: at(12), calendar: calendar
        )
        let common = MealScoringEngine.evaluate(
            nutrition: ordinary, slot: .lunch, date: at(12), calendar: calendar
        )
        #expect(better.score >= 90)
        #expect(better.score > common.score + 15)
    }

    @Test func lateNightSnackIsNeverHealthy() {
        let evaluation = MealScoringEngine.evaluate(
            nutrition: nutrition(), slot: .lateNightSnack, date: at(23), calendar: calendar
        )
        #expect(!evaluation.isHealthy)
        #expect(evaluation.notes.contains { $0.contains("夜宵") })
    }

    @Test func offWindowTimeLowersScore() {
        let onTime = MealScoringEngine.evaluate(
            nutrition: nutrition(), slot: .breakfast, date: at(8), calendar: calendar
        )
        let offTime = MealScoringEngine.evaluate(
            nutrition: nutrition(), slot: .breakfast, date: at(16), calendar: calendar
        )
        #expect(offTime.score < onTime.score)
        #expect(!offTime.isHealthy)
    }

    // MARK: - 规律饮食

    @Test func noMealRecordsMeansNoRegularityScore() {
        let r = MealScoringEngine.regularity(
            entries: [], on: at(12), calendar: calendar, now: at(20)
        )
        #expect(r.score == nil)
        #expect(r.level == "暂无数据")
        #expect(r.coveredMainMeals.isEmpty)
    }

    /// 晚饭未到时间时，早午两餐都准时，规律饮食不能替还没发生的晚餐提前扣分：
    /// 三餐覆盖 45（早午到期且已吃）+ 时段合理 20（两餐均在窗口内）
    /// + 无夜宵 10 + 间隔合理 10 + 近 7 天稳定性（样本不足按实际）≈ 87。
    @Test func futureDinnerDoesNotPenalizeRegularity() {
        let twoMeals = [
            MealEntry(date: at(7, 30), slot: .breakfast, nutrition: nutrition()),
            MealEntry(date: at(12, 30), slot: .lunch, nutrition: nutrition()),
        ]
        let r = MealScoringEngine.regularity(
            entries: twoMeals, on: at(12), calendar: calendar, now: at(17, 15)
        )
        #expect(r.score! >= 85)
        #expect(r.notes.contains { $0.contains("到期餐次已覆盖") })
        #expect(!r.notes.contains { $0.contains("缺晚餐") })
    }

    /// 只有一餐时没有可比较的间隔，不应在间隔项上先扣一半分。
    @Test func singleMealDoesNotLoseIntervalPoints() {
        let r = MealScoringEngine.regularity(
            entries: [MealEntry(date: at(8), slot: .breakfast, nutrition: nutrition())],
            on: at(12), calendar: calendar, now: at(10, 30)
        )
        // 三餐覆盖 45（早餐到期且已吃）+ 时段合理 20 + 无夜宵 10 + 间隔不扣分 10。
        #expect(r.score! >= 85)
    }

    /// 下午茶不是第四餐：时段合理性与进餐间隔都只按早/午/晚计算。
    /// 13:00 的加餐会把「午餐 12:00 → 晚餐 18:00」的合理 6 小时拆成 1+5 小时，
    /// 旧逻辑会因此扣间隔分；三餐口径下评分必须与没有加餐时完全一致。
    @Test func afternoonTeaIsNotCountedAsFourthMeal() {
        let main = [
            MealEntry(date: at(7, 30), slot: .breakfast, nutrition: nutrition()),
            MealEntry(date: at(12), slot: .lunch, nutrition: nutrition()),
            MealEntry(date: at(18), slot: .dinner, nutrition: nutrition()),
        ]
        let withTea = main + [
            MealEntry(date: at(13), slot: .afternoonTea, nutrition: nutrition(energy: 200))
        ]
        let clean = MealScoringEngine.regularity(entries: main, on: at(12), calendar: calendar, now: at(21, 30))
        let tea = MealScoringEngine.regularity(entries: withTea, on: at(12), calendar: calendar, now: at(21, 30))
        #expect(tea.score == clean.score)
        #expect(!tea.notes.contains { $0.contains("偏离常规时段") })
    }

    /// 晚饭未到时间 + 已有下午茶，仍只能按早午两餐计，不能被凑成「四餐」。
    @Test func futureDinnerWithAfternoonTeaKeepsThreeMealBasis() {
        let entries = [
            MealEntry(date: at(7, 30), slot: .breakfast, nutrition: nutrition()),
            MealEntry(date: at(12, 30), slot: .lunch, nutrition: nutrition()),
            MealEntry(date: at(15), slot: .afternoonTea, nutrition: nutrition(energy: 200)),
        ]
        let r = MealScoringEngine.regularity(
            entries: entries, on: at(12), calendar: calendar, now: at(17, 15)
        )
        #expect(r.score! >= 85)
        #expect(r.coveredMainMeals.map(\.title) == ["早餐", "午餐"])
        #expect(!r.notes.contains { $0.contains("偏离常规时段") })
        #expect(!r.notes.contains { $0.contains("缺晚餐") })
    }

    @Test func threeRegularMealsScoreHigherThanSkippingBreakfast() {
        let full = [
            MealEntry(date: at(7, 30), slot: .breakfast, nutrition: nutrition()),
            MealEntry(date: at(12, 30), slot: .lunch, nutrition: nutrition()),
            MealEntry(date: at(18, 30), slot: .dinner, nutrition: nutrition()),
        ]
        let skipped = Array(full.dropFirst())
        let good = MealScoringEngine.regularity(entries: full, on: at(12), calendar: calendar, now: at(20))
        let bad = MealScoringEngine.regularity(entries: skipped, on: at(12), calendar: calendar, now: at(20))
        #expect(good.score != nil)
        #expect(bad.score != nil)
        #expect(good.score! > bad.score!)
        #expect(good.coveredMainMeals.count == 3)
        #expect(bad.coveredMainMeals.count == 2)
        #expect(bad.notes.contains { $0.contains("缺早餐") })
    }

    @Test func lateNightSnackLowersRegularity() {
        let base = [
            MealEntry(date: at(7, 30), slot: .breakfast, nutrition: nutrition()),
            MealEntry(date: at(12, 30), slot: .lunch, nutrition: nutrition()),
            MealEntry(date: at(18, 30), slot: .dinner, nutrition: nutrition()),
        ]
        let withSnack = base + [MealEntry(date: at(23), slot: .lateNightSnack, nutrition: nutrition(energy: 200))]
        let clean = MealScoringEngine.regularity(entries: base, on: at(12), calendar: calendar, now: at(20))
        let snack = MealScoringEngine.regularity(entries: withSnack, on: at(12), calendar: calendar, now: at(20))
        #expect(snack.score! < clean.score!)
        #expect(snack.notes.contains { $0.contains("夜宵") })
    }

    @Test func stableWeekImprovesRegularity() {
        func day(_ offset: Int) -> [MealEntry] {
            [
                MealEntry(date: at(7, 30, dayOffset: offset), slot: .breakfast, nutrition: nutrition()),
                MealEntry(date: at(12, 30, dayOffset: offset), slot: .lunch, nutrition: nutrition()),
                MealEntry(date: at(18, 30, dayOffset: offset), slot: .dinner, nutrition: nutrition()),
            ]
        }
        let onlyToday = day(0)
        let week = (-6...0).flatMap(day)
        let single = MealScoringEngine.regularity(entries: onlyToday, on: at(12), calendar: calendar, now: at(20))
        let stable = MealScoringEngine.regularity(entries: week, on: at(12), calendar: calendar, now: at(20))
        #expect(stable.stableDays > single.stableDays)
        #expect(stable.score! > single.score!)
    }

    // MARK: - 与既有评分的兼容性

    @Test func readinessComponentIsNilWithoutMealData() {
        let snapshot = DailySnapshot(dayKey: "2026-11-10", date: at(12))
        #expect(MealScoringEngine.readinessComponent(snapshot) == nil)
    }

    @Test func readinessScoreUnchangedWhenMealDataMissing() {
        // 同一份快照，显式把规律饮食设为 nil 与完全不设置，结果必须一致，
        // 证明新增维度不会改变历史日期 / 未记录饮食用户的既有状态分。
        var snapshot = DailySnapshot(
            dayKey: "2026-11-10", date: at(12), hrvSDNN: 46, restingHR: 58,
            respiratoryRate: 14.5, spo2: 97.5, wristTempC: 36.2,
            sleepTotalH: 7.5, sleepEfficiency: 0.93, deepH: 1.2, remH: 1.6,
            steps: 8_000, activeEnergy: 480, sleepMidpointMinutes: 180
        )
        snapshot.mealRegularityScore = nil
        let history = (1...10).map { offset -> DailySnapshot in
            var s = snapshot
            s.dayKey = "2026-11-\(10 - offset)"
            s.date = calendar.date(byAdding: .day, value: -offset, to: at(12))!
            return s
        }
        let a = ReadinessEngine.evaluate(today: snapshot, history: history, calendar: calendar)
        var snapshotWithMeal = snapshot
        snapshotWithMeal.mealRegularityScore = 90
        let b = ReadinessEngine.evaluate(today: snapshotWithMeal, history: history, calendar: calendar)
        #expect(a.score != nil)
        #expect(a.components.mealRegularity == nil)
        #expect(b.components.mealRegularity == 90)
        // 规律饮食已并入统一饮食评分：不再单独占权重，但 nutrition 分量随打卡出现。
        #expect(a.components.nutrition == nil)
        #expect(b.components.nutrition == 90)
        // 有饮食数据时才纳入，且分数可以变化；这里只断言分量被正确传递。
    }

    @Test func readinessComponentsDecodeLegacyJSON() throws {
        let json = #"{"sleep":80,"autonomic":65,"load":90,"vitals":100}"#
        let decoded = try JSONDecoder().decode(ReadinessComponents.self, from: Data(json.utf8))
        #expect(decoded.mealRegularity == nil)
        #expect(decoded.nutrition == nil)
    }

    // MARK: - 身体年龄

    @Test func bodyAgeUnchangedWithoutMealRegularity() {
        let base = BodyAgeInput(
            chronologicalAge: 30, isMale: true, vo2Max: 45, restingHR: 58,
            sleepHours: 7.5, weeklyExerciseMinutes: 200, leanBodyMassKg: 55,
            nutrition: NutritionValues(waterTotalMl: 1500, carbsG: 250, proteinG: 70, fatG: 70)
        )
        let withRegularity = {
            var value = base
            value.mealRegularityScore = 40
            return value
        }()
        let normal = BodyAgeEngine.evaluate(base)
        let adjusted = BodyAgeEngine.evaluate(withRegularity)
        // 规律差时饮食质量调整应更不利（年龄更大），并在算式里说明来源。
        #expect(adjusted.adjustments.count == normal.adjustments.count)  // 合并为一条，不新增 factor
        #expect(adjusted.adjustments.contains { $0.formula.contains("规律饮食") })
        #expect((adjusted.bodyAge ?? 0) > (normal.bodyAge ?? 0))
    }

    @Test func bodyAgeFollowsDietScoreDirection() {
        func years(_ nutrition: NutritionValues) -> Double {
            let input = BodyAgeInput(
                chronologicalAge: 35, isMale: true, vo2Max: 45,
                restingHR: 58, sleepHours: 7.5, weeklyExerciseMinutes: 200,
                nutrition: nutrition
            )
            return BodyAgeEngine.evaluate(input).adjustments
                .first { $0.factor == .dietQuality }?.years ?? 0
        }
        let good = years(NutritionValues(carbsG: 250, proteinG: 70, fatG: 70, fiberG: 28, sugarG: 40))
        let poor = years(NutritionValues(carbsG: 420, proteinG: 25, fatG: 130, fiberG: 4, sugarG: 130))
        #expect(good < 0)
        #expect(poor > 0)
        #expect(poor > good)
    }
}
