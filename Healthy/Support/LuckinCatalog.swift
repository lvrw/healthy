import Foundation

/// 瑞幸咖啡产品营养库（2026-11-19 更新，依据用户提供的两张营养数据表 + 瑞幸官网公示图）。
/// 这是本地营养库「瑞幸咖啡」预置分组与咖啡因打卡「瑞幸咖啡」快捷入口的同一份数据源，
/// 两边都从这里派生，避免产品名 / 数值各写一份。
/// 数值口径：推荐点单配置下「每杯」值（默认大杯 / 冰 / 不另外加糖），16oz 与超大杯在 portion 标注。
/// 热量 / 咖啡因以营养数据表为准；图中标「—」但库里已有公示值的保留原值。
/// 碳水 / 蛋白质 / 脂肪未公示时为推算值；咖啡因未公示者 `caffeineEstimated = true`。
/// 图片使用瑞幸官网 CDN 产品图，未上新官网的同系列饮品按风格复用同类官方图。
///
/// 含水量口径（2026-11-20 修正）：`waterMl` 是**这杯实际含的水**，不再等于杯容量。
/// 旧口径直接写杯容量（拿铁 450ml 就记 450ml 水），把牛奶、椰乳、糖浆里的非水成分也算成水，
/// 导致一天喝两杯奶咖就能虚增近 900ml 饮水量。现按「成分配比 × 各成分含水率」折算，
/// 含水率取自公开食物成分数据：纯水 / 茶汤 / 黑咖啡 100%，全脂牛奶 87.5%
/// （牛乳水分 87.5 g/100 g），燕麦奶 88%，厚椰乳 85%（脂肪 7.5 + 碳水 6 + 蛋白 1.2 g/100 ml，
/// 其余为水），100% 果汁 88%，含糖碳酸饮料 93%（可口可乐 10.6 g 糖/100 ml），
/// 无糖碳酸 99%，糖浆约 30%，奶盖 / 奶油约 60%，冰淇淋约 60%。
/// 由此得到分类系数并对每杯取整到 5 ml：
/// - 标准拿铁 / 奶铁 / 奶咖 0.88：浓缩 60 + 牛奶 360 + 糖浆 30 → (60 + 315 + 9) / 450 ≈ 0.85，
///   按门店实际奶量（约 380 ml）折算取 0.88；
/// - 生椰拿铁 0.86（椰乳为基）、燕麦奶咖 0.88、泰奶 0.83（炼乳 + 糖浆）、
///   可可 / 黑巧 0.86、奶盖类 0.84、奶昔 / 含小料 0.84、冰沙 0.84、冰淇淋 0.60；
/// - 美式 / 黑咖 0.99、果味美式 0.95、气泡美式 0.96、果茶 0.95、纯茶 0.99、
///   含糖碳酸 0.93、无糖碳酸 0.99、纯牛奶 0.875、燕麦奶 0.88、豆浆 0.90、果汁 0.88。
/// 联动喝水、热量与咖啡因仍按各自口径独立记录，本次只改含水量，其它字段保持原值。
///
/// 2026-11-23 补入「乳酸菌美式」：2026-07 瑞幸 × 多邻国新品，已从官网当前 28 款在售列表下架，
/// 热量取官方新闻稿的大杯口径（108 kcal），咖啡因按同系列标准美式推算并标 `caffeineEstimated`，
/// 图片复用官网美式官方图；详细碳水 / 蛋白质 / 脂肪为按热量反推的估算值。
struct LuckinDrink: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    /// 官网分类名，用于快捷选择列表分组。
    var category: String
    var keywords: [String]
    /// 营养库里展示的份量说明（含咖啡因文本）。
    var portion: String
    /// 咖啡因 mg/杯；0 表示不含咖啡因或未公示。
    var caffeineMg: Double
    /// 咖啡因是否为推算值。
    var caffeineEstimated: Bool
    /// 官网公示的热量，其余宏量为推算值。
    var nutrition: IntakeNutrition
    /// 每杯含水量（ml），按成分配比折算；不等于杯容量，详见文件头口径说明。
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
        // MARK: - 拿铁类
        LuckinDrink(id: "lk.coconut", name: "生椰拿铁", category: "拿铁类", keywords: ["生椰拿铁"], portion: "咖啡因118.4mg · 1 大杯 / 450ml", caffeineMg: 118.4, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 179, carbsG: 7.4, proteinG: 0.7, fatG: 13.7), waterMl: 385, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/52155ea342784e5e92935467d921b24c.png"),
        LuckinDrink(id: "lk.jasmine", name: "茉莉花香拿铁", category: "拿铁类", keywords: ["茉莉花香拿铁"], portion: "咖啡因236mg · 1 大杯 / 450ml", caffeineMg: 236, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 76, carbsG: 10, proteinG: 4.5, fatG: 2), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/0de4a497f3ba47fab6239bac36840385.png"),
        LuckinDrink(id: "lk.latte", name: "拿铁", category: "拿铁类", keywords: ["拿铁", "瑞幸拿铁"], portion: "咖啡因98.6mg · 1 大杯 / 450ml", caffeineMg: 98.6, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 268, carbsG: 22, proteinG: 11, fatG: 14), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/81a3af83583a4752bf00a0e40df95e59.png"),
        LuckinDrink(id: "lk.coconut_double", name: "冰吸生椰拿铁", category: "拿铁类", keywords: ["冰吸生椰拿铁", "冰吸生椰"], portion: "咖啡因162.5mg · 1 大杯 / 450ml", caffeineMg: 162.5, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 196, carbsG: 15, proteinG: 3, fatG: 12), waterMl: 385, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/52155ea342784e5e92935467d921b24c.png"),
        LuckinDrink(id: "lk.butter", name: "小黄油拿铁", category: "拿铁类", keywords: ["小黄油拿铁"], portion: "咖啡因171.9mg · 1 大杯 / 450ml", caffeineMg: 171.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 250, carbsG: 20, proteinG: 9, fatG: 14), waterMl: 385, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/f061918c5d4c4688b0b84f477f74fd21.png"),
        LuckinDrink(id: "lk.coconut_triple", name: "生椰三重奏拿铁", category: "拿铁类", keywords: ["生椰三重奏拿铁", "生椰三重奏"], portion: "咖啡因147.6mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 147.6, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 470, carbsG: 45, proteinG: 10, fatG: 28), waterMl: 380, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/0ddfaeeba9d94a1583dfb8fafcb1e28f.png"),
        LuckinDrink(id: "lk.lightcoconut", name: "轻椰茉莉拿铁", category: "拿铁类", keywords: ["轻椰茉莉拿铁"], portion: "咖啡因179.1mg · 1 大杯 / 450ml", caffeineMg: 179.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 120, carbsG: 16, proteinG: 2, fatG: 5), waterMl: 390, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/0ddfaeeba9d94a1583dfb8fafcb1e28f.png"),
        LuckinDrink(id: "lk.velvet", name: "丝绒拿铁", category: "拿铁类", keywords: ["丝绒拿铁"], portion: "咖啡因≈98.6mg · 1 大杯 / 450ml", caffeineMg: 98.6, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 376, carbsG: 34, proteinG: 12, fatG: 20), waterMl: 390, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/26f156673e8f4eb6ab9fb2c0c6b68102.jpeg"),
        LuckinDrink(id: "lk.velvet_dragon", name: "钱塘龙井拿铁", category: "拿铁类", keywords: ["钱塘龙井拿铁", "钱塘龙井"], portion: "咖啡因228.2mg · 1 大杯 / 450ml", caffeineMg: 228.2, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 105, carbsG: 16, proteinG: 4, fatG: 3), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/0de4a497f3ba47fab6239bac36840385.png"),
        LuckinDrink(id: "lk.saltcoconut", name: "海盐焦糖拿铁", category: "拿铁类", keywords: ["海盐焦糖拿铁", "海盐焦糖"], portion: "咖啡因152mg · 1 大杯 / 450ml", caffeineMg: 152, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 206, carbsG: 27, proteinG: 4, fatG: 9), waterMl: 390, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/f061918c5d4c4688b0b84f477f74fd21.png"),
        LuckinDrink(id: "lk.green_sand", name: "绿沙沙拿铁", category: "拿铁类", keywords: ["绿沙沙拿铁", "绿沙沙"], portion: "咖啡因28.8mg · 1 大杯 / 450ml", caffeineMg: 28.8, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 183, carbsG: 22, proteinG: 6, fatG: 8), waterMl: 385, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/8939050e89864b0cad44065159ca49ab.png"),
        LuckinDrink(id: "lk.osmanthus", name: "桂花米酿拿铁", category: "拿铁类", keywords: ["桂花米酿拿铁", "桂花米酿"], portion: "咖啡因135.9mg · 1 大杯 / 450ml", caffeineMg: 135.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 197, carbsG: 28, proteinG: 6, fatG: 7), waterMl: 390, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/6cd25d89b5cf40a69f38f93b2e58c776.png"),
        LuckinDrink(id: "lk.thaiyuanyeung", name: "泰奶鸳鸯拿铁", category: "拿铁类", keywords: ["泰奶鸳鸯拿铁"], portion: "咖啡因143.1mg · 1 大杯 / 450ml", caffeineMg: 143.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 300, carbsG: 42, proteinG: 6.5, fatG: 11), waterMl: 375, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/17/7ecb19d3d2db4cf2baec8eb041689138.png"),
        LuckinDrink(id: "lk.minicheese", name: "小奶酪拿铁", category: "拿铁类", keywords: ["小奶酪拿铁"], portion: "咖啡因≈98.6mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 98.6, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 260, carbsG: 24, proteinG: 9, fatG: 14), waterMl: 380, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/6cd25d89b5cf40a69f38f93b2e58c776.png"),
        LuckinDrink(id: "lk.empress_yuechang", name: "皇后限定苹果拿铁", category: "拿铁类", keywords: ["皇后限定苹果拿铁", "皇后苹果拿铁"], portion: "咖啡因97.2mg · 1 大杯 / 450ml", caffeineMg: 97.2, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 202, carbsG: 33, proteinG: 5, fatG: 6), waterMl: 390, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/53a095b960a04fd1b92bbe1ae45bd9ea.png"),
        LuckinDrink(id: "lk.cocoalatte", name: "99%可可黑巧拿铁", category: "拿铁类", keywords: ["99%可可黑巧拿铁", "可可黑巧拿铁", "黑巧拿铁"], portion: "咖啡因≈98.6mg · 1 大杯 / 450ml · 热量来自能量补充表；咖啡因按同系列推算", caffeineMg: 98.6, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 393, carbsG: 44, proteinG: 9, fatG: 18), waterMl: 385, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/4f760d6b14cd4ccfb6b4881e94211a00.png"),
        // MARK: - 其他非咖啡类
        LuckinDrink(id: "lk.mangopomelo", name: "生椰杨枝甘露", category: "其他非咖啡类", keywords: ["生椰杨枝甘露"], portion: "咖啡因14.9mg · 1 大杯 / 450ml", caffeineMg: 14.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 176, carbsG: 28, proteinG: 2, fatG: 5.5), waterMl: 380, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/11/18b64d3f2900454490805d02fa40e398.png"),
        LuckinDrink(id: "lk.avocado_kale", name: "牛油果羽衣酸奶昔（仔仔杯）", category: "其他非咖啡类", keywords: ["牛油果羽衣酸奶昔", "仔仔杯", "羽衣酸奶昔"], portion: "咖啡因0mg（<0.2mg） · 1 大杯 / 350ml", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 284, carbsG: 32, proteinG: 7, fatG: 14), waterMl: 295, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/705abce21ae340f4af2b9990eca08cf5.png"),
        LuckinDrink(id: "lk.classicthai", name: "经典泰奶", category: "其他非咖啡类", keywords: ["经典泰奶"], portion: "咖啡因137.3mg · 1 大杯 / 450ml", caffeineMg: 137.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 330, carbsG: 52, proteinG: 4.4, fatG: 10), waterMl: 375, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/17/8796417fbf2241279bf56124441b50ca.png"),
        LuckinDrink(id: "lk.saltedthai", name: "咸法酪泰奶", category: "其他非咖啡类", keywords: ["咸法酪泰奶"], portion: "咖啡因≈137.3mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 137.3, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 290, carbsG: 46, proteinG: 4.5, fatG: 9), waterMl: 375, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/31/dedbf3234ca24cb9ba3c42dd17891d35.png"),
        LuckinDrink(id: "lk.matchacheese", name: "抹茶奶酪拿铁", category: "其他非咖啡类", keywords: ["抹茶奶酪拿铁"], portion: "咖啡因≈80mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 80, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 250, carbsG: 34, proteinG: 9, fatG: 8), waterMl: 380, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/8939050e89864b0cad44065159ca49ab.png"),
        LuckinDrink(id: "lk.cocoapearl", name: "99%可可珍珠牛乳", category: "其他非咖啡类", keywords: ["99%可可珍珠牛乳", "可可珍珠牛乳", "珍珠牛乳"], portion: "咖啡因0mg · 1 大杯 / 450ml · 不含咖啡因；热量来自能量补充表", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 310, carbsG: 46, proteinG: 8, fatG: 11), waterMl: 380, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/26f156673e8f4eb6ab9fb2c0c6b68102.jpeg"),
        LuckinDrink(id: "lk.cocoapure", name: "99%可可黑巧", category: "其他非咖啡类", keywords: ["99%可可黑巧", "可可黑巧"], portion: "咖啡因0mg · 1 大杯 / 450ml · 不含咖啡因；热量来自能量补充表", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 397, carbsG: 48, proteinG: 8, fatG: 20), waterMl: 385, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/4f760d6b14cd4ccfb6b4881e94211a00.png"),
        // MARK: - 美式类
        LuckinDrink(id: "lk.americano", name: "标准美式", category: "美式类", keywords: ["标准美式", "美式", "美式咖啡", "冰美式", "热美式"], portion: "咖啡因164.3mg · 1 大杯 / 450ml", caffeineMg: 164.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 11, carbsG: 2, proteinG: 0.5, fatG: 0), waterMl: 445, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/2d5a0991ec494824bce275529e6082e2.png"),
        LuckinDrink(id: "lk.lactobacillus", name: "乳酸菌美式", category: "美式类", keywords: ["乳酸菌美式", "乳酸菌", "多邻国乳酸菌美式"], portion: "咖啡因≈164.3mg · 热量108kcal（官方新闻稿） · 1 大杯 / 450ml", caffeineMg: 164.3, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 108, carbsG: 25, proteinG: 1, fatG: 0.5), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/2d5a0991ec494824bce275529e6082e2.png"),
        LuckinDrink(id: "lk.strongamericano", name: "加浓美式", category: "美式类", keywords: ["加浓美式"], portion: "咖啡因198.9mg · 1 大杯 / 450ml", caffeineMg: 198.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 14, carbsG: 2.5, proteinG: 0.5, fatG: 0), waterMl: 445, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/80e338ad3e6f49728043565ccb700416.png"),
        LuckinDrink(id: "lk.orangec", name: "橙C美式", category: "美式类", keywords: ["橙C美式"], portion: "咖啡因158.4mg · 1 大杯 / 450ml", caffeineMg: 158.4, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 128, carbsG: 29, proteinG: 1.2, fatG: 0.5), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8083ab7c6e9f4a2d8556abf6864d6c36.png"),
        LuckinDrink(id: "lk.butteramericano", name: "小黄油美式", category: "美式类", keywords: ["小黄油美式"], portion: "咖啡因212mg · 1 大杯 / 450ml", caffeineMg: 212, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 173, carbsG: 19, proteinG: 4, fatG: 8.5), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/3e15b9d9c55d468882b839a7684d6b28.png"),
        LuckinDrink(id: "lk.applec", name: "苹果C美式", category: "美式类", keywords: ["苹果C美式"], portion: "咖啡因171.9mg · 1 大杯 / 450ml", caffeineMg: 171.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 133, carbsG: 30, proteinG: 1, fatG: 0.3), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/53a095b960a04fd1b92bbe1ae45bd9ea.png"),
        LuckinDrink(id: "lk.pomeloc", name: "柚C美式", category: "美式类", keywords: ["柚C美式"], portion: "咖啡因184.1mg · 1 大杯 / 450ml", caffeineMg: 184.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 137, carbsG: 31, proteinG: 1, fatG: 0.5), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/13/2ec3e5a946a4432e8fdf88ec07d8ac95.png"),
        LuckinDrink(id: "lk.qingjuc", name: "小青桔C美式", category: "美式类", keywords: ["小青桔C美式", "青桔美式"], portion: "咖啡因154mg · 1 大杯 / 450ml", caffeineMg: 154, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 115, carbsG: 27, proteinG: 0.8, fatG: 0.2), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/cc620ca04fa3425f83a5a1f6d46b1b77.png"),
        LuckinDrink(id: "lk.freshblend", name: "缤纷C美式", category: "美式类", keywords: ["缤纷C美式"], portion: "咖啡因37.1mg · 1 大杯 / 450ml", caffeineMg: 37.1, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 100, carbsG: 24, proteinG: 0.8, fatG: 0.2), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8083ab7c6e9f4a2d8556abf6864d6c36.png"),
        LuckinDrink(id: "lk.watermeloncoconut", name: "大西瓜生椰冷萃", category: "美式类", keywords: ["大西瓜生椰冷萃", "西瓜生椰冷萃"], portion: "咖啡因21.7mg · 1 大杯 / 450ml", caffeineMg: 21.7, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 102, carbsG: 18, proteinG: 1.5, fatG: 3), waterMl: 405, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/e4e461eddeaf40838c351fc4cb9a8ccf.png"),
        LuckinDrink(id: "lk.darkchocolate", name: "全冰黑巧美式", category: "美式类", keywords: ["全冰黑巧美式"], portion: "咖啡因21.2mg · 1 大杯 / 450ml", caffeineMg: 21.2, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 113, carbsG: 17, proteinG: 2, fatG: 4.5), waterMl: 420, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/4f760d6b14cd4ccfb6b4881e94211a00.png"),
        LuckinDrink(id: "lk.lemonsparkling", name: "柠C气泡美式（鲜果版）", category: "美式类", keywords: ["柠C气泡美式", "鲜果版", "柠C气泡美式（鲜果版）"], portion: "咖啡因29.8mg · 1 大杯 / 450ml", caffeineMg: 29.8, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 77, carbsG: 18, proteinG: 0.5, fatG: 0.2), waterMl: 430, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/cc620ca04fa3425f83a5a1f6d46b1b77.png"),
        LuckinDrink(id: "lk.passionfruitc", name: "百香果C美式", category: "美式类", keywords: ["百香果C美式"], portion: "咖啡因0mg · 1 大杯 / 450ml · 咖啡因/热量未公示", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8083ab7c6e9f4a2d8556abf6864d6c36.png"),
        LuckinDrink(id: "lk.cheesecake", name: "全冰奶酪美式", category: "美式类", keywords: ["全冰奶酪美式", "奶酪美式"], portion: "咖啡因0mg · 1 大杯 / 450ml · 咖啡因/热量未公示", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0), waterMl: 415, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/80e338ad3e6f49728043565ccb700416.png"),
        LuckinDrink(id: "lk.empressapplec", name: "皇后限定苹果C美式", category: "美式类", keywords: ["皇后限定苹果C美式", "苹果C美式"], portion: "咖啡因136.3mg · 1 大杯 / 450ml", caffeineMg: 136.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 131, carbsG: 31, proteinG: 1, fatG: 0.3), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/53a095b960a04fd1b92bbe1ae45bd9ea.png"),
        LuckinDrink(id: "lk.freshlemonc", name: "鲜切柠C美式", category: "美式类", keywords: ["鲜切柠C美式"], portion: "咖啡因116mg · 1 大杯 / 596ml · 超大杯", caffeineMg: 116, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 112, carbsG: 26, proteinG: 0.6, fatG: 0.2), waterMl: 570, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/13/b98a6caa54b74773bb955b583c01c5d5.png"),
        // MARK: - 冰茶冰奶类
        LuckinDrink(id: "lk.appleicetea", name: "苹果C冰茶", category: "冰茶冰奶类", keywords: ["苹果C冰茶"], portion: "咖啡因19.2mg · 1 大杯 / 450ml", caffeineMg: 19.2, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 117, carbsG: 28, proteinG: 0.5, fatG: 0), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8e7270373e1e4f268a1df64a4b75582d.png"),
        LuckinDrink(id: "lk.grapeicetea", name: "葡萄冰茶", category: "冰茶冰奶类", keywords: ["葡萄冰茶"], portion: "咖啡因17.9mg · 1 大杯 / 450ml", caffeineMg: 17.9, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 115, carbsG: 27, proteinG: 0.5, fatG: 0), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/e4e461eddeaf40838c351fc4cb9a8ccf.png"),
        LuckinDrink(id: "lk.helloapplejasmine", name: "Hello 苹果茉莉", category: "冰茶冰奶类", keywords: ["Hello 苹果茉莉", "苹果茉莉"], portion: "咖啡因36mg · 1 大杯 / 450ml", caffeineMg: 36, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 192, carbsG: 44, proteinG: 1, fatG: 0.5), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/df199354f80a4bea943d81f117c619f0.png"),
        LuckinDrink(id: "lk.qingjujasmine", name: "小青桔茉莉冰奶", category: "冰茶冰奶类", keywords: ["小青桔茉莉冰奶", "青桔茉莉"], portion: "咖啡因30mg · 1 大杯 / 450ml", caffeineMg: 30, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 148, carbsG: 22, proteinG: 4, fatG: 5), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/df199354f80a4bea943d81f117c619f0.png"),
        LuckinDrink(id: "lk.lycheejasmine", name: "荔枝茉莉冰奶", category: "冰茶冰奶类", keywords: ["荔枝茉莉冰奶", "荔枝冰奶"], portion: "咖啡因7.37mg · 1 大杯 / 450ml", caffeineMg: 7.37, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 125, carbsG: 20, proteinG: 4, fatG: 4.5), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/c26adbd1664148979a965aa7b48ecc34.png"),
        LuckinDrink(id: "lk.flamenco", name: "弗朗明戈·跳跳冰茶", category: "冰茶冰奶类", keywords: ["弗朗明戈·跳跳冰茶", "跳跳冰茶"], portion: "咖啡因4.47mg · 1 大杯 / 450ml", caffeineMg: 4.47, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 128, carbsG: 30, proteinG: 0.5, fatG: 0), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/e4e461eddeaf40838c351fc4cb9a8ccf.png"),
        LuckinDrink(id: "lk.passionfruiticetea", name: "百香果C冰茶", category: "冰茶冰奶类", keywords: ["百香果C冰茶"], portion: "咖啡因0mg · 1 大杯 / 450ml · 咖啡因/热量未公示", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8e7270373e1e4f268a1df64a4b75582d.png"),
        LuckinDrink(id: "lk.watermelonjasmine", name: "大西瓜茉莉冰奶", category: "冰茶冰奶类", keywords: ["大西瓜茉莉冰奶", "西瓜茉莉冰奶"], portion: "咖啡因0mg · 1 大杯 / 450ml · 咖啡因/热量未公示", caffeineMg: 0, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/e4e461eddeaf40838c351fc4cb9a8ccf.png"),
        LuckinDrink(id: "lk.empressappleicetea", name: "皇后限定苹果C冰茶", category: "冰茶冰奶类", keywords: ["皇后限定苹果C冰茶"], portion: "咖啡因19.17mg · 1 大杯 / 450ml", caffeineMg: 19.17, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 130, carbsG: 31, proteinG: 0.5, fatG: 0), waterMl: 425, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8e7270373e1e4f268a1df64a4b75582d.png"),
        // MARK: - 轻乳茶类
        LuckinDrink(id: "lk.lightjasmine", name: "鲜萃轻轻茉莉", category: "轻乳茶类", keywords: ["鲜萃轻轻茉莉"], portion: "咖啡因83.3mg · 1 大杯 / 450ml", caffeineMg: 83.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 100, carbsG: 16, proteinG: 3, fatG: 1.8), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/c26adbd1664148979a965aa7b48ecc34.png"),
        LuckinDrink(id: "lk.osmanthusoolong", name: "桂花米酿乌龙", category: "轻乳茶类", keywords: ["桂花米酿乌龙", "米酿乌龙"], portion: "咖啡因78.3mg · 1 大杯 / 450ml", caffeineMg: 78.3, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 219, carbsG: 32, proteinG: 5, fatG: 7), waterMl: 405, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/c26adbd1664148979a965aa7b48ecc34.png"),
        // MARK: - 果蔬茶类
        LuckinDrink(id: "lk.kale", name: "羽衣轻体果蔬茶", category: "果蔬茶类", keywords: ["羽衣轻体果蔬茶"], portion: "咖啡因≈31mg · 1 大杯 / 450ml · 含茉莉花茶汤，咖啡因为推算值", caffeineMg: 31, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 94, carbsG: 20, proteinG: 1.5, fatG: 0.5), waterMl: 420, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/705abce21ae340f4af2b9990eca08cf5.png"),
        // MARK: - 冷萃类
        LuckinDrink(id: "lk.geshadream", name: "瑰夏之梦", category: "冷萃类", keywords: ["瑰夏之梦", "浪漫之梦"], portion: "咖啡因78.75mg · 1 大杯 / 450ml", caffeineMg: 78.75, caffeineEstimated: false, nutrition: IntakeNutrition(energyKcal: 161, carbsG: 23, proteinG: 2, fatG: 5.5), waterMl: 405, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/c920c6961bab4ee78cf888b78efa6d10.png"),
        LuckinDrink(id: "lk.geishawhite", name: "瑰夏白冷萃", category: "冷萃类", keywords: ["瑰夏白冷萃"], portion: "咖啡因≈78mg · 1 大杯 / 450ml · 热量/营养为推算值", caffeineMg: 78, caffeineEstimated: true, nutrition: IntakeNutrition(energyKcal: 120, carbsG: 15, proteinG: 3, fatG: 5), waterMl: 395, imageURL: "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/b60b1112a0cc492c88822ada9e3d078c.png"),
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
    ///
    /// 搜索按空白拆成多个词做 AND 匹配（兼容中文全角空格与大小写）：
    /// 「生椰 拿铁」「乳酸菌 美式」都能命中对应产品，避免整串包含判断漏掉分词输入。
    static func grouped(query: String = "") -> [LuckinDrinkGroup] {
        let tokens = query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let matched = drinks.filter { drink in
            guard !tokens.isEmpty else { return true }
            let fields = ([drink.name] + drink.keywords).map { $0.lowercased() }
            return tokens.allSatisfy { token in
                fields.contains { $0.contains(token) }
            }
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
