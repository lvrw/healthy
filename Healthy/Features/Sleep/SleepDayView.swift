import SwiftUI

struct SleepDayView: View {
    let snapshot: DailySnapshot
    let history: [DailySnapshot]

    private var calendar: Calendar { .current }
    private var config: ScoringConfig { ScoringConfig() }

    private var summary: SleepDaySummary {
        let threshold = SleepTrendAggregates.lateThreshold(history: history, today: snapshot, calendar: calendar)
        return SleepTrendAggregates.daySummary(snapshot, lateThresholdMinutes: threshold)
    }

    private var intervals: [SleepStageInterval] {
        SleepStageCodec.decode(snapshot.sleepStagesJSON)
    }

    private var midpointSD: Double? {
        ScoreSupport.sleepMidpointSD(history: history, today: snapshot, config: config, calendar: calendar)
    }

    private var dip: Double? {
        let sleepEnd = intervals.map(\.end).max()
        return SleepAnalysisEngine.dipPercentForDay(
            avgHR: snapshot.avgHR,
            sleepHR: snapshot.sleepAvgHR,
            sleepHours: snapshot.sleepTotalH,
            dayKey: snapshot.dayKey,
            sleepEnd: sleepEnd
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            ringsCard
            conclusionCard
            dimensionsCard
            hypnogramCard
            if !intervals.isEmpty {
                restorativeCard
            }
            heartRateCard
            SleepVitalsCard(snapshot: snapshot, history: history)
        }
    }

    private var ringsCard: some View {
        HStack(spacing: 24) {
            MetricRing(
                text: snapshot.sleepTotalH.map { String(format: "%.1fh", $0) } ?? "—",
                progress: (snapshot.sleepTotalH ?? 0) / config.sleepTargetHours,
                title: "睡眠时长",
                caption: "目标 \(String(format: "%.1f", config.sleepTargetHours)) 小时",
                tint: .indigo
            )
            MetricRing(
                text: summary.qualityScore.map { "\(Int($0.rounded()))" } ?? "—",
                progress: (summary.qualityScore ?? 0) / 100,
                title: "睡眠质量",
                caption: "效率 + 恢复性展示合成",
                tint: .purple
            )
        }
        .frame(maxWidth: .infinity)
        .appCard(padding: 20)
    }

    private var conclusionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AppSectionHeader(title: "昨晚结论", icon: "text.alignleft", tint: .indigo)
            ForEach(conclusions, id: \.self) { line in
                Text("· \(line)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var conclusions: [String] {
        var lines: [String] = []
        if let hours = snapshot.sleepTotalH {
            if hours >= config.sleepLowTargetHours {
                lines.append(String(format: "睡了 %.1f 小时，达到 7 小时以上目标。", hours))
            } else {
                lines.append(String(format: "只睡了 %.1f 小时，低于 7 小时目标，今天注意补觉。", hours))
            }
        }
        if let efficiency = snapshot.sleepEfficiency {
            lines.append(efficiency >= 0.85
                ? String(format: "效率 %.0f%%，入睡后大部分时间都在睡着。", efficiency * 100)
                : String(format: "效率 %.0f%%，夜间清醒偏多，留意咖啡因与屏幕时间。", efficiency * 100))
        }
        if let ratio = summary.restorativeRatio {
            let percent = ratio * 100
            if ratio >= SleepAnalysisEngine.restorativeLow && ratio <= SleepAnalysisEngine.restorativeHigh {
                lines.append(String(format: "恢复性睡眠占 %.0f%%，落在 33%%–48%% 参考带内。", percent))
            } else if ratio < SleepAnalysisEngine.restorativeLow {
                lines.append(String(format: "恢复性睡眠占 %.0f%%，低于 33%% 参考带，深睡 / REM 偏少。", percent))
            } else {
                lines.append(String(format: "恢复性睡眠占 %.0f%%，高于 48%% 参考带。", percent))
            }
        }
        if summary.isLateBedtime {
            lines.append("入睡时间晚于你过去 28 天的习惯（中位数 + 60 分钟），算晚睡。")
        }
        if lines.isEmpty {
            lines.append("数据不足，暂无结论。")
        }
        return lines
    }

    private var dimensionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "五维拆解", icon: "slider.horizontal.3", tint: .indigo)
            dimensionRow(
                label: "时长",
                progress: (snapshot.sleepTotalH ?? 0) / config.sleepHighTargetHours,
                value: snapshot.sleepTotalH.map { String(format: "%.1f / %.1f 小时", $0, config.sleepTargetHours) } ?? "—",
                tint: .indigo
            )
            dimensionRow(
                label: "效率",
                progress: snapshot.sleepEfficiency ?? 0,
                value: snapshot.sleepEfficiency.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                tint: .teal
            )
            dimensionRow(
                label: "深睡",
                progress: stageProgress(stageRatio(snapshot.deepH), cap: 0.23),
                value: stageRatio(snapshot.deepH).map { String(format: "%.0f%% · 参考 13–23%%", $0 * 100) } ?? "—",
                tint: .indigo
            )
            dimensionRow(
                label: "REM",
                progress: stageProgress(stageRatio(snapshot.remH), cap: 0.25),
                value: stageRatio(snapshot.remH).map { String(format: "%.0f%% · 参考 20–25%%", $0 * 100) } ?? "—",
                tint: .purple
            )
            dimensionRow(
                label: "规律性",
                progress: midpointSD.map { max(0, 1 - $0 / 120) } ?? 0,
                value: midpointSD.map { String(format: "±%.0f 分钟（近 7 天中点波动）", $0) } ?? "—",
                tint: .blue
            )
        }
        .appCard()
    }

    private func stageRatio(_ hours: Double?) -> Double? {
        guard let hours, let total = snapshot.sleepTotalH, total > 0 else { return nil }
        return hours / total
    }

    private func stageProgress(_ ratio: Double?, cap: Double) -> Double {
        (ratio ?? 0) / cap
    }

    private func dimensionRow(label: String, progress: Double, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption.weight(.medium))
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: max(0, min(1, progress)) * geometry.size.width)
                }
            }
            .frame(height: 6)
        }
    }

    private var hypnogramCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "睡眠分期", icon: "chart.bar.doc.horizontal.fill", tint: .indigo)
            HypnogramChart(intervals: intervals)
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
            Text("选择色块可查看该段起止时间与时长。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private var restorativeCard: some View {
        let hoursByStage = Dictionary(
            intervals.map { ($0.stage, $0.end.timeIntervalSince($0.start) / 3600) },
            uniquingKeysWith: +
        )
        let total = hoursByStage.values.reduce(0, +)
        let order: [SleepStageKind] = [.deep, .rem, .core, .awake]
        return VStack(alignment: .leading, spacing: 10) {
            AppSectionHeader(title: "恢复性睡眠构成", icon: "battery.100.bolt", tint: .purple)
            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(order, id: \.self) { stage in
                        if let hours = hoursByStage[stage], total > 0 {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(HypnogramChart.color(stage).opacity(0.85))
                                .frame(width: max(0, CGFloat(hours / total) * (geometry.size.width - 6)))
                        }
                    }
                }
            }
            .frame(height: 14)
            .clipShape(Capsule())
            ForEach(order, id: \.self) { stage in
                if let hours = hoursByStage[stage], total > 0 {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(HypnogramChart.color(stage))
                            .frame(width: 6, height: 6)
                        Text(HypnogramChart.label(stage))
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1f 小时 · %.0f%%", hours, hours / total * 100))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Text("恢复性睡眠 = 深睡 + REM；此页所有分数仅作展示，不参与状态 / 压力评分。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private var heartRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppSectionHeader(title: "睡眠心率与 dip", icon: "heart.fill", tint: .pink)
            if let avg = snapshot.sleepAvgHR {
                let level = SleepAnalysisEngine.heartRateLevel(avg)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(avg.rounded()))")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("次/分 · \(level.label)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let min = snapshot.sleepMinHR, let max = snapshot.sleepMaxHR {
                        Text("\(Int(min.rounded()))–\(Int(max.rounded()))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let minValue = snapshot.sleepMinHR, let maxValue = snapshot.sleepMaxHR, maxValue > minValue {
                    heartRateTrack(minValue: minValue, avg: avg, maxValue: maxValue)
                }
                Text("参考：>75 偏高 · 60–75 正常 · 40–60 优秀。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("没有睡眠窗口心率数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("心率 dip")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if let dip {
                    let level = SleepAnalysisEngine.dipLevel(dip)
                    Text(String(format: "%.0f%% · %@", dip, level.label))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(level == .low ? Color.orange : Color.green)
                } else {
                    Text("无数据")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text("dip = (日间心率 − 睡眠心率) / 日间心率；日间心率由全天均值推算，属估算，睡眠尚未结束（当天进行中）时显示为无数据。参考：<10% 偏低 · 10–20% 正常 · >20% 优秀。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func heartRateTrack(minValue: Double, avg: Double, maxValue: Double) -> some View {
        let domain = 35.0...95.0
        func position(_ value: Double) -> CGFloat {
            CGFloat((value - domain.lowerBound) / (domain.upperBound - domain.lowerBound))
        }
        return GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 8)
                Capsule()
                    .fill(Color.pink.opacity(0.3))
                    .frame(width: max(0, (position(maxValue) - position(minValue)) * width), height: 8)
                    .offset(x: position(minValue) * width)
                Circle()
                    .fill(Color.pink)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    .offset(x: position(avg) * width - 7)
            }
        }
        .frame(height: 14)
    }
}

// configured by qoder