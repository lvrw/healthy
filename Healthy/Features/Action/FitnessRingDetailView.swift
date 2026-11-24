import SwiftUI

/// 行动页「健身」卡下钻：按健康 App 健身页的口径展示活动 / 锻炼 / 站立三个圆环。
/// 只使用当日累计值与健身 App 里设置的活动圆环目标，不额外推断小时序列。
struct FitnessRingDetailView: View {
    /// 选中日期的指标；nil 表示这天没有同步到健身数据。
    let metrics: DailyMetrics?
    /// 当前查看的日期，用于标题与空态文案。
    let date: Date

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let activeColor = Color(red: 1.0, green: 0.231, blue: 0.361)
    private static let exerciseColor = Color(red: 0.549, green: 0.878, blue: 0.310)
    private static let standColor = Color(red: 0.333, green: 0.784, blue: 0.918)

    private struct RingMetric: Identifiable {
        let id: String
        let title: String
        let icon: String
        let unit: String
        let value: Double?
        let goal: Double
        let tint: Color

        var progress: Double {
            guard let value, goal > 0 else { return 0 }
            return min(1, max(0, value / goal))
        }

        var percent: Int { Int((progress * 100).rounded()) }

        var valueText: String {
            guard let value else { return "—" }
            return "\(Int(value.rounded()))"
        }

        var goalText: String { "\(Int(goal.rounded()))" }
    }

    /// 三个环：目标优先用健身 App 的真实圆环目标，摘要缺失才回退 500 卡 / 30 分 / 12 小时。
    private var rings: [RingMetric] {
        [
            RingMetric(
                id: "active",
                title: "活动",
                icon: "flame.fill",
                unit: "千卡",
                value: metrics?.activeEnergy,
                goal: max(metrics?.activeEnergyGoal ?? 500, 1),
                tint: Self.activeColor
            ),
            RingMetric(
                id: "exercise",
                title: "锻炼",
                icon: "figure.run",
                unit: "分钟",
                value: metrics?.exerciseMinutes,
                goal: max(metrics?.exerciseGoalMinutes ?? 30, 1),
                tint: Self.exerciseColor
            ),
            RingMetric(
                id: "stand",
                title: "站立",
                icon: "figure.stand",
                unit: "小时",
                value: metrics?.standMinutes.map { $0 / 60 },
                goal: max(metrics?.standGoalHours ?? 12, 1),
                tint: Self.standColor
            ),
        ]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ringOverview
                VStack(spacing: 14) {
                    ForEach(rings) { ring in
                        metricCard(ring)
                    }
                }
                footerText
                if metrics == nil {
                    Text("\(dayText) 还没有健身数据，同步健康 App 后再来查看。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
        .background(AppScreenBackground(tone: .mint))
        .navigationTitle("健身")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dayText: String {
        date.formatted(.dateTime.month().day())
    }

    /// 三个同心圆环：外→内为活动 / 锻炼 / 站立，与健康 App 健身页一致。
    private var ringOverview: some View {
        VStack(spacing: 16) {
            ZStack {
                ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                    let diameter: CGFloat = 252 - CGFloat(index) * 44
                    Circle()
                        .stroke(ring.tint.opacity(0.16), lineWidth: 18)
                        .frame(width: diameter, height: diameter)
                    Circle()
                        .trim(from: 0, to: ring.progress)
                        .stroke(ring.tint, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: diameter, height: diameter)
                        .animation(reduceMotion ? nil : .snappy, value: ring.progress)
                }
            }
            .frame(height: 268)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                rings.map { "\($0.title) \($0.percent)%" }.joined(separator: "，")
            )

            HStack(spacing: 0) {
                ForEach(rings) { ring in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(ring.tint)
                            .frame(width: 8, height: 8)
                        Text(ring.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(ring.percent)%")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(ring.tint)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .appCard(padding: 20)
        .cardScrollEffect()
    }

    private func metricCard(_ ring: RingMetric) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: ring.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ring.tint)
                    .frame(width: 26, height: 26)
                    .background(ring.tint.opacity(0.14), in: Circle())
                Text(ring.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppPalette.ink)
                Spacer()
                Text(ring.progress >= 1 ? "已达标" : "\(ring.percent)%")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(ring.progress >= 1 ? ring.tint : .secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ring.valueText)
                    .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(ring.tint)
                Text("/ \(ring.goalText) \(ring.unit)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            ProgressView(value: ring.progress)
                .tint(ring.tint)
        }
        .appCard()
        .cardScrollEffect()
    }

    private var footerText: some View {
        Text("目标取自健身 App 里设置的活动圆环；本页只展示当日累计，不提供小时明细。数据来自健康 App，仅供日常参考。")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// configured by qoder