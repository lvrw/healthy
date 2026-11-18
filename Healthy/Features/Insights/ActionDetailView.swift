import Charts
import SwiftUI

struct ActionDetailView: View {
    let action: InsightAction
    let days: [ActionDay]
    /// 详情页顶部的「记录 / 设置」入口：由调用方按行动类型给出，空数组时不显示。
    /// 入口原先贴在行动页外层卡片上，现已收进详情页内部。
    var entries: [ActionCardSheet] = []
    /// 饮食设置页的维持热量估算值；其他行动用不到，传 nil。
    var estimatedMaintenanceKcal: Double? = nil

    /// 逐日日历中被点击的日期，用于在日历内展开当日数值框；nil 表示未选中。
    @State private var selectedDay: CalendarDay?
    /// 顶部日期切换条选中的日期：饮水 / 咖啡因详情支持按天查看，所有当日数值跟随它。
    @State private var selectedDate = DayKey.startOfDay(.now)
    /// 导航栏右上角齿轮打开的设置页。
    @State private var settingsSheet: ActionCardSheet?

    /// 喝水目标与「喝水配置」共用同一组偏好：配置页保存后本页立刻刷新，
    /// 标题、符合判定、逐日日历与等级分布都跟着新目标走。
    @AppStorage(IntakeGoal.waterDefaultsKey) private var storedWaterTargetMl = IntakeGoal.defaultWaterTargetMl
    /// 咖啡因上限同理：标题与「符合」判定都跟随「咖啡因配置」。
    @AppStorage(IntakeGoal.caffeineDefaultsKey) private var storedCaffeineLimitMg = IntakeGoal.defaultCaffeineLimitMg

    /// 生效的喝水目标（毫升），先做一次范围钳制，避免偏好里出现异常值。
    private var waterTargetMl: Double {
        IntakeGoal.clamp(storedWaterTargetMl, in: IntakeGoal.waterRange)
    }

    /// 生效的咖啡因上限（毫克），同样做范围钳制。
    private var caffeineLimitMg: Double {
        IntakeGoal.clamp(storedCaffeineLimitMg, in: IntakeGoal.caffeineRange)
    }

    /// 页面标题：喝水 / 咖啡因按当前配置展示，其他行动是固定口径。
    private var displayTitle: String {
        action.title(waterTargetMl: waterTargetMl, caffeineLimitMg: caffeineLimitMg)
    }

    /// 详情页的统计窗口：与逐日日历 / 等级分布同一批日子（近 30 个自然日）。
    /// 之前直接用 `days`（可达 60 天），会出现「柱子按 30 天数、压力差按 60 天算」的两套口径。
    private var windowDays: [ActionDay] {
        days.filter { $0.date >= calendarStart }
    }

    private var summary: ActionImpactSummary {
        ActionImpactEngine.evaluate(
            days: windowDays,
            waterTargetMl: waterTargetMl,
            caffeineLimitMg: caffeineLimitMg
        )
    }

    /// 今日的咖啡因超限提示：仅在咖啡因详情页、所选日期有记录且超过配置上限时展示。
    /// 行动页卡片与这里共用 `IntakeGoal` 的配置值，避免「卡片说超了、详情说没超」。
    private var caffeineOverLimit: (current: Double, excess: Double)? {
        guard action == .caffeineModerate else { return nil }
        let key = DayKey.key(for: selectedDate)
        guard let day = days.first(where: { DayKey.key(for: $0.date) == key }),
              let current = day.manual["caffeine"],
              current > caffeineLimitMg
        else { return nil }
        return (current, current - caffeineLimitMg)
    }

    /// 只有饮水 / 咖啡因详情支持日期切换，其他行动是近 30 天的整体分析。
    private var supportsDaySwitch: Bool {
        action == .water1500 || action == .caffeineModerate
    }

    private var isSelectedToday: Bool {
        Calendar.current.isDate(selectedDate, inSameDayAs: .now)
    }

    private var impact: ActionImpact? {
        (summary.positive + summary.negative).first { $0.action == action }
    }

    /// 本行动在统计窗口内的完整口径：区分「总天数不足 / 某一组不足 5 天 / 差异 < 2 分」三种情况，
    /// 等级分布卡片据此展示均值和准确的提示文案，不再一律写「天数不足」。
    private var impactDetail: ActionImpactOutcome {
        ActionImpactEngine.detail(
            action: action,
            days: windowDays,
            waterTargetMl: waterTargetMl,
            caffeineLimitMg: caffeineLimitMg
        )
    }

    /// 日历窗口起点：含今天在内的最近 30 个自然日。
    private var calendarStart: Date {
        DayKey.addingDays(-29, to: DayKey.startOfDay(.now))
    }

    /// 统计口径：最近 30 个自然日内、有该行动数据的日子；无数据日不计入等级分布。
    private var points: [ActionTrendPoint] {
        ActionImpactEngine.trendPoints(
            action: action,
            days: days,
            waterTargetMl: waterTargetMl,
            caffeineLimitMg: caffeineLimitMg
        )
            .filter { $0.date >= calendarStart }
    }

    /// 详情页主色：跟随行动页该标签的图标色，头部卡片、逐日日历、图例与等级分布共用，
    /// 保证日历与上方卡片同色。
    private var actionTint: Color {
        ActionTileKind.tint(for: action)
    }

    /// 「影响」徽标的语义色：积极影响绿、消极因素黄，与行动标签色相互独立。
    private var impactTint: Color {
        impact?.isPositive == false ? Color.yellow : Color.green
    }

    private var pointByKey: [String: ActionTrendPoint] {
        Dictionary(points.map { (DayKey.key(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// 日历格子：point 为 nil 表示该自然日没有此行动的数据；inWindow 为 false 时是补齐整周的空白占位。
    private struct CalendarDay: Identifiable, Equatable {
        let date: Date
        let point: ActionTrendPoint?
        let inWindow: Bool

        var id: Date { date }
    }

    /// 表头固定「周一 → 周日」，不随系统 locale 的 firstWeekday 变化。
    private let weekdayLabels = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    /// 日历按 7 天一行切分；calendarDays 前后已补齐整周，总数必为 7 的倍数。
    private var calendarRows: [[CalendarDay]] {
        let days = calendarDays
        return stride(from: 0, to: days.count, by: 7).map { start in
            Array(days[start..<min(start + 7, days.count)])
        }
    }

    /// 日历网格：最近 30 个自然日（含今天）按周一→周日排布；
    /// 前后补空白占位补齐整周，占位日不计入统计、不可点击。
    private var calendarDays: [CalendarDay] {
        let byKey = pointByKey
        let start = calendarStart
        let today = DayKey.startOfDay(.now)
        let calendar = Calendar.current
        // Gregorian weekday：1=周日、2=周一…7=周六；先回退到起点所在周的周一。
        let leading = (calendar.component(.weekday, from: start) + 5) % 7
        // 再补到今天所在周的周日，保证每行都是完整 7 天。
        let trailing = (8 - calendar.component(.weekday, from: today)) % 7
        let gridStart = DayKey.addingDays(-leading, to: start)
        return (0..<(leading + 30 + trailing)).map { offset in
            let date = DayKey.addingDays(offset, to: gridStart)
            let inWindow = date >= start && date <= today
            return CalendarDay(date: date, point: inWindow ? byKey[DayKey.key(for: date)] : nil, inWindow: inWindow)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if supportsDaySwitch {
                    ActionDayStrip(selectedDate: $selectedDate, tint: actionTint)
                        .onChange(of: selectedDate) { _, newValue in
                            let key = DayKey.key(for: newValue)
                            withAnimation(.snappy) {
                                selectedDay = calendarDays.first {
                                    $0.inWindow && DayKey.key(for: $0.date) == key
                                }
                            }
                        }
                }
                headerCard
                if let caffeineOverLimit {
                    overLimitBanner(caffeineOverLimit)
                }
                if entries.contains(where: { !$0.isSettings }) {
                    ActionEntryBar(
                        entries: entries.filter { !$0.isSettings },
                        date: selectedDate,
                        estimatedMaintenanceKcal: estimatedMaintenanceKcal
                    )
                }
                if let impact {
                    impactCard(impact)
                }
                calendarCard
                distributionCard
                Text("分级口径：平均压力差 <2 视为无显著差异（均值照常展示、不参与分级），≥7 为「中」，≥15 为「大」；分组各需 ≥\(ActionImpactEngine.minDaysPerGroup) 天、总天数 ≥\(ActionImpactEngine.minAnalysisDays) 天，统计窗口为近 30 天。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            // iOS 26 浮动标签栏在 push 后的详情页仍会显示，为末尾卡片留出滚动空间，
            // 避免最后一段说明紧贴标签栏、被半透明玻璃盖住。
            .padding(.bottom, 72)
        }
        .background(AppScreenBackground(tone: .mint))
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let settingsEntry = entries.first(where: \.isSettings) {
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
                date: selectedDate,
                estimatedMaintenanceKcal: estimatedMaintenanceKcal
            )
        }
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            Image(systemName: action.icon)
                .font(.title2)
                .foregroundStyle(actionTint)
                .frame(width: 44, height: 44)
                .background(
                    actionTint.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.headline)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .appCard()
    }

    /// 头部副标题：饮水 / 咖啡因展示所选日期的「当日值 / 目标」，其余行动仍是整体分析天数。
    private var headerSubtitle: String {
        guard supportsDaySwitch else { return "共分析 \(summary.daysAnalyzed) 天" }
        let key = DayKey.key(for: selectedDate)
        let point = pointByKey[key]
        let dateText = isSelectedToday ? "今日" : selectedDate.formatted(.dateTime.month().day())
        let current = point.map { action.metricText($0.metricValue) } ?? "—"
        let target = action == .water1500 ? waterTargetMl : caffeineLimitMg
        return "\(dateText) \(current) / \(Int(target.rounded())) \(action.metricUnit) · 近 30 天共 \(summary.daysAnalyzed) 天"
    }

    /// 超限警告：红底叹号 + 当日摄入 / 上限，与行动页卡片使用同一组配置值。
    private func overLimitBanner(_ over: (current: Double, excess: Double)) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppPalette.red)
            VStack(alignment: .leading, spacing: 2) {
                Text("咖啡因已超出上限 \(Int(over.excess.rounded())) 毫克")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.red)
                Text("\(isSelectedToday ? "今日" : selectedDate.formatted(.dateTime.month().day())) \(Int(over.current.rounded())) / \(Int(caffeineLimitMg.rounded())) 毫克")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .appCard()
    }

    private func impactCard(_ impact: ActionImpact) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("与其他日子相比")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("影响：\(impact.impact.label)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(impactTint)
            }
            Text(impact.isPositive
                ? String(format: "符合「%@」的日子，压力平均低 %.0f 分。", displayTitle, abs(impact.delta))
                : String(format: "符合「%@」的日子，压力平均高 %.0f 分。", displayTitle, abs(impact.delta)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("相关不等于因果：这只是历史数据里的统计关联。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    /// 星期表头：与日期行共用 HStack + maxWidth:.infinity 的列宽规则，保证列对齐。
    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(weekdayLabels.indices, id: \.self) { index in
                Text(weekdayLabels[index])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(index >= 5 ? Color.secondary.opacity(0.6) : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .padding(.bottom, 2)
    }

    /// 日历主体：逐行 HStack 的确定性布局，不使用 LazyVGrid。
    /// LazyVGrid 在本页与 selectedDay 动画叠加时会出现「最后一行溢出网格、
    /// 压住图例与说明文字」同时卡片底部多出幽灵空白的错位；
    /// 这里让网格高度始终等于全部行的实际高度，避免懒加载高度估算不一致。
    private var calendarGrid: some View {
        let rows = calendarRows
        return VStack(spacing: 6) {
            weekdayHeader
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(rows[row]) { day in
                        dayCell(day)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
        }
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "逐日日历", icon: "calendar", tint: actionTint)
            calendarGrid
            // 点击格子只在日历内展开一行小数值框，不弹窗、不遮挡页面。
            if let selectedDay {
                dayValueBox(selectedDay)
                    .transition(.opacity)
            }
            Divider()
                .padding(.vertical, 2)
            HStack(spacing: 14) {
                legendDot(actionTint, "符合")
                legendDot(.gray.opacity(0.5), "不符合")
                legendDot(.gray.opacity(0.3), "无数据")
                Spacer()
                Text("近 30 天")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("数值为\(action.metricCaption)，与等级分布同源；浅灰日期为补位，不计入统计。")
                Text("按周一到周日排列 · 点击日期查看数值，再点一次收起。")
                // 环境音量的口径与来源单独说明，避免和「行动页格子」看起来是两个数。
                if action == .quietUnder55 {
                    Text(NoisePresentation.sourceNote)
                }
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    /// 单个日历格子：窗口内可点击查看数值，窗口外是补齐整周的浅灰占位。
    private func dayCell(_ day: CalendarDay) -> some View {
        Group {
            if day.inWindow {
                dayButton(day)
            } else {
                placeholderCell(day)
            }
        }
    }

    /// 窗口内格子：符合日用主色浅底 + 状态点，其余保持留白，避免整片密集色块；今日与主色描边区分。
    private func dayButton(_ day: CalendarDay) -> some View {
        let status = day.point?.status
        let hasData = status != nil
        let isMet = status == .met
        let isSelected = selectedDay == day
        let isToday = DayKey.key(for: day.date) == DayKey.key(for: .now)
        return Button {
            // 动画只包住状态变更，不再给整张卡片加隐式 animation，
            // 避免网格 cell 参与几何插值后与下方图例错位。
            withAnimation(.snappy) {
                selectedDay = isSelected ? nil : day
            }
            // 点击日历格子时同步顶部日期条，两处始终指向同一天。
            if !isSelected {
                selectedDate = DayKey.startOfDay(day.date)
            }
        } label: {
            VStack(spacing: 2) {
                Text(day.date.formatted(.dateTime.day()))
                    .font(.caption2.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isToday ? actionTint : (hasData ? Color.secondary : Color.gray.opacity(0.35)))
                Text(day.point.map { action.metricText($0.metricValue) } ?? "·")
                    .font(.caption.weight(hasData ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(hasData ? Color.primary : Color.gray.opacity(0.3))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Circle()
                    .fill(isMet ? actionTint : (hasData ? Color.gray.opacity(0.35) : Color.clear))
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                isMet
                    ? actionTint.opacity(isSelected ? 0.22 : 0.13)
                    : (hasData ? Color.clear : Color.primary.opacity(0.025)),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? actionTint : (isToday ? actionTint.opacity(0.35) : Color.clear),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(day.date.formatted(.dateTime.month().day()))，\(statusText(status))，点击查看当日数值")
    }

    /// 窗口外占位：极淡日期、无底色，保持行高一致，不参与统计也不可点击。
    private func placeholderCell(_ day: CalendarDay) -> some View {
        Text(day.date.formatted(.dateTime.day()))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(Color.gray.opacity(0.2))
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .accessibilityHidden(true)
    }

    /// 日历格子与小数值框共用的状态文案。
    private func statusText(_ status: ActionStatus?) -> String {
        guard let status else { return "无数据" }
        return status == .met ? "符合" : "不符合"
    }

    /// 日历格子与小数值框共用的状态色。
    private func statusColor(_ status: ActionStatus?) -> Color {
        guard let status else { return Color.gray.opacity(0.45) }
        return status == .met ? actionTint : Color.gray
    }

    /// 点击格子后在日历内就地展开的小数值框：日期 + 实测值（含单位）+ 状态 + 当日压力，不弹窗。
    /// 6 个行动标签与洞察页「关键行动」共用本详情页，因此所有标签的日历都有此入口。
    private func dayValueBox(_ day: CalendarDay) -> some View {
        let status = day.point?.status
        let value = day.point.map { action.metricText($0.metricValue) } ?? "—"
        let unit = day.point == nil ? "" : action.metricUnit
        return HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(actionTint.opacity(0.13))
                Image(systemName: action.icon)
                    .font(.caption)
                    .foregroundStyle(actionTint)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(day.date.formatted(.dateTime.month().day()))
                        .font(.caption.weight(.semibold))
                    Text(statusText(status))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(statusColor(status))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(statusColor(status).opacity(0.12), in: Capsule())
                }
                Text(day.point.map { "\(action.metricCaption) · 压力 \(Int($0.stress.rounded()))" }
                     ?? "无数据 · 不计入等级分布")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(actionTint.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(actionTint.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var distributionCard: some View {
        let metCount = points.filter { $0.status == .met }.count
        let notMetCount = points.count - metCount
        let detail = impactDetail
        return VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "等级分布", icon: "chart.pie", tint: actionTint)
            Chart {
                BarMark(x: .value("状态", "符合"), y: .value("天数", metCount))
                    .foregroundStyle(actionTint)
                    .cornerRadius(4)
                BarMark(x: .value("状态", "不符合"), y: .value("天数", notMetCount))
                    .foregroundStyle(.gray.opacity(0.5))
                    .cornerRadius(4)
            }
            .chartYAxisLabel("近 \(points.count) 个有数据日")
            .frame(height: 140)
            HStack(spacing: 20) {
                stat("符合日压力均值", detail.averageStressMet.map { String(format: "%.0f", $0) } ?? "—")
                stat("不符合日压力均值", detail.averageStressNotMet.map { String(format: "%.0f", $0) } ?? "—")
                stat("压力差", detail.delta.map { String(format: "%+.0f", -$0) } ?? "—")
            }
            if let note = distributionNote(detail) {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .appCard()
    }

    /// 等级分布下方的解释：只有真的「天数不够」才说天数，差异过小要明说是显著性门槛。
    private func distributionNote(_ detail: ActionImpactOutcome) -> String? {
        switch detail {
        case .impact:
            return nil
        case let .insufficientTotal(daysAnalyzed):
            return "近 30 天只有 \(daysAnalyzed) 天可用数据，不足 \(ActionImpactEngine.minAnalysisDays) 天，暂不计算压力差。"
        case let .insufficientGroups(daysMet, daysNotMet):
            return "符合 \(daysMet) 天、不符合 \(daysNotMet) 天，任一组不足 \(ActionImpactEngine.minDaysPerGroup) 天，暂不计算压力差。"
        case let .notSignificant(daysMet, daysNotMet, _, _, delta):
            return String(
                format: "符合 %d 天、不符合 %d 天已够门槛，但两组平均压力只差 %.1f 分（< %.0f 分），按「无显著差异」处理，不参与影响分级。",
                daysMet, daysNotMet, abs(delta), ActionImpactEngine.neutralDelta
            )
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
        }
    }
}

// configured by qoder
