import Foundation

/// 餐次分类。时间窗以「当天 00:00 起的分钟数」表示，跨午夜的夜宵拆成两段。
/// 窗口连续且覆盖全天 24 小时，任何时刻都能推断出一个餐次。
enum MealSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast
    case lunch
    case afternoonTea
    case dinner
    case lateNightSnack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: return "早餐"
        case .lunch: return "午餐"
        case .afternoonTea: return "下午茶"
        case .dinner: return "晚餐"
        case .lateNightSnack: return "夜宵"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .afternoonTea: return "cup.and.saucer.fill"
        case .dinner: return "sunset.fill"
        case .lateNightSnack: return "moon.stars.fill"
        }
    }

    /// 该餐次在「规律三餐」口径里是否算主餐。
    var isMainMeal: Bool {
        switch self {
        case .breakfast, .lunch, .dinner: return true
        case .afternoonTea, .lateNightSnack: return false
        }
    }

    /// 建议时间窗（半开区间）。夜宵跨午夜，用两段表示。
    var windows: [(lower: Int, upper: Int)] {
        switch self {
        case .breakfast: return [(5 * 60, 10 * 60)]           // 05:00–10:00
        case .lunch: return [(10 * 60, 14 * 60)]              // 10:00–14:00
        case .afternoonTea: return [(14 * 60, 17 * 60)]      // 14:00–17:00
        case .dinner: return [(17 * 60, 21 * 60)]             // 17:00–21:00
        case .lateNightSnack: return [(21 * 60, 24 * 60), (0, 5 * 60)] // 21:00–05:00
        }
    }

    /// 该餐次占全天营养目标的建议比例（三餐为主，加餐占小头）。
    var energyShare: Double {
        switch self {
        case .breakfast: return 0.25
        case .lunch: return 0.32
        case .afternoonTea: return 0.08
        case .dinner: return 0.28
        case .lateNightSnack: return 0.07
        }
    }

    /// 按用餐时刻推断餐次；落在窗口边界归后一个窗口，保证 24 小时无空档。
    static func infer(from date: Date, calendar: Calendar = .current) -> MealSlot {
        let minute = minuteOfDay(date, calendar: calendar)
        for slot in ordered {
            for window in slot.windows where minute >= window.lower && minute < window.upper {
                return slot
            }
        }
        return .lateNightSnack
    }

    /// 判断某时刻是否落在该餐次建议窗口内（用于规律饮食的「时段合理性」）。
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        let minute = MealSlot.minuteOfDay(date, calendar: calendar)
        return windows.contains { minute >= $0.lower && minute < $0.upper }
    }

    /// 展示顺序：早 → 午 → 下午茶 → 晚 → 夜宵。
    static let ordered: [MealSlot] = [.breakfast, .lunch, .afternoonTea, .dinner, .lateNightSnack]

    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// 一条饮食打卡，供餐次/规律/评分引擎使用（纯值类型，可跨并发域）。
struct MealEntry: Sendable, Equatable, Identifiable {
    var id: String
    var date: Date
    var slot: MealSlot
    var nutrition: IntakeNutrition
    /// 保存时算好的每餐评分；旧记录可能没有，规律引擎不依赖它。
    var score: Double? = nil

    init(id: String = UUID().uuidString, date: Date, slot: MealSlot, nutrition: IntakeNutrition, score: Double? = nil) {
        self.id = id
        self.date = date
        self.slot = slot
        self.nutrition = nutrition
        self.score = score
    }
}

/// 单餐健康评价。
struct MealEvaluation: Sendable, Equatable {
    /// 0–100，越高越健康。
    var score: Double
    /// 是否判定为「健康」（达到健康线且没有硬性不健康因素）。
    var isHealthy: Bool
    /// 结论文案（优秀 / 良好 / 一般 / 需注意）。
    var level: String
    /// 具体加分/扣分说明，用于 UI 展示与解释。
    var notes: [String]
}

/// 规律饮食评价。
struct MealRegularity: Sendable, Equatable {
    /// 0–100；没有任何饮食记录时为 nil，评分层会跳过该维度。
    var score: Double?
    var level: String
    var summary: String
    /// 当天覆盖到的主餐（早餐/午餐/晚餐）。
    var coveredMainMeals: [MealSlot]
    /// 近 7 天里进餐时刻稳定的天数。
    var stableDays: Int
    /// 可解释的原因 / 建议。
    var notes: [String]
}

/// 饮食的餐次划分、单餐健康评分与规律饮食判断。全部为纯函数，便于单测与跨并发域调用。
enum MealScoringEngine {

    // MARK: - 单餐评分

    /// 给一餐评分：以饱和脂肪、糖、碳水、总脂肪为核心扣分项，膳食纤维与蛋白质为加分项，
    /// 全天参考值按餐次占比缩放；水作为轻微辅助项，再计入「是否落在建议时段」「是否夜宵」。
    /// 及格 60 / 优秀 90；饱和脂肪、糖或脂肪任一明显偏高时不能评为优秀，两项以上直接不及格。
    static func evaluate(
        nutrition: IntakeNutrition,
        slot: MealSlot,
        date: Date,
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current
    ) -> MealEvaluation {
        let share = slot.energyShare
        let proteinTarget = config.nutritionProteinTargetG * share
        let waterTarget = config.nutritionWaterTargetMl * share
        // 咖啡因在一天内集中摄入（早上一杯咖啡就上百 mg），不能按单餐能量占比缩放到 50mg。
        // 单餐与全天共用同一个日上限，只有单餐摄入本身就超过全天建议量时才扣分。
        let caffeineLimit = config.nutritionCaffeineLimitMg

        var notes: [String] = []

        let quality = NutritionEngine.dietQuality(
            saturatedFat: nutrition.saturatedFatG,
            fat: nutrition.fatG,
            carbs: nutrition.carbsG,
            sugar: nutrition.sugarG,
            fiber: nutrition.fiberG,
            protein: nutrition.proteinG,
            caffeine: nutrition.caffeineMg,
            share: share,
            caffeineLimitOverride: caffeineLimit,
            config: config
        ) ?? config.nutritionPassingScore

        // 核心扣分提示，便于 UI 解释为什么油/糖/碳水偏高的餐次分数低。
        let saturatedFatLimit = config.nutritionSaturatedFatLimitG * share
        let fatLimit = config.nutritionFatLimitG * share
        let carbLimit = config.nutritionCarbsLimitG * share
        let sugarLimit = config.nutritionSugarLimitG * share
        if nutrition.saturatedFatG > saturatedFatLimit {
            notes.append("饱和脂肪偏多（建议不超过 \(Int(saturatedFatLimit)) g）")
        }
        if nutrition.fatG > fatLimit {
            notes.append("总脂肪偏多（建议不超过 \(Int(fatLimit)) g）")
        }
        if nutrition.carbsG > carbLimit {
            notes.append("碳水偏多（建议不超过 \(Int(carbLimit)) g）")
        }
        if nutrition.sugarG > sugarLimit {
            notes.append("糖偏多（建议不超过 \(Int(sugarLimit)) g）")
        }
        if nutrition.caffeineMg > caffeineLimit {
            notes.append("咖啡因偏多（建议全天不超过 \(Int(caffeineLimit)) mg）")
        }
        // 优质营养素提示：体现「增加蛋白质 / 纤维摄入」的目标。
        if nutrition.proteinG >= proteinTarget {
            notes.append("蛋白质充足（≥ \(Int(proteinTarget)) g）")
        } else if nutrition.proteinG < proteinTarget * 0.6 {
            notes.append("蛋白质偏少（建议 \(Int(proteinTarget)) g）")
        }
        if nutrition.fiberG >= config.nutritionFiberTargetG * share {
            notes.append("膳食纤维充足")
        }

        var score = quality
        // 水：只有饮品这类带含水量的记录才评价，普通餐食不因没填水而扣分；
        // 也不参与核心硬上限判断，只做轻微辅助扣分。
        if nutrition.waterMl > 0 {
            let water = MealScoringEngine.floorScore(nutrition.waterMl, target: waterTarget)
            score -= (100 - water) * config.mealWaterPenaltyFactor
        }
        var hasTimingPenalty = false

        // 时段合理性：不在建议窗口内扣固定分。
        if !slot.contains(date, calendar: calendar) {
            score -= config.mealOffWindowPenalty
            notes.append("用餐时间偏离该餐次常规时段")
            hasTimingPenalty = true
        }
        // 夜宵单独扣分：即使营养均衡，进食时机本身也不利于规律作息。
        if slot == .lateNightSnack {
            score -= config.mealLateNightPenalty
            notes.append("夜宵不利于规律作息")
            hasTimingPenalty = true
        }
        score = ScoreSupport.clampScore(score)

        let level: String
        if score >= config.mealExcellentThreshold { level = "优秀" }
        else if score >= config.mealHealthyThreshold { level = "良好" }
        else if score >= config.mealFairThreshold { level = "一般" }
        else { level = "需注意" }

        // 健康 = 达到健康线，且没有夜宵 / 用餐时段偏离这类硬性因素。
        let isHealthy = score >= config.mealHealthyThreshold
            && slot != .lateNightSnack
            && !hasTimingPenalty

        if notes.isEmpty { notes.append("营养结构均衡，用餐时段合理") }
        return MealEvaluation(score: score, isHealthy: isHealthy, level: level, notes: notes)
    }

    // MARK: - 规律饮食

    /// 判断某一天的饮食是否规律：三餐覆盖 + 时段合理 + 夜宵 + 进餐间隔，
    /// 再叠加近 7 天同一餐次进餐时刻的稳定性（标准差式口径）。
    /// 只有早/午/晚三餐参与评分（夜宵为独立扣分项），下午茶等加餐不计入餐数；
    /// 未到时间的餐次也不提前扣分。
    /// - parameter entries: 近 N 天全部饮食打卡（引擎内部筛选窗口）。
    static func regularity(
        entries: [MealEntry],
        on date: Date,
        config: ScoringConfig = ScoringConfig(),
        calendar: Calendar = .current,
        now: Date = .now
    ) -> MealRegularity {
        let dayKey = DayKey.key(for: date, calendar: calendar)
        let today = entries
            .filter { DayKey.key(for: $0.date, calendar: calendar) == dayKey }
            .sorted { $0.date < $1.date }

        guard !today.isEmpty else {
            return MealRegularity(
                score: nil,
                level: "暂无数据",
                summary: "今天还没有饮食记录，记录后可查看规律饮食分析。",
                coveredMainMeals: [],
                stableDays: 0,
                notes: ["记录早餐、午餐、晚餐后可评估饮食规律"]
            )
        }

        var score = 0.0
        var notes: [String] = []

        // 1) 三餐覆盖（最高 45 分）。只对「已到期」的主餐次检查覆盖：
        //    当前时间已过该餐次建议窗口结束 + 30 分钟缓冲，才算到期。
        //    这样早上 8 点吃完早餐，不会因为午餐晚餐还没到时间就被扣缺餐分。
        let dueGraceMinutes = 30
        let nowMinute = MealSlot.minuteOfDay(now, calendar: calendar)
        let dueMainMeals = MealSlot.ordered.filter { slot in
            guard slot.isMainMeal else { return false }
            // 主餐次都不跨午夜，取第一个窗口的 upper 即可
            guard let window = slot.windows.first else { return false }
            return nowMinute >= window.upper + dueGraceMinutes
        }

        let covered = dueMainMeals.filter { slot in
            today.contains { $0.slot == slot }
        }
        if dueMainMeals.isEmpty {
            // 还没有任何主餐次到期（比如大清早），给满分避免误扣
            score += 45
        } else {
            score += Double(covered.count) / Double(dueMainMeals.count) * 45
        }
        let missing = dueMainMeals.filter { !covered.contains($0) }
        let futureMainMeals = MealSlot.ordered.filter { $0.isMainMeal && !dueMainMeals.contains($0) }
        if !missing.isEmpty {
            notes.append("今天还缺" + missing.map(\.title).joined(separator: "、"))
        } else if dueMainMeals.isEmpty {
            notes.append("今日主餐尚未到检查时点")
        } else if !futureMainMeals.isEmpty {
            notes.append("到期餐次已覆盖")
        } else {
            notes.append("三餐齐全")
        }

        // 2) 时段合理性（最高 20 分）：只按早/午/晚三餐评估，分母是「已到期主餐」数，
        //    分子是其中有记录且落在建议窗口内的餐次数。下午茶 / 夜宵不参与，
        //    未到时间的餐次也不进入分母，避免四餐口径和提前扣分。
        let onTimeMainMeals = dueMainMeals.filter { slot in
            today.contains { $0.slot == slot && slot.contains($0.date, calendar: calendar) }
        }
        if dueMainMeals.isEmpty {
            // 还没有任何主餐到期（比如大清早），给满分避免误扣
            score += 20
        } else {
            score += Double(onTimeMainMeals.count) / Double(dueMainMeals.count) * 20
        }
        let offTime = dueMainMeals.filter { slot in
            today.contains { $0.slot == slot } && !onTimeMainMeals.contains(slot)
        }.count
        if offTime > 0 {
            notes.append("有 \(offTime) 餐偏离常规时段")
        }

        // 3) 夜宵（10 分）：无夜宵得满分，有则 0 分并提示。
        let hasLateNight = today.contains { $0.slot == .lateNightSnack }
        if hasLateNight {
            notes.append("今天有夜宵")
        } else {
            score += 10
        }

        // 4) 进餐间隔（最高 10 分）：只按早/午/晚三餐的相邻间隔计算，下午茶 / 夜宵不参与，
        //    避免加餐把一段合理间隔拆成两段短间隔而误扣分数。
        let mainEntries = today.filter { $0.slot.isMainMeal }
        var reasonableGaps = 0
        var gapCount = 0
        if mainEntries.count >= 2 {
            for i in 1..<mainEntries.count {
                gapCount += 1
                let hours = mainEntries[i].date.timeIntervalSince(mainEntries[i - 1].date) / 3600
                if hours >= config.mealMinGapHours, hours <= config.mealMaxGapHours {
                    reasonableGaps += 1
                }
            }
            score += Double(reasonableGaps) / Double(gapCount) * 10
        } else {
            // 只有一餐时没有可比较的间隔，不评也不扣分（缺餐已由三餐覆盖项体现），
            // 保持与「未到期的餐次不扣分」一致。
            score += 10
        }

        // 5) 近 7 天进餐时刻稳定性（最高 15 分）。
        let stableDays = stableDayCount(entries: entries, before: date, config: config, calendar: calendar)
        score += Double(stableDays) / Double(config.mealRegularityWindowDays) * 15
        if stableDays == 0 {
            notes.append("近 7 天进餐时刻波动较大或记录不足")
        } else {
            notes.append("近 7 天有 \(stableDays) 天进餐时刻稳定")
        }

        // coveredMainMeals 是今天实际吃过的所有主餐（供 UI 展示，不受到期逻辑影响）。
        let eatenMainMeals = MealSlot.ordered.filter { slot in
            slot.isMainMeal && today.contains { $0.slot == slot }
        }

        score = ScoreSupport.clampScore(score)
        let level: String
        if score >= config.mealRegularityGoodThreshold { level = "规律" }
        else if score >= config.mealRegularityFairThreshold { level = "基本规律" }
        else { level = "不规律" }

        let summary: String
        switch level {
        case "规律":
            summary = "三餐定时、时段合理，近一周进餐节奏稳定。"
        case "基本规律":
            summary = "整体尚可，仍有缺餐或时段偏移可改善。"
        default:
            summary = "进餐时间或餐次分布不够规律，建议固定三餐时段。"
        }

        return MealRegularity(
            score: score,
            level: level,
            summary: summary,
            coveredMainMeals: eatenMainMeals,
            stableDays: stableDays,
            notes: notes
        )
    }

    /// 近 N 天里，同一餐次进餐时刻与「该餐次历史中位数」偏差不超过阈值的天数。
    /// 每天只要有任一主餐在容差内即计为稳定日；不足 2 天历史时不计入（避免样本过少误判）。
    private static func stableDayCount(
        entries: [MealEntry],
        before date: Date,
        config: ScoringConfig,
        calendar: Calendar
    ) -> Int {
        let start = calendar.date(byAdding: .day, value: -(config.mealRegularityWindowDays - 1), to: calendar.startOfDay(for: date)) ?? date
        let window = entries.filter { $0.date >= start && $0.date <= date }
        var minutesBySlot: [MealSlot: [Int]] = [:]
        for entry in window where entry.slot.isMainMeal {
            minutesBySlot[entry.slot, default: []].append(MealSlot.minuteOfDay(entry.date, calendar: calendar))
        }
        // 历史样本不足时返回 0，UI 会提示「记录不足」。
        let totalSamples = minutesBySlot.values.reduce(0) { $0 + $1.count }
        guard totalSamples >= 2 else { return 0 }

        var medians: [MealSlot: Double] = [:]
        for (slot, minutes) in minutesBySlot {
            let sorted = minutes.sorted()
            medians[slot] = sorted.count % 2 == 0
                ? Double(sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
                : Double(sorted[sorted.count / 2])
        }

        var byDay: [String: [MealEntry]] = [:]
        for entry in window where entry.slot.isMainMeal {
            byDay[DayKey.key(for: entry.date, calendar: calendar), default: []].append(entry)
        }
        var stable = 0
        for (_, dayEntries) in byDay {
            let ok = dayEntries.contains { entry in
                guard let median = medians[entry.slot] else { return false }
                return abs(Double(MealSlot.minuteOfDay(entry.date, calendar: calendar)) - median)
                    <= config.mealStableMinuteTolerance
            }
            if ok { stable += 1 }
        }
        return min(stable, config.mealRegularityWindowDays)
    }

    // MARK: - 评分层接入

    /// 供 ReadinessEngine 使用的规律饮食分量：0–100；无数据时 nil，加权平均会自动忽略，
    /// 因此不会改变任何既有评分结果。
    static func readinessComponent(_ snapshot: DailySnapshot, config: ScoringConfig = ScoringConfig()) -> Double? {
        guard let regularity = snapshot.mealRegularityScore else { return nil }
        return ScoreSupport.clampScore(regularity)
    }

    // MARK: - 私有打分工具

    private static func floorScore(_ value: Double, target: Double) -> Double {
        guard target > 0 else { return 100 }
        return ScoreSupport.clampScore(value / target * 100)
    }
}
