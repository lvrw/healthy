import SwiftUI

struct CurrentStateCard: View {
    let snapshot: CurrentStateSnapshot?
    let isRefreshing: Bool
    let error: String?
    let updatedAt: Date?
    let onRefresh: () -> Void
    /// 详情页按入口过滤：HRV 页只留「此刻状态 + 心率」，压力页只留「此刻压力 + 心率」。
    var mode: DayDetailMode = .hrv

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label {
                    Text("此刻")
                        .font(.headline)
                } icon: {
                    Image(systemName: mode == .hrv ? "waveform.path.ecg" : "bolt.heart.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == .hrv ? Color.pink : Color.orange)
                        .frame(width: 28, height: 28)
                        .background((mode == .hrv ? Color.pink : Color.orange).opacity(0.12), in: Circle())
                }
                Spacer()
                Button {
                    onRefresh()
                } label: {
                    if isRefreshing {
                        ProgressView()
                    } else {
                        Label("刷新", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing)
            }

            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            } else if let snapshot {
                HStack(spacing: 0) {
                    if mode == .hrv {
                        metric(
                            title: "此刻状态",
                            value: snapshot.currentState.map { "\(Int($0.rounded()))" } ?? "—",
                            tint: .primary
                        )
                    } else {
                        metric(
                            title: "此刻压力",
                            value: snapshot.instantStress.map { "\(Int($0.rounded()))" } ?? "—",
                            tint: stressTint(snapshot.instantStressLevel)
                        )
                    }
                    Divider().frame(height: 38)
                    metric(
                        title: "当前心率",
                        value: snapshot.heartRate.map { "\(Int($0.rounded()))" } ?? "—",
                        caption: "次/分",
                        tint: .pink
                    )
                }
                HStack(spacing: 6) {
                    Text(snapshot.confidence.label)
                    if let date = snapshot.heartRateAt {
                        Text("· 心率 \(date.formatted(.relative(presentation: .named)))")
                    }
                    if let updatedAt {
                        Text("· 更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                if let note = snapshot.note {
                    Text(note)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("点刷新获取最近一次心率，并估算此刻状态与压力。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(mode == .hrv ? stateFormulaText : stressFormulaText)
                Text("与下方圆环口径不同：圆环是全天评分；此刻压力取最近一次心率 / HRV，并以 28 天日均心率为中心。非医疗诊断。")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .appCard()
    }

    private func metric(title: String, value: String, caption: String? = nil, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(AppType.display(26))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stressTint(_ level: StressLevel?) -> Color {
        switch level {
        case .low: return .teal
        case .moderateLow: return .blue
        case .elevated: return .orange
        case .high: return .red
        case nil: return .secondary
        }
    }

    private var stateFormulaText: String {
        let config = ScoringConfig()
        let readiness = Int((config.instantStateReadinessWeight * 100).rounded())
        let stress = Int((config.instantStateStressWeight * 100).rounded())
        return "此刻状态 = \(readiness)% 今日状态 + \(stress)%（100 − 此刻压力），是即时综合体感。"
    }

    private var stressFormulaText: String {
        "此刻压力按最近一次心率与 HRV，相对 28 天日均心率 / HRV 基线即时估算。"
    }
}

#Preview {
    CurrentStateCard(
        snapshot: CurrentStateSnapshot(
            instantStress: 42,
            instantStressLevel: .moderateLow,
            currentState: 76,
            heartRate: 62,
            heartRateAt: .now.addingTimeInterval(-240),
            confidence: .fresh,
            note: nil
        ),
        isRefreshing: false,
        error: nil,
        updatedAt: .now,
        onRefresh: {}
    )
    .padding()
    .background(Color(.systemGroupedBackground))
}
