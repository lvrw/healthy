import Foundation

enum ReadinessEngine {
    static func evaluate(
        today: DailySnapshot,
        history: [DailySnapshot],
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current,
        context: DayProgressContext = .complete
    ) -> ReadinessResult {
        let baseline = Baseline.compute(history: history, today: today, config: config, calendar: calendar)
        let sleep = sleepComponent(today, config: config)
        let autonomic = autonomicComponent(today, baseline: baseline, config: config)
        let load = loadComponent(history: history, today: today, config: config, calendar: calendar)
        let vitals = vitalsComponent(today, baseline: baseline, config: config)
        let circadian = circadianComponent(
            history: history, today: today, config: config,
            calendar: calendar, context: context
        )
        let fitnessBody = fitnessBodyComponent(
            today: today,
            history: history,
            baseline: baseline,
            config: config,
            calendar: calendar
        )
        // 身体成分分仅用于「更多指标」分组卡的角标展示，不并入总分权重，
        // 保持原有综合评分口径不变。
        let bodyComposition = bodyCompositionComponent(today)
        // 饮食评分（全 App 统一口径）：饮食质量 70% + 规律饮食 30%。
        // 取代原先「饮水+饮食」与「规律饮食」两个独立分量，避免同一天出现两个饮食分数；
        // 缺项时归一化、全缺时返回 nil，加权平均自动跳过。
        let diet = NutritionEngine.combinedScore(
            NutritionValues.from(today),
            regularity: today.mealRegularityScore,
            config: config,
            progress: context.activity
        )

        let weighted = ScoreSupport.weightedAverage([
            (config.readinessSleepWeight, sleep),
            (config.readinessAutonomicWeight, autonomic),
            (config.readinessLoadWeight, load),
            (config.readinessVitalsWeight, vitals),
            (config.readinessCircadianWeight, circadian),
            (config.readinessFitnessBodyWeight, fitnessBody),
            (config.readinessNutritionWeight + config.readinessMealRegularityWeight, diet),
        ])
        let sources = ScoreSupport.availableSources(today)
        let confidence = ScoreSupport.confidence(
            baselineDays: baseline.baselineDays,
            completeness: sources.count,
            config: config
        )

        return ReadinessResult(
            score: confidence == .insufficient ? nil : weighted,
            components: ReadinessComponents(
                sleep: sleep,
                autonomic: autonomic,
                load: load,
                vitals: vitals,
                circadian: circadian,
                fitnessBody: fitnessBody,
                nutrition: diet,
                // 规律饮食分仍单独留档供明细解释，但不再作为独立权重参与综合评分。
                mealRegularity: today.mealRegularityScore,
                bodyComposition: bodyComposition
            ),
            completeness: sources.count,
            missing: sources.missing,
            confidence: confidence,
            baselineDays: baseline.baselineDays
        )
    }

    private static func sleepComponent(_ today: DailySnapshot, config: ScoringConfig) -> Double? {
        guard let hours = MetricSanitizer.value(today.sleepTotalH, in: MetricRange.sleepHours) else {
            return nil
        }
        var duration = 100 - 18 * max(0, config.sleepLowTargetHours - hours)
        duration -= 10 * max(0, hours - config.sleepHighTargetHours)
        duration = ScoreSupport.clampScore(duration)

        var parts: [(weight: Double, score: Double?)] = [(0.60, duration)]
        if let efficiency = MetricSanitizer.value(today.sleepEfficiency, in: MetricRange.efficiency) {
            parts.append((0.25, efficiency * 100))
        }
        if let deep = MetricSanitizer.value(today.deepH, in: MetricRange.sleepHours),
           let rem = MetricSanitizer.value(today.remH, in: MetricRange.sleepHours),
           hours > 0 {
            let ratio = (deep + rem) / hours
            parts.append((0.15, ScoreSupport.clampScore(ratio / config.deepRemTargetRatio * 100)))
        }
        return ScoreSupport.weightedAverage(parts)
    }

    private static func autonomicComponent(
        _ today: DailySnapshot,
        baseline: BaselineResult,
        config: ScoringConfig
    ) -> Double? {
        let hrv = MetricSanitizer.value(today.hrvSDNN, in: MetricRange.hrv)
        let restingHR = MetricSanitizer.value(today.restingHR, in: MetricRange.restingHR)
        let zHRV = hrv.flatMap { baseline.zHRV($0) }.map { ScoreSupport.clampZ($0, config.zClamp) }
        let zRestingHR = restingHR
            .flatMap { baseline.zScore($0, stats: baseline.restingHR) }
            .map { ScoreSupport.clampZ($0, config.zClamp) }

        switch (zHRV, zRestingHR) {
        case let (.some(zH), .some(zR)):
            return ScoreSupport.clampScore(50 + 18 * zH - 14 * zR)
        case let (.some(zH), nil):
            return ScoreSupport.clampScore(50 + 18 * zH)
        case let (nil, .some(zR)):
            return ScoreSupport.clampScore(50 - 14 * zR)
        case (nil, nil):
            return nil
        }
    }

    private static func loadComponent(
        history: [DailySnapshot],
        today: DailySnapshot,
        config: ScoringConfig,
        calendar: Calendar
    ) -> Double? {
        let todayStart = calendar.startOfDay(for: today.date)
        let window7Start = DayKey.addingDays(-7, to: todayStart, calendar: calendar)
        let window28Start = DayKey.addingDays(-config.baselineWindowDays, to: todayStart, calendar: calendar)

        var load7: [Double] = []
        var load28: [Double] = []
        for snapshot in history {
            let start = calendar.startOfDay(for: snapshot.date)
            guard start < todayStart, start >= window28Start else { continue }
            let steps = MetricSanitizer.value(snapshot.steps, in: MetricRange.steps)
            let energy = MetricSanitizer.value(snapshot.activeEnergy, in: MetricRange.activeEnergy)
            let distance = MetricSanitizer.value(snapshot.distanceWalkingKm, in: MetricRange.distanceKm)
            let flights = MetricSanitizer.value(snapshot.flightsClimbed, in: MetricRange.flightsClimbed)
            guard steps != nil || energy != nil || distance != nil || flights != nil else { continue }
            let load = (energy ?? 0)
                + (steps ?? 0) * 0.04
                + (distance ?? 0) * 5
                + (flights ?? 0) * 1.5
            load28.append(load)
            if start >= window7Start {
                load7.append(load)
            }
        }

        guard load7.count >= config.minLoadDays,
              load28.count >= config.minBaselineDays,
              let mean7 = ScoreSupport.mean(load7),
              let mean28 = ScoreSupport.mean(load28),
              mean28 > 0
        else { return nil }

        let ratio = mean7 / mean28
        let score = 100 - 70 * max(0, ratio - 1.3) - 40 * max(0, 0.7 - ratio)
        return ScoreSupport.clampScore(score)
    }

    private static func vitalsComponent(
        _ today: DailySnapshot,
        baseline: BaselineResult,
        config: ScoringConfig
    ) -> Double? {
        var available = false
        var score = 100.0

        if let temp = MetricSanitizer.value(today.wristTempC, in: MetricRange.wristTemp),
           let z = baseline.zScore(temp, stats: baseline.wristTempC) {
            available = true
            score -= 18 * max(0, ScoreSupport.clampZ(z, config.zClamp))
        }
        // 经期追踪基础体温按产品要求已停止读取，不再参与生命体征评分。
        if let resp = MetricSanitizer.value(today.respiratoryRate, in: MetricRange.respiratoryRate),
           let z = baseline.zScore(resp, stats: baseline.respiratoryRate) {
            available = true
            score -= 12 * max(0, ScoreSupport.clampZ(z, config.zClamp))
        }
        if let spo2 = MetricSanitizer.value(today.spo2, in: MetricRange.spo2) {
            available = true
            score -= 2 * max(0, 97 - spo2)
        }
        if let systolic = MetricSanitizer.value(today.systolicBP, in: MetricRange.systolicBP),
           let diastolic = MetricSanitizer.value(today.diastolicBP, in: MetricRange.diastolicBP) {
            available = true
            if systolic >= 140 || diastolic >= 90 {
                score -= 25
            } else {
                if let z = baseline.zScore(systolic, stats: baseline.systolicBP) {
                    score -= 10 * max(0, ScoreSupport.clampZ(z, config.zClamp))
                }
                if let z = baseline.zScore(diastolic, stats: baseline.diastolicBP) {
                    score -= 8 * max(0, ScoreSupport.clampZ(z, config.zClamp))
                }
            }
        }
        if let glucose = MetricSanitizer.value(today.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) {
            available = true
            if let z = baseline.zScore(glucose, stats: baseline.bloodGlucose), z > 2 {
                score -= 10
            }
        }

        return available ? ScoreSupport.clampScore(score) : nil
    }

    private static func circadianComponent(
        history: [DailySnapshot],
        today: DailySnapshot,
        config: ScoringConfig,
        calendar: Calendar,
        context: DayProgressContext
    ) -> Double? {
        var parts: [(weight: Double, score: Double?)] = []

        // 日照只在有日光的时段累积：夜里不能用清醒时间推算「应该晒了多久」。
        if let daylight = MetricSanitizer.value(today.daylightMinutes, in: MetricRange.daylightMinutes),
           let target = DayProgress.stagedTarget(config.daylightTargetMinutes, progress: context.daylight) {
            let score = ScoreSupport.clampScore(daylight / target * 100)
            parts.append((0.55, score))
        }
        if let sd = ScoreSupport.sleepMidpointSD(
            history: history,
            today: today,
            config: config,
            calendar: calendar
        ) {
            let score = ScoreSupport.clampScore(100 - 1.5 * max(0, sd - config.sleepMidpointSDFloor))
            parts.append((0.45, score))
        }
        return ScoreSupport.weightedAverage(parts)
    }

    private static func fitnessBodyComponent(
        today: DailySnapshot,
        history: [DailySnapshot],
        baseline: BaselineResult,
        config: ScoringConfig,
        calendar: Calendar
    ) -> Double? {
        var parts: [(weight: Double, score: Double?)] = []

        if let vo2 = latestVO2(today: today, history: history, calendar: calendar),
           let z = baseline.zScore(vo2, stats: baseline.vo2Max) {
            parts.append((0.30, ScoreSupport.clampScore(50 + 12 * ScoreSupport.clampZ(z, config.zClamp))))
        }
        if let speed = MetricSanitizer.value(today.walkingSpeedMps, in: MetricRange.walkingSpeed),
           let z = baseline.zScore(speed, stats: baseline.walkingSpeed) {
            parts.append((0.15, ScoreSupport.clampScore(50 + 10 * ScoreSupport.clampZ(z, config.zClamp))))
        }
        if let steadiness = MetricSanitizer.value(today.walkingSteadinessPct, in: MetricRange.walkingSteadinessPct),
           let z = baseline.zScore(steadiness, stats: baseline.walkingSteadiness) {
            parts.append((0.15, ScoreSupport.clampScore(50 + 10 * ScoreSupport.clampZ(z, config.zClamp))))
        }

        let weight7 = ScoreSupport.recentValues(
            windowDays: 7, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.bodyMassKg, in: MetricRange.bodyMassKg) }
        let weight28 = ScoreSupport.recentValues(
            windowDays: 28, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.bodyMassKg, in: MetricRange.bodyMassKg) }
        if weight7.count >= 3, weight28.count >= 3,
           let mean7 = ScoreSupport.mean(weight7),
           let mean28 = ScoreSupport.mean(weight28),
           mean28 > 0 {
            let change = abs(mean7 - mean28) / mean28
            parts.append((0.15, ScoreSupport.clampScore(100 - 200 * change)))
        }

        let fat7 = ScoreSupport.recentValues(
            windowDays: 7, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.bodyFatPct, in: MetricRange.bodyFatPct) }
        let fat28 = ScoreSupport.recentValues(
            windowDays: 28, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.bodyFatPct, in: MetricRange.bodyFatPct) }
        if fat7.count >= 3, fat28.count >= 3,
           let mean7 = ScoreSupport.mean(fat7),
           let mean28 = ScoreSupport.mean(fat28) {
            parts.append((0.15, ScoreSupport.clampScore(100 - 30 * abs(mean7 - mean28))))
        }

        let lean7 = ScoreSupport.recentValues(
            windowDays: 7, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.leanBodyMassKg, in: MetricRange.leanBodyMassKg) }
        let lean28 = ScoreSupport.recentValues(
            windowDays: 28, history: history, today: today, calendar: calendar
        ) { MetricSanitizer.value($0.leanBodyMassKg, in: MetricRange.leanBodyMassKg) }
        if lean7.count >= 3, lean28.count >= 3,
           let mean7 = ScoreSupport.mean(lean7),
           let mean28 = ScoreSupport.mean(lean28) {
            parts.append((0.10, ScoreSupport.clampScore(100 - 40 * abs(mean7 - mean28))))
        }

        return ScoreSupport.weightedAverage(parts)
    }

    /// 身体成分分组卡展示分（0–100）：BMI、体脂率、瘦体重占比、腰围。
    /// 仅用于分组角标，不并入综合评分加权；缺项自动按剩余权重归一化。
    private static func bodyCompositionComponent(_ today: DailySnapshot) -> Double? {
        var parts: [(weight: Double, score: Double?)] = []
        if let bmi = MetricSanitizer.value(today.bmi, in: MetricRange.bmi) {
            let deviation = max(0, 18.5 - bmi) + max(0, bmi - 24)
            parts.append((0.40, ScoreSupport.clampScore(100 - deviation * 8)))
        }
        if let fat = MetricSanitizer.value(today.bodyFatPct, in: MetricRange.bodyFatPct) {
            // 评分链路不读取性别，这里用 15–25% 的通用参考带。
            let deviation = max(0, 15 - fat) + max(0, fat - 25)
            parts.append((0.35, ScoreSupport.clampScore(100 - deviation * 4)))
        }
        if let lean = MetricSanitizer.value(today.leanBodyMassKg, in: MetricRange.leanBodyMassKg),
           let weight = MetricSanitizer.value(today.bodyMassKg, in: MetricRange.bodyMassKg),
           weight > 0 {
            parts.append((0.15, ScoreSupport.clampScore(lean / weight / 0.75 * 100)))
        }
        if let waist = MetricSanitizer.value(today.waistCircumferenceCm, in: MetricRange.waistCircumferenceCm) {
            parts.append((0.10, ScoreSupport.clampScore(100 - max(0, waist - 90) * 2)))
        }
        return ScoreSupport.weightedAverage(parts)
    }

    private static func latestVO2(
        today: DailySnapshot,
        history: [DailySnapshot],
        calendar: Calendar
    ) -> Double? {
        let cutoff = DayKey.addingDays(
            -28,
            to: calendar.startOfDay(for: today.date),
            calendar: calendar
        )
        return (history + [today])
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
            .last { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) != nil }
            .flatMap { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) }
    }
}
