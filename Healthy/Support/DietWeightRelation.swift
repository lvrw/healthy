import Foundation

/// 饮食与体重关系卡的单日输入。只保留计算所需的摄入热量与体重，
/// 避免显示层直接依赖 SwiftData 模型，也方便单测构造「缺体重 / 缺热量」的边界场景。
struct DietWeightDay {
    /// 该条记录的日期，窗口排序与截断都以它为准。
    let date: Date
    /// 当日摄入热量（膳食能量；同步值缺失时用本 App 打卡能量兜底）。
    let energyKcal: Double?
    /// 当日体重（智能秤 / 健康 App 记录，通常不是每天都有）。
    let bodyMassKg: Double?
}

/// 关系卡趋势线上的一个点：热量与体重共用同一条时间轴，各自缺失时单独为 nil。
struct DietWeightPoint: Identifiable {
    /// 用日期作为身份标识，两条序列叠在同一张图上时不会互相冲突。
    var id: Date { date }
    /// 记录日期。
    let date: Date
    /// 当日摄入热量，缺记录时为 nil。
    let energyKcal: Double?
    /// 当日体重，缺记录时为 nil。
    let bodyMassKg: Double?
}

/// 近 7 天饮食与体重的对照读数，供饮食详情页的关系区直接渲染。
struct DietWeightRelation {
    /// 统计窗口的自然日数（含当天）。用户口径：只看最近 7 天。
    static let windowDays = 7

    /// 窗口内按日期升序排列的点，供两条迷你曲线共用时间轴。
    let points: [DietWeightPoint]
    /// 窗口内有热量记录的日子求出的日均摄入；没有记录时为 nil。
    let averageEnergyKcal: Double?
    /// 当日摄入目标，只用于文案对照与图表参考线，不参与曲线归一化。
    let thresholdKcal: Double?
    /// 窗口内最早一次有效体重。
    let firstBodyMassKg: Double?
    /// 窗口内最近一次有效体重。
    let lastBodyMassKg: Double?
    /// 最近体重减最早体重；不足两次记录时为 nil。
    let bodyMassChangeKg: Double?
    /// 后半窗口日均摄入减前半窗口日均摄入，正数为摄入上行。
    let energyTrendKcal: Double?
    /// 同时有热量与体重的天数，低于 3 天时不下方向性结论。
    let pairedDays: Int
    /// 一句话解读；数据不足时给出明确的继续记录提示，不留空白。
    let summary: String

    /// 从候选日数据算出关系读数。
    /// - Parameters:
    ///   - days: 任意顺序的日数据；内部按日期升序排序，只保留最近 7 个自然日。
    ///   - thresholdKcal: 摄入目标，nil 时文案不提目标。
    ///   - calendar: 计算自然日窗口的日历，默认当前日历。
    /// - Returns: 可直接渲染的关系读数；输入为空时返回空态文案。
    static func evaluate(
        days: [DietWeightDay],
        thresholdKcal: Double? = nil,
        calendar: Calendar = .current
    ) -> DietWeightRelation {
        let sorted = days.sorted { $0.date < $1.date }
        let window = trimmedWindow(sorted, calendar: calendar)
        let points = window.map {
            DietWeightPoint(date: $0.date, energyKcal: $0.energyKcal, bodyMassKg: $0.bodyMassKg)
        }

        let energies = window.compactMap(\.energyKcal).filter(\.isFinite)
        let averageEnergy = energies.isEmpty ? nil : energies.reduce(0, +) / Double(energies.count)
        let weights = window.compactMap(\.bodyMassKg).filter(\.isFinite)
        let firstWeight = weights.first
        let lastWeight = weights.last
        // 只有一次称量时 first == last，差值恒为 0；那不是「没变化」而是「无从比较」。
        let change: Double?
        if weights.count >= 2, let first = firstWeight, let last = lastWeight {
            change = last - first
        } else {
            change = nil
        }
        let paired = window.filter { $0.energyKcal != nil && $0.bodyMassKg != nil }.count
        let trend = energyTrend(energies)

        return DietWeightRelation(
            points: points,
            averageEnergyKcal: averageEnergy,
            thresholdKcal: thresholdKcal,
            firstBodyMassKg: firstWeight,
            lastBodyMassKg: lastWeight,
            bodyMassChangeKg: change,
            energyTrendKcal: trend,
            pairedDays: paired,
            summary: makeSummary(
                average: averageEnergy,
                threshold: thresholdKcal,
                change: change,
                trend: trend,
                paired: paired,
                weightCount: weights.count
            )
        )
    }

    /// 按最近一条记录的日期往前取 30 个自然日，避免远期数据稀释均值与趋势。
    private static func trimmedWindow(
        _ sorted: [DietWeightDay],
        calendar: Calendar
    ) -> [DietWeightDay] {
        guard let anchor = sorted.last?.date else { return [] }
        let start = calendar.date(byAdding: .day, value: -(windowDays - 1), to: calendar.startOfDay(for: anchor))
            ?? anchor
        return sorted.filter { calendar.startOfDay(for: $0.date) >= start }
    }

    /// 用「有热量记录的日子」平分前后两段，取两段均值的差；不足四天不下趋势结论。
    private static func energyTrend(_ energies: [Double]) -> Double? {
        let half = energies.count / 2
        guard half >= 2, energies.count - half >= 2 else { return nil }
        let early = Array(energies.prefix(half))
        let late = Array(energies.suffix(energies.count - half))
        let earlyAvg = early.reduce(0, +) / Double(early.count)
        let lateAvg = late.reduce(0, +) / Double(late.count)
        return lateAvg - earlyAvg
    }

    /// 生成一句话解读：先陈述数值，再在配对样本充足时给出方向性判断。
    private static func makeSummary(
        average: Double?,
        threshold: Double?,
        change: Double?,
        trend: Double?,
        paired: Int,
        weightCount: Int
    ) -> String {
        guard let average else {
            return "近 \(windowDays) 天还没有饮食记录，记录之后就能看到摄入与体重的变化关系。"
        }
        var parts: [String] = []
        if let threshold {
            parts.append("日均摄入 \(Int(average.rounded())) kcal，目标 \(Int(threshold.rounded())) kcal")
        } else {
            parts.append("日均摄入 \(Int(average.rounded())) kcal")
        }
        guard let change else {
            parts.append(weightCount <= 1 ? "体重记录不足两次" : "这段时间体重没有变化")
            parts.append("继续称量后可以看变化")
            return parts.joined(separator: "，") + "。"
        }
        let direction = change < -0.05 ? "下降" : (change > 0.05 ? "上升" : "基本稳定")
        parts.append(String(format: "体重%@ %.1f kg", direction, abs(change)))
        // 体重受活动、水分、睡眠等多因素影响，样本太少时只报告事实、不推断因果。
        guard paired >= 3, let trend else {
            return parts.joined(separator: "，") + "。"
        }
        if trend < -80 && change < -0.05 {
            parts.append("摄入在减少，与体重下降方向一致")
        } else if trend > 80 && change > 0.05 {
            parts.append("摄入在增加，与体重上升方向一致")
        } else if (trend < -80 && change > 0.05) || (trend > 80 && change < -0.05) {
            parts.append("摄入与体重变化方向不一致，体重还受活动与水分影响")
        }
        return parts.joined(separator: "，") + "。"
    }
}
