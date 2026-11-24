import Charts
import SwiftUI

/// 首页所有带分项评分的指标卡（评分拆解区 + 更多指标区）点进去的详情页。
/// 今日明细直接复用首页卡片的 MetricGroup（同一份 rows / footnote），
/// 趋势部分从 DailyMetrics 历史里按字段取值，避免两处口径不一致。
struct MetricGroupDetailView: View {
    let group: MetricGroup
    /// 当日分项评分（0–100），数据不足时为 nil。
    let score: Double?
    /// @Query 结果，按 dayKey 倒序（今天在前）。
    let metrics: [DailyMetrics]
    /// 详情页顶部的「记录 / 设置」入口（目前只有饮食详情用到），空数组时不显示。
    let entries: [ActionCardSheet]
    /// 饮食设置页的维持热量估算值。
    let estimatedMaintenanceKcal: Double?
    /// 饮食详情头部额外展示的「今日摄入 / 阈值 kcal」；其他分组传 nil 时不显示。
    let calorieSummary: String?
    /// 今日摄入超出阈值的千卡数：非 nil 时在摘要旁加一枚红色超限胶囊。
    let calorieOverageKcal: Double?
    /// 详情页当前查看的日期；饮食详情可切换日期，其余分组固定为今天。
    var dayDate: Date = DayKey.startOfDay(.now)
    /// 摄入与体重对照区；只有饮食详情传入，其他分组为 nil。
    let dietWeightRelation: DietWeightRelation?

    /// 默认选中当前分组的第一个指标，保证详情页打开时图表一定有内容可选。
    @State private var selectedField: MetricTrendField
    /// 趋势图被点选的日期：在对应节点上方弹出当日数值。
    @State private var selectedPointDate: Date?
    /// 导航栏右上角齿轮打开的设置页。
    @State private var settingsSheet: ActionCardSheet?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        group: MetricGroup,
        score: Double?,
        metrics: [DailyMetrics],
        entries: [ActionCardSheet] = [],
        estimatedMaintenanceKcal: Double? = nil,
        calorieSummary: String? = nil,
        calorieOverageKcal: Double? = nil,
        dayDate: Date = DayKey.startOfDay(.now),
        dietWeightRelation: DietWeightRelation? = nil
    ) {
        self.group = group
        self.score = score
        self.metrics = metrics
        self.entries = entries
        self.estimatedMaintenanceKcal = estimatedMaintenanceKcal
        self.calorieSummary = calorieSummary
        self.calorieOverageKcal = calorieOverageKcal
        self.dayDate = dayDate
        self.dietWeightRelation = dietWeightRelation
        _selectedField = State(initialValue: MetricTrendField.fields(for: group.title).first ?? .vo2Max)
    }

    /// 日期前缀：今天说「今日」，切到历史日期后统一说「当日」。
    private var dayPrefix: String {
        Calendar.current.isDate(dayDate, inSameDayAs: .now) ? "今日" : "当日"
    }

    /// 记录类入口仍放在页头入口条；设置类入口收进导航栏齿轮。
    private var recordEntries: [ActionCardSheet] {
        entries.filter { !$0.isSettings }
    }

    private var settingsEntry: ActionCardSheet? {
        entries.first(where: \.isSettings)
    }

    /// 详情趋势窗口：最近 30 个有记录的自然日，按时间正序。
    private var window: [DailyMetrics] {
        Array(metrics.prefix(30).reversed())
    }

    private var fields: [MetricTrendField] {
        MetricTrendField.fields(for: group.title)
    }

    private var points: [MetricTrendPoint] {
        window.compactMap { row in
            selectedField.value(row).map { MetricTrendPoint(date: row.date, value: $0) }
        }
    }

    private var average: Double? {
        guard !points.isEmpty else { return nil }
        return points.reduce(0) { $0 + $1.value } / Double(points.count)
    }

    private var highest: Double? { points.map(\.value).max() }
    private var lowest: Double? { points.map(\.value).min() }

    /// 点选日期对应的最近节点；松手在两点之间时也能吸附到最近的节点。
    private var selectedPoint: MetricTrendPoint? {
        guard let selectedPointDate else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(selectedPointDate))
                < abs($1.date.timeIntervalSince(selectedPointDate))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                // 睡眠报告入口固定在详情页最顶上（头部卡之后第一张），
                // 原先排在趋势卡之后，打开页面根本看不到，被当成「没有了」。
                if group.title == "睡眠" {
                    sleepReportCard
                }
                if !recordEntries.isEmpty {
                    ActionEntryBar(
                        entries: recordEntries,
                        date: dayDate,
                        estimatedMaintenanceKcal: estimatedMaintenanceKcal
                    )
                }
                todayCard
                // 饮食相关分组额外展示「饮食评分构成 + 当日餐次时间轴」，跟随所选日期。
                // 顶部 score 就是统一饮食评分，传给卡片避免再算一个规律分造成双分数。
                if group.title == "饮食" || group.title == "饮食与饮水" {
                    MealTimelineCard(date: dayDate, unifiedScore: score)
                }
                trendCard
                // 饮食详情额外展示「摄入与体重」近 7 天对照，跟随所选日期重新取值。
                if let dietWeightRelation {
                    dietWeightRelationCard(relation: dietWeightRelation)
                }
                sourceCard
            }
            .padding(16)
        }
        .background(AppScreenBackground(tone: .white))
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let settingsEntry {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        settingsSheet = settingsEntry
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(settingsEntry.label)
                }
            }
        }
        .sheet(item: $settingsSheet) { sheet in
            ActionCardSheetPage(
                sheet: sheet,
                date: dayDate,
                estimatedMaintenanceKcal: estimatedMaintenanceKcal
            )
        }
    }

    /// 头部：分组图标 + 当日分项评分，与首页卡片右上角角标一致。
    /// 饮食额外显示「今日摄入 / 阈值」胶囊，超限时并列一枚红色超出胶囊。
    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: group.icon)
                    .font(.title2)
                    .foregroundStyle(group.tint)
                    .frame(width: 44, height: 44)
                    .background(
                        group.tint.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.title)
                        .font(.headline)
                    Text("\(dayPrefix)分项评分 · 相对个人基线")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let score {
                    Text("\(Int(score.rounded())) 分")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .foregroundStyle(group.tint)
                } else {
                    Text("暂无评分")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            if calorieSummary != nil || calorieOverageKcal != nil {
                HStack(spacing: 6) {
                    if let calorieSummary {
                        Text(calorieSummary)
                            .font(.caption.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(group.tint.opacity(0.1), in: Capsule())
                    }
                    if let overage = calorieOverageKcal, overage > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text("超出 \(Int(overage.rounded())) kcal")
                                .font(.caption2.weight(.semibold).monospacedDigit())
                        }
                        .foregroundStyle(AppPalette.red)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(AppPalette.red.opacity(0.1), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .appCard()
        .cardScrollEffect()
    }

    /// 今日明细：直接渲染首页卡片里的 rows，保证点进去不会「换一套数」。
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "\(dayPrefix)明细", icon: "list.bullet.rectangle", tint: group.tint)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.rows) { row in
                    MetricInfoRowView(row: row)
                }
            }
            if let footnote = group.footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .appCard()
        .cardScrollEffect()
    }

    /// 近 30 天趋势：切换分组内的单个指标，折线 + 最新 / 均值 / 最高 / 最低。
    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "近 30 天趋势", icon: "chart.xyaxis.line", tint: group.tint)
            if fields.isEmpty {
                Text("该分组暂无可绘制趋势的指标。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Picker("指标", selection: $selectedField) {
                    ForEach(fields) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.menu)

                if points.isEmpty {
                    Text("近 30 天还没有「\(selectedField.label)」的数据。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 100, alignment: .center)
                } else {
                    Chart {
                        ForEach(points) { point in
                            LineMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value(selectedField.label, point.value)
                            )
                            .foregroundStyle(group.tint)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("日期", point.date, unit: .day),
                                y: .value(selectedField.label, point.value)
                            )
                            .foregroundStyle(group.tint)
                            .symbolSize(24)
                        }
                        if let selectedPoint {
                            RuleMark(x: .value("日期", selectedPoint.date, unit: .day))
                                .foregroundStyle(group.tint.opacity(0.35))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            PointMark(
                                x: .value("日期", selectedPoint.date, unit: .day),
                                y: .value(selectedField.label, selectedPoint.value)
                            )
                            .foregroundStyle(group.tint)
                            .symbolSize(72)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month().day())
                        }
                    }
                    .frame(height: 180)
                    // 每个节点都可点击：点中后吸附到最近的节点，并在其上方弹出当日数值。
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            ZStack {
                                Rectangle()
                                    .fill(.clear)
                                    .contentShape(Rectangle())
                                    .gesture(
                                        SpatialTapGesture()
                                            .onEnded { value in
                                                guard let plotFrame = proxy.plotFrame else { return }
                                                let x = value.location.x - geometry[plotFrame].origin.x
                                                guard let date = proxy.value(atX: x, as: Date.self) else { return }
                                                let hit = points.min {
                                                    abs($0.date.timeIntervalSince(date))
                                                        < abs($1.date.timeIntervalSince(date))
                                                }
                                                withAnimation(reduceMotion ? nil : .snappy) {
                                                    if let hit, let selectedPoint,
                                                       Calendar.current.isDate(hit.date, inSameDayAs: selectedPoint.date) {
                                                        selectedPointDate = nil
                                                    } else {
                                                        selectedPointDate = date
                                                    }
                                                }
                                            }
                                    )
                                if let selectedPoint,
                                   let plotFrame = proxy.plotFrame,
                                   let x = proxy.position(forX: selectedPoint.date),
                                   let y = proxy.position(forY: selectedPoint.value) {
                                    ChartCalloutOverlay(
                                        lines: calloutLines(selectedPoint),
                                        anchor: CGPoint(
                                            x: geometry[plotFrame].origin.x + x,
                                            y: geometry[plotFrame].origin.y + y
                                        ),
                                        containerSize: geometry.size
                                    )
                                }
                            }
                        }
                    }
                    .onChange(of: selectedField) { _, _ in
                        selectedPointDate = nil
                    }

                    HStack(spacing: 8) {
                        stat("最新", points.last?.value)
                        stat("均值", average)
                        stat("最高", highest)
                        stat("最低", lowest)
                    }
                }
            }
        }
        .appCard()
        .cardScrollEffect()
    }

    /// 节点弹窗文案：日期 + 指标值 + 相对近 30 天均值。
    private func calloutLines(_ point: MetricTrendPoint) -> [String] {
        var lines = [
            point.date.formatted(.dateTime.month().day().weekday(.abbreviated)),
            "\(selectedField.label) \(format(point.value))",
        ]
        guard let average, points.count > 1 else { return lines }
        let diff = point.value - average
        if abs(diff) < 0.5 {
            lines.append("与均值持平")
        } else {
            let sign = diff > 0 ? "+" : "−"
            let number = String(format: "%.\(selectedField.decimals)f", abs(diff))
            let unitSuffix = selectedField.unit.isEmpty ? "" : " \(selectedField.unit)"
            lines.append("较均值 \(sign)\(number)\(unitSuffix)")
        }
        return lines
    }

    private func stat(_ title: String, _ value: Double?) -> some View {
        VStack(spacing: 3) {
            Text(value.map { format($0, withUnit: false) } ?? "—")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title + (selectedField.unit.isEmpty ? "" : " · " + selectedField.unit))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// 数值格式：整数型指标不带小数，比率 / 时长类保留 1 位。
    private func format(_ value: Double, withUnit: Bool = true) -> String {
        let number = String(format: "%.\(selectedField.decimals)f", value)
        return withUnit && !selectedField.unit.isEmpty ? "\(number) \(selectedField.unit)" : number
    }

    /// 饮食详情专用：摄入与体重近 7 天对照，复用行动页同一套计算与渲染，口径一致。
    private func dietWeightRelationCard(relation: DietWeightRelation) -> some View {
        DietWeightRelationContent(relation: relation)
            .appCard()
            .cardScrollEffect()
    }

    /// 睡眠分组专用：原首页卡内的「睡眠报告」入口，改在详情页 push，避免导航链接嵌套。
    /// 位置固定在页面最顶上（头部卡之后第一张）。
    private var sleepReportCard: some View {
        NavigationLink {
            SleepReportView(metrics: metrics)
        } label: {
            HStack {
                Label("查看完整睡眠报告", systemImage: "moon.zzz.fill")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(group.tint)
        }
        .appCard()
        .cardScrollEffect()
    }

    /// 口径说明：沿用首页脚注的分组来源，再补一句趋势窗口说明。
    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "数据来源与口径", icon: "info.circle", tint: .gray)
            Text(MetricTrendField.sourceText(for: group.title))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("趋势只展示已同步到本地的历史日数据，最多 30 天；所有数值仅供日常参考，非医疗诊断。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
        .cardScrollEffect()
    }
}

private struct MetricTrendPoint: Identifiable {
    let date: Date
    let value: Double

    var id: Date { date }
}

/// 分组内可绘制趋势的字段。字段名与 DailyMetrics / MetricGroupFactory 一一对应，
/// 不用闭包提取值，避免 Swift 6 严格并发下跨隔离域传递函数。
enum MetricTrendField: String, CaseIterable, Identifiable {
    case vo2Max, walkingSpeed, steadiness, distance, flights
    case daylight, mindful, sleepMidpoint, mood
    case bodyMass, bodyFat, leanMass, bmi, waist
    case systolic, diastolic, glucose
    case water, energy, carbs, protein, fat, fiber, sugar, sodium, caffeine
    case sleepTotal, sleepEfficiency, deepSleep, remSleep, sleepAvgHR
    case hrv, restingHR
    case steps, activeEnergy, exerciseMinutes, workoutMinutes
    case respiratoryRate, spo2, wristTemp

    var id: String { rawValue }

    var label: String {
        switch self {
        case .vo2Max: return "VO2max"
        case .walkingSpeed: return "步行速度"
        case .steadiness: return "步行稳定性"
        case .distance: return "步行 + 跑步"
        case .flights: return "爬楼"
        case .daylight: return "日照"
        case .mindful: return "正念"
        case .sleepMidpoint: return "睡眠中点"
        case .mood: return "心情"
        case .bodyMass: return "体重"
        case .bodyFat: return "体脂率"
        case .leanMass: return "瘦体重"
        case .bmi: return "BMI"
        case .waist: return "腰围"
        case .systolic: return "收缩压"
        case .diastolic: return "舒张压"
        case .glucose: return "血糖"
        case .water: return "喝水合计"
        case .energy: return "热量摄入"
        case .carbs: return "碳水化合物"
        case .protein: return "蛋白质"
        case .fat: return "脂肪"
        case .fiber: return "膳食纤维"
        case .sugar: return "糖"
        case .sodium: return "钠"
        case .caffeine: return "咖啡因合计"
        case .sleepTotal: return "睡眠时长"
        case .sleepEfficiency: return "睡眠效率"
        case .deepSleep: return "深睡"
        case .remSleep: return "REM"
        case .sleepAvgHR: return "睡眠心率"
        case .hrv: return "HRV"
        case .restingHR: return "静息心率"
        case .steps: return "步数"
        case .activeEnergy: return "活动能量"
        case .exerciseMinutes: return "锻炼"
        case .workoutMinutes: return "训练时长"
        case .respiratoryRate: return "呼吸频率"
        case .spo2: return "血氧"
        case .wristTemp: return "手腕温度"
        }
    }

    var unit: String {
        switch self {
        case .vo2Max: return "ml/kg/min"
        case .walkingSpeed: return "km/h"
        case .steadiness, .bodyFat: return "%"
        case .distance: return "km"
        case .flights: return "层"
        case .daylight, .mindful: return "分钟"
        case .sleepMidpoint: return "时"
        case .mood, .bmi: return ""
        case .bodyMass, .leanMass: return "kg"
        case .waist: return "cm"
        case .systolic, .diastolic: return "mmHg"
        case .glucose, .sodium, .caffeine: return "mg"
        case .water: return "ml"
        case .energy: return "kcal"
        case .carbs, .protein, .fat, .fiber, .sugar: return "g"
        case .sleepTotal, .deepSleep, .remSleep: return "小时"
        case .sleepEfficiency, .spo2: return "%"
        case .sleepAvgHR, .restingHR, .respiratoryRate: return "次/分"
        case .hrv: return "ms"
        case .steps: return "步"
        case .activeEnergy: return "千卡"
        case .exerciseMinutes, .workoutMinutes: return "分钟"
        case .wristTemp: return "℃"
        }
    }

    var decimals: Int {
        switch self {
        case .vo2Max, .walkingSpeed, .sleepMidpoint, .mood, .bodyMass,
             .bodyFat, .leanMass, .bmi, .waist,
             .sleepTotal, .deepSleep, .remSleep, .respiratoryRate, .wristTemp: return 1
        default: return 0
        }
    }

    func value(_ row: DailyMetrics) -> Double? {
        switch self {
        case .vo2Max: return row.vo2Max
        case .walkingSpeed: return row.walkingSpeedMps.map { $0 * 3.6 }
        case .steadiness: return row.walkingSteadinessPct
        case .distance: return row.distanceWalkingKm
        case .flights: return row.flightsClimbed
        case .daylight: return row.daylightMinutes
        case .mindful: return row.mindfulMinutes
        case .sleepMidpoint: return row.sleepMidpointMinutes.map { $0 / 60 }
        case .mood: return row.stateOfMindValence
        case .bodyMass: return row.bodyMassKg
        case .bodyFat: return row.bodyFatPct
        case .leanMass: return row.leanBodyMassKg
        case .bmi: return row.bmi
        case .waist: return row.waistCircumferenceCm
        case .systolic: return row.systolicBP
        case .diastolic: return row.diastolicBP
        case .glucose: return row.bloodGlucoseMgDl
        case .water: return row.waterTotalMl
        case .energy: return row.dietaryEnergyKcal
        case .carbs: return row.dietaryCarbsG
        case .protein: return row.dietaryProteinG
        case .fat: return row.dietaryFatG
        case .fiber: return row.dietaryFiberG
        case .sugar: return row.dietarySugarG
        case .sodium: return row.dietarySodiumMg
        case .caffeine: return row.dietaryCaffeineMg
        case .sleepTotal: return row.sleepTotalH
        case .sleepEfficiency: return row.sleepEfficiency.map { $0 * 100 }
        case .deepSleep: return row.deepH
        case .remSleep: return row.remH
        case .sleepAvgHR: return row.sleepAvgHR
        case .hrv: return row.hrvLatest ?? row.hrvSDNN
        case .restingHR: return row.restingHR
        case .steps: return row.steps
        case .activeEnergy: return row.activeEnergy
        case .exerciseMinutes: return row.exerciseMinutes
        case .workoutMinutes: return row.workoutMinutes
        case .respiratoryRate: return row.respiratoryRate
        case .spo2: return row.spo2
        case .wristTemp: return row.wristTempC
        }
    }

    /// 分组 → 可切换字段，顺序与首页卡片 rows 一致。
    static func fields(for title: String) -> [MetricTrendField] {
        switch title {
        case "睡眠": return [.sleepTotal, .sleepEfficiency, .deepSleep, .remSleep, .sleepAvgHR]
        case "心率变异性 / 静息心率": return [.hrv, .restingHR]
        case "活动": return [.steps, .activeEnergy, .exerciseMinutes, .workoutMinutes]
        case "生命体征": return [.respiratoryRate, .spo2, .wristTemp]
        case "心肺体能": return [.vo2Max, .walkingSpeed, .steadiness, .flights, .distance]
        case "生活节律": return [.daylight, .mindful, .mood, .sleepMidpoint]
        case "身体成分": return [.bodyMass, .bodyFat, .leanMass, .bmi, .waist]
        case "身体状况": return [.bodyMass, .bodyFat, .leanMass, .bmi, .waist]
        case "心血管代谢": return [.systolic, .diastolic, .glucose]
        case "饮食与饮水": return [.water, .energy, .carbs, .protein, .fat, .fiber, .sugar, .sodium, .caffeine]
        case "饮食": return [.energy, .carbs, .protein, .fat, .fiber, .sugar, .sodium]
        default: return []
        }
    }

    static func sourceText(for title: String) -> String {
        switch title {
        case "睡眠":
            return "睡眠时长、分期与睡眠心率来自健康 App（主要由 Apple Watch 记录）。恢复性分为展示指标，不参与状态 / 压力评分；心率 dip 由全天平均心率推算，睡眠尚未结束的当天显示无数据。"
        case "心率变异性 / 静息心率":
            return "HRV 取当日最新 SDNN 读数，静息心率由 Apple Watch 全天采样得出；两项均相对 28 天个人基线评估，数值缺失时沿用最近一次读数。"
        case "活动":
            return "步数、活动能量、锻炼与训练时长来自健康 App；活动负荷评分取近 7 天与近 28 天均值之比。"
        case "生命体征":
            return "呼吸频率、血氧与手腕温度来自 Apple Watch 的睡眠期间采样；血压 / 血糖没有设备时可在健康 App 手动记录，异常值仅作提示，非医疗诊断。"
        case "心肺体能":
            return "VO2max、步行速度 / 稳定性、爬楼与步行距离来自健康 App（主要由 Apple Watch 记录）；VO2max 的变化量对比近 28 天最低值。"
        case "生活节律":
            return "日照、正念、心情来自健康 App；作息规律取近 28 天睡眠中点的标准差，中点按当日睡眠结束时间折算。"
        case "身体成分":
            return "体重、体脂率、瘦体重、BMI 与腰围来自智能秤或健康 App 手动记录；体重变化对比 7 天前最近一次读数。"
        case "身体状况":
            return "体重、体脂率、瘦体重、BMI 与腰围来自智能秤或健康 App 手动记录；体重变化对比 7 天前最近一次读数。"
        case "心血管代谢":
            return "血压与血糖来自健康 App、外接设备或手动记录；没有设备时可在健康 App 补录。"
        case "饮食与饮水":
            return "喝水、咖啡因为健康 App 同步值与本 App 打卡合并后的当日总量（已去重）；其余营养来自健康 App 的膳食记录与本 App 食物打卡。"
        case "饮食":
            return "热量、碳水、蛋白质、脂肪、膳食纤维、糖与钠来自健康 App 的膳食记录及本 App 食物打卡；喝水与咖啡因在行动页单独展示。"
        default:
            return "数据来自健康 App 与本 App 打卡记录。"
        }
    }
}
