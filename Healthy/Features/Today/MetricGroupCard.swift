import SwiftUI

/// 「更多指标」分组卡，排版与睡眠卡 / 评分拆解卡保持一致。
struct MetricGroupCard: View {
    let title: String
    let icon: String
    let tint: Color
    let rows: [InfoRow]
    var footnote: String? = nil
    /// 分项评分（0–100）。来自当日 ReadinessComponents：
    /// 心肺体能 → fitnessBody，生活节律 → circadian，饮食与饮水 → nutrition。
    /// 无评分的分组不显示角标。
    var score: Double? = nil
    /// 首页卡片可点进详情页时显示右侧箭头，静态复用（如预览）时保持原样。
    var showsDetail: Bool = false
    /// 数据不全被跳过时的角标文案；无评分时替代分数显示。
    var skipLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: title,
                icon: icon,
                tint: tint,
                trailing: (score != nil || skipLabel != nil || showsDetail)
                    ? AnyView(MetricCardTrailing(
                        score: score, tint: tint, showsDetail: showsDetail, skipLabel: skipLabel
                    ))
                    : nil
            )
            VStack(alignment: .leading, spacing: 6) {
                ForEach(rows) { row in
                    MetricInfoRowView(row: row)
                }
            }
            if let footnote {
                Text(footnote)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .appCard()
        .cardScrollEffect()
    }
}

#Preview {
    MetricGroupCard(
        title: "心肺体能",
        icon: "figure.run",
        tint: .blue,
        rows: [
            InfoRow(label: "VO2max", value: "42.0 ml/kg/min（+1.2）"),
            InfoRow(label: "步行速度", value: "4.9 km/h"),
            InfoRow(label: "步行稳定性", value: "85%"),
        ],
        footnote: "步行指标来自 Apple Watch。",
        score: 78
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
