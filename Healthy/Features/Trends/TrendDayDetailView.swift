import SwiftUI

struct TrendDayDetailView: View {
    let score: DailyScore
    let metrics: DailyMetrics

    private var components: ReadinessComponents? {
        guard let json = score.readinessComponentsJSON?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReadinessComponents.self, from: json)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryCard
                componentCard
                metricsCard
            }
            .padding(16)
        }
        .background(AppScreenBackground())
        .navigationTitle(score.date.formatted(.dateTime.year().month(.wide).day()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.readiness.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                    Text("身体状态")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(score.stress.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text(score.stress.map { "压力 · \(StressEngine.level(for: $0, config: ScoringConfig()).label)" } ?? "压力")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ConfidenceBadge(raw: score.confidenceRaw)
            }
            Text("基线 \(score.baselineDays) 天 · 数据源 \(score.completeness)/\(MetricSource.allCases.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !score.missing.isEmpty {
                Text("缺失：\(score.missing)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .appCard()
    }

    @ViewBuilder
    private var componentCard: some View {
        if let components {
            VStack(alignment: .leading, spacing: 10) {
                Text("状态分项")
                    .font(.headline)
                componentRow("睡眠", components.sleep)
                componentRow("自主神经", components.autonomic)
                componentRow("活动负荷", components.load)
                componentRow("生命体征", components.vitals)
                componentRow("昼夜节律", components.circadian)
                componentRow("体能与身体", components.fitnessBody)
            }
            .appCard()
        }
    }

    private func componentRow(_ title: String, _ value: Double?) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption)
                .frame(width: 72, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                    Capsule()
                        .fill(Color.green.opacity(0.6))
                        .frame(width: max(0, min(1, (value ?? 0) / 100)) * geometry.size.width)
                }
            }
            .frame(height: 6)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当天关键指标")
                .font(.headline)
            metricRow("睡眠时长", metrics.sleepTotalH.map { String(format: "%.1f 小时", $0) })
            metricRow("睡眠效率", metrics.sleepEfficiency.map { String(format: "%.0f%%", $0 * 100) })
            metricRow("HRV（SDNN）", metrics.hrvSDNN.map { "\(Int($0.rounded())) ms" })
            metricRow("静息心率", metrics.restingHR.map { "\(Int($0.rounded())) 次/分" })
            metricRow("平均心率", metrics.avgHR.map { "\(Int($0.rounded())) 次/分" })
            metricRow("步数", metrics.steps.map { "\(Int($0.rounded()))" })
            metricRow("锻炼时间", metrics.exerciseMinutes.map { "\(Int($0.rounded())) 分钟" })
            metricRow("睡眠心率", metrics.sleepAvgHR.map { "\(Int($0.rounded())) 次/分" })
        }
        .appCard()
    }

    private func metricRow(_ title: String, _ value: String?) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value ?? "—")
                .font(.subheadline.monospacedDigit())
        }
        .padding(.vertical, 2)
    }
}

// configured by qoder
