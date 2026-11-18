import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                // 与 iOS 端 sectionTitle 同款标题风格：左对齐、subheadline semibold、次要色
                HStack(alignment: .center) {
                    Text("Healthy")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await env.refresh() }
                    } label: {
                        if env.isLoading {
                            ProgressView()
                                .scaleEffect(0.65)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.cyan)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(env.isLoading)
                    .accessibilityLabel("同步数据")
                }
                .padding(.horizontal, 4)

                if !env.healthAvailable {
                    Text("需在 Apple Watch 真机上运行以读取健康数据")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let msg = env.errorMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                if env.latestHRVms == nil, env.waterMlToday == 0, env.caffeineMgToday == 0, env.healthAvailable {
                    Button("连接健康数据") { Task { await env.requestAccess() } }
                        .buttonStyle(.borderedProminent)
                }

                row(
                    title: "HRV",
                    value: env.latestHRVms.map { String(format: "%.0f ms", $0) } ?? "—",
                    accent: .cyan,
                    dest: HRVView()
                )
                row(
                    title: "压力",
                    value: stressText,
                    accent: stressColor(env.stress.level),
                    dest: StressView()
                )
                row(
                    title: "喝水",
                    value: String(format: "%.0f ml", env.waterMlToday),
                    accent: .blue,
                    dest: WaterView()
                )
                row(
                    title: "咖啡因",
                    value: String(format: "%.0f mg", env.caffeineMgToday),
                    accent: caffeineColor,
                    dest: CaffeineView()
                )
            }
            .padding(.horizontal, 4)
        }
        .refreshable { await env.refresh() }
        .onAppear { env.onAppear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await env.refresh() } }
        }
    }

    private var stressText: String {
        guard let score = env.stress.score else { return "基线不足" }
        return String(format: "%d · %@", Int(score), env.stress.level.title)
    }

    private var caffeineColor: Color { env.caffeineMgToday > 200 ? .red : .orange }

    private func row(title: String, value: String, accent: Color, dest: some View) -> some View {
        NavigationLink { dest } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.caption).foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(accent)
                }
                Spacer()
                Image(systemName: "chevron.forward").foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }
}

func shortTime(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "HH:mm"
    return f.string(from: date)
}

func weekdaySymbol(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "EEE"
    return f.string(from: date)
}
