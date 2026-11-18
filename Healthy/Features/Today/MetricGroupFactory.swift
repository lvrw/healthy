import SwiftUI

struct MetricGroup {
    let title: String
    let icon: String
    let tint: Color
    let rows: [InfoRow]
    let footnote: String?
}

enum MetricGroupFactory {
    static func groups(metrics: [DailyMetrics], calendar: Calendar = .current) -> [MetricGroup] {
        guard let today = metrics.first else { return [] }
        let others = Array(metrics.dropFirst())
        var groups: [MetricGroup] = []

        let fitness = fitnessRows(today: today, others: others)
        if !fitness.isEmpty {
            groups.append(MetricGroup(
                title: "心肺体能",
                icon: "figure.run",
                tint: .blue,
                rows: fitness,
                footnote: nil
            ))
        }

        let lifestyle = lifestyleRows(today: today, others: others, calendar: calendar)
        if !lifestyle.isEmpty {
            groups.append(MetricGroup(
                title: "生活节律",
                icon: "sun.max.fill",
                tint: .orange,
                rows: lifestyle,
                footnote: nil
            ))
        }

        let body = bodyRows(today: today, others: others)
        if !body.isEmpty {
            groups.append(MetricGroup(
                title: "身体成分",
                icon: "scalemass.fill",
                tint: .purple,
                rows: body,
                footnote: nil
            ))
        }

        let cardio = cardioRows(today: today)
        if !cardio.isEmpty {
            groups.append(MetricGroup(
                title: "心血管代谢",
                icon: "heart.fill",
                tint: .red,
                rows: cardio,
                footnote: "血压 / 血糖没有设备时，可在健康 App 手动记录。"
            ))
        }

        let nutrition = nutritionRows(today: today)
        if !nutrition.isEmpty {
            groups.append(MetricGroup(
                title: "饮食与饮水",
                icon: "fork.knife",
                tint: .mint,
                rows: nutrition,
                footnote: "喝水、咖啡因为健康 App 同步值与本 App 打卡合并后的当日总量（已去重）；其余饮食指标来自健康 App 的营养记录。"
            ))
        }

        return groups
    }

    /// 健康页「身体状况」分组：体重、体脂、肌肉量、BMI、腰围等，数据来自智能秤 / 健康 App。
    static func bodyCompositionGroup(metrics: [DailyMetrics]) -> MetricGroup? {
        guard let today = metrics.first else { return nil }
        let rows = bodyRows(today: today, others: Array(metrics.dropFirst()))
        guard !rows.isEmpty else { return nil }
        return MetricGroup(
            title: "身体状况",
            icon: "scalemass.fill",
            tint: .purple,
            rows: rows,
            footnote: "体重 / 体脂 / 肌肉量来自智能秤或健康 App；BMI 由身高与体重推算，仅供日常参考。"
        )
    }

    private static func fitnessRows(today: DailyMetrics, others: [DailyMetrics]) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let vo2 = today.vo2Max {
            var value = String(format: "%.1f ml/kg/min", vo2)
            if let delta = vo2Delta(today: today, others: others) {
                value += String(format: "（%+.1f）", delta)
            }
            rows.append(InfoRow(label: "VO2max", value: value))
        }
        if let speed = today.walkingSpeedMps {
            rows.append(InfoRow(label: "步行速度", value: String(format: "%.1f km/h", speed * 3.6)))
        }
        if let steadiness = today.walkingSteadinessPct {
            rows.append(InfoRow(label: "步行稳定性", value: String(format: "%.0f%%", steadiness)))
        }
        if let flights = today.flightsClimbed {
            rows.append(InfoRow(label: "爬楼", value: String(format: "%.0f 层", flights)))
        }
        if let distance = today.distanceWalkingKm {
            rows.append(InfoRow(label: "步行 + 跑步", value: String(format: "%.1f km", distance)))
        }
        return rows
    }

    private static func lifestyleRows(
        today: DailyMetrics,
        others: [DailyMetrics],
        calendar: Calendar
    ) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let daylight = today.daylightMinutes {
            rows.append(InfoRow(label: "日照", value: String(format: "%.0f 分钟", daylight)))
        }
        if let mindful = today.mindfulMinutes {
            rows.append(InfoRow(label: "正念", value: String(format: "%.0f 分钟", mindful)))
        }
        if let valence = today.stateOfMindValence {
            rows.append(InfoRow(
                label: "心情",
                value: String(format: "%@（%+.2f）", moodLabel(valence), valence)
            ))
        }
        let history = others.map(\.snapshot)
        if let sd = ScoreSupport.sleepMidpointSD(
            history: history,
            today: today.snapshot,
            config: ScoringConfig(),
            calendar: calendar
        ) {
            let midpoint = clock(today.sleepMidpointMinutes)
            let suffix = midpoint.map { " · 中点 \($0)" } ?? ""
            rows.append(InfoRow(
                label: "作息规律",
                value: String(format: "± %.0f 分钟%@", sd, suffix)
            ))
        } else if let midpoint = clock(today.sleepMidpointMinutes) {
            rows.append(InfoRow(label: "睡眠中点", value: midpoint))
        }
        return rows
    }

    private static func bodyRows(today: DailyMetrics, others: [DailyMetrics]) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let weight = today.bodyMassKg {
            var value = String(format: "%.1f kg", weight)
            if let change = weightChange(today: today, others: others) {
                value += String(format: "（7 天 %+.1f）", change)
            }
            rows.append(InfoRow(label: "体重", value: value))
        }
        if let fat = today.bodyFatPct {
            rows.append(InfoRow(label: "体脂率", value: String(format: "%.1f%%", fat)))
        }
        if let lean = today.leanBodyMassKg {
            rows.append(InfoRow(label: "瘦体重", value: String(format: "%.1f kg", lean)))
        }
        if let bmi = today.bmi {
            rows.append(InfoRow(label: "BMI", value: String(format: "%.1f", bmi)))
        }
        if let waist = today.waistCircumferenceCm {
            rows.append(InfoRow(label: "腰围", value: String(format: "%.1f cm", waist)))
        }
        return rows
    }

    private static func cardioRows(today: DailyMetrics) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let systolic = today.systolicBP, let diastolic = today.diastolicBP {
            let date = today.date.formatted(.dateTime.month().day())
            rows.append(InfoRow(
                label: "血压",
                value: String(format: "%.0f/%.0f mmHg · %@", systolic, diastolic, date)
            ))
        }
        if let glucose = today.bloodGlucoseMgDl {
            rows.append(InfoRow(
                label: "血糖",
                value: String(format: "%.0f mg/dL（%.1f mmol/L）", glucose, glucose / 18)
            ))
        }
        return rows
    }

    /// 饮水与饮食读取字段的逐项展示。喝水 / 咖啡因只展示合并后的当日总量
    ///（健康 App 同步值 + 本 App 打卡，已去重），不再单列来源；
    /// 目标阈值取自 IntakeGoal 配置，跟随用户在设置里调整的最新值。
    private static func nutritionRows(today: DailyMetrics) -> [InfoRow] {
        var rows: [InfoRow] = []
        if let total = today.waterTotalMl {
            let target = IntakeGoal.waterTargetMl()
            rows.append(InfoRow(label: "喝水合计", value: String(format: "%.0f / %.0f ml", total, target)))
        }
        rows.append(contentsOf: dietRows(today))
        if let caffeine = today.dietaryCaffeineMg {
            let limit = IntakeGoal.caffeineLimitMg()
            rows.append(InfoRow(label: "咖啡因合计", value: String(format: "%.0f / %.0f mg", caffeine, limit)))
        }
        return rows
    }

    /// 营养摄入明细（不含喝水 / 咖啡因），首页「饮食与饮水」分组与行动页饮食详情共用同一套取值。
    private static func dietRows(_ today: DailyMetrics) -> [InfoRow] {
        var rows: [InfoRow] = []
        // 同步链路曾把合并总量冲成 nil，此时用 WaterMerge 存下的本地 meal 能量兜底，
        // 保证「今日明细」与行动页饮食卡看到同一个今日摄入值。
        if let energy = today.dietaryEnergyKcal ?? today.localMealEnergyKcal {
            rows.append(InfoRow(label: "热量摄入", value: String(format: "%.0f kcal", energy)))
        }
        if let carbs = today.dietaryCarbsG {
            rows.append(InfoRow(label: "碳水化合物", value: String(format: "%.0f g", carbs)))
        }
        if let protein = today.dietaryProteinG {
            rows.append(InfoRow(label: "蛋白质", value: String(format: "%.0f g", protein)))
        }
        if let fat = today.dietaryFatG {
            rows.append(InfoRow(label: "脂肪", value: String(format: "%.0f g", fat)))
        }
        if let fiber = today.dietaryFiberG {
            rows.append(InfoRow(label: "膳食纤维", value: String(format: "%.0f g", fiber)))
        }
        if let sugar = today.dietarySugarG {
            rows.append(InfoRow(label: "糖", value: String(format: "%.0f g", sugar)))
        }
        if let sodium = today.dietarySodiumMg {
            rows.append(InfoRow(label: "钠", value: String(format: "%.0f mg", sodium)))
        }
        // 评分统一在详情页头部的「饮食评分」展示（饮食质量 70% + 规律饮食 30%）。
        // 这里只留餐次数量作为明细，不再单列「规律饮食 X 分 / 餐次平均分」，避免一天出现多个饮食分数。
        if let count = today.mealCount {
            rows.append(InfoRow(label: "今日餐次", value: String(format: "%d 餐", count)))
        }
        return rows
    }

    /// 行动页「身体成分」卡片：与健康页共用 bodyRows 的取值口径。
    /// others 只用于 7 天体重变化，传空数组时仅展示当日读数。
    static func bodyGroup(today: DailyMetrics?, others: [DailyMetrics] = []) -> MetricGroup? {
        guard let today else { return nil }
        let rows = bodyRows(today: today, others: others)
        guard !rows.isEmpty else { return nil }
        return MetricGroup(
            title: "身体成分",
            icon: "scalemass.fill",
            tint: .purple,
            rows: rows,
            footnote: nil
        )
    }

    /// 行动页「饮食」格子的详情分组：只列营养摄入；喝水 / 咖啡因在行动页各有独立格子，不在此重复。
    /// 当天没有营养数据时给一行空态提示，避免详情页出现空白卡片。
    static func dietGroup(today: DailyMetrics?) -> MetricGroup {
        let rows = today.map { dietRows($0) } ?? []
        return MetricGroup(
            title: "饮食",
            icon: "fork.knife",
            tint: .green,
            rows: rows.isEmpty ? [InfoRow(label: "今日饮食", value: "暂无数据")] : rows,
            footnote: "营养摄入来自健康 App 的膳食记录与本 App 食物打卡；喝水与咖啡因在行动页单独展示。"
        )
    }

    private static func vo2Delta(today: DailyMetrics, others: [DailyMetrics]) -> Double? {
        guard let current = today.vo2Max else { return nil }
        let cutoff = DayKey.addingDays(-28, to: today.date)
        let earlier = others
            .filter { $0.date < today.date && $0.date >= cutoff }
            .compactMap(\.vo2Max)
        guard let baseline = earlier.min() else { return nil }
        return current - baseline
    }

    private static func weightChange(today: DailyMetrics, others: [DailyMetrics]) -> Double? {
        guard let current = today.bodyMassKg else { return nil }
        let cutoff = DayKey.addingDays(-7, to: today.date)
        let earlier = others.first { $0.date <= cutoff && $0.bodyMassKg != nil }?.bodyMassKg
            ?? others.last(where: { $0.bodyMassKg != nil })?.bodyMassKg
        guard let baseline = earlier else { return nil }
        return current - baseline
    }

    private static func moodLabel(_ valence: Double) -> String {
        if valence <= -0.2 { return "消极" }
        if valence < 0.2 { return "中性" }
        return "积极"
    }

    private static func clock(_ minutes: Double?) -> String? {
        guard let minutes else { return nil }
        let normalized = ((minutes.truncatingRemainder(dividingBy: 1_440)) + 1_440)
            .truncatingRemainder(dividingBy: 1_440)
        let hour = Int(normalized) / 60
        let minute = Int(normalized) % 60
        return String(format: "%02d:%02d", hour, minute)
    }
}
