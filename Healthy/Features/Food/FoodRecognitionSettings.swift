import Foundation

/// 食物识别开关：是否使用 AI（云端大模型）识别。
/// 关闭时退化为「本地营养库匹配」——本地营养库按文字/关键词匹配回填营养。
enum FoodRecognitionSettings {
    private static let key = "healthy.food.aiRecognitionEnabled"

    /// 默认开启 AI 识别；用户可在「设置 → AI 服务」里关闭。
    static var isAIEnabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
