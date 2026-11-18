import SwiftData
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @AppStorage("healthy.onboarded") private var onboarded = false
    @State private var step = 0
    @State private var isRequesting = false
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: index == step ? 18 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: step)
                    }
                }
                .padding(.top, 12)

                Spacer(minLength: 8)

                switch step {
                case 0:
                    welcome
                case 1:
                    healthKit
                default:
                    aiSetup
                }

                Spacer(minLength: 8)
                footer
            }
            .padding(24)
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var welcome: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 64))
                .foregroundStyle(.pink)
            Text("今日状态")
                .font(.largeTitle.bold())
            Text("读取 Apple Watch 的健康数据，在本地计算身体状态与压力，并用 AI 生成每天的建议。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                Label("数据只在这台设备上分析和保存", systemImage: "lock.shield")
                Label("只把日级汇总指标发送给你选择的 AI 服务", systemImage: "arrow.up.right.circle")
                Label("不提供医疗诊断", systemImage: "stethoscope")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private var healthKit: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 56))
                .foregroundStyle(.pink)
            Text("授权健康数据")
                .font(.title2.bold())
            Text("需要读取睡眠、HRV、心率、呼吸、血氧、手腕温度（Apple Watch 睡眠测量）、活动与静息能量、步行与体能、日照、正念、心情、体重体脂、血压和血糖数据，用于计算状态与压力。血压/血糖没有设备时，可在健康 App 手动记录。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button {
                requestAuthorization()
            } label: {
                Group {
                    if isRequesting {
                        ProgressView()
                    } else {
                        Text("授权读取健康数据")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
            if let healthMessage {
                Text(healthMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("如果某项数据没有开启，可以在「健康」App 的共享页面里补充授权。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var aiSetup: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 56))
                .foregroundStyle(.yellow)
            Text("配置 AI 服务")
                .font(.title2.bold())
            Text("使用千问（OpenAI 兼容接口）生成智能评分解读。Key 只保存在本机钥匙串，之后可随时切换 DeepSeek。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            NavigationLink("去配置 AI 服务") {
                AISettingsView()
            }
            .buttonStyle(.bordered)
            Text("也可以先跳过，之后在「设置 → AI 服务」里配置。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("上一步") {
                    step -= 1
                }
                .buttonStyle(.bordered)
            }
            Spacer()
            Button(step == 2 ? "开始使用" : "继续") {
                if step == 2 {
                    onboarded = true
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func requestAuthorization() {
        guard !isRequesting else { return }
        isRequesting = true
        healthMessage = nil
        Task {
            await appModel.requestHealthAuthorization()
            if case .failed(let reason) = appModel.phase {
                isRequesting = false
                healthMessage = reason
                return
            }
            healthMessage = "已提交授权，正在读取最近的健康数据…"
            await appModel.sync()
            isRequesting = false
            switch appModel.phase {
            case .done(let inserted):
                healthMessage = "已读取健康数据（新增 \(inserted) 天）。"
            case .failed(let reason):
                healthMessage = "读取失败：\(reason)"
            default:
                healthMessage = "已提交授权。"
            }
        }
    }
}

#Preview {
    let container = try! ModelContainer(
        for: DailyMetrics.self, DailyScore.self, DailyReport.self, ChatSession.self, ActionCheckIn.self, MoodEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return OnboardingView()
        .environment(AppModel(context: container.mainContext))
        .modelContainer(container)
}
