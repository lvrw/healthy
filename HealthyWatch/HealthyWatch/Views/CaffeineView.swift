import SwiftUI

struct CaffeineView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var hapticTick = 0
    private let limit = 200.0
    private let presets: [AmountPreset] = [
        AmountPreset(label: "美式咖啡", amount: 95),
        AmountPreset(label: "拿铁", amount: 127),
        AmountPreset(label: "红茶", amount: 47),
        AmountPreset(label: "可乐", amount: 34),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Gauge(value: min(env.caffeineMgToday, limit * 1.5), in: 0...(limit * 1.5)) {
                    Text("咖啡因").font(.caption2)
                } currentValueLabel: {
                    Text("\(Int(env.caffeineMgToday))")
                        .font(.title3.weight(.bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(env.caffeineMgToday > limit ? .red : .orange)

                Text(String(format: "%.0f / %.0f mg", env.caffeineMgToday, limit))
                    .font(.headline)

                if env.caffeineMgToday > limit {
                    Text("已超过每日建议上限").font(.caption2).foregroundStyle(.red)
                }

                if !env.canWriteCaffeine, env.healthAvailable {
                    Button("授权以记录咖啡因") { Task { await env.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }

                VStack(spacing: 8) {
                    ForEach(presets) { p in
                        Button {
                            Task {
                                await env.addCaffeine(p.amount)
                                hapticTick += 1
                            }
                        } label: {
                            Label("+\(Int(p.amount)) mg · \(p.label)", systemImage: "cup.and.saucer.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .sensoryFeedback(.success, trigger: hapticTick)
            }
            .padding()
        }
        .navigationTitle("咖啡因")
    }
}

/// 喝水 / 咖啡因快速添加的预设项。
struct AmountPreset: Identifiable {
    let id = UUID()
    let label: String
    let amount: Double
}
