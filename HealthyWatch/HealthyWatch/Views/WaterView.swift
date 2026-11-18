import SwiftUI

struct WaterView: View {
    @EnvironmentObject private var env: AppEnvironment
    @State private var hapticTick = 0
    /// 目标来自 iPhone 的「喝水配置」推送；AppEnvironment 已做范围钳制并跟随更新。
    private var target: Double { env.waterTargetMl }
    private let presets: [AmountPreset] = [
        AmountPreset(label: "小口 100", amount: 100),
        AmountPreset(label: "水杯 200", amount: 200),
        AmountPreset(label: "一杯 350", amount: 350),
        AmountPreset(label: "大杯 500", amount: 500),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Gauge(value: min(env.waterMlToday, target), in: 0...target) {
                    // 圆环里只留数值：导航标题已经是「喝水」，再放一次文字会压住数字。
                    EmptyView()
                } currentValueLabel: {
                    Text("\(Int(env.waterMlToday))")
                        .font(.title3.weight(.bold))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(.blue)

                Text(String(format: "%.0f / %.0f ml", env.waterMlToday, target))
                    .font(.headline)

                if !env.canWriteWater, env.healthAvailable {
                    Button("授权以记录喝水") { Task { await env.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }

                VStack(spacing: 8) {
                    ForEach(presets) { p in
                        Button {
                            Task {
                                await env.addWater(p.amount)
                                hapticTick += 1
                            }
                        } label: {
                            Label("+\(Int(p.amount)) ml", systemImage: "drop.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .sensoryFeedback(.success, trigger: hapticTick)
            }
            .padding()
        }
        .navigationTitle("喝水")
    }
}
