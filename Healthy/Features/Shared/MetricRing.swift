import SwiftUI

struct MetricRing: View {
    let text: String
    let progress: Double
    let title: String
    let caption: String
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.07), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0, min(1, progress)))
                    .stroke(
                        AngularGradient(
                            colors: [tint.opacity(0.45), tint, tint.opacity(0.75)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 10, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: tint.opacity(0.3), radius: 6)
                    .animation(
                        reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.8),
                        value: progress
                    )
                VStack(spacing: 0) {
                    Text(text)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 108, height: 108)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// configured by qoder