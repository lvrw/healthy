import Foundation

/// 麦咖啡（McCafé）饮品的咖啡因估算。
///
/// 麦当劳官方营养计算器只公示热量与宏量营养，不公示咖啡因，因此按「品类 + 杯型」给出可解释的估算值。
/// 咖啡因打卡页（`MccafeCaffeine.quickAction`）与饮食识别记录（`DrinkIntakeEstimator`）共用本口径，
/// 保证同一杯麦咖啡在两个入口记下的咖啡因一致。
///
/// 纯逻辑、只依赖 Foundation，放在 Support 供 App 与测试 target 共同编译。
enum MccafeCaffeineEstimate {
    /// 麦咖啡专属命名词：这些词只出现在麦当劳麦咖啡分组的产品名里。
    /// 通用饮品估算器靠它识别「这杯是麦咖啡」，改用本口径（按杯型给咖啡因），
    /// 否则「奶铁」「鲜萃」等词不在通用系数表里，会出现只补了水、咖啡因仍为 0。
    static let exclusiveNameKeywords = [
        "奶铁", "浓浓", "雪冰", "阿芙佳朵", "鲜萃", "黑巧",
    ]

    /// 名称是否为麦咖啡专属产品（用于通用估算器分流）。
    static func isExclusiveName(_ name: String) -> Bool {
        let lower = name.lowercased()
        return exclusiveNameKeywords.contains { lower.contains($0) }
    }

    /// 按品类 + 杯型估算咖啡因（毫克）。牛奶 / 燕麦奶等无咖啡饮品返回 0。
    static func estimatedMg(for name: String) -> Double {
        let size = cupSize(of: name)
        if name.contains("阿芙佳朵") { return name.contains("抹茶") ? 15 : 45 }
        // 滴滤黑咖（2025-02 上架，无杯型名）：按中杯美式档估算。
        if name.contains("鲜萃") { return 110 }
        // 单份浓缩 espresso：低于中杯奶咖档，单独给可解释的估算值。
        if name.contains("浓缩咖啡") { return 65 }
        if name.contains("抹茶") { return size == .large ? 60 : 45 }
        if name.contains("黑巧") { return size == .large ? 30 : 25 }
        if name.contains("雪冰") { return size == .large ? 12 : 10 }
        guard containsCoffee(name) else { return 0 }
        switch size {
        case .small: return 75
        case .medium, .unspecified: return 110
        case .large: return 150
        }
    }

    private enum CupSize { case small, medium, large, unspecified }

    private static func cupSize(of name: String) -> CupSize {
        if name.contains("（小）") { return .small }
        if name.contains("（中）") { return .medium }
        if name.contains("（大）") { return .large }
        return .unspecified
    }

    private static func containsCoffee(_ name: String) -> Bool {
        ["美式", "奶铁", "拿铁", "玛奇朵", "卡布奇诺", "摩卡", "浓缩"].contains { name.contains($0) }
    }
}
