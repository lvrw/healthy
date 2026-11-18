import SwiftUI

struct ScoreRing: View {
    let title: String
    let value: Double?
    let tint: Color
    let caption: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var progress: Double {
        guard let value else { return 0 }
        return max(0, min(1, value / 100))
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.45), tint, tint.opacity(0.75)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.35), radius: 8)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.8),
                        value: progress
                    )
                VStack(spacing: 0) {
                    Text(value.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .snappy, value: value)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 132, height: 132)

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    HStack(spacing: 24) {
        ScoreRing(title: "身体状态", value: 78, tint: .green, caption: "较好")
        ScoreRing(title: "压力", value: 42, tint: .orange, caption: "中低")
    }
    .padding()
}
