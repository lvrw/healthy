import SwiftUI

struct StressView: View {
    @EnvironmentObject private var env: AppEnvironment

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let score = env.stress.score {
                    Gauge(value: score, in: 0...100) {
                        Text("压力").font(.caption)
                    } currentValueLabel: {
                        Text("\(Int(score))").font(.title2.weight(.bold))
                    } minimumValueLabel: {
                        Text("0").font(.caption2)
                    } maximumValueLabel: {
                        Text("100").font(.caption2)
                    }
                    .gaugeStyle(.accessoryCircular)
                    .tint(stressColor(env.stress.level))

                    Text(env.stress.level.title)
                        .font(.headline)
                        .foregroundStyle(stressColor(env.stress.level))
                } else {
                    Image(systemName: "waveform.path.ecg")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("暂无足够基线").font(.headline).foregroundStyle(.secondary)
                }

                infoRow("HRV z 分数", env.stress.zScore.map { String(format: "%.2f", $0) } ?? "—")
                infoRow("基线天数", "\(env.stress.baselineDays) 天（需 ≥ 7）")
                infoRow("置信度", confidenceText)

                Text("压力由近 28 天 HRV 基线推算：压力 = 50 − 16·z，z 为最新 HRV 相对基线的标准差倍数（与 Healthy iOS 端口径一致）。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("压力")
    }

    private var confidenceText: String {
        switch env.stress.confidence {
        case .insufficient: return "基线不足"
        case .low: return "数据较少"
        case .full: return "充足"
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.weight(.medium))
        }
    }
}

/// 压力等级配色（与 iOS 端 StressLevelStyle 保持一致的高/中/低语义）。
func stressColor(_ level: StressLevel) -> Color {
    switch level {
    case .low: return .green
    case .moderateLow: return .yellow
    case .elevated: return .orange
    case .high: return .red
    }
}
