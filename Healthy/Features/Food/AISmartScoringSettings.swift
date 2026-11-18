import Foundation

/// 智能评分开关：是否使用 AI（云端大模型）生成每日健康简报 / 评分解读。
/// 关闭时仅保留本机确定性评分（状态 / 压力），不再调用大模型。
enum AISmartScoringSettings {
    private static let key = "healthy.ai.smartScoringEnabled"

    /// 默认开启 AI 智能评分；用户可在「设置 → AI 服务」里关闭。
    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
