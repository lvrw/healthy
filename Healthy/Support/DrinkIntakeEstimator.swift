import Foundation

/// 饮品的水量与咖啡因兜底估算。
///
/// 背景：营养库里大量饮品（可乐、美式、果汁、奶茶…）只登记了热量与三大营养素，
/// 「水」「咖啡因」两项是 0；AI 识别也常常只填热量。用户记录一杯可乐 / 拿铁时，
/// 当日饮水量与咖啡因就会漏记。
///
/// 这里按「名称品类 + 实际容量」给出缺省值，规则是**只补 0 值**：
/// 已登记真实数据的条目（瑞幸等）保持原值，不会被估算覆盖；
/// 麦咖啡官方不公示咖啡因，其专属命名走 `MccafeCaffeineEstimate` 的品类 + 杯型口径。
enum DrinkIntakeEstimator {
    /// 咖啡因品类系数表（毫克 / 毫升），按顺序匹配，先命中先用。
    /// 系数来自常见公示值：美式 ≈ 0.36（450ml / 164mg）、拿铁 ≈ 0.22（450ml / 99mg）、
    /// 茶饮 ≈ 0.10、可乐 ≈ 0.10（330ml / 34mg）、浓缩咖啡 ≈ 2.0（30ml / 60mg）。
    private struct CaffeineProfile {
        /// 命中任一关键词即视为该品类。
        let keywords: [String]
        /// 每毫升咖啡因毫克数。
        let mgPerMl: Double
    }

    private static let caffeineProfiles: [CaffeineProfile] = [
        // 浓缩咖啡：体积小、浓度高，必须排在「咖啡」类前面。
        CaffeineProfile(keywords: ["浓缩", "espresso", "意式"], mgPerMl: 2.0),
        CaffeineProfile(
            keywords: ["美式", "冷萃", "手冲", "滴滤", "黑咖啡", "冰咖啡", "americano", "cold brew"],
            mgPerMl: 0.36
        ),
        CaffeineProfile(
            keywords: ["拿铁", "latte", "卡布", "奇诺", "摩卡", "玛奇朵", "澳白", "馥芮白", "flat white",
                       "星冰乐", "frappuccino"],
            mgPerMl: 0.22
        ),
        CaffeineProfile(keywords: ["能量饮料", "红牛", "魔爪", "monster", "energy drink"], mgPerMl: 0.32),
        CaffeineProfile(keywords: ["可乐", "cola", "百事", "pepsi"], mgPerMl: 0.10),
        CaffeineProfile(keywords: ["茶", "tea", "鸳鸯", "奶茶", "乌龙", "普洱", "茉莉"], mgPerMl: 0.10),
        CaffeineProfile(keywords: ["可可", "巧克力", "cocoa", "chocolate"], mgPerMl: 0.05),
    ]

    /// 明确标注「无咖啡因」的词：命中后不再估算咖啡因（水照常估算）。
    private static let decafKeywords = ["无咖啡因", "低咖啡因", "decaf", "去咖啡因"]

    /// 需要按容量补「水」的饮品关键词。注意不能只写「水」，否则「水煮鱼」「水煮肉片」
    /// 这类菜名也会被当成饮料；只列明确的饮用水 / 饮品词。
    private static let drinkKeywords = [
        "咖啡", "coffee", "拿铁", "奶铁", "美式", "卡布", "摩卡", "玛奇朵", "澳白", "馥芮白", "浓缩",
        "冷萃", "手冲", "星冰乐", "茶", "tea", "奶茶", "乌龙", "普洱", "茉莉",
        "可乐", "cola", "雪碧", "sprite", "汽水", "苏打", "气泡水", "芬达", "七喜",
        "果汁", "juice", "果茶", "酸梅汤", "凉茶", "冬瓜茶",
        "牛奶", "milk", "豆浆", "豆奶", "酸奶", "奶昔", "可可", "巧克力饮",
        "矿泉水", "纯净水", "饮用水", "白开水", "椰子水", "电解质水", "运动饮料",
        "能量饮料", "红牛", "魔爪", "啤酒", "beer", "红酒", "白酒", "鸡尾酒", "酒",
    ]

    /// 认定为一杯饮品的最小容量（ml）。低于这个量按「浓缩液 / 粉末 / 配料」处理，不折算成水。
    private static let minimumDrinkVolumeMl: Double = 100

    /// 是否为「单独饮用的液体」：
    /// - 纯水 / 矿泉水等名称即使按克记（g≈ml）也算；
    /// - 其余饮品必须按 ml / L 记录，且名称命中饮品词。
    /// 咖啡蛋糕、茶叶蛋、水煮鱼、红酒炖牛肉等即使名字里有饮品词，只要按克记就是饭菜，
    /// 其中所含的水不属于「单独饮用的水」，不进饮水记录、不生成额外条目。
    static func isDrink(_ item: MealItem) -> Bool {
        let name = item.name.lowercased()
        guard !name.isEmpty else { return false }
        if isPlainWaterName(name) { return true }
        guard item.portionUnit == "ml" || item.portionUnit == "L" else { return false }
        // 麦咖啡的「奶铁 / 浓浓 / 雪冰 / 黑巧」等专属命名不在通用饮品词表里，
        // 按 ml 记时同样是单独饮用的液体，不能当成饭菜丢掉水与咖啡因。
        if MccafeCaffeineEstimate.isExclusiveName(name) { return true }
        return drinkKeywords.contains { name.contains($0) }
    }

    /// 该饮品的水量（毫升）：只统计单独饮用的液体（见 `isDrink`），饭菜本身的水一律为 0。
    /// 已有值优先；纯水按容量 100% 计，咖啡 / 茶 / 可乐 / 果汁等按 90% 计（冰块、奶泡、果肉不计入）。
    static func waterMl(for item: MealItem) -> Double {
        guard isDrink(item) else { return 0 }
        if item.perPortion.waterMl > 0 { return item.perPortion.waterMl }
        let volume = item.portionAmount
        guard volume >= minimumDrinkVolumeMl else { return 0 }
        let ratio = isPlainWater(item) ? 1.0 : 0.9
        return (volume * ratio).rounded()
    }

    /// 该饮品的咖啡因（毫克）：已有值优先；否则按品类系数 × 水量估算。
    static func caffeineMg(for item: MealItem) -> Double {
        if item.perPortion.caffeineMg > 0 { return item.perPortion.caffeineMg }
        let name = item.name.lowercased()
        guard !name.isEmpty, !decafKeywords.contains(where: { name.contains($0) }) else { return 0 }
        // 麦咖啡的「奶铁 / 鲜萃 / 雪冰 / 阿芙佳朵」等词不在通用系数表里，
        // 若走通用匹配会得到 0（只补了水、没补咖啡因）。改用麦咖啡专属估算，
        // 与咖啡因打卡页同一口径（按品类 + 杯型，牛奶 / 燕麦奶仍为 0）。
        if MccafeCaffeineEstimate.isExclusiveName(name) {
            return MccafeCaffeineEstimate.estimatedMg(for: item.name)
        }
        guard let profile = caffeineProfiles.first(where: { profile in
            profile.keywords.contains { name.contains($0) }
        }) else { return 0 }
        let base = waterMl(for: item)
        guard base > 0 else { return 0 }
        // 保留一位小数，避免 UI 出现 118.40000000000001 这类浮点尾数。
        return (base * profile.mgPerMl * 10).rounded() / 10
    }

    /// 纯饮用水（不含其他成分）：补水按 100% 容量计。
    private static func isPlainWater(_ item: MealItem) -> Bool {
        isPlainWaterName(item.name.lowercased())
    }

    private static func isPlainWaterName(_ name: String) -> Bool {
        let plainKeywords = ["矿泉水", "纯净水", "饮用水", "白开水", "纯悦", "冰露", "怡宝", "农夫山泉"]
        if plainKeywords.contains(where: { name.contains($0) }) { return true }
        return name == "水" || name == "冰水" || name == "热水"
    }

    /// 给一样食物补齐水量与咖啡因，只填空缺（0 值），已有数据原样保留。
    /// 非饮品（饭菜 / 固体食物）本身含有的水显式归零：只统计单独饮用的水，
    /// 避免整餐汇总、健康 App 写回与饮水合并时把它当成一杯水重复统计。
    static func applying(to item: MealItem) -> MealItem {
        var copy = item
        guard isDrink(item) else {
            copy.perPortion.waterMl = 0
            return copy
        }
        if copy.perPortion.waterMl <= 0 {
            copy.perPortion.waterMl = waterMl(for: item)
        }
        if copy.perPortion.caffeineMg <= 0 {
            copy.perPortion.caffeineMg = caffeineMg(for: item)
        }
        return copy
    }

    /// 批量补齐（识别结果、补充食材、记录编辑共用）。
    static func applying(to items: [MealItem]) -> [MealItem] {
        items.map { applying(to: $0) }
    }
}
