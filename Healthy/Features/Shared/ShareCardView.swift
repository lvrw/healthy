import SwiftUI

struct ShareCardView: View {
    enum Template: String, CaseIterable, Identifiable {
        case status = "今日状态"
        case sleep = "睡眠日报"
        var id: String { rawValue }
    }

    let score: DailyScore?
    let metrics: DailyMetrics?

    @Environment(\.dismiss) private var dismiss
    @State private var template: Template = .status
    @State private var renderedImage: Image?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("模板", selection: $template) {
                        ForEach(Template.allCases) { template in
                            Text(template.rawValue).tag(template)
                        }
                    }
                    .pickerStyle(.segmented)

                    card
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)

                    if let renderedImage {
                        ShareLink(
                            item: renderedImage,
                            preview: SharePreview("今日状态分享", image: renderedImage)
                        ) {
                            Label("导出分享图", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Text("分享图在本机生成，不含设备标识；仅供记录与分享，不构成医疗建议。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
            }
            .background(AppScreenBackground())
            .navigationTitle("分享")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
            .task(id: template) {
                await render()
            }
        }
    }

    @MainActor
    private func render() async {
        let renderer = ImageRenderer(
            content: card
                .environment(\.colorScheme, .light)
                .environment(\.dynamicTypeSize, .large)
        )
        renderer.scale = 3
        if let uiImage = renderer.uiImage {
            renderedImage = Image(uiImage: uiImage)
        }
    }

    private var dateText: String {
        Date.now.formatted(.dateTime.year().month(.wide).day())
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("今日状态")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(dateText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            switch template {
            case .status:
                statusContent
            case .sleep:
                sleepContent
            }
            Spacer(minLength: 0)
            Text("相对 28 天个人基线 · 非医疗诊断")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(24)
        .frame(width: 320, height: 420, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [Color.indigo, Color.teal.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var statusContent: some View {
        let presentation = TodayStatusPresentation.make(stress: score?.stress)
        return VStack(alignment: .leading, spacing: 14) {
            Text(presentation.word)
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(alignment: .top, spacing: 28) {
                statBlock("身体状态", score?.readiness)
                statBlock("压力", score?.stress)
            }
            if score?.confidenceRaw == ScoreConfidence.insufficient.rawValue {
                Text("个人基线积累中，数值仅供参考。")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }

    private var sleepContent: some View {
        let ratio = SleepAnalysisEngine.restorativeRatio(
            deepH: metrics?.deepH,
            remH: metrics?.remH,
            totalH: metrics?.sleepTotalH
        )
        return VStack(alignment: .leading, spacing: 14) {
            Text("睡眠日报")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            HStack(alignment: .top, spacing: 28) {
                statBlock("时长", metrics?.sleepTotalH, unit: "h", digits: 1)
                statBlock(
                    "效率",
                    metrics?.sleepEfficiency.map { $0 * 100 },
                    unit: "%"
                )
                statBlock("恢复性", ratio.map { $0 * 100 }, unit: "%")
            }
            if let quality = SleepTrendAggregates.qualityScore(
                efficiency: metrics?.sleepEfficiency,
                restorativeRatio: ratio
            ) {
                Text(String(format: "质量分（展示口径） %d", Int(quality.rounded())))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    private func statBlock(
        _ title: String,
        _ value: Double?,
        unit: String = "",
        digits: Int = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value.map { String(format: "%.\(digits)f%@", $0, unit) } ?? "—")
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

// configured by qoder