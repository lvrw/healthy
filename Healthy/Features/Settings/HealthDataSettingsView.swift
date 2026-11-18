import SwiftUI
import UIKit

/// 健康数据子页面：授权请求（带结果反馈）、同步入口，以及双向同步的范围与规则说明。
struct HealthDataSettingsView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openURL) private var openURL
    @State private var isRequesting = false
    @State private var authMessage: String?
    @State private var authOK = false

    var body: some View {
        Form {
            Section {
                Button {
                    requestAuthorization()
                } label: {
                    HStack {
                        Text("请求健康数据授权")
                        if isRequesting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isRequesting)
                if let authMessage {
                    Label {
                        Text(authMessage)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: authOK ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    }
                    .foregroundStyle(authOK ? Color.green : Color.red)
                }
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Label("打开系统设置", systemImage: "arrow.up.forward.app")
                }
            } header: {
                Text("授权")
            } footer: {
                Text("新增写入类型时会再次出现授权弹窗；如果被拒绝过或看不到弹窗，请通过「打开系统设置 → 隐私与安全性 → 健康」手动开启。写入权限用于把喝水量、咖啡因，以及饮食的能量 / 碳水 / 蛋白质 / 脂肪 / 纤维 / 糖 / 钠写回健康 App，拒绝写入不会影响其他数据的读取。")
            }

            Section {
                Button("同步（全量）") {
                    Task { await appModel.resyncAll() }
                }
                .disabled(appModel.phase == .syncing)
                syncStatus
            } header: {
                Text("同步")
            }
        }
        .navigationTitle("健康数据")
    }

    private func requestAuthorization() {
        guard !isRequesting else { return }
        isRequesting = true
        authMessage = nil
        Task {
            let result = await appModel.requestHealthAuthorizationWithFeedback()
            authOK = result.ok
            authMessage = result.message
            isRequesting = false
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        switch appModel.phase {
        case .idle:
            Text("尚未同步")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .syncing:
            HStack(spacing: 8) {
                ProgressView()
                Text("正在同步…")
            }
        case .done(let inserted):
            Text("同步完成，新增 \(inserted) 天。")
                .font(.footnote)
        case .failed(let reason):
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

#Preview {
    NavigationStack {
        HealthDataSettingsView()
    }
}
