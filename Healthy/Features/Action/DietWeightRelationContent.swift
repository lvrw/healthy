import Charts
import SwiftUI

/// 饮食详情页的对照区：把最近 7 天的摄入热量与体重放在同一时间轴上。
/// 计算逻辑在 DietWeightRelation，这里只负责渲染，不重复取值口径。
struct DietWeightRelationContent: View {
    /// 由近 60 天指标里最近 7 天算出的关系读数。
    let relation: DietWeightRelation

    /// 有热量记录的点，用于上方曲线；缺失日子直接跳过，不让曲线假装是 0。
    private var energyPoints: [DietWeightPoint] {
        relation.points.filter { $0.energyKcal != nil }
    }

    /// 有体重记录的点，用于下方曲线；智能秤通常几天才有一点，曲线允许断档。
    private var weightPoints: [DietWeightPoint] {
        relation.points.filter { $0.bodyMassKg != nil }
    }

    /// 体重变化的方向色：下降偏绿（向好），上升偏橙，持平用中性灰。
    private var changeTint: Color {
        guard let change = relation.bodyMassChangeKg else { return .secondary }
        if change < -0.05 { return AppPalette.greenDeep }
        if change > 0.05 { return AppPalette.orange }
        return .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            stats
            if !energyPoints.isEmpty || !weightPoints.isEmpty {
                charts
            }
            Text(relation.summary)
                .font(.caption2)
                .foregroundStyle(AppPalette.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 小区标题：与外层「饮食」卡标题区分开，右侧标注统计窗口。
    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppPalette.greenDeep)
            Text("摄入与体重")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppPalette.ink2)
            Spacer(minLength: 0)
            Text("近 \(DietWeightRelation.windowDays) 天")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 两个关键读数：7 天日均摄入与体重变化，直接表达「吃多少 / 体重怎么走」。
    private var stats: some View {
        HStack(spacing: 0) {
            statBlock(
                title: "日均摄入",
                value: relation.averageEnergyKcal.map { String(Int($0.rounded())) } ?? "—",
                unit: "kcal",
                tint: AppPalette.greenDeep
            )
            Divider().frame(height: 30)
            statBlock(
                title: "体重变化",
                value: relation.bodyMassChangeKg.map {
                    String(format: "%+.1f", $0)
                } ?? "—",
                unit: "kg",
                tint: changeTint
            )
        }
    }

    /// 单个统计块：数值用等宽数字，单位缩小跟在基线后。
    private func statBlock(title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                Text(unit)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 上下两条共用时间跨度的迷你曲线：上热量、下体重，一眼看出走势是否同向。
    private var charts: some View {
        VStack(spacing: 4) {
            chartCaption(title: "摄入", tint: AppPalette.greenDeep)
            energyChart
            chartCaption(title: "体重", tint: .purple)
            weightChart
        }
    }

    /// 每条曲线的行标题：左侧色点 + 指标名。
    private func chartCaption(title: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tint)
                .frame(width: 4, height: 4)
            Text(title)
                .font(.caption2)
                .foregroundStyle(AppPalette.ink3)
        }
    }

    /// 摄入热量曲线：面积渐变 + 实线，最后一点加高亮，不画坐标轴。
    private var energyChart: some View {
        Chart {
            ForEach(energyPoints) { point in
                let value = point.energyKcal ?? 0
                AreaMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("摄入", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppPalette.green.opacity(0.28), AppPalette.green.opacity(0.01)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("摄入", value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AppPalette.greenDeep)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
            if let last = energyPoints.last {
                PointMark(
                    x: .value("日期", last.date, unit: .day),
                    y: .value("摄入", last.energyKcal ?? 0)
                )
                .foregroundStyle(AppPalette.greenDeep)
                .symbolSize(18)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 32)
        .accessibilityHidden(true)
    }

    /// 体重曲线：只连真实称量点，采样稀疏时保留折线而不是补零。
    private var weightChart: some View {
        Chart {
            ForEach(weightPoints) { point in
                LineMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("体重", point.bodyMassKg ?? 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(Color.purple)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                PointMark(
                    x: .value("日期", point.date, unit: .day),
                    y: .value("体重", point.bodyMassKg ?? 0)
                )
                .foregroundStyle(Color.purple)
                .symbolSize(16)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 32)
        .accessibilityHidden(true)
    }
}
