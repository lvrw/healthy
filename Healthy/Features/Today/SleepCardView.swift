import SwiftUI

struct SleepCardView: View {
    let metrics: DailyMetrics
    let componentScore: Double?
    /// 首页整卡可点进详情页时显示右侧箭头。
    var showsDetail: Bool = false
    /// 睡眠数据不全被跳过时的角标文案。
    var skipLabel: String? = nil

    private var intervals: [SleepStageInterval] {
        SleepStageCodec.decode(metrics.sleepStagesJSON)
    }

    /// 今日睡眠明细行：首页卡片与详情页共用，避免文案 / 口径出现两套。
    static func detailRows(_ metrics: DailyMetrics) -> [InfoRow] {
        let intervals = SleepStageCodec.decode(metrics.sleepStagesJSON)
        let ratio = SleepAnalysisEngine.restorativeRatio(
            deepH: metrics.deepH,
            remH: metrics.remH,
            totalH: metrics.sleepTotalH
        )
        let dip = SleepAnalysisEngine.dipPercentForDay(
            avgHR: metrics.avgHR,
            sleepHR: metrics.sleepAvgHR,
            sleepHours: metrics.sleepTotalH,
            dayKey: metrics.dayKey,
            sleepEnd: intervals.map(\.end).max()
        )

        var rows: [InfoRow] = []
        if let ratio, let deep = metrics.deepH, let rem = metrics.remH {
            rows.append(InfoRow(
                label: "恢复性睡眠（深睡 + REM）",
                value: String(
                    format: "%.1f 小时 · %.0f%% · 展示分 %.0f",
                    deep + rem,
                    ratio * 100,
                    SleepAnalysisEngine.restorativeScore(ratio: ratio)
                )
            ))
        }
        if let hr = metrics.sleepAvgHR {
            let level = SleepAnalysisEngine.heartRateLevel(hr)
            rows.append(InfoRow(label: "睡眠心率", value: "\(Int(hr.rounded())) 次/分 · \(level.label)"))
        }
        rows.append(InfoRow(
            label: "心率 dip（估算）",
            value: dip.map { String(format: "%.0f%% · %@", $0, SleepAnalysisEngine.dipLevel($0).label) } ?? "无数据"
        ))
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(
                title: "睡眠",
                icon: "moon.zzz.fill",
                tint: .indigo,
                trailing: (componentScore != nil || skipLabel != nil || showsDetail)
                    ? AnyView(MetricCardTrailing(
                        score: componentScore,
                        tint: .indigo,
                        showsDetail: showsDetail,
                        skipLabel: skipLabel
                    ))
                    : nil
            )
            HStack(spacing: 24) {
                MetricRing(
                    text: metrics.sleepTotalH.map { String(format: "%.1fh", $0) } ?? "—",
                    progress: (metrics.sleepTotalH ?? 0) / ScoringConfig().sleepTargetHours,
                    title: "睡眠时长",
                    caption: "目标 7.5 小时",
                    tint: .indigo
                )
                MetricRing(
                    text: metrics.sleepEfficiency.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                    progress: metrics.sleepEfficiency ?? 0,
                    title: "睡眠效率",
                    caption: "入睡后实际睡着占比",
                    tint: .teal
                )
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HypnogramChart(intervals: intervals, showAxes: false, interactive: false)
                HStack(spacing: 10) {
                    ForEach([SleepStageKind.deep, .core, .rem, .awake], id: \.self) { stage in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(HypnogramChart.color(stage))
                                .frame(width: 6, height: 6)
                            Text(HypnogramChart.label(stage))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.detailRows(metrics)) { row in
                    MetricInfoRowView(row: row)
                }
            }
            Text("恢复性分为展示指标，不参与状态 / 压力评分；dip 由全天平均心率推算。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
        .cardScrollEffect()
    }
}

// configured by qoder