import Foundation

/// 瑞幸咖啡官网在售产品（2026-11-13 读取、2026-11-18 复核 https://www.lkcoffee.com/products，
/// 经官网产品列表接口 /portalcapi/resource/portal/product/list 全量核对为 28 款，产品与数值无变化）。
/// 这是本地营养库「瑞幸咖啡」预置分组与咖啡因打卡「瑞幸咖啡」快捷入口的同一份数据源，
/// 两边都从这里派生，避免产品名 / 数值各写一份。
/// 数值口径：官网公示的推荐点单配置下「每杯」值（默认大杯 / 冰 / 默认浓度 / 不另外加糖），
/// 16oz 与超大杯产品在 portion 里单独标注；官网只公示热量、咖啡因及个别产品的蛋白质，
/// 碳水 / 蛋白质 / 脂肪为按公开配方成分（厚椰乳、牛奶、丝绒厚奶、NFC 果汁等营养参考）拆算的推算值，
/// 未公示热量的 6 款热量同样为推算值（portion 标「推算」），打卡说明里会区分展示。
/// 官网未公示咖啡因的产品同样收录（咖啡因记 0），选择列表里全部展示，打卡时只写热量 / 蛋白质与水量。
/// 官网未公示咖啡因的产品同样收录：值参考同系列公示产品或公开测评推算，
/// `caffeineEstimated` 置 true 并在 portion 标「推算」，UI 与打卡说明里会区分展示。
struct LuckinDrink: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    /// 官网分类名，用于快捷选择列表分组。
    var category: String
    var keywords: [String]
    /// 营养库里展示的份量说明（含咖啡因文本）。
    var portion: String
    /// 咖啡因 mg/杯；0 表示不含咖啡因。官网未公示时为推算值（caffeineEstimated = true）。
    var caffeineMg: Double
    /// 咖啡因是否为推算值（官网未公示，参考同系列公示产品或公开测评推算）。
    var caffeineEstimated: Bool
    /// 官网公示的热量 / 蛋白质，其余宏量营养未公示留 0。
    var nutrition: IntakeNutrition
    /// 杯容量（ml），用于饮品打卡时联动的含水量。
    var waterMl: Double
    /// 官网产品图片 URL（远程 CDN），用于快捷选择卡片展示。
    var imageURL: String?
}

/// 选择列表里的一个官网分类分组。
struct LuckinDrinkGroup: Sendable, Equatable, Identifiable {
    var category: String
    var drinks: [LuckinDrink]
    var id: String { category }
}

enum LuckinCatalog {
    static let drinks: [LuckinDrink] = [
        LuckinDrink(id: "lk.coconut", name: "生椰拿铁", category: "拿铁类", keywords: ["生椰拿铁"], portion: "咖啡因118.4mg · 1 大杯 / 450ml", caffeineMg: 118.4, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 179, carbsG: 7.4, proteinG: 0.7, fatG: 13.7), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/52155ea342784e5e92935467d921b24c.png"),
        LuckinDrink(id: "lk.jasmine", name: "茉莉花香拿铁", category: "拿铁类", keywords: ["茉莉花香拿铁"], portion: "咖啡因236mg · 1 大杯 / 450ml", caffeineMg: 236, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 76, carbsG: 10, proteinG: 4.5, fatG: 2), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/0de4a497f3ba47fab6239bac36840385.png"),
        LuckinDrink(id: "lk.latte", name: "拿铁", category: "拿铁类", keywords: ["拿铁", "瑞幸拿铁"], portion: "咖啡因98.6mg · 1 大杯 / 450ml", caffeineMg: 98.6, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 268, carbsG: 22, proteinG: 11, fatG: 14), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/81a3af83583a4752bf00a0e40df95e59.png"),
        LuckinDrink(id: "lk.butter", name: "小黄油拿铁", category: "拿铁类", keywords: ["小黄油拿铁"], portion: "咖啡因171.9mg · 1 大杯 / 450ml", caffeineMg: 171.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 250, carbsG: 20, proteinG: 9, fatG: 14), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/f061918c5d4c4688b0b84f477f74fd21.png"),
        LuckinDrink(id: "lk.lightcoconut", name: "轻椰茉莉拿铁", category: "拿铁类", keywords: ["轻椰茉莉拿铁"], portion: "咖啡因179.1mg · 1 大杯 / 450ml", caffeineMg: 179.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 120, carbsG: 16, proteinG: 2, fatG: 5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/0ddfaeeba9d94a1583dfb8fafcb1e28f.png"),
        LuckinDrink(id: "lk.velvet", name: "丝绒拿铁", category: "拿铁类", keywords: ["丝绒拿铁"], portion: "咖啡因≈98.6mg（推算）· 1 大杯 / 450ml", caffeineMg: 98.6, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 376, carbsG: 34, proteinG: 12, fatG: 20), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/26f156673e8f4eb6ab9fb2c0c6b68102.jpeg"),
        LuckinDrink(id: "lk.thaiyuanyeung", name: "泰奶鸳鸯拿铁", category: "拿铁类", keywords: ["泰奶鸳鸯拿铁"], portion: "咖啡因143.1mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 143.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 300, carbsG: 42, proteinG: 6.5, fatG: 11), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/17/7ecb19d3d2db4cf2baec8eb041689138.png"),
        LuckinDrink(id: "lk.minicheese", name: "小奶酪拿铁", category: "拿铁类", keywords: ["小奶酪拿铁"], portion: "咖啡因≈98.6mg（推算）· 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 98.6, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 260, carbsG: 24, proteinG: 9, fatG: 14), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/6cd25d89b5cf40a69f38f93b2e58c776.png"),
        LuckinDrink(id: "lk.mangopomelo", name: "生椰杨枝甘露", category: "其他非咖啡类", keywords: ["生椰杨枝甘露"], portion: "咖啡因14.9mg · 1 大杯 / 450ml", caffeineMg: 14.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 176, carbsG: 28, proteinG: 2, fatG: 5.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/11/18b64d3f2900454490805d02fa40e398.png"),
        LuckinDrink(id: "lk.classicthai", name: "经典泰奶", category: "其他非咖啡类", keywords: ["经典泰奶"], portion: "咖啡因137.3mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 137.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 330, carbsG: 52, proteinG: 4.4, fatG: 10), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/17/8796417fbf2241279bf56124441b50ca.png"),
        LuckinDrink(id: "lk.saltedthai", name: "咸法酪泰奶", category: "其他非咖啡类", keywords: ["咸法酪泰奶"], portion: "咖啡因≈137.3mg（推算）· 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 137.3, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 290, carbsG: 46, proteinG: 4.5, fatG: 9), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/31/dedbf3234ca24cb9ba3c42dd17891d35.png"),
        LuckinDrink(id: "lk.matchacheese", name: "抹茶奶酪拿铁", category: "其他非咖啡类", keywords: ["抹茶奶酪拿铁"], portion: "咖啡因≈80mg（推算）· 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 80, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 250, carbsG: 34, proteinG: 9, fatG: 8), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/8939050e89864b0cad44065159ca49ab.png"),
        LuckinDrink(id: "lk.americano", name: "标准美式", category: "美式类", keywords: ["标准美式", "美式", "美式咖啡"], portion: "咖啡因164.3mg · 1 大杯 / 450ml", caffeineMg: 164.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 11, carbsG: 2, proteinG: 0.5, fatG: 0), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/2d5a0991ec494824bce275529e6082e2.png"),
        LuckinDrink(id: "lk.strongamericano", name: "加浓美式", category: "美式类", keywords: ["加浓美式"], portion: "咖啡因198.9mg · 1 大杯 / 450ml", caffeineMg: 198.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 14, carbsG: 2.5, proteinG: 0.5, fatG: 0), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/80e338ad3e6f49728043565ccb700416.png"),
        LuckinDrink(id: "lk.orangec", name: "橙C美式", category: "美式类", keywords: ["橙C美式"], portion: "咖啡因158.4mg · 1 大杯 / 450ml", caffeineMg: 158.4, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 122, carbsG: 27, proteinG: 1.2, fatG: 0.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8083ab7c6e9f4a2d8556abf6864d6c36.png"),
        LuckinDrink(id: "lk.butteramericano", name: "小黄油美式", category: "美式类", keywords: ["小黄油美式"], portion: "咖啡因212mg · 1 大杯 / 450ml", caffeineMg: 212, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 173, carbsG: 19, proteinG: 4, fatG: 8.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/3e15b9d9c55d468882b839a7684d6b28.png"),
        LuckinDrink(id: "lk.applec", name: "苹果C美式", category: "美式类", keywords: ["苹果C美式"], portion: "咖啡因136.4mg · 1 大杯 / 450ml", caffeineMg: 136.4, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 131, carbsG: 30, proteinG: 1, fatG: 0.3), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/53a095b960a04fd1b92bbe1ae45bd9ea.png"),
        LuckinDrink(id: "lk.pomeloc", name: "柚C美式", category: "美式类", keywords: ["柚C美式"], portion: "咖啡因184.1mg · 1 大杯 / 450ml", caffeineMg: 184.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 137, carbsG: 31, proteinG: 1, fatG: 0.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/13/2ec3e5a946a4432e8fdf88ec07d8ac95.png"),
        LuckinDrink(id: "lk.darkchocolate", name: "全冰黑巧美式", category: "美式类", keywords: ["全冰黑巧美式"], portion: "咖啡因35.9mg · 1 杯 / 16oz", caffeineMg: 35.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 132, carbsG: 19, proteinG: 3, fatG: 5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/4f760d6b14cd4ccfb6b4881e94211a00.png"),
        LuckinDrink(id: "lk.lemonsparkling", name: "柠C气泡美式", category: "美式类", keywords: ["柠C气泡美式"], portion: "咖啡因134mg · 1 大杯 / 450ml", caffeineMg: 134, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 83, carbsG: 19, proteinG: 0.5, fatG: 0.2), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/cc620ca04fa3425f83a5a1f6d46b1b77.png"),
        LuckinDrink(id: "lk.freshlemonc", name: "鲜切柠C美式", category: "美式类", keywords: ["鲜切柠C美式"], portion: "咖啡因116mg · 1 超大杯 / 596ml", caffeineMg: 116, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 112, carbsG: 26, proteinG: 0.6, fatG: 0.2), waterMl: 596, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/13/b98a6caa54b74773bb955b583c01c5d5.png"),
        LuckinDrink(id: "lk.appleicetea", name: "苹果C冰茶", category: "冰茶冰奶类", keywords: ["苹果C冰茶"], portion: "咖啡因19.2mg · 1 大杯 / 450ml", caffeineMg: 19.2, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 130, carbsG: 31, proteinG: 0.5, fatG: 0), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8e7270373e1e4f268a1df64a4b75582d.png"),
        LuckinDrink(id: "lk.grapeicetea", name: "葡萄冰茶", category: "冰茶冰奶类", keywords: ["葡萄冰茶"], portion: "咖啡因17.9mg · 1 大杯 / 450ml", caffeineMg: 17.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 115, carbsG: 27, proteinG: 0.5, fatG: 0), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/e4e461eddeaf40838c351fc4cb9a8ccf.png"),
        LuckinDrink(id: "lk.helloapplejasmine", name: "Hello 苹果茉莉", category: "冰茶冰奶类", keywords: ["Hello 苹果茉莉", "苹果茉莉"], portion: "咖啡因41.5mg · 1 杯 / 16oz", caffeineMg: 41.5, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 173, carbsG: 40, proteinG: 1, fatG: 0.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/df199354f80a4bea943d81f117c619f0.png"),
        LuckinDrink(id: "lk.lightjasmine", name: "鲜萃轻轻茉莉", category: "轻乳茶类", keywords: ["鲜萃轻轻茉莉"], portion: "咖啡因83.3mg · 1 大杯 / 450ml", caffeineMg: 83.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 95, carbsG: 16, proteinG: 3, fatG: 1.8), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/c26adbd1664148979a965aa7b48ecc34.png"),
        LuckinDrink(id: "lk.kale", name: "羽衣轻体果蔬茶", category: "果蔬茶类", keywords: ["羽衣轻体果蔬茶"], portion: "咖啡因≈31mg（推算，含茉莉花茶汤）· 1 大杯 / 450ml", caffeineMg: 31, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 94, carbsG: 20, proteinG: 1.5, fatG: 0.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/705abce21ae340f4af2b9990eca08cf5.png"),
        LuckinDrink(id: "lk.geshadream", name: "瑰夏之梦", category: "冷萃类", keywords: ["瑰夏之梦"], portion: "咖啡因78.8mg · 1 杯 / 16oz", caffeineMg: 78.8, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 161, carbsG: 23, proteinG: 2, fatG: 5.5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/c920c6961bab4ee78cf888b78efa6d10.png"),
        LuckinDrink(id: "lk.geishawhite", name: "瑰夏白冷萃", category: "冷萃类", keywords: ["瑰夏白冷萃"], portion: "咖啡因≈78.8mg（推算）· 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 78.8, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 120, carbsG: 15, proteinG: 3, fatG: 5), waterMl: 450, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/b60b1112a0cc492c88822ada9e3d078c.png"),
    ]

    /// 官网分类顺序（只保留当前有产品的分类）。
    static var categories: [String] {
        var seen: Set<String> = []
        return drinks.compactMap { drink in
            seen.insert(drink.category).inserted ? drink.category : nil
        }
    }

    /// 按分类分组，供列表展示；搜索时只保留命中的产品。
    /// 列出官网全部在售产品（含未公示咖啡因的），不再按咖啡因过滤。
    static func grouped(query: String = "") -> [LuckinDrinkGroup] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matched = drinks.filter { drink in
            guard !trimmed.isEmpty else { return true }
            return drink.name.lowercased().contains(trimmed)
                || drink.keywords.contains { $0.lowercased().contains(trimmed) }
        }
        return categories.compactMap { category in
            let items = matched.filter { $0.category == category }
            return items.isEmpty ? nil : LuckinDrinkGroup(category: category, drinks: items)
        }
    }

    /// 转成咖啡因打卡的一次快捷加量：只在点击时构造，不写入 UserDefaults，
    /// 因此不占用「设置 → 快捷按键」里可编辑的 6 个名额。
    static func quickAction(for drink: LuckinDrink) -> IntakeQuickAction {
        var nutrition = drink.nutrition
        nutrition.waterMl = drink.waterMl
        return IntakeQuickAction(
            id: "luckin-\(drink.id)",
            title: drink.name,
            amount: drink.caffeineMg,
            nutrition: nutrition
        )
    }
}
