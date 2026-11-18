import Foundation

enum LLMProviderID: String, CaseIterable, Identifiable, Codable, Sendable {
    case qwen
    case deepSeek
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .qwen: return "千问"
        case .deepSeek: return "DeepSeek"
        case .custom: return "自定义"
        }
    }

    var defaultBaseURL: String {
        switch self {
        case .qwen: return "https://cn-beijing.maas.qianwenaiapi.com/compatible-mode/v1"
        case .deepSeek: return "https://api.deepseek.com/v1"
        case .custom: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .qwen: return "qwen3.8-flash"
        // deepseek-chat / deepseek-reasoner 已于 2026-07-24 下线，现役模型为 deepseek-flash
        case .deepSeek: return "deepseek-flash"
        case .custom: return ""
        }
    }
}

struct LLMSettings: Codable, Sendable, Equatable {
    var provider: LLMProviderID
    var baseURL: String
    var model: String

    static let `default` = LLMSettings(
        provider: .qwen,
        baseURL: LLMProviderID.qwen.defaultBaseURL,
        model: LLMProviderID.qwen.defaultModel
    )
}

enum LLMSettingsStore {
    private static let key = "healthy.llm.settings"

    /// 已下线的 DeepSeek 模型名，读到旧设置时统一改写为现役模型
    private static let retiredDeepSeekModels: Set<String> = [
        "deepseek-chat",
        "deepseek-reasoner",
        "deepseek-v4-flash",
        "deepseek-v4-flash-vision-exp",
    ]

    static func load() -> LLMSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(LLMSettings.self, from: data)
        else {
            return .default
        }
        return migrated(settings)
    }

    static func save(_ settings: LLMSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func migrated(_ settings: LLMSettings) -> LLMSettings {
        guard settings.provider == .deepSeek,
              retiredDeepSeekModels.contains(settings.model.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return settings
        }
        var result = settings
        result.model = LLMProviderID.deepSeek.defaultModel
        return result
    }
}
