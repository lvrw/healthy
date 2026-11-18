import Foundation

/// 参与身体年龄估算的维度。原型（docs/）里的「影响因素」逐项展示，
/// 这里只收录 DailySnapshot 中确实有数据源的维度；训练区间时长、力量训练时长
/// 暂无对应 HealthKit 采样，暂不参与估算（TODO: 接入 workouts 心率区间后补充）。
enum BodyAgeFactor: String, Sendable, CaseIterable, Identifiable {
    case sleepDuration
    case sleepRegularity
    case weeklyExercise
    case steps
    case vo2Max
    case restingHR
    case bodyFat
    /// 健康 App 同步的外部水量 + 本 App 打卡水量的 7 日均值。
    case hydration
    /// 健康 App 同步的饮食营养综合分。
    case dietQuality
    /// 以下为扩展维度：睡眠效率、自主神经恢复、身体形态、心血管代谢与户外/正念。
    case sleepEfficiency
    case hrvRecovery
    case bmi
    case bloodPressure
    case bloodGlucose
    case daylight
    case mindfulness

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleepDuration: return "睡眠时长"
        case .sleepRegularity: return "睡眠一致性"
        case .weeklyExercise: return "周运动量"
        case .steps: return "步数"
        case .vo2Max: return "最大摄氧量"
        case .restingHR: return "静息心率"
        case .bodyFat: return "体脂率"
        case .hydration: return "饮水量"
        case .dietQuality: return "饮食质量"
        case .sleepEfficiency: return "睡眠效率"
        case .hrvRecovery: return "HRV 恢复"
        case .bmi: return "BMI"
        case .bloodPressure: return "血压"
        case .bloodGlucose: return "血糖"
        case .daylight: return "日照"
        case .mindfulness: return "正念"
        }
    }

    /// SF Symbols 名称，由 UI 层消费；计算层不引入 SwiftUI。
    var symbol: String {
        switch self {
        case .sleepDuration: return "moon.zzz.fill"
        case .sleepRegularity: return "clock.fill"
        case .weeklyExercise: return "figure.run"
        case .steps: return "shoeprints.fill"
        case .vo2Max: return "lungs.fill"
        case .restingHR: return "heart.fill"
        case .bodyFat: return "scalemass.fill"
        case .hydration: return "drop.fill"
        case .dietQuality: return "fork.knife"
        case .sleepEfficiency: return "bed.double.fill"
        case .hrvRecovery: return "waveform.path.ecg"
        case .bmi: return "figure.stand"
        case .bloodPressure: return "heart.circle.fill"
        case .bloodGlucose: return "drop.circle.fill"
        case .daylight: return "sun.max.fill"
        case .mindfulness: return "brain.head.profile"
        }
    }

    var order: Int {
        switch self {
        case .sleepDuration: return 0
        case .sleepRegularity: return 1
        case .weeklyExercise: return 2
        case .steps: return 3
        case .vo2Max: return 4
        case .restingHR: return 5
        case .bodyFat: return 6
        case .hydration: return 7
        case .dietQuality: return 8
        case .sleepEfficiency: return 9
        case .hrvRecovery: return 10
        case .bmi: return 11
        case .bloodPressure: return 12
        case .bloodGlucose: return 13
        case .daylight: return 14
        case .mindfulness: return 15
        }
    }
}

/// 单个维度对身体年龄的加减岁数，以及可展开的计算依据。
struct BodyAgeAdjustment: Sendable, Equatable, Identifiable {
    var id: String { factor.rawValue }
    var factor: BodyAgeFactor
    var years: Double
    /// 当前实测值（含取值窗口），例如「6.3 小时/天（近 7 日均值）」。
    var measured: String
    /// 参考带，例如「7–9 小时/天」。
    var reference: String
    /// 具体算式与封顶，例如「(7 − 6.3) × 0.8 = +0.6 岁，最多 +4 岁」。
    var formula: String
    /// 数据来源说明。
    var note: String

    var name: String { factor.title }
}

struct BodyAgeInput: Sendable, Equatable {
    var chronologicalAge: Double?
    var isMale: Bool?
    var vo2Max: Double?
    var restingHR: Double?
    var sleepHours: Double?
    var weeklyExerciseMinutes: Double?
    /// 近 7 日 workouts 心率区间累计分钟（Z1–Z5），由 HealthKit 心率采样折算；缺失为 nil。
    var weeklyZoneMinutes: [Double]? = nil
    var leanBodyMassKg: Double?
    /// 近 7 日平均每日步数。
    var dailySteps: Double? = nil
    /// 近 7 日入睡中点（分钟）的样本标准差，衡量睡眠一致性。
    var sleepMidpointSDMinutes: Double? = nil
    /// 最近一次体脂率读数（百分比，例如 18.5 表示 18.5%）。
    var bodyFatPct: Double? = nil
    /// 近 7 日饮水与饮食均值；为空时两个维度都不参与估算。
    var nutrition: NutritionValues = NutritionValues()
    /// 近 7 日规律饮食评分均值（0–100）；无饮食打卡时为 nil，此时不产生额外年龄调整。
    var mealRegularityScore: Double? = nil
    /// 扩展维度：近 7 日均值（睡眠效率 / HRV / 日照 / 正念）与最近一次读数（BMI / 血压 / 血糖）。
    var sleepEfficiency: Double? = nil
    var hrvSDNN: Double? = nil
    var bmi: Double? = nil
    var systolicBP: Double? = nil
    var diastolicBP: Double? = nil
    var bloodGlucoseMgDl: Double? = nil
    var daylightMinutes: Double? = nil
    var mindfulMinutes: Double? = nil
}

/// 每日一个身体年龄样本，用于回归出衰老速度。
struct BodyAgeSample: Sendable, Equatable, Identifiable {
    var date: Date
    var chronologicalAge: Double
    var bodyAge: Double
    var id: Date { date }
}

enum AgingSpeedLevel: String, Sendable, Equatable {
    case younger
    case normal
    case accelerated

    var label: String {
        switch self {
        case .younger: return "老得更慢 · 变年轻中"
        case .normal: return "与实际年龄同步"
        case .accelerated: return "衰老偏快"
        }
    }
}

/// 原型标尺 -1x ~ 3x，1.0x 为中性基准。
enum BodyAgeScale {
    static let lower: Double = -1
    static let neutral: Double = 1
    static let upper: Double = 3
    /// 身体年龄当前值取近 7 天窗口的展示口径。
    static let windowDays = 28
    /// 速度拟合窗口。此前与展示口径共用 28 天，跨度太短导致单日异常
    /// （如某天睡眠骤降）被年化放大，速度长期顶在标尺端点；
    /// 拉长到 84 天后单日波动对斜率的影响被摊薄约一个数量级。
    static let speedWindowDays = 84
    /// 拟合前对每日身体年龄做 7 天滑动平均，进一步抑制单日测量噪声。
    static let smoothingWindowDays = 7
    static let minimumSpanDays = 14
    static let minimumSamples = 7
    /// 回算历史身体年龄时必须凑满 7 天窗口，避免边界处「只有 3 天运动量」
    /// 被当成一周总量而制造假趋势。
    static let minimumWindowDays = 7
    /// 7 天窗口 + 14 天趋势跨度：出第一个实测速度大约需要 21 天连续数据。
    static let minimumDataDays = 21
}

struct BodyAgeResult: Sendable, Equatable {
    var bodyAge: Double?
    var chronologicalAge: Double?
    /// bodyAge − chronologicalAge，正数「多 X 岁」，负数「少 X 岁」。
    var ageGap: Double?
    /// 展示用衰老速度；历史不足时为中性基准 1.0（isAgingSpeedBaseline = true）。
    var agingSpeed: Double?
    var isAgingSpeedBaseline: Bool
    /// 参与速度估算的历史跨度天数，0 表示无法估算。
    var sampleSpanDays: Int
    var level: AgingSpeedLevel?
    var adjustments: [BodyAgeAdjustment]
    /// 顶部一句话解读。
    var interpretation: String
    /// 「为什么是 1.0x」展开说明。
    var explanation: String
}

/// 基础代谢的取值来源，用于「健康」页标注口径。
enum BMRSource: Sendable, Equatable {
    /// 健康 App「静息能量」近 N 个完整日的均值。
    case basalEnergy(days: Int)
    /// 只有今天有静息能量时按已过时间折算全天。
    case basalEnergyTodayProjection
    /// Katch-McArdle：使用同步到的瘦体重。
    case leanBodyMass
    /// Katch-McArdle：瘦体重由体重 ×（1 − 体脂率）推算。
    case estimatedLeanBodyMass
}

/// 基础代谢估算结果（千卡/天）及其来源。
struct BMREstimate: Sendable, Equatable {
    var kcal: Double
    var source: BMRSource
}

/// 娱乐性估算，非医学指标。
///
/// 身体年龄 = 实际年龄 + Σ(各维度偏离参考带的加减岁数)，各维度均单独封顶。
/// 所有系数都是经验设定、用于可视化相对变化，不是医学模型
/// （TODO: 有真实队列数据后再做校准）。
///
/// 衰老速度 = 近 84 天「身体年龄」（先做 7 天滑动平均）相对「实际年龄」的
/// 回归斜率（岁/年）：1.0x 表示每过一年身体年龄也长一岁（与实际年龄同速），
/// 这是标尺的**基准**，不是把「身体年龄 ÷ 实际年龄」当速度。
/// 小于 1 老得更慢，小于 0 在变年轻，大于 1 老得更快。
/// 历史不足 14 天时按 1.0x 中性基准占位并标注「数据积累中」。
enum BodyAgeEngine {
    static func vo2Norm(age: Double, male: Bool) -> Double {
        (male ? 58 : 46) - 0.4 * age
    }

    /// Z1–Z5 强度权重：中等强度以上更被看重，极限区略降以抑制过度训练加分。
    static let zoneWeights: [Double] = [0.4, 0.8, 1.0, 1.0, 0.7]

    /// workouts 各心率区间分钟 → 有效训练分钟（按强度加权）。
    static func effectiveTrainingMinutes(_ zoneMinutes: [Double]) -> Double {
        guard zoneMinutes.count == WorkoutZoneMinutes.zoneCount else { return zoneMinutes.reduce(0, +) }
        return zip(zoneMinutes, zoneWeights).reduce(0) { $0 + $1.0 * $1.1 }
    }

    static func evaluate(
        _ input: BodyAgeInput,
        samples: [BodyAgeSample] = [],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BodyAgeResult {
        guard let age = input.chronologicalAge, age > 0, age.isFinite else {
            return BodyAgeResult(
                bodyAge: nil,
                chronologicalAge: nil,
                ageGap: nil,
                agingSpeed: nil,
                isAgingSpeedBaseline: false,
                sampleSpanDays: 0,
                level: nil,
                adjustments: [],
                interpretation: "",
                explanation: ""
            )
        }

        let adjustments = makeAdjustments(input, age: age)
        let total = adjustments.reduce(0) { $0 + $1.years }
        // 全为 0 的浮点残差不影响：sum 后加到实际年龄上。
        let bodyAge = total == 0 ? age : (age + total)

        let measuredSpeed = agingSpeed(from: samples, now: now, calendar: calendar)
        let span = sampleSpan(from: samples, now: now, calendar: calendar)
        let isBaseline = measuredSpeed == nil
        let speed = measuredSpeed ?? BodyAgeScale.neutral
        let level = agingLevel(speed)
        // 展示口径与拟合一致：平滑后的每日样本数。
        let smoothedSampleCount = movingAverage(
            usableSamples(samples, now: now, calendar: calendar).sorted { $0.date < $1.date },
            window: BodyAgeScale.smoothingWindowDays
        ).count

        return BodyAgeResult(
            bodyAge: bodyAge,
            chronologicalAge: age,
            ageGap: bodyAge - age,
            agingSpeed: speed,
            isAgingSpeedBaseline: isBaseline,
            sampleSpanDays: span,
            level: level,
            adjustments: adjustments,
            interpretation: interpretation(speed: speed, level: level, isBaseline: isBaseline),
            explanation: explanation(speed: speed, isBaseline: isBaseline, spanDays: span, sampleCount: smoothedSampleCount)
        )
    }

    /// <0.8 老得更慢 / 0.8–1.2 与年龄同步 / >1.2 偏快。
    static func agingLevel(_ speed: Double) -> AgingSpeedLevel {
        if speed < 0.8 { return .younger }
        if speed <= 1.2 { return .normal }
        return .accelerated
    }

    /// Katch-McArdle 基础代谢：370 + 21.6 × 瘦体重(kg)。
    static func bmr(leanBodyMassKg: Double?) -> Double? {
        guard let leanBodyMassKg, leanBodyMassKg > 0 else { return nil }
        return 370 + 21.6 * leanBodyMassKg
    }

    /// 智能秤没有单独同步瘦体重时，用体重 × (1 − 体脂率) 推算瘦体重。
    /// 两项数据都缺失时返回 nil，由调用方继续尝试其它数据源。
    static func estimatedLeanBodyMass(weightKg: Double?, bodyFatPct: Double?) -> Double? {
        guard let weightKg = MetricSanitizer.value(weightKg, in: MetricRange.bodyMassKg),
              let bodyFatPct = MetricSanitizer.value(bodyFatPct, in: MetricRange.bodyFatPct)
        else { return nil }
        let lean = weightKg * (1 - bodyFatPct / 100)
        return MetricSanitizer.value(lean, in: MetricRange.leanBodyMassKg)
    }

    /// 静息能量取近 28 天完整日均值：与「日均基础代谢」口径一致。
    static let basalEnergyWindowDays = 28
    /// 今日累计折算全天所需的最小时间进度，凌晨样本太少会放大噪声。
    static let basalEnergyProjectionThreshold = 0.15

    /// 健康 App 的「静息能量」（basalEnergyBurned）是 Apple Watch 按日累计的基础代谢估算，
    /// 单位就是千卡/天，不需要再用公式反推。今天只累计到当前时刻，不能当成全天值，
    /// 因此优先取近 28 天已过完的完整日均值；只有首次同步、尚无历史时才折算今天。
    /// 调用方传入的 snapshots 按日期倒序（最新在前）。
    static func basalEnergyEstimate(
        snapshots: [DailySnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        windowDays: Int = basalEnergyWindowDays
    ) -> BMREstimate? {
        let todayStart = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -windowDays, to: todayStart) else {
            return nil
        }
        let completed = snapshots
            .filter { $0.date >= cutoff && $0.date < todayStart }
            .compactMap { snapshot -> Double? in
                guard let raw = snapshot.basalEnergyKcal, raw.isFinite, raw > 0 else { return nil }
                return MetricSanitizer.value(raw, in: MetricRange.basalEnergyKcal)
            }
        if !completed.isEmpty {
            let mean = completed.reduce(0, +) / Double(completed.count)
            return BMREstimate(kcal: mean, source: .basalEnergy(days: completed.count))
        }

        guard let today = snapshots.first(where: { calendar.isDate($0.date, inSameDayAs: now) }),
              let raw = today.basalEnergyKcal, raw.isFinite, raw > 0,
              let value = MetricSanitizer.value(raw, in: MetricRange.basalEnergyKcal)
        else { return nil }
        let progress = now.timeIntervalSince(todayStart) / 86_400
        guard progress >= basalEnergyProjectionThreshold else { return nil }
        let projected = min(value / min(1, progress), MetricRange.basalEnergyKcal.upperBound)
        return BMREstimate(kcal: projected, source: .basalEnergyTodayProjection)
    }

    /// 体成分是稀疏读数：智能秤不是每天称，最新一天没记录不代表没有值。
    /// 与全量回填窗口一致，取近 118 天内最近一次有效读数，避免基础代谢凭空变空。
    static let bodyCompositionLookbackDays = 118

    /// 分别取「去脂体重 / 体重 / 体脂率」的最近一次有效读数。
    /// 三项可能不在同一天（例如某天只称了体重），因此各自独立取最近值再组合推算。
    /// 调用方传入的 snapshots 按日期倒序（最新在前），这里仍显式排序，不依赖顺序。
    static func latestBodyComposition(
        snapshots: [DailySnapshot],
        now: Date = .now,
        calendar: Calendar = .current,
        windowDays: Int = bodyCompositionLookbackDays
    ) -> (leanBodyMassKg: Double?, bodyMassKg: Double?, bodyFatPct: Double?) {
        guard let cutoff = calendar.date(
            byAdding: .day, value: -windowDays, to: calendar.startOfDay(for: now)
        ) else { return (nil, nil, nil) }
        let recent = snapshots.filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
        func latest(_ keyPath: KeyPath<DailySnapshot, Double?>, in range: ClosedRange<Double>) -> Double? {
            for snapshot in recent {
                if let raw = snapshot[keyPath: keyPath], raw.isFinite, raw > 0,
                   let value = MetricSanitizer.value(raw, in: range) {
                    return value
                }
            }
            return nil
        }
        return (
            latest(\.leanBodyMassKg, in: MetricRange.leanBodyMassKg),
            latest(\.bodyMassKg, in: MetricRange.bodyMassKg),
            latest(\.bodyFatPct, in: MetricRange.bodyFatPct)
        )
    }

    /// 基础代谢以公式计算为主：Katch-McArdle（去脂体重，或体重 × 体脂率推算）。
    /// 体成分稀疏，输入取近 118 天最近一次有效读数；只有公式完全算不出时，
    /// 才用健康 App 静息能量兜底，保证不会出现无理由的空值。
    static func bmrEstimate(
        snapshots: [DailySnapshot],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BMREstimate? {
        let composition = latestBodyComposition(snapshots: snapshots, now: now, calendar: calendar)
        if let kcal = bmr(leanBodyMassKg: composition.leanBodyMassKg) {
            return BMREstimate(kcal: kcal, source: .leanBodyMass)
        }
        if let lean = estimatedLeanBodyMass(
            weightKg: composition.bodyMassKg, bodyFatPct: composition.bodyFatPct
        ), let kcal = bmr(leanBodyMassKg: lean) {
            return BMREstimate(kcal: kcal, source: .estimatedLeanBodyMass)
        }
        return basalEnergyEstimate(snapshots: snapshots, now: now, calendar: calendar)
    }

    // MARK: - 从 HealthKit 快照构造输入与历史

    /// 取 asOf 当天及之前 6 天窗口构造输入；不依赖调用方数组顺序。
    /// chronologicalAge 是 now 当天的年龄，历史日期会按天数差回推。
    static func input(
        asOf: Date,
        snapshots: [DailySnapshot],
        chronologicalAge: Double?,
        isMale: Bool?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BodyAgeInput {
        let window = windowSnapshots(asOf: asOf, snapshots: snapshots, calendar: calendar)
        // 只有「今天」需要折算：睡眠期间无法喝水 / 运动，尚未过完的累计量
        // 不能当成全天结果拉低 7 日窗口；历史日期一律是完整日。
        let dayStart = calendar.startOfDay(for: asOf)
        let history = snapshots.filter { $0.date < dayStart }
        let todaySnapshot = window.first { calendar.isDate($0.date, inSameDayAs: asOf) }
        let dayContext: DayProgressContext = {
            guard let todaySnapshot, calendar.isDate(asOf, inSameDayAs: now) else { return .complete }
            return DayProgress.context(
                for: asOf, today: todaySnapshot, history: history, now: now, calendar: calendar
            )
        }()
        let adjusted = window.map {
            prorateTodayCumulatives($0, asOf: asOf, context: dayContext, calendar: calendar)
        }
        let latestFirst = adjusted.sorted { $0.date > $1.date }

        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: asOf),
            to: calendar.startOfDay(for: now)
        ).day ?? 0
        let ageAt: Double? = chronologicalAge.map { $0 - Double(days) / 365.25 }

        let restingHR = mean(latestFirst.map(\.restingHR), in: MetricRange.restingHR)
        let sleepHours = mean(latestFirst.map(\.sleepTotalH), in: MetricRange.sleepHours)
        let steps = mean(latestFirst.map(\.steps), in: MetricRange.steps)
        let exercise = latestFirst.compactMap(\.exerciseMinutes)
        // 折算后可能少了今天的样本，按有效天数折算回 7 日累计，避免少算一天。
        let exerciseTotal: Double? = exercise.isEmpty
            ? nil
            : exercise.reduce(0, +) * 7 / Double(exercise.count)
        // 近 7 日各区间分钟求和后按有效天数折算回整周，口径与 exerciseTotal 一致。
        let zoneDays = adjusted.compactMap(\.workoutZoneMinutes)
        let weeklyZoneMinutes: [Double]? = zoneDays.isEmpty
            ? nil
            : {
                var summed = [Double](repeating: 0, count: WorkoutZoneMinutes.zoneCount)
                for arr in zoneDays where arr.count == WorkoutZoneMinutes.zoneCount {
                    for i in 0..<summed.count { summed[i] += arr[i] }
                }
                let factor = 7 / Double(zoneDays.count)
                return summed.map { $0 * factor }
            }()
        // 稀疏读数：7 日窗口内最近一次读数优先；窗口内完全没有该维度记录时，
        // 沿「历史平均值 → 最近记录」的趋势线插补（见 recordedValue）。缺失不当 0 岁。
        let vo2 = recordedValue(
            latestFirst.lazy.compactMap { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) }.first,
            in: snapshots, asOf: asOf, now: now, calendar: calendar
        ) { MetricSanitizer.value($0.vo2Max, in: MetricRange.vo2Max) }
        let bodyFat = recordedValue(
            latestFirst.lazy.compactMap { MetricSanitizer.value($0.bodyFatPct, in: MetricRange.bodyFatPct) }.first,
            in: snapshots, asOf: asOf, now: now, calendar: calendar
        ) { MetricSanitizer.value($0.bodyFatPct, in: MetricRange.bodyFatPct) }
        let midpoints = latestFirst.compactMap {
            MetricSanitizer.value($0.sleepMidpointMinutes, in: MetricRange.sleepMidpointMinutes)
        }
        let midpointSD: Double? = midpoints.count >= 3
            ? ScoreSupport.standardDeviation(midpoints)
            : nil
        // 饮水/饮食同样用 7 日窗口均值：单日暴饮暴食不应把身体年龄拉出跳变。
        var nutrition = NutritionValues.average(latestFirst.map { NutritionValues.from($0) })
        // 饮水缺失只代表没打卡，不代表喝了 0 毫升：沿有记录的趋势线插补。
        nutrition.waterTotalMl = recordedValue(
            nutrition.waterTotalMl, in: snapshots, asOf: asOf, now: now, calendar: calendar
        ) { NutritionValues.from($0).waterTotalMl }
        // 规律饮食同样取近 7 日有记录日的均值；7 日全无记录时沿趋势线插补。
        let regularityScores = latestFirst.compactMap(\.mealRegularityScore)
        let windowRegularity = regularityScores.isEmpty
            ? nil
            : regularityScores.reduce(0, +) / Double(regularityScores.count)
        let mealRegularityScore = recordedValue(
            windowRegularity, in: snapshots, asOf: asOf, now: now, calendar: calendar
        ) { $0.mealRegularityScore }

        return BodyAgeInput(
            chronologicalAge: ageAt,
            isMale: isMale,
            vo2Max: vo2,
            restingHR: restingHR,
            sleepHours: sleepHours,
            weeklyExerciseMinutes: exerciseTotal,
            weeklyZoneMinutes: weeklyZoneMinutes,
            leanBodyMassKg: nil,
            dailySteps: steps,
            sleepMidpointSDMinutes: midpointSD,
            bodyFatPct: bodyFat,
            nutrition: nutrition,
            mealRegularityScore: mealRegularityScore,
            sleepEfficiency: mean(latestFirst.map(\.sleepEfficiency), in: MetricRange.efficiency),
            hrvSDNN: mean(latestFirst.map(\.hrvSDNN), in: MetricRange.hrv),
            bmi: recordedValue(
                latestFirst.lazy.compactMap { MetricSanitizer.value($0.bmi, in: MetricRange.bmi) }.first,
                in: snapshots, asOf: asOf, now: now, calendar: calendar
            ) { MetricSanitizer.value($0.bmi, in: MetricRange.bmi) },
            systolicBP: recordedValue(
                latestFirst.lazy.compactMap { MetricSanitizer.value($0.systolicBP, in: MetricRange.systolicBP) }.first,
                in: snapshots, asOf: asOf, now: now, calendar: calendar
            ) { MetricSanitizer.value($0.systolicBP, in: MetricRange.systolicBP) },
            diastolicBP: recordedValue(
                latestFirst.lazy.compactMap { MetricSanitizer.value($0.diastolicBP, in: MetricRange.diastolicBP) }.first,
                in: snapshots, asOf: asOf, now: now, calendar: calendar
            ) { MetricSanitizer.value($0.diastolicBP, in: MetricRange.diastolicBP) },
            bloodGlucoseMgDl: recordedValue(
                latestFirst.lazy.compactMap { MetricSanitizer.value($0.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) }.first,
                in: snapshots, asOf: asOf, now: now, calendar: calendar
            ) { MetricSanitizer.value($0.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) },
            daylightMinutes: mean(latestFirst.map(\.daylightMinutes), in: MetricRange.daylightMinutes),
            mindfulMinutes: mean(latestFirst.map(\.mindfulMinutes), in: MetricRange.mindfulMinutes)
        )
    }

    /// 把今日尚未过完的累计型指标按清醒 / 日光窗口折算为全天预估。
    /// 睡眠中（进度 0）时直接排除今日的累计项，而不是按 0 参与平均。
    private static func prorateTodayCumulatives(
        _ snapshot: DailySnapshot,
        asOf: Date,
        context: DayProgressContext,
        calendar: Calendar
    ) -> DailySnapshot {
        guard context.isPartialDay, calendar.isDate(snapshot.date, inSameDayAs: asOf) else {
            return snapshot
        }
        let activity = context.activity
        let daylight = context.daylight
        var copy = snapshot
        copy.steps = DayProgress.projected(snapshot.steps, progress: activity, ceiling: 60_000)
        copy.activeEnergy = DayProgress.projected(snapshot.activeEnergy, progress: activity, ceiling: 3_000)
        copy.exerciseMinutes = DayProgress.projected(snapshot.exerciseMinutes, progress: activity, ceiling: 180)
        copy.daylightMinutes = DayProgress.projected(snapshot.daylightMinutes, progress: daylight, ceiling: 240)
        copy.mindfulMinutes = DayProgress.projected(snapshot.mindfulMinutes, progress: activity, ceiling: 240)
        copy.waterTotalMl = DayProgress.projected(snapshot.waterTotalMl, progress: activity, ceiling: 6_000)
        copy.externalWaterMl = DayProgress.projected(snapshot.externalWaterMl, progress: activity, ceiling: 6_000)
        copy.localWaterMl = DayProgress.projected(snapshot.localWaterMl, progress: activity, ceiling: 6_000)
        // 身体年龄只使用碳水、蛋白质、脂肪、水、咖啡因 5 项做日内折算，
        // 其余营养摄入指标（能量 / 纤维 / 糖 / 钠等）不参与体龄计算。
        copy.dietaryCarbsG = DayProgress.projected(snapshot.dietaryCarbsG, progress: activity, ceiling: 600)
        copy.dietaryProteinG = DayProgress.projected(snapshot.dietaryProteinG, progress: activity, ceiling: 300)
        copy.dietaryFatG = DayProgress.projected(snapshot.dietaryFatG, progress: activity, ceiling: 300)
        copy.dietaryCaffeineMg = DayProgress.projected(snapshot.dietaryCaffeineMg, progress: activity, ceiling: 1_000)
        return copy
    }

    /// 逐日回算身体年龄，得到用于速度回归的样本序列（默认最近 84 天，
    /// 与速度拟合窗口一致；身体年龄展示本身仍用近 7 天窗口）。
    static func samples(
        snapshots: [DailySnapshot],
        chronologicalAge: Double?,
        isMale: Bool?,
        now: Date = .now,
        calendar: Calendar = .current,
        days: Int = BodyAgeScale.speedWindowDays
    ) -> [BodyAgeSample] {
        guard chronologicalAge != nil else { return [] }
        let today = calendar.startOfDay(for: now)
        var result: [BodyAgeSample] = []
        for offset in 0..<max(0, days) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            guard windowSnapshots(asOf: date, snapshots: snapshots, calendar: calendar).count
                    >= BodyAgeScale.minimumWindowDays else { continue }
            let dayInput = input(
                asOf: date,
                snapshots: snapshots,
                chronologicalAge: chronologicalAge,
                isMale: isMale,
                now: now,
                calendar: calendar
            )
            guard let age = dayInput.chronologicalAge, age > 0,
                  let bodyAge = bodyAgeOnly(dayInput) else { continue }
            result.append(BodyAgeSample(date: date, chronologicalAge: age, bodyAge: bodyAge))
        }
        return result
    }

    /// 最小二乘斜率：Δ身体年龄 / Δ实际年龄（岁/年）。
    /// 拟合前先对每日身体年龄做 7 天滑动平均：单日异常（某天睡得很少、
    /// 步数暴增）只以 1/7 的权重进入端点，不会被年化放大成「衰老 x 倍」。
    /// 样本不足或实际年龄跨度退化时返回 nil，由展示层回退到 1.0x 基准。
    static func agingSpeed(
        from samples: [BodyAgeSample],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Double? {
        let usable = usableSamples(samples, now: now, calendar: calendar)
            .sorted { $0.date < $1.date }
        guard usable.count >= BodyAgeScale.smoothingWindowDays else { return nil }
        let smoothed = movingAverage(usable, window: BodyAgeScale.smoothingWindowDays)
        guard smoothed.count >= BodyAgeScale.minimumSamples else { return nil }
        guard let first = smoothed.map(\.date).min(),
              let last = smoothed.map(\.date).max(),
              let span = calendar.dateComponents([.day], from: first, to: last).day,
              span >= BodyAgeScale.minimumSpanDays else { return nil }

        let xs = smoothed.map(\.chronologicalAge)
        let ys = smoothed.map(\.bodyAge)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        let denominator = zip(xs, ys).reduce(0) { acc, pair in
            acc + (pair.0 - meanX) * (pair.0 - meanX)
        }
        guard denominator > 1e-9 else { return nil }
        let numerator = zip(xs, ys).reduce(0) { acc, pair in
            acc + (pair.0 - meanX) * (pair.1 - meanY)
        }
        let slope = numerator / denominator
        guard slope.isFinite else { return nil }
        return clamp(slope, BodyAgeScale.lower, BodyAgeScale.upper)
    }

    /// 对身体年龄序列做向前滑动平均，只保留凑满完整窗口的平滑点。
    /// 部分窗口（序列开头不足 window 个样本）会被丢弃：它们相对真实曲线存在
    /// 随索引变化的偏移，会让「完全平稳」的数据也拟出虚假斜率（约 +0.02~0.09x）。
    static func movingAverage(_ samples: [BodyAgeSample], window: Int) -> [BodyAgeSample] {
        guard window > 1, samples.count >= window else { return [] }
        var result: [BodyAgeSample] = []
        result.reserveCapacity(samples.count - window + 1)
        for index in (window - 1)..<samples.count {
            let slice = samples[(index - window + 1)...index]
            let mean = slice.reduce(0) { $0 + $1.bodyAge } / Double(window)
            result.append(BodyAgeSample(
                date: samples[index].date,
                chronologicalAge: samples[index].chronologicalAge,
                bodyAge: mean
            ))
        }
        return result
    }

    // MARK: - 各维度加减岁数

    private static func makeAdjustments(_ input: BodyAgeInput, age: Double) -> [BodyAgeAdjustment] {
        var adjustments: [BodyAgeAdjustment] = []

        if let vo2 = MetricSanitizer.value(input.vo2Max, in: MetricRange.vo2Max),
           let male = input.isMale {
            let norm = vo2Norm(age: age, male: male)
            let years = clamp((norm - vo2) * 0.2, -5, 5)
            adjustments.append(.init(
                factor: .vo2Max,
                years: years,
                measured: String(format: "%.1f ml/kg/min（最近一次读数）", vo2),
                reference: String(format: "同年龄性别常模约 %.1f（%@）", norm, male ? "58 − 0.4 × 年龄" : "46 − 0.4 × 年龄"),
                formula: String(format: "(%.1f − %.1f) × 0.2 = %+.1f 岁；封顶 ±5 岁", norm, vo2, years),
                note: "近 7 天内最近一次 VO2max 读数，来自 HealthKit；缺失性别时无法计算常模。"
            ))
        }
        if let hr = MetricSanitizer.value(input.restingHR, in: MetricRange.restingHR) {
            let years: Double
            let formula: String
            if hr < 60 {
                years = clamp((hr - 60) * 0.1, -3, 0)
                formula = String(format: "(%.0f − 60) × 0.1 = %+.1f 岁；最多 −3 岁", hr, years)
            } else if hr > 75 {
                years = clamp((hr - 75) * 0.15, 0, 3)
                formula = String(format: "(%.0f − 75) × 0.15 = %+.1f 岁；最多 +3 岁", hr, years)
            } else {
                years = 0
                formula = "落在 60–75 正常带内，不加不减。"
            }
            adjustments.append(.init(
                factor: .restingHR,
                years: years,
                measured: String(format: "%.0f 次/分（近 7 日均值）", hr),
                reference: "60–75 次/分",
                formula: formula,
                note: "心率越低（在正常范围内）通常代表心肺效率越好，系数 0.1 / 0.15 为经验值。"
            ))
        }
        if let sleep = MetricSanitizer.value(input.sleepHours, in: MetricRange.sleepHours) {
            let years: Double
            let formula: String
            if sleep < 7 {
                years = clamp((7 - sleep) * 0.8, 0, 4)
                formula = String(format: "(7 − %.1f) × 0.8 = %+.1f 岁；最多 +4 岁", sleep, years)
            } else if sleep > 9 {
                years = clamp((sleep - 9) * 0.5, 0, 2)
                formula = String(format: "(%.1f − 9) × 0.5 = %+.1f 岁；最多 +2 岁", sleep, years)
            } else {
                years = 0
                formula = "落在 7–9 小时正常带内，不加不减。"
            }
            adjustments.append(.init(
                factor: .sleepDuration,
                years: years,
                measured: String(format: "%.1f 小时/天（近 7 日均值）", sleep),
                reference: "7–9 小时/天",
                formula: formula,
                note: "睡眠不足按 0.8 岁/小时、过长按 0.5 岁/小时计入，均为经验系数。"
            ))
        }
        if let sd = input.sleepMidpointSDMinutes, sd.isFinite, sd >= 0 {
            let years = clamp((max(0, sd) - 30) * 0.02, -0.6, 2)
            adjustments.append(.init(
                factor: .sleepRegularity,
                years: years,
                measured: String(format: "入睡中点波动 SD %.0f 分钟（近 7 日）", sd),
                reference: "SD ≤ 30 分钟视为规律",
                formula: String(format: "(%.0f − 30) × 0.02 = %+.1f 岁；封顶 −0.6 / +2.0 岁", sd, years),
                note: "用近 7 日入睡中点的样本标准差衡量作息规律性，至少需要 3 天睡眠分期数据。"
            ))
        }
        // 优先用 workouts 心率区间折算的「有效训练分钟」（中等强度以上更被看重），
        // 心率数据缺失时退回近 7 日锻炼总时长，保证旧口径不被破坏。
        let trainingMinutes: Double? = {
            if let zone = input.weeklyZoneMinutes, zone.reduce(0, +) > 0 {
                return BodyAgeEngine.effectiveTrainingMinutes(zone)
            }
            return input.weeklyExerciseMinutes
        }()
        if let minutes = trainingMinutes, minutes >= 0, minutes.isFinite {
            let years = clamp((150 - minutes) * 0.01, -2, 3)
            let (measured, note): (String, String)
            if let zone = input.weeklyZoneMinutes, zone.reduce(0, +) > 0 {
                measured = String(format: "%.0f 有效训练分钟/周（近 7 日 workouts 心率区间折算）", minutes)
                note = "取近 7 日 workouts 心率区间累计，按强度加权为有效训练分钟（Z1–Z5 权重 0.4/0.8/1.0/1.0/0.7）；心率数据缺失时退回锻炼总时长。"
            } else {
                measured = String(format: "%.0f 分钟/周（近 7 日累计）", minutes)
                note = "取近 7 日 Apple Watch 锻炼分钟累计；心率区间数据缺失时使用的退回口径。"
            }
            adjustments.append(.init(
                factor: .weeklyExercise,
                years: years,
                measured: measured,
                reference: "150 分钟/周（WHO 成人建议下限）",
                formula: String(format: "(150 − %.0f) × 0.01 = %+.1f 岁；封顶 −2 / +3 岁", minutes, years),
                note: note
            ))
        }
        if let steps = MetricSanitizer.value(input.dailySteps, in: MetricRange.steps) {
            let years = clamp((8_000 - steps) / 1_000 * 0.15, -1.5, 2)
            adjustments.append(.init(
                factor: .steps,
                years: years,
                measured: String(format: "%.0f 步/天（近 7 日均值）", steps),
                reference: "8,000 步/天",
                formula: String(format: "(8000 − %.0f) ÷ 1000 × 0.15 = %+.1f 岁；封顶 −1.5 / +2.0 岁", steps, years),
                note: "每少 1,000 步加 0.15 岁、每多 1,000 步减 0.15 岁，经验系数。"
            ))
        }
        if let fat = MetricSanitizer.value(input.bodyFatPct, in: MetricRange.bodyFatPct),
           let male = input.isMale {
            let lower = male ? 10.0 : 18.0
            let upper = male ? 20.0 : 28.0
            let deviation = fat < lower ? (fat - lower) : (fat > upper ? (fat - upper) : 0)
            let years = clamp(deviation * 0.15, -2, 2)
            adjustments.append(.init(
                factor: .bodyFat,
                years: years,
                measured: String(format: "%.1f%%（最近一次读数）", fat),
                reference: String(format: "%.0f–%.0f%%（%@参考带）", lower, upper, male ? "男" : "女"),
                formula: String(format: "超出参考带 %.1f 个百分点 × 0.15 = %+.1f 岁；封顶 ±2 岁", deviation, years),
                note: "带内记 0 岁；参考带按性别区分，需先在档案里填写性别。"
            ))
        }

        // 饮水与饮食：只在同步到数据后才参与，历史缺数据的日期不会凭空多出两项。
        let config = ScoringConfig()
        if let water = MetricSanitizer.value(input.nutrition.waterTotalMl, in: MetricRange.waterMl) {
            let years = clamp((config.nutritionWaterTargetMl - water) / 1_000 * 0.4, -0.6, 1.2)
            adjustments.append(.init(
                factor: .hydration,
                years: years,
                measured: String(format: "%.0f 毫升/天（近 7 日均值）", water),
                reference: String(format: "%.0f 毫升/天", config.nutritionWaterTargetMl),
                formula: String(
                    format: "(%.0f − %.0f) ÷ 1000 × 0.4 = %+.1f 岁；封顶 −0.6 / +1.2 岁",
                    config.nutritionWaterTargetMl, water, years
                ),
                note: "健康 App 同步的饮水量与本 App 喝水打卡合并后取近 7 日均值；回写到健康 App 的样本已从读取结果里排除，不会重复计数。"
            ))
        }
        // 饮食质量 = 营养质量（健康 App 同步）+ 规律饮食（本 App 餐次打卡）。
        // 两者合并为一条 dietQuality 调整，保持 BodyAgeFactor 的 id 唯一与既有列表顺序不变；
        // 没有饮食打卡时规律部分恒为 0，既有身体年龄结果完全不变。
        let regularity = input.mealRegularityScore
        let regularityYears: Double = {
            guard let regularity else { return 0 }
            let cap = config.bodyAgeMealRegularityCap
            return clamp((75 - regularity) * config.bodyAgeMealRegularityFactor, -cap, cap)
        }()
        if input.nutrition.hasDietData,
           let score = NutritionEngine.dietScore(input.nutrition, config: config) {
            // 饮食评分下降 → 增龄；评分改善 → 减龄。中性基准取及格/优秀的中点 75 分。
            let nutritionYears = clamp(
                (config.bodyAgeDietNeutralScore - score) * config.bodyAgeDietFactor,
                -config.bodyAgeDietImprovementCap,
                config.bodyAgeDietWorseningCap
            )
            let years = clamp(
                nutritionYears + regularityYears,
                -config.bodyAgeDietImprovementCap - config.bodyAgeMealRegularityCap,
                config.bodyAgeDietWorseningCap + config.bodyAgeMealRegularityCap
            )
            var formula = String(
                format: "(%.0f − %.0f) × %.3f = %+.1f 岁",
                config.bodyAgeDietNeutralScore, score, config.bodyAgeDietFactor, nutritionYears
            )
            var note = "饮食评分以饱和脂肪/总脂肪、糖、碳水为扣分项，膳食纤维与蛋白质为加分项；60 分及格、90 分优秀。低于 75 分增龄，高于 75 分减龄；饮水单独计入 hydration。系数均为经验值。"
            if let regularity {
                formula += String(format: "；规律饮食 (75 − %.0f) × %.3f = %+.1f 岁", regularity, config.bodyAgeMealRegularityFactor, regularityYears)
                note += " 另叠加规律饮食（三餐覆盖、进餐时段、夜宵与近 7 天进餐时刻稳定性）。"
            }
            formula += String(format: "；合计 %+.1f 岁", years)
            adjustments.append(.init(
                factor: .dietQuality,
                years: years,
                measured: String(format: "饮食评分 %.0f / 100（近 7 日均值）", score),
                reference: "75 分为中性基准（60 及格 / 90 优秀）",
                formula: formula,
                note: note
            ))
        } else if let regularity {
            // 只有本 App 餐次打卡、健康 App 没有营养总量时，规律饮食单独成一条。
            adjustments.append(.init(
                factor: .dietQuality,
                years: regularityYears,
                measured: String(format: "规律饮食评分 %.0f / 100（近 7 日均值）", regularity),
                reference: "75 分为中性基准",
                formula: String(
                    format: "(75 − %.0f) × %.3f = %+.1f 岁；封顶 ±%.1f 岁",
                    regularity, config.bodyAgeMealRegularityFactor, regularityYears, config.bodyAgeMealRegularityCap
                ),
                note: "由本 App 餐次打卡的三餐覆盖、进餐时段、夜宵与近 7 天进餐时刻稳定性综合得出；系数均为经验值。"
            ))
        }

        // MARK: 扩展维度：每项单独封顶且系数更小，避免新增指标把年龄数字大幅推高。
        if let efficiency = MetricSanitizer.value(input.sleepEfficiency, in: MetricRange.efficiency) {
            let years = clamp((0.85 - efficiency) * 6, -0.5, 1.0)
            adjustments.append(.init(
                factor: .sleepEfficiency,
                years: years,
                measured: String(format: "%.0f%%（近 7 日均值）", efficiency * 100),
                reference: "≥ 85%",
                formula: String(format: "(0.85 − %.2f) × 6 = %+.1f 岁；封顶 −0.5 / +1.0 岁", efficiency, years),
                note: "睡眠效率 = 实际睡眠 ÷ 卧床时长，来自睡眠分期；系数 6 为经验值。"
            ))
        }
        if let hrv = MetricSanitizer.value(input.hrvSDNN, in: MetricRange.hrv) {
            let years = clamp((40 - hrv) * 0.02, -0.8, 0.8)
            adjustments.append(.init(
                factor: .hrvRecovery,
                years: years,
                measured: String(format: "%.0f ms（近 7 日均值）", hrv),
                reference: "约 40 ms（SDNN 经验参考）",
                formula: String(format: "(40 − %.0f) × 0.02 = %+.1f 岁；封顶 ±0.8 岁", hrv, years),
                note: "HRV 个体差异大，这里只做粗略的相对比较；更可靠的口径是相对个人 28 天基线，见「今日状态」页。"
            ))
        }
        if let bmi = MetricSanitizer.value(input.bmi, in: MetricRange.bmi) {
            let deviation = max(0, 18.5 - bmi) + max(0, bmi - 24)
            let years = clamp(deviation * 0.12, -0.5, 1.0)
            adjustments.append(.init(
                factor: .bmi,
                years: years,
                measured: String(format: "%.1f（最近一次读数）", bmi),
                reference: "18.5–24",
                formula: String(format: "偏离参考带 %.1f × 0.12 = %+.1f 岁；封顶 −0.5 / +1.0 岁", deviation, years),
                note: "BMI 不区分肌肉与脂肪，落在参考带内记 0 岁；与体脂率维度并列展示。"
            ))
        }
        if let systolic = MetricSanitizer.value(input.systolicBP, in: MetricRange.systolicBP),
           let diastolic = MetricSanitizer.value(input.diastolicBP, in: MetricRange.diastolicBP) {
            let years: Double
            if systolic >= 140 || diastolic >= 90 { years = 1.0 }
            else if systolic >= 120 || diastolic >= 80 { years = 0.4 }
            else { years = -0.2 }
            adjustments.append(.init(
                factor: .bloodPressure,
                years: years,
                measured: String(format: "%.0f/%.0f mmHg（最近一次读数）", systolic, diastolic),
                reference: "< 120/80 mmHg",
                formula: String(format: "按 120/80 与 140/90 两档分界计入 %+.1f 岁", years),
                note: "单次手动录入不代表长期血压水平，仅作展示参考，不构成诊断。"
            ))
        }
        if let glucose = MetricSanitizer.value(input.bloodGlucoseMgDl, in: MetricRange.bloodGlucose) {
            let years = clamp((glucose - 100) / 20 * 0.2, -0.3, 0.8)
            adjustments.append(.init(
                factor: .bloodGlucose,
                years: years,
                measured: String(format: "%.0f mg/dL（最近一次读数）", glucose),
                reference: "空腹 < 100 mg/dL",
                formula: String(format: "(%.0f − 100) ÷ 20 × 0.2 = %+.1f 岁；封顶 −0.3 / +0.8 岁", glucose, years),
                note: "健康 App 中的血糖记录未必是空腹值，这里按经验区间粗略折算。"
            ))
        }
        if let daylight = MetricSanitizer.value(input.daylightMinutes, in: MetricRange.daylightMinutes) {
            let years = clamp((20 - daylight) * 0.02, -0.5, 0.5)
            adjustments.append(.init(
                factor: .daylight,
                years: years,
                measured: String(format: "%.0f 分钟/天（近 7 日均值）", daylight),
                reference: "≥ 20 分钟/天",
                formula: String(format: "(20 − %.0f) × 0.02 = %+.1f 岁；封顶 ±0.5 岁", daylight, years),
                note: "日照只在有日光时段累积；今日尚未过完的部分按日光窗口进度折算，睡眠时段不计入。"
            ))
        }
        if let mindful = MetricSanitizer.value(input.mindfulMinutes, in: MetricRange.mindfulMinutes) {
            let years = clamp((10 - mindful) * 0.03, -0.4, 0.4)
            adjustments.append(.init(
                factor: .mindfulness,
                years: years,
                measured: String(format: "%.0f 分钟/天（近 7 日均值）", mindful),
                reference: "≥ 10 分钟/天",
                formula: String(format: "(10 − %.0f) × 0.03 = %+.1f 岁；封顶 ±0.4 岁", mindful, years),
                note: "正念分钟来自健康 App；今日尚未过完的部分按清醒窗口进度折算，睡眠时段不计入。"
            ))
        }

        return adjustments.sorted { $0.factor.order < $1.factor.order }
    }

    private static func bodyAgeOnly(_ input: BodyAgeInput) -> Double? {
        guard let age = input.chronologicalAge, age > 0 else { return nil }
        let total = makeAdjustments(input, age: age).reduce(0) { $0 + $1.years }
        return total == 0 ? age : age + total
    }

    // MARK: - 说明文案（中性文档口吻，不引用任何对话内容）

    static func interpretation(speed: Double, level: AgingSpeedLevel, isBaseline: Bool) -> String {
        if isBaseline {
            return "数据积累中：有效历史还不足以拟合趋势，暂按 1.0x（与日历同速）显示。约需 \(BodyAgeScale.minimumDataDays) 天连续数据后改为实测值。"
        }
        switch level {
        case .younger:
            return String(format: "最近每过 1 年，身体年龄只增长 %.1f 岁%@", speed, speed < 0 ? "（甚至在往下走）" : "，老得比日历慢，方向不错。")
        case .normal:
            return "身体年龄与实际年龄基本同步，每过一年大约长一岁。想让数字往下走，可以从影响最大的那几项入手。"
        case .accelerated:
            return String(format: "最近每过 1 年，身体年龄增长 %.1f 岁，快于日历；下面影响最大的维度值得优先调整。", speed)
        }
    }

    static func explanation(speed: Double, isBaseline: Bool, spanDays: Int, sampleCount: Int) -> String {
        var lines = [
            "衰老速度衡量最近一段时间身体年龄变化的快慢：把近 \(BodyAgeScale.speedWindowDays) 天的每日身体年龄做 \(BodyAgeScale.smoothingWindowDays) 天滑动平均，再相对实际年龄做最小二乘拟合，得到「每过 1 年，身体年龄增长几岁」。身体年龄本身只反映当前所处水平，两者口径不同。",
            "· 1.0x：与日历同速，是标尺的基准刻度。",
            "· 低于 1.0x：老得更慢；负值表示身体年龄在下降。",
            "· 高于 1.0x：衰老偏快。标尺范围 -1x ~ 3x，超出按端点显示。",
            "滑动平均用于抑制单日测量波动：一天睡得少、走得多的影响只有 1/7 进入拟合端点，不会被年化放大。",
        ]
        if isBaseline {
            lines.append("当前显示的是占位基准：有效历史不足（趋势跨度 ≥ \(BodyAgeScale.minimumSpanDays) 天、≥ \(BodyAgeScale.minimumSamples) 个每日样本，每个样本需凑满完整 7 天窗口，约需 \(BodyAgeScale.minimumDataDays) 天连续数据），还不能得出实测速度。")
        } else {
            lines.append(String(format: "当前的 %.1fx 来自 %d 天跨度、%d 个每日样本（滑动平均后）的最小二乘拟合；各项指标长期稳定时，速度会落在 1.0x 附近。", speed, spanDays, sampleCount))
        }
        lines.append("所有系数均为娱乐性经验设定，不构成医学指标或诊断。")
        return lines.joined(separator: "\n")
    }

    // MARK: - 私有工具

    /// 稀疏读数的插补回看上限：与体成分口径一致，最多回看 118 天。
    /// VO2max、血压、BMI、体脂率、血糖这类「状态量」不是每天都测，只认 7 日窗口会让
    /// 历史回算的大部分日期整项缺席、被当成 0 岁（等于「状态最佳」）：数据断档在
    /// 衰老速度里表现为变年轻，读数恢复反而把体龄推高，把速度曲线拟成锯齿。
    static let sparseReadingLookbackDays = 118

    /// 稀疏读数取值（趋势插补）。
    ///
    /// 7 日窗口内有读数就直接用窗口内最近一次；窗口内没有时，不给常数均值，
    /// 而是沿「历史平均值 → 最近一次记录」这条趋势线取值：
    /// - 起点 = 除最近一条外所有记录的均值，锚在它们的日期重心；
    /// - 终点 = 最近一条记录（值 + 日期）；
    /// - 两点之间线性插值，起点之前保持起点值，终点之后保持最近记录值。
    ///
    /// 为什么不用均值：均值会把「血压 128 → 112」「VO2max 33 → 38」这类真实改善抹成一条平线，
    /// 断档期全取同一个数，衰老速度就看不出趋势。也不能取 0：那等于把「没测」当成「状态最佳」，
    /// 断档反而显得变年轻、读数恢复反而把体龄推高（旧实现里 VO2max 因此贡献 +2.59 岁/年）。
    ///
    /// 时间轴按 `now` 锚定，不按 `asOf`：回算 84 天历史时各日期必须落在同一条趋势线上，
    /// 否则每天都因「当时能看到几条记录」不同而跳变，把速度曲线拟成锯齿。
    /// 回看范围内一条记录都没有时返回 nil，该维度整体不参与评分。
    private static func recordedValue(
        _ windowValue: Double?,
        in snapshots: [DailySnapshot],
        asOf: Date,
        now: Date,
        calendar: Calendar,
        lookbackDays: Int = sparseReadingLookbackDays,
        extract: (DailySnapshot) -> Double?
    ) -> Double? {
        if let windowValue { return windowValue }
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -lookbackDays, to: today) else {
            return nil
        }
        var readings: [(day: Date, value: Double)] = []
        for snapshot in snapshots {
            let day = calendar.startOfDay(for: snapshot.date)
            guard day >= cutoff, day <= today, let value = extract(snapshot), value.isFinite else {
                continue
            }
            readings.append((day, value))
        }
        guard let latest = readings.max(by: { $0.day < $1.day }) else { return nil }
        let earlier = readings.filter { $0.day < latest.day }
        guard !earlier.isEmpty else { return latest.value }

        let earlierMean = earlier.reduce(0) { $0 + $1.value } / Double(earlier.count)
        // 起点日期取更早记录的「日期重心」，避免多条记录挤在一天时把斜率算歪。
        let anchor = earlier.reduce(0.0) { $0 + $1.day.timeIntervalSince1970 } / Double(earlier.count)
        let start = Date(timeIntervalSince1970: anchor)
        let target = calendar.startOfDay(for: asOf)
        if target <= start { return earlierMean }
        if target >= latest.day { return latest.value }
        let span = latest.day.timeIntervalSince(start)
        guard span > 0 else { return latest.value }
        let ratio = target.timeIntervalSince(start) / span
        return earlierMean + (latest.value - earlierMean) * ratio
    }

    private static func usableSamples(
        _ samples: [BodyAgeSample],
        now: Date,
        calendar: Calendar
    ) -> [BodyAgeSample] {
        let today = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -BodyAgeScale.speedWindowDays, to: today) else {
            return []
        }
        return samples.filter {
            $0.bodyAge.isFinite
                && $0.chronologicalAge.isFinite
                && $0.chronologicalAge > 0
                && $0.date >= cutoff
                && $0.date <= now
        }
    }

    private static func sampleSpan(
        from samples: [BodyAgeSample],
        now: Date,
        calendar: Calendar
    ) -> Int {
        let usable = usableSamples(samples, now: now, calendar: calendar)
            .sorted { $0.date < $1.date }
        guard usable.count >= BodyAgeScale.smoothingWindowDays else { return 0 }
        let smoothed = movingAverage(usable, window: BodyAgeScale.smoothingWindowDays)
        guard smoothed.count >= BodyAgeScale.minimumSamples,
              let first = smoothed.map(\.date).min(),
              let last = smoothed.map(\.date).max() else { return 0 }
        let span = calendar.dateComponents([.day], from: first, to: last).day ?? 0
        return span >= BodyAgeScale.minimumSpanDays ? span : 0
    }

    private static func windowSnapshots(
        asOf: Date,
        snapshots: [DailySnapshot],
        calendar: Calendar
    ) -> [DailySnapshot] {
        let end = calendar.startOfDay(for: asOf)
        guard let start = calendar.date(byAdding: .day, value: -6, to: end) else { return [] }
        return snapshots.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= end
        }
    }

    private static func mean(_ values: [Double?], in range: ClosedRange<Double>) -> Double? {
        let usable = values.compactMap { MetricSanitizer.value($0, in: range) }
        guard !usable.isEmpty else { return nil }
        return usable.reduce(0, +) / Double(usable.count)
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        min(max(value, lower), upper)
    }
}

// configured by qoder
