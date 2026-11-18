import SwiftUI

struct AISettingsView: View {
    @Environment(\.modelContext) private var context
    @State private var settings = LLMSettingsStore.load()
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var isTesting = false
    @State private var status: TestState = .idle
    @State private var previewJSON: String?
    @State private var previewError: String?
    @State private var aiFoodEnabled = FoodRecognitionSettings.isAIEnabled
    @State private var aiSmartScoringEnabled = AISmartScoringSettings.isEnabled

    enum TestState: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        Form {
            Section("服务商") {
                Picker("服务商", selection: $settings.provider) {
                    ForEach(LLMProviderID.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .onChange(of: settings.provider) { _, newValue in
                    if newValue != .custom {
                        settings.baseURL = newValue.defaultBaseURL
                        settings.model = newValue.defaultModel
                    }
                    hasSavedKey = KeychainStore().hasKey(account: newValue.rawValue)
                }
            }

            Section("接口") {
                TextField("Base URL", text: $settings.baseURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("模型", text: $settings.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("API Key") {
                SecureField(hasSavedKey ? "已保存，留空表示不修改" : "粘贴 API Key", text: $apiKey)
                Button("保存设置") {
                    save()
                }
                Button {
                    testConnection()
                } label: {
                    HStack(spacing: 8) {
                        Text("测试连接")
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting)
                statusView
            }

            Section {
                Toggle("食物识别", isOn: $aiFoodEnabled)
                    .onChange(of: aiFoodEnabled) { _, newValue in
                        FoodRecognitionSettings.isAIEnabled = newValue
                    }
                Text("开启时，「识别食物」会调用上面配置的视觉模型分析照片与文字；模型不支持图片时（如 deepseek-v4-pro）只按文字描述估算；关闭时改用本地营养库匹配，从本地营养库按名称 / 关键词匹配，不联网。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("智能评分", isOn: $aiSmartScoringEnabled)
                    .onChange(of: aiSmartScoringEnabled) { _, newValue in
                        AISmartScoringSettings.isEnabled = newValue
                    }
                Text("开启时，每日健康简报 / 评分解读由 AI 生成；关闭后仅保留本机确定性评分，不再调用大模型。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI 功能")
            }

            Section {
                Button("查看将发送给 AI 的数据") {
                    loadPreview()
                }
                if let previewError {
                    Text(previewError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Text("Key 只保存在本机钥匙串（不同步 iCloud），请求时才会读入内存。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("千问使用工作空间专属地址与 qwen3.8-flash；切到 DeepSeek 时服务商选 DeepSeek，Base URL 与模型会自动填好。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("deepseek-flash 支持图片输入（content 片段数组）；deepseek-v4-pro 等纯文本模型不支持，识别时会自动只发文字。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI 服务")
        .onAppear {
            hasSavedKey = KeychainStore().hasKey(account: settings.provider.rawValue)
        }
        .sheet(isPresented: Binding(
            get: { previewJSON != nil },
            set: { if !$0 { previewJSON = nil } }
        )) {
            if let previewJSON {
                DataPreviewView(json: previewJSON)
            }
        }
    }

    private func loadPreview() {
        do {
            previewJSON = try BriefingService(context: context).previewPayload(dayKey: DayKey.key(for: .now))
            previewError = nil
        } catch {
            previewError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch status {
        case .idle:
            EmptyView()
        case .success(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.green)
        case .failure(let message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private func save() {
        LLMSettingsStore.save(settings)
        if !apiKey.isEmpty {
            do {
                try KeychainStore().save(apiKey, account: settings.provider.rawValue)
                apiKey = ""
                hasSavedKey = true
                status = .success("设置已保存")
            } catch {
                status = .failure("保存 Key 失败：\(error.localizedDescription)")
            }
        } else {
            status = .success("设置已保存")
        }
    }

    private func testConnection() {
        guard !isTesting else { return }
        LLMSettingsStore.save(settings)
        let key = apiKey.isEmpty ? KeychainStore().read(account: settings.provider.rawValue) : apiKey
        guard let key, !key.isEmpty else {
            status = .failure("请先填写 API Key")
            return
        }
        isTesting = true
        status = .idle
        Task {
            defer { isTesting = false }
            do {
                let result = try await LLMClient().testConnection(
                    configuration: .init(
                        baseURL: settings.baseURL,
                        model: settings.model,
                        apiKey: key,
                        provider: settings.provider
                    )
                )
                let latency = Int((result.latency * 1000).rounded())
                status = .success("连接成功 · \(latency) ms · \(result.model)")
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AISettingsView()
    }
}
