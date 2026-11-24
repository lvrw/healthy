import SwiftUI

struct InfoRow: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let value: String
}

/// 与睡眠卡指标行一致的排版：小号标签、加粗数值、首行基线对齐。
/// 评分拆解区与「更多指标」区的卡片共用，避免各卡字号/间距各不相同。
struct MetricInfoRowView: View {
    let row: InfoRow

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(row.label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(row.value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
    }
}

/// 指标卡头部右侧：分项评分 + 可点击指示箭头。
/// 评分拆解卡（ComponentCard / SleepCardView）与「更多指标」卡共用，保证角标样式一致。
struct MetricCardTrailing: View {
    let score: Double?
    let tint: Color
    var showsDetail: Bool = false
    /// 数据不全被跳过时的角标文案；仅在无评分时显示。
    var skipLabel: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let score {
                Text("\(Int(score.rounded())) 分")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            } else if let skipLabel {
                Text(skipLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
            }
            if showsDetail {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// 与 SleepCardView 共用同一套卡片语言：AppSectionHeader + tint 色评分角标、
/// 统一的指标行、脚注、12pt 内间距。评分缺失时不显示角标。
struct ComponentCard: View {
    let title: String
    let icon: String
    let tint: Color
    let score: Double?
    let rows: [InfoRow]
    var footnote: String? = nil
    /// 首页整卡可点进详情页时显示右侧箭头。
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
    ComponentCard(
        title: "睡眠",
        icon: "moon.zzz.fill",
        tint: .indigo,
        score: 82,
        rows: [
            InfoRow(label: "时长", value: "7.4 小时"),
            InfoRow(label: "效率", value: "93%"),
            InfoRow(label: "深睡 + REM", value: "2.8 小时"),
        ],
        footnote: "恢复性分为展示指标，不参与状态 / 压力评分。"
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
