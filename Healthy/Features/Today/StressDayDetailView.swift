import SwiftUI

struct StressDayDetailView: View {
    let summary: IntradaySummary

    private var tiers: [StressTier] {
        StressTierPresentation.tiers()
    }

    private var bucketCounts: [StressLevel: Int] {
        var counts: [StressLevel: Int] = [:]
        for bucket in summary.buckets {
            guard bucket.context == .normal, let stress = bucket.stress else { continue }
            let level = StressEngine.level(for: stress, config: ScoringConfig())
            counts[level, default: 0] += 1
        }
        return counts
    }

    var body: some View {
        List {
            Section {
                ForEach(tiers, id: \.level) { tier in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(tier.level.tint)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(tier.level.label)（\(tier.rangeText)）")
                                .font(.subheadline.weight(.medium))
                            Text(String(format: "对应 HRV z %.2f ~ %.2f", tier.zLowerBound, tier.zUpperBound))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(bucketCounts[tier.level] ?? 0) 段")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("z 区间由小时压力公式（压力 = 50 − 16×z，z 截断 ±2.5）反推，仅为我们口径的展示换算；桶宽 15 分钟。")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } header: {
                Text("四档对照")
            }

            Section("全部读数（\(summary.readings.count) 条）") {
                if summary.readings.isEmpty {
                    Text("今天还没有 HRV 读数。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.readings.reversed()) { reading in
                    HStack {
                        Text(reading.date.formatted(date: .omitted, time: .shortened))
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(reading.sdnn.map { "SDNN \(Int($0.rounded())) ms" }
                            ?? reading.rmssd.map { "RMSSD \(Int($0.rounded())) ms" }
                            ?? "—")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(reading.stress.map { "\(Int($0.rounded())) · \(reading.level?.label ?? "—")" } ?? "—")
                            .font(.caption.weight(.medium).monospacedDigit())
                    }
                }
            }

            Section("原始心率桶（\(summary.buckets.count) 段）") {
                if summary.buckets.isEmpty {
                    Text("今天还没有心率分桶数据。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.buckets) { bucket in
                    HStack {
                        Text("\(bucket.start.formatted(date: .omitted, time: .shortened))–\(bucket.end.formatted(date: .omitted, time: .shortened))")
                            .font(.caption.monospacedDigit())
                        Spacer()
                        Text(bucket.heartRate.map { "\(Int($0.rounded())) bpm" } ?? "无数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(contextText(bucket.context))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .navigationTitle("当日详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contextText(_ context: HourContext) -> String {
        switch context {
        case .normal: return "常规"
        case .workout: return "运动"
        case .sleeping: return "睡眠"
        case .activity: return "活动"
        case .noHeartRate: return "无心率"
        case .noBaseline: return "基线积累中"
        }
    }
}

// configured by qoder