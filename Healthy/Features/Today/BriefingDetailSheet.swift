import SwiftUI

/// 「智能评分」详情页：完整展示当日报告（评分解读 / 建议 / 注意事项），
/// 并提供重新生成入口。对应今日页智能评分卡的「点开查看详情」。
/// 排版：顶部为重新生成入口，随后是双圆环评分 hero 卡与各分区卡片。
struct BriefingDetailSheet: View {
    let report: BriefingReport
    let readiness: Double?
    let stress: Double?
    let baselineDays: Int
    /// 报告生成时间（DailyReport.generatedAt）；与今日页卡片「数据更新于」同一来源。
    var updatedAt: Date? = nil
    let isGenerating: Bool
    /// 重新生成失败时在卡片内直接给出原因，避免只显示旧报告、用户以为没反应。
    var errorMessage: String? = nil
    let onRegenerate: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    regenerateCard
                    scoreHero
                    sectionCard(
                        title: "身体状态",
                        icon: "figure.walk",
                        tint: .green
                    ) {
                        levelChip(report.readiness.level, tint: .green)
                        Text(report.readiness.interpretation)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    sectionCard(
                        title: "压力",
                        icon: "heart.fill",
                        tint: .orange
                    ) {
                        levelChip(report.stress.level, tint: .orange)
                        Text(report.stress.analysis)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    suggestionsCard
                    if !report.cautions.isEmpty {
                        cautionsCard
                    }
                    Text(report.disclaimer)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .background(AppScreenBackground(tone: .lavender))
            .navigationTitle("智能评分")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 顶部重新生成

    /// 重新生成入口固定在页面最上方；生成中保留旧报告并提示等待。
    private var regenerateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isGenerating {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在重新生成，当前仍显示上一次的评分…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    onRegenerate()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("重新生成智能评分")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(AppPalette.greenDeep)
                    )
                }
                .buttonStyle(.plain)
            }
            if let errorMessage, !errorMessage.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 14)
        .cardScrollEffect()
    }

    // MARK: - 评分 hero

    /// 双圆环评分卡：身体状态 + 压力，下方接整体解读与基线说明。
    private var scoreHero: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ScoreRing(title: "身体状态", value: readiness, tint: .green, caption: report.readiness.level)
                ScoreRing(title: "压力", value: stress, tint: .orange, caption: report.stress.level)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                Text(report.summary)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if baselineDays > 0 {
                    Label("个人基线 \(baselineDays) 天 · 评分相对个人基线计算", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let updatedAt {
                    Text("数据更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appCard()
        .cardScrollEffect()
    }

    // MARK: - 分区

    private var suggestionsCard: some View {
        sectionCard(title: "今日建议", icon: "checklist", tint: .blue) {
            ForEach(Array(report.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.blue)
                        .frame(width: 20, height: 20)
                        .background(Color.blue.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title)
                            .font(.subheadline.weight(.semibold))
                        if !suggestion.detail.isEmpty {
                            Text(suggestion.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var cautionsCard: some View {
        sectionCard(title: "注意", icon: "exclamationmark.triangle.fill", tint: .red) {
            ForEach(report.cautions, id: \.self) { caution in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                        .padding(.top, 2)
                    Text(caution)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// 等级胶囊：浅色底 + 同色文字，用于「较好 / 中低」这类 AI 等级词。
    private func levelChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        tint: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: title, icon: icon, tint: tint)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
        .cardScrollEffect()
    }
}
