import Foundation
import Testing

struct BodyAgeEngineTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var fixedNow: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!
    }

    @Test func balancedProfileKeepsBodyAgeAtChronological() {
        let norm = BodyAgeEngine.vo2Norm(age: 35, male: true)
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            vo2Max: norm,
            restingHR: 65,
            sleepHours: 7.5,
            weeklyExerciseMinutes: 150,
            leanBodyMassKg: nil
        )
        let result = BodyAgeEngine.evaluate(input)
        // 每项都落在参考带内：仍然逐项展示 0.0 岁，便于解释「为什么没变化」。
        #expect(result.adjustments.count == 4)
        #expect(result.adjustments.allSatisfy { $0.years == 0 })
        #expect(result.bodyAge == 35)
        #expect(result.ageGap == 0)
        // 没有历史样本时按 1.0x 中性基准占位，而不是把年龄比当成速度。
        #expect(result.agingSpeed == 1.0)
        #expect(result.isAgingSpeedBaseline)
        #expect(result.level == .normal)
    }

    @Test func fitProfileLowersBodyAge() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            vo2Max: 55,
            restingHR: 52,
            sleepHours: 7.5,
            weeklyExerciseMinutes: 300,
            leanBodyMassKg: 60
        )
        let result = BodyAgeEngine.evaluate(input)
        // vo2: (44 − 55) × 0.2 = −2.2；rhr: (52 − 60) × 0.1 = −0.8；运动: (150 − 300) × 0.01 = −1.5
        // 睡眠 7.5 小时在参考带内，作为 0.0 岁的一项保留。
        #expect(result.adjustments.count == 4)
        #expect(abs(result.bodyAge! - 30.5) < 0.01)
        #expect(abs(result.ageGap! + 4.5) < 0.01)
        #expect(result.agingSpeed == 1.0)
        #expect(result.isAgingSpeedBaseline)
    }

    @Test func sleepDebtAddsYearsWithClamp() {
        let input = BodyAgeInput(
            chronologicalAge: 40,
            isMale: true,
            vo2Max: nil,
            restingHR: nil,
            sleepHours: 2.0,
            weeklyExerciseMinutes: nil,
            leanBodyMassKg: nil
        )
        let result = BodyAgeEngine.evaluate(input)
        // (7 − 2) × 0.8 = 4，封顶 +4
        #expect(result.adjustments.count == 1)
        #expect(result.adjustments[0].years == 4)
        #expect(result.bodyAge == 44)
    }

    @Test func athleteRestingHRIsClamped() {
        let input = BodyAgeInput(
            chronologicalAge: 30,
            isMale: true,
            vo2Max: nil,
            restingHR: 30,
            sleepHours: nil,
            weeklyExerciseMinutes: nil,
            leanBodyMassKg: nil
        )
        let result = BodyAgeEngine.evaluate(input)
        // (30 − 60) × 0.1 = −3，封顶 −3
        #expect(result.adjustments[0].years == -3)
    }

    @Test func missingChronologicalAgeLeavesResultEmpty() {
        let input = BodyAgeInput(
            chronologicalAge: nil,
            isMale: nil,
            vo2Max: 50,
            restingHR: 60,
            sleepHours: 8,
            weeklyExerciseMinutes: 200,
            leanBodyMassKg: nil
        )
        let result = BodyAgeEngine.evaluate(input)
        #expect(result.bodyAge == nil)
        #expect(result.agingSpeed == nil)
        #expect(result.level == nil)
        #expect(result.adjustments.isEmpty)
    }

    @Test func vo2NeedsSexToBeScored() {
        let withSex = BodyAgeInput(chronologicalAge: 35, isMale: true, vo2Max: 50, restingHR: nil, sleepHours: nil, weeklyExerciseMinutes: nil, leanBodyMassKg: nil)
        let withoutSex = BodyAgeInput(chronologicalAge: 35, isMale: nil, vo2Max: 50, restingHR: nil, sleepHours: nil, weeklyExerciseMinutes: nil, leanBodyMassKg: nil)
        #expect(BodyAgeEngine.evaluate(withSex).adjustments.count == 1)
        #expect(BodyAgeEngine.evaluate(withoutSex).adjustments.isEmpty)
    }

    @Test func agingLevelBoundaries() {
        #expect(BodyAgeEngine.agingLevel(0.79) == .younger)
        #expect(BodyAgeEngine.agingLevel(0.8) == .normal)
        #expect(BodyAgeEngine.agingLevel(1.2) == .normal)
        #expect(BodyAgeEngine.agingLevel(1.21) == .accelerated)
    }

    @Test func bmrUsesKatchMcArdle() {
        // 370 + 21.6 × 60 = 1666
        #expect(BodyAgeEngine.bmr(leanBodyMassKg: 60) == 1_666)
        #expect(BodyAgeEngine.bmr(leanBodyMassKg: nil) == nil)
    }

    @Test func adjustmentsOnlyIncludeAvailableInputs() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: false,
            vo2Max: nil,
            restingHR: 78,
            sleepHours: nil,
            weeklyExerciseMinutes: 60,
            leanBodyMassKg: nil
        )
        let result = BodyAgeEngine.evaluate(input)
        #expect(result.adjustments.count == 2)
        // rhr >75: (78 − 75) × 0.15 = 0.45；运动: (150 − 60) × 0.01 = 0.9
        #expect(abs(result.bodyAge! - 36.35) < 0.01)
    }

    // MARK: - 新增维度与可解释文案

    @Test func additionalFactorsUseAvailableData() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            vo2Max: nil,
            restingHR: nil,
            sleepHours: nil,
            weeklyExerciseMinutes: nil,
            leanBodyMassKg: nil,
            dailySteps: 4_000,
            sleepMidpointSDMinutes: 90,
            bodyFatPct: 30
        )
        let result = BodyAgeEngine.evaluate(input)
        func years(_ factor: BodyAgeFactor) -> Double? {
            result.adjustments.first { $0.factor == factor }?.years
        }
        #expect(result.adjustments.count == 3)
        // 步数 (8000 − 4000) / 1000 × 0.15 = +0.6
        #expect(abs(years(.steps)! - 0.6) < 0.01)
        // 睡眠一致性 (90 − 30) × 0.02 = +1.2
        #expect(abs(years(.sleepRegularity)! - 1.2) < 0.01)
        // 男性体脂参考带 10–20%：(30 − 20) × 0.15 = +1.5
        #expect(abs(years(.bodyFat)! - 1.5) < 0.01)
        #expect(abs(result.bodyAge! - 38.3) < 0.01)
    }

    @Test func adjustmentsAreOrderedLikePrototypeAndCarryExplanation() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            vo2Max: 40,
            restingHR: 65,
            sleepHours: 7.5,
            weeklyExerciseMinutes: 150,
            leanBodyMassKg: nil,
            dailySteps: 8_000,
            sleepMidpointSDMinutes: 20,
            bodyFatPct: 18
        )
        let result = BodyAgeEngine.evaluate(input)
        #expect(result.adjustments.map(\.factor) == [
            .sleepDuration, .sleepRegularity, .weeklyExercise, .steps, .vo2Max, .restingHR, .bodyFat
        ])
        for adjustment in result.adjustments {
            #expect(!adjustment.measured.isEmpty)
            #expect(!adjustment.reference.isEmpty)
            #expect(!adjustment.formula.isEmpty)
            #expect(!adjustment.note.isEmpty)
        }
    }

    @Test func bodyFatNeedsSexToBeScored() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: nil,
            vo2Max: nil,
            restingHR: nil,
            sleepHours: nil,
            weeklyExerciseMinutes: nil,
            leanBodyMassKg: nil,
            bodyFatPct: 30
        )
        #expect(BodyAgeEngine.evaluate(input).adjustments.isEmpty)
    }

    @Test func explanationUsesNeutralDocumentationTone() {
        let input = BodyAgeInput(chronologicalAge: 35, isMale: true)
        let result = BodyAgeEngine.evaluate(input)
        #expect(result.isAgingSpeedBaseline)
        #expect(result.interpretation.contains("暂按 1.0x"))
        #expect(result.explanation.contains("最小二乘拟合"))
        #expect(result.explanation.contains("占位基准"))
        #expect(result.explanation.contains("滑动平均"))
        #expect(result.sampleSpanDays == 0)
    }

    @Test func bmrFallsBackToLeanMassEstimatedFromWeightAndFat() {
        // 体重 70kg、体脂率 18% → 瘦体重 70 × 0.82 = 57.4kg
        let lean = BodyAgeEngine.estimatedLeanBodyMass(weightKg: 70, bodyFatPct: 18)
        #expect(abs(lean! - 57.4) < 0.001)
        // 有任一数据缺失就无法推算。
        #expect(BodyAgeEngine.estimatedLeanBodyMass(weightKg: nil, bodyFatPct: 18) == nil)
        #expect(BodyAgeEngine.estimatedLeanBodyMass(weightKg: 70, bodyFatPct: nil) == nil)
        // 推算出的瘦体重能算出 BMR：370 + 21.6 × 57.4 ≈ 1609.8
        let bmr = BodyAgeEngine.bmr(leanBodyMassKg: lean)
        #expect(abs(bmr! - 1_609.84) < 0.01)
    }

    /// 单日异常不应把速度顶到标尺端点：84 天平稳数据 + 最后一天身体年龄突增 4 岁，
    /// 7 天滑动平均后端点只抬升 4/7 岁，速度应落在 1.5x 以内
    /// （旧口径：28 天窗口 + 不平滑，同样的尖峰会直接拟合到 3.0x 封顶）。
    @Test func singleDaySpikeDoesNotPegAgingSpeed() {
        let now = fixedNow
        let cal = calendar
        let days = 84
        let samples: [BodyAgeSample] = (0..<days).map { offset in
            let date = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
            let age = 35 - Double(offset) / 365.25
            let spike = offset == 0 ? 4.0 : 0
            return BodyAgeSample(date: date, chronologicalAge: age, bodyAge: age + 2 + spike)
        }
        let speed = BodyAgeEngine.agingSpeed(from: samples, now: now, calendar: cal)
        #expect(speed != nil)
        #expect(speed! < 1.5)
        #expect(speed! > 0.5)
    }

    // MARK: - 输入窗口与历史

    @Test func inputUsesSevenDayWindowAndIsOrderIndependent() {
        let now = fixedNow
        let cal = calendar
        var snapshots: [DailySnapshot] = []
        for offset in 0..<10 {
            let date = cal.date(byAdding: .day, value: -offset, to: now)!
            snapshots.append(DailySnapshot(
                dayKey: "2026-11-\(9 - offset)",
                date: date,
                restingHR: 60,
                sleepTotalH: offset < 7 ? 8 : 2,
                steps: 8_000,
                exerciseMinutes: 20,
                vo2Max: 40,
                sleepMidpointMinutes: 180 + Double(offset * 10),
                bodyFatPct: 18
            ))
        }
        let ascending = snapshots.sorted { $0.date < $1.date }
        let input = BodyAgeEngine.input(
            asOf: now,
            snapshots: ascending,
            chronologicalAge: 35,
            isMale: true,
            now: now,
            calendar: cal
        )
        // 只取最近 7 天：更早的 2 小时睡眠不参与均值。
        #expect(input.sleepHours == 8)
        #expect(input.weeklyExerciseMinutes == 140)
        #expect(input.dailySteps == 8_000)
        #expect(input.vo2Max == 40)
        #expect(input.bodyFatPct == 18)
        #expect(input.sleepMidpointSDMinutes != nil)
        #expect(input.chronologicalAge == 35)

        let shuffled = BodyAgeEngine.input(
            asOf: now,
            snapshots: ascending.reversed(),
            chronologicalAge: 35,
            isMale: true,
            now: now,
            calendar: cal
        )
        #expect(shuffled == input)
    }

    @Test func inputBackdatesChronologicalAgeForHistory() {
        let now = fixedNow
        let cal = calendar
        let past = cal.date(byAdding: .day, value: -14, to: now)!
        let input = BodyAgeEngine.input(
            asOf: past,
            snapshots: [],
            chronologicalAge: 35,
            isMale: true,
            now: now,
            calendar: cal
        )
        #expect(abs(input.chronologicalAge! - (35 - 14 / 365.25)) < 0.0001)
    }

    /// 稀疏读数在 7 日窗口内没有记录时，按回看范围内「有记录日」的均值插补。
    /// 没记录只代表没测 / 没打卡，不代表该项等于 0；按 0 处理会让数据断档
    /// 在衰老速度里表现为变年轻，读数恢复反而把体龄推高。
    @Test func sparseReadingsFollowTrendToLatestRecord() {
        let now = fixedNow
        let cal = calendar
        var snapshots: [DailySnapshot] = []
        // 最近 7 天只有睡眠与步数，没有 VO2max / 血压 / 饮水记录。
        for offset in 0..<7 {
            snapshots.append(DailySnapshot(
                dayKey: "d-\(offset)",
                date: cal.date(byAdding: .day, value: -offset, to: now)!,
                sleepTotalH: 7.5,
                steps: 8_000
            ))
        }
        // 30 天前与 10 天前各一次记录：趋势从 34 → 38（血压 118 → 110、饮水 1000 → 2000）。
        for (offset, vo2, sbp, water) in [(30, 34.0, 118.0, 1_000.0), (10, 38.0, 110.0, 2_000.0)] {
            snapshots.append(DailySnapshot(
                dayKey: "old-\(offset)",
                date: cal.date(byAdding: .day, value: -offset, to: now)!,
                vo2Max: vo2,
                systolicBP: sbp,
                diastolicBP: 76,
                waterTotalMl: water
            ))
        }
        func input(daysAgo: Int) -> BodyAgeInput {
            BodyAgeEngine.input(
                asOf: cal.date(byAdding: .day, value: -daysAgo, to: now)!,
                snapshots: snapshots, chronologicalAge: 35, isMale: true,
                now: now, calendar: cal
            )
        }

        // 今天：窗口内没有记录，取最近一次记录值，不取两点均值。
        let today = input(daysAgo: 0)
        #expect(today.vo2Max == 38)
        #expect(today.systolicBP == 110)
        #expect(today.diastolicBP == 76)
        #expect(today.nutrition.waterTotalMl == 2_000)

        // 20 天前：落在趋势线正中，按时间线性插值（34 与 38 的中点 = 36）。
        let midway = input(daysAgo: 20)
        #expect(midway.vo2Max == 36)
        #expect(midway.systolicBP == 114)
        #expect(midway.nutrition.waterTotalMl == 1_500)

        // 早于最早记录：停在趋势起点，不外推。
        let earlier = input(daysAgo: 45)
        #expect(earlier.vo2Max == 34)
        #expect(earlier.nutrition.waterTotalMl == 1_000)
    }

    /// 回看范围内一条记录都没有时仍返回 nil，该维度整体不参与评分。
    @Test func missingSparseReadingsStayOutOfScoring() {
        let now = fixedNow
        let cal = calendar
        let snapshots = (0..<7).map { offset in
            DailySnapshot(
                dayKey: "d-\(offset)",
                date: cal.date(byAdding: .day, value: -offset, to: now)!,
                restingHR: 62,
                sleepTotalH: 7.5,
                steps: 8_000
            )
        }
        let input = BodyAgeEngine.input(
            asOf: now, snapshots: snapshots, chronologicalAge: 35, isMale: true,
            now: now, calendar: cal
        )
        #expect(input.vo2Max == nil)
        #expect(input.systolicBP == nil)
        #expect(input.nutrition.waterTotalMl == nil)

        let result = BodyAgeEngine.evaluate(input)
        #expect(result.adjustments.contains { $0.factor == .vo2Max } == false)
        #expect(result.adjustments.contains { $0.factor == .bloodPressure } == false)
    }

    // MARK: - 衰老速度斜率

    /// speed 是 d(身体年龄)/d(实际年龄)；gap 是当前身体年龄与实际年龄之差。
    private func linearSamples(days: Int = 28, speed: Double, gap: Double = 2, now: Date, cal: Calendar) -> [BodyAgeSample] {
        (0..<days).compactMap { offset in
            guard let date = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now)) else { return nil }
            let age = 35 - Double(offset) / 365.25
            return BodyAgeSample(date: date, chronologicalAge: age, bodyAge: 35 + gap + speed * (age - 35))
        }
    }

    @Test func agingSpeedIsTrendSlopeNotAgeRatio() {
        let now = fixedNow
        let cal = calendar
        let samples = linearSamples(speed: 0.3, now: now, cal: cal)
        // 身体年龄始终比实际年龄大 2 岁左右（比值约 1.06），但速度是 0.3x。
        let speed = BodyAgeEngine.agingSpeed(from: samples, now: now, calendar: cal)
        #expect(speed != nil)
        #expect(abs(speed! - 0.3) < 0.01)
    }

    @Test func parallelGrowthMeansExactlyOneX() {
        let now = fixedNow
        let cal = calendar
        let samples = linearSamples(speed: 1.0, gap: 4, now: now, cal: cal)
        let speed = BodyAgeEngine.agingSpeed(from: samples, now: now, calendar: cal)
        #expect(abs(speed! - 1.0) < 0.01)
    }

    @Test func negativeSlopeMeansGettingYoungerAndIsClamped() {
        let now = fixedNow
        let cal = calendar
        let samples = linearSamples(speed: -0.4, now: now, cal: cal)
        #expect(abs(BodyAgeEngine.agingSpeed(from: samples, now: now, calendar: cal)! + 0.4) < 0.01)
        let extreme = linearSamples(speed: -8, now: now, cal: cal)
        #expect(BodyAgeEngine.agingSpeed(from: extreme, now: now, calendar: cal) == BodyAgeScale.lower)
    }

    @Test func insufficientHistoryReturnsNil() {
        let now = fixedNow
        let cal = calendar
        let short = linearSamples(days: 6, speed: 0.3, now: now, cal: cal)
        #expect(BodyAgeEngine.agingSpeed(from: short, now: now, calendar: cal) == nil)
        let narrow = linearSamples(days: 8, speed: 0.3, now: now, cal: cal)
        #expect(BodyAgeEngine.agingSpeed(from: narrow, now: now, calendar: cal) == nil)
        #expect(BodyAgeEngine.agingSpeed(from: [], now: now, calendar: cal) == nil)
    }

    @Test func evaluateUsesMeasuredSpeedWhenHistoryIsEnough() {
        let now = fixedNow
        let cal = calendar
        let samples = linearSamples(speed: 0.3, now: now, cal: cal)
        let input = BodyAgeInput(chronologicalAge: 35, isMale: true)
        let result = BodyAgeEngine.evaluate(input, samples: samples, now: now, calendar: cal)
        #expect(!result.isAgingSpeedBaseline)
        #expect(abs(result.agingSpeed! - 0.3) < 0.01)
        #expect(result.level == .younger)
        // 平滑只保留完整 7 天窗口：28 个原始样本 → 22 个平滑样本，跨度 27−6=21 天。
        #expect(result.sampleSpanDays == 21)
        #expect(result.explanation.contains("最小二乘拟合"))
    }

    @Test func evaluateFallsBackToOneXBaselineWithoutHistory() {
        let input = BodyAgeInput(chronologicalAge: 35, isMale: true)
        let result = BodyAgeEngine.evaluate(input)
        #expect(result.isAgingSpeedBaseline)
        #expect(result.agingSpeed == BodyAgeScale.neutral)
        #expect(result.level == .normal)
    }

    @Test func samplesBuilderProducesDailyHistory() {
        let now = fixedNow
        let cal = calendar
        var snapshots: [DailySnapshot] = []
        for offset in 0..<30 {
            let date = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
            snapshots.append(DailySnapshot(
                dayKey: "d-\(offset)",
                date: date,
                restingHR: 65,
                sleepTotalH: 7.5,
                steps: 8_000,
                exerciseMinutes: 22,
                // VO2max 常模随年龄下降，固定读数会让速度略低于 1.0x；
                // 这里只用恒定项验证逐日窗口与历史构造。
                sleepMidpointMinutes: 180,
                bodyFatPct: 18
            ))
        }
        let samples = BodyAgeEngine.samples(
            snapshots: snapshots,
            chronologicalAge: 35,
            isMale: true,
            now: now,
            calendar: cal
        )
        // 30 天快照、28 天回算上限，且每个样本必须有完整 7 天窗口 → 24 个样本。
        #expect(samples.count == 24)
        // 指标恒定 → 身体年龄只随实际年龄平移 → 速度恰为 1.0x。
        let speed = BodyAgeEngine.agingSpeed(from: samples, now: now, calendar: cal)
        #expect(speed != nil)
        #expect(abs(speed! - 1.0) < 0.01)
    }

    // MARK: - 训练心率区间

    @Test func workoutZoneIndexBucketsByMaxHeartRate() {
        // 最大心率 190：Z1<60%(114) / Z2 60–70%(114–133) / Z3 70–80%(133–152)
        // / Z4 80–90%(152–171) / Z5≥90%(171+)
        let maxHR = 190.0
        #expect(WorkoutZoneMinutes.zoneIndex(heartRate: 100, maxHeartRate: maxHR) == 0)
        #expect(WorkoutZoneMinutes.zoneIndex(heartRate: 120, maxHeartRate: maxHR) == 1)
        #expect(WorkoutZoneMinutes.zoneIndex(heartRate: 140, maxHeartRate: maxHR) == 2)
        #expect(WorkoutZoneMinutes.zoneIndex(heartRate: 160, maxHeartRate: maxHR) == 3)
        #expect(WorkoutZoneMinutes.zoneIndex(heartRate: 185, maxHeartRate: maxHR) == 4)
    }

    @Test func effectiveTrainingMinutesWeightsZones() {
        // 0.4×10 + 0.8×20 + 1.0×30 + 1.0×15 + 0.7×5 = 68.5
        let minutes = BodyAgeEngine.effectiveTrainingMinutes([10, 20, 30, 15, 5])
        #expect(abs(minutes - 68.5) < 0.001)
    }

    @Test func exerciseDimensionPrefersZoneMinutes() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            weeklyZoneMinutes: [10, 20, 30, 15, 5]
        )
        let result = BodyAgeEngine.evaluate(input)
        let adjustment = result.adjustments.first { $0.factor == .weeklyExercise }
        #expect(adjustment != nil)
        #expect(adjustment!.measured.contains("有效训练分钟"))
        #expect(adjustment!.note.contains("心率区间"))
        // 有效训练 68.5 分钟：(150 − 68.5) × 0.01 ≈ +0.8 岁
        #expect(abs(adjustment!.years - 0.815) < 0.01)
    }

    @Test func exerciseDimensionFallsBackToDurationWithoutZones() {
        let input = BodyAgeInput(
            chronologicalAge: 35,
            isMale: true,
            weeklyExerciseMinutes: 150
        )
        let result = BodyAgeEngine.evaluate(input)
        let adjustment = result.adjustments.first { $0.factor == .weeklyExercise }
        #expect(adjustment != nil)
        #expect(adjustment!.measured.contains("分钟/周（近 7 日累计）"))
        #expect(adjustment!.note.contains("退回"))
    }

    @Test func inputAggregatesWeeklyZoneMinutes() {
        let now = fixedNow
        let cal = calendar
        let zones: [Double] = [10, 20, 30, 15, 5]
        var snapshots: [DailySnapshot] = []
        for offset in 0..<7 {
            let date = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now))!
            snapshots.append(DailySnapshot(
                dayKey: "z-\(offset)",
                date: date,
                exerciseMinutes: 30,
                workoutZoneMinutes: zones
            ))
        }
        let input = BodyAgeEngine.input(
            asOf: now,
            snapshots: snapshots,
            chronologicalAge: 35,
            isMale: true,
            now: now,
            calendar: cal
        )
        #expect(input.weeklyZoneMinutes != nil)
        #expect(input.weeklyZoneMinutes!.count == WorkoutZoneMinutes.zoneCount)
        // 7 天每日 [10,20,30,15,5] 求和即整周区间分钟，与 weeklyExerciseMinutes 口径一致。
        #expect(abs(input.weeklyZoneMinutes![2] - 210) < 0.001)
    }

    // MARK: - 基础代谢：健康 App 静息能量优先，Katch-McArdle 兜底

    /// 构造按日期倒序的快照（与 HealthProfileView 的 @Query 顺序一致）。
    private func bmrSnapshot(
        offset: Int,
        now: Date,
        basal: Double? = nil,
        lean: Double? = nil,
        weight: Double? = nil,
        fat: Double? = nil
    ) -> DailySnapshot {
        let date = calendar.date(
            byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)
        )!
        return DailySnapshot(
            dayKey: "bmr-\(offset)",
            date: date,
            activeEnergy: nil,
            basalEnergyKcal: basal,
            bodyMassKg: weight,
            bodyFatPct: fat,
            leanBodyMassKg: lean
        )
    }

    @Test func basalEnergyUsesCompleteDayAverageAndIgnoresPartialToday() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [
            bmrSnapshot(offset: 0, now: now, basal: 800),   // 今天只累计到中午
            bmrSnapshot(offset: 1, now: now, basal: 1_600),
            bmrSnapshot(offset: 2, now: now, basal: 1_700),
            bmrSnapshot(offset: 3, now: now, basal: 1_800),
        ]
        let estimate = BodyAgeEngine.basalEnergyEstimate(snapshots: snapshots, now: now, calendar: cal)
        #expect(estimate != nil)
        #expect(abs(estimate!.kcal - 1_700) < 0.001)
        #expect(estimate!.source == .basalEnergy(days: 3))
    }

    @Test func basalEnergySkipsZeroAndOutOfWindowDays() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [
            bmrSnapshot(offset: 0, now: now, basal: 800),
            bmrSnapshot(offset: 1, now: now, basal: 0),      // 无有效读数
            bmrSnapshot(offset: 2, now: now, basal: 1_700),
            bmrSnapshot(offset: 29, now: now, basal: 4_000), // 超出 28 天窗口
        ]
        let estimate = BodyAgeEngine.basalEnergyEstimate(snapshots: snapshots, now: now, calendar: cal)
        #expect(estimate?.kcal == 1_700)
        #expect(estimate?.source == .basalEnergy(days: 1))
    }

    @Test func basalEnergyTodayIsProjectedWhenNoHistory() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [bmrSnapshot(offset: 0, now: now, basal: 800)]
        let estimate = BodyAgeEngine.basalEnergyEstimate(snapshots: snapshots, now: now, calendar: cal)
        #expect(estimate != nil)
        #expect(abs(estimate!.kcal - 1_600) < 0.01)
        #expect(estimate!.source == .basalEnergyTodayProjection)
    }

    @Test func basalEnergyIsNotProjectedTooEarlyInTheDay() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 1))!
        let snapshots = [bmrSnapshot(offset: 0, now: now, basal: 70)]
        #expect(BodyAgeEngine.basalEnergyEstimate(snapshots: snapshots, now: now, calendar: cal) == nil)
    }

    @Test func bmrPrefersFormulaOverBasalEnergy() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [
            bmrSnapshot(offset: 0, now: now, basal: 800),
            bmrSnapshot(offset: 1, now: now, basal: 1_720, lean: 60),
        ]
        let estimate = BodyAgeEngine.bmrEstimate(snapshots: snapshots, now: now, calendar: cal)
        // 公式优先：370 + 21.6 × 60 = 1666，静息能量 1720 不参与。
        #expect(estimate?.kcal == 1_666)
        #expect(estimate?.source == .leanBodyMass)
    }

    /// 体成分是稀疏读数：今天没称不代表没有值，要回溯到最近一次记录。
    @Test func bmrUsesMostRecentLeanMassWhenTodayHasNoBodyComposition() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [
            bmrSnapshot(offset: 0, now: now),
            bmrSnapshot(offset: 3, now: now),
            bmrSnapshot(offset: 9, now: now, lean: 60),
        ]
        let estimate = BodyAgeEngine.bmrEstimate(snapshots: snapshots, now: now, calendar: cal)
        #expect(estimate?.kcal == 1_666)
        #expect(estimate?.source == .leanBodyMass)
    }

    /// 体重与体脂率可能不在同一天，分别取最近一次再组合推算去脂体重。
    @Test func bmrCombinesMostRecentWeightAndFat() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [
            bmrSnapshot(offset: 0, now: now),
            bmrSnapshot(offset: 2, now: now, weight: 70),
            bmrSnapshot(offset: 6, now: now, fat: 18),
        ]
        let estimate = BodyAgeEngine.bmrEstimate(snapshots: snapshots, now: now, calendar: cal)
        #expect(estimate != nil)
        #expect(abs(estimate!.kcal - 1_609.84) < 0.01)
        #expect(estimate!.source == .estimatedLeanBodyMass)
    }

    @Test func bmrFallsBackToBasalEnergyOnlyWithoutBodyComposition() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let snapshots = [
            bmrSnapshot(offset: 0, now: now, basal: 800),
            bmrSnapshot(offset: 1, now: now, basal: 1_720),
        ]
        let estimate = BodyAgeEngine.bmrEstimate(snapshots: snapshots, now: now, calendar: cal)
        #expect(estimate?.kcal == 1_720)
        #expect(estimate?.source == .basalEnergy(days: 1))
    }

    @Test func bodyCompositionOutsideLookbackIsIgnored() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        let composition = BodyAgeEngine.latestBodyComposition(
            snapshots: [bmrSnapshot(offset: 119, now: now, lean: 60, weight: 70, fat: 18)],
            now: now,
            calendar: cal
        )
        #expect(composition.leanBodyMassKg == nil)
        #expect(composition.bodyMassKg == nil)
        #expect(composition.bodyFatPct == nil)
    }

    @Test func bmrUsesKatchMcArdleFormula() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        // 直接同步到瘦体重：370 + 21.6 × 60 = 1666
        let lean = BodyAgeEngine.bmrEstimate(
            snapshots: [bmrSnapshot(offset: 0, now: now, lean: 60)], now: now, calendar: cal
        )
        #expect(lean?.kcal == 1_666)
        #expect(lean?.source == .leanBodyMass)
        // 只有体重与体脂率：70 × (1 − 0.18) = 57.4kg → 1609.84
        let estimated = BodyAgeEngine.bmrEstimate(
            snapshots: [bmrSnapshot(offset: 0, now: now, weight: 70, fat: 18)], now: now, calendar: cal
        )
        #expect(estimated != nil)
        #expect(abs(estimated!.kcal - 1_609.84) < 0.01)
        #expect(estimated!.source == .estimatedLeanBodyMass)
    }

    @Test func bmrIsNilWithoutAnyDataSource() {
        let cal = calendar
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 9, hour: 12))!
        #expect(BodyAgeEngine.bmrEstimate(snapshots: [], now: now, calendar: cal) == nil)
        #expect(BodyAgeEngine.bmrEstimate(
            snapshots: [bmrSnapshot(offset: 0, now: now)], now: now, calendar: cal
        ) == nil)
    }
}

// configured by qoder
