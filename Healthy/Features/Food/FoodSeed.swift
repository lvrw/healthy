import Foundation
import SwiftData

/// 首次启动预置内置食物分组（麦当劳全菜单 + 瑞幸咖啡）。
/// 麦当劳数据来源：麦当劳中国官方营养计算器（https://www.mcdonalds.com.cn/nutrition_calculator，
/// 2026-11 抓取），能量千焦按 ÷4.184 四舍五入折算千卡，分量取官网「分量」列；
/// 营养字段完全对齐苹果健康 App「营养摄入」的 40 项指标（见 NutritionField）：
/// 能量、三大营养素、脂肪细分、膳食纤维 / 糖 / 胆固醇、水、咖啡因、酒精摄入量、
/// 全部矿物质与维生素。官网 / 模型未公示或无法判断的指标一律留 0，不臆造数值。
/// 当前仅「评分 / 身体年龄」使用碳水、蛋白质、脂肪、水、咖啡因 5 项，其余指标只做留档与展示。
/// 幂等：分组仅缺失时补齐；麦当劳与瑞幸菜单变动频繁，各自用数据版本号控制，
/// 版本升级时按 ID 重建已有分组内的预置条目（前缀 mcd. / lk.），用户自行新增的条目不受影响。
enum FoodSeed {
    private static let flagKey = "didSeedBuiltinFoodGroups"
    private static let luckinGroupID = "group.luckin.coffee"
    /// 瑞幸预置数据版本；官网菜单变化时 +1，让已安装过的 App 也能同步到新数据。
    private static let luckinVersionKey = "builtinLuckinSeedVersion"
    private static let luckinVersion = 5 // 2026-11-18：全量补碳蛋脂推算值 + 6 款补推算热量
    /// 麦当劳预置数据版本；官网菜单变化时 +1，让已安装过的 App 也能同步到新数据。
    private static let mcdVersionKey = "builtinMcdSeedVersion"
    private static let mcdVersion = 2 // 2026-11-18：官网 McCafé 列表核对补录浓缩咖啡 / 鲜萃咖啡

    static func ensureBuiltinGroups(in context: ModelContext) {
        let defaults = UserDefaults.standard
        let luckinOutdated = defaults.integer(forKey: luckinVersionKey) < luckinVersion
        let mcdOutdated = defaults.integer(forKey: mcdVersionKey) < mcdVersion
        defer { defaults.set(true, forKey: flagKey) }

        let existingIDs = Set(((try? context.fetch(FetchDescriptor<FoodGroup>())) ?? []).map(\.id))
        for group in builtinGroups where group.id != luckinGroupID && !existingIDs.contains(group.id) {
            let fg = FoodGroup(id: group.id, name: group.name, sortOrder: group.sortOrder, isBuiltin: group.isBuiltin)
            context.insert(fg)
            insert(items: group.items, groupID: group.id, into: context)
        }

        // 麦当劳：首次启动或数据版本升级时，按官网当前菜单重建已有分组的预置条目。
        // 新分组由上面的「缺失补齐」逻辑创建；这里只刷新已存在的分组，
        // 只删除本模块生成的 mcd. 前缀条目，用户在各分组里自行新增的条目保持不动。
        if mcdOutdated {
            let existingFoods = (try? context.fetch(FetchDescriptor<CustomFood>())) ?? []
            for group in builtinGroups where group.id.hasPrefix("group.mcd.") && existingIDs.contains(group.id) {
                for food in existingFoods where food.groupID == group.id && food.id.hasPrefix("mcd.") {
                    context.delete(food)
                }
                insert(items: group.items, groupID: group.id, into: context)
            }
            defaults.set(mcdVersion, forKey: mcdVersionKey)
        }

        // 瑞幸：首次启动或数据版本升级时，按官网当前菜单重建预置条目。
        // 只删除本模块生成的 lk. 前缀条目，用户在该分组里自行新增的条目保持不动。
        if luckinOutdated, let luckin = builtinGroups.first(where: { $0.id == luckinGroupID }) {
            if !existingIDs.contains(luckinGroupID) {
            let fg = FoodGroup(id: luckin.id, name: luckin.name, sortOrder: luckin.sortOrder, isBuiltin: luckin.isBuiltin)
            context.insert(fg)
            }
            let existingFoods = (try? context.fetch(FetchDescriptor<CustomFood>())) ?? []
            for food in existingFoods where food.groupID == luckinGroupID && food.id.hasPrefix("lk.") {
                context.delete(food)
            }
            insert(items: luckin.items, groupID: luckin.id, into: context)
            defaults.set(luckinVersion, forKey: luckinVersionKey)
        }
        try? context.save()
    }

    private static func insert(items: [ItemSeed], groupID: String, into context: ModelContext) {
        for item in items {
            let food = CustomFood(name: item.name, keywords: item.keywords, portion: item.portion,
                                  nutrition: item.nutrition, groupID: groupID, imageURL: item.imageURL)
            food.id = item.id
            context.insert(food)
        }
    }

    private struct ItemSeed {
        let id: String
        let name: String
        let keywords: [String]
        let portion: String
        let nutrition: IntakeNutrition
        /// 官网产品图片 URL，由 FoodSeed.image(for:) 根据名字模糊匹配得到。
        var imageURL: String? { FoodSeed.image(for: name) }
    }

    /// 官网菜单图片名 → URL 映射。FoodSeed 里的产品名常带尺寸后缀
    /// （如「薯条（小）」「优品豆浆（大）」「麦乐鸡（5块）」），官网图只显示主名
    /// （「薯条」「优品豆浆」「麦乐鸡 (5块)」），由 image(for:) 做精确+去后缀模糊匹配。
    private static let imageByName: [String: String] = [
        // MARK: 早餐
        "猪柳麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091558332871.png",
        "猪柳蛋麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091558498724.png",
        "双层猪柳蛋麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/12/202212191104077687.png",
        "火腿扒麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091559476910.png",
        "大脆鸡扒麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091600076790.png",
        "原味板烧鸡腿麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/09/202209301037275168.png",
        "双层原味板烧鸡腿麦满分": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/09/202209301037584746.png",
        "原味板烧鸡腿炒双蛋堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/12/202212191104292706.png",
        "猪柳炒双蛋堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091601375124.png",
        "火腿扒早安营养卷": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208021616493001.png",
        "图林根香肠早安营养卷": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208021618177760.png",
        "皮蛋鸡肉粥": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/05/202005061021247170.png",
        "雪菜脆笋鸡肉粥": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/05/202005061023475981.png",
        "脆薯饼": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091604513345.png",
        "脆香油条": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091605077842.png",
        "德式图林根香肠": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2021/04/202104191521441185.png",
        "优品豆浆": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/12/202412031411454215.png",

        // MARK: 汉堡
        "巨无霸": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081011205699.png",
        "汉堡包": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081011488477.png",
        "麦辣鸡腿汉堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/04/202504091717393584.png",
        "板烧鸡腿堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/10/202410121642022710.png",
        "麦香鸡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081013011355.png",
        "麦香鱼": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081013175111.png",
        "吉士汉堡包": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081013284833.png",
        "双层吉士汉堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/05/202505191553352680.png",
        "不素之霸双层牛堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/07/202407021437072297.png",
        "双层深海鳕鱼堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208111413054231.png",
        "培根安格斯厚牛堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081022028042.png",
        "芝士安格斯厚牛堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208081022182900.png",
        "培根蔬萃双层牛堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/09/202209261029176483.png",
        "酥酥多笋卷": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/12/202412031221494776.png",

        // MARK: 小食
        "薯条": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091547349086.png",
        "脆脆薯条": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/11/202411281827123412.png",
        "麦辣鸡翅": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/04/202504091714077263.png",
        "薄皮焦香V翅": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/03/202503261723251059.png",
        "麦乐鸡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091547543048.png",
        "麦乐鸡 (5块)": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091547543048.png",
        "那么大鸡排（椒盐风味）": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091551151077.png",
        "玉米杯": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091548118821.png",
        "苹果片": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091552098343.png",

        // MARK: 甜品
        "圆筒冰淇淋": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/05/202005270949182813.png",
        "奥利奥麦旋风": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/03/202003191447419769.png",
        "草莓麦旋风": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/03/202003191447495324.png",
        "朱古力新地": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/03/202003191510126381.png",
        "草莓新地": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/03/202003191449258974.png",
        "迷你朱古力新地": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/05/202505112256468336.png",
        "迷你草莓新地": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/05/202505112259357730.png",
        "香芋派": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091556569394.png",
        "菠萝派": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091557147058.png",

        // MARK: 饮品
        "可口可乐": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091541242793.png",
        "无糖可口可乐": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091542266222.png",
        "阳光柠檬红茶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/12/202412111430239925.png",
        "雪碧": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091543354438.png",
        "怡泉+C": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/05/202505112325105835.png",
        "阳光橙麦炫酷": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/03/202003191452518874.png",
        "美汁源100%苹果汁": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/11/202411281822478466.png",
        "100%苹果汁": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/05/202505081052503366.png",
        "纯牛奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/12/202412031439237239.png",
        "纯牛奶（盒装）": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/12/202412031439237239.png",
        "锡兰红茶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091546249996.png",
        "纯悦": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/11/202411281844518339.png",
        "美汁源100%苹果汁 (小)": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/05/202505081053474066.png",

        // MARK: McCafé
        "冰奶铁": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292204543004.png",
        "热奶铁": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292205408283.png",
        "冰燕麦奶铁": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292206117637.png",
        "热燕麦奶铁": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292206368008.png",
        "冰美式": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292208383944.png",
        "热美式": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292209017033.png",
        "冰焦糖玛奇朵": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292209215242.png",
        "热焦糖玛奇朵": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292209422511.png",
        "卡布奇诺": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292210057378.png",
        "浓缩咖啡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2020/11/202011152311386312.png",
        "冰浓浓燕麦黑巧": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292214326960.png",
        "热浓浓燕麦黑巧": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208301011268722.png",
        "冰浓浓抹茶牛奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292216395610.png",
        "热浓浓抹茶牛奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292216596791.png",
        "冰燕麦奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292214522529.png",
        "热燕麦奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292215082309.png",
        "鲜萃咖啡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2025/02/202502201050044696.png",
        "冰浓浓黑巧": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292217199815.png",
        "热浓浓黑巧": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292217366580.png",
        "冰牛奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292218348675.png",
        "热牛奶": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292218491274.png",
        "浓浓抹茶雪冰": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292219089745.png",
        "浓浓黑巧雪冰": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208292219557802.png",
        "抹茶阿芙佳朵": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/07/202407251729244473.png",
        "咖啡阿芙佳朵": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2024/07/202407251730361207.png",

        // MARK: 开心乐园餐
        "儿童鱼排堡": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2019/09/201909241723061060.png",
        "麦乐鸡（4块）": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091607474918.png",
        "薯条（迷你）": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2019/09/201909241658187803.png",
        "玉米杯 (小)": "https://officiaweb-afd.mcdonalds.com.cn/public/upload/attachment/2022/08/202208091608181706.png",

        // MARK: 瑞幸咖啡（官网 lkcoffee.com）
        "生椰拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/52155ea342784e5e92935467d921b24c.png",
        "茉莉花香拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/0de4a497f3ba47fab6239bac36840385.png",
        "拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/81a3af83583a4752bf00a0e40df95e59.png",
        "小黄油拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/f061918c5d4c4688b0b84f477f74fd21.png",
        "轻椰茉莉拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/0ddfaeeba9d94a1583dfb8fafcb1e28f.png",
        "丝绒拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/08/26f156673e8f4eb6ab9fb2c0c6b68102.jpeg",
        "泰奶鸳鸯拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/17/7ecb19d3d2db4cf2baec8eb041689138.png",
        "小奶酪拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/6cd25d89b5cf40a69f38f93b2e58c776.png",
        "标准美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/2d5a0991ec494824bce275529e6082e2.png",
        "加浓美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/05/26/80e338ad3e6f49728043565ccb700416.png",
        "橙C美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/8083ab7c6e9f4a2d8556abf6864d6c36.png",
        "小黄油美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/3e15b9d9c55d468882b839a7684d6b28.png",
        "苹果C美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/53a095b960a04fd1b92bbe1ae45bd9ea.png",
        "柚C美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/13/2ec3e5a946a4432e8fdf88ec07d8ac95.png",
        "全冰黑巧美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/07/12/4f760d6b14cd4ccfb6b4881e94211a00.png",
        "柠C气泡美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/11/cc620ca04fa3425f83a5a1f6d46b1b77.png",
        "鲜切柠C美式": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/11/13/b98a6caa54b74773bb955b583c01c5d5.png",
        "生椰杨枝甘露": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/06/11/18b64d3f2900454490805d02fa40e398.png",
        "经典泰奶": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/17/8796417fbf2241279bf56124441b50ca.png",
        "咸法酪泰奶": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/08/31/dedbf3234ca24cb9ba3c42dd17891d35.png",
        "抹茶奶酪拿铁": "https://img.luckincoffeecdn.com/luckymediaadmin/2026/09/07/8939050e89864b0cad44065159ca49ab.png",
    ]

    /// 由产品名推断官网图片 URL。依次：精确匹配 → 去尺寸后缀（「（小）」「（大）」「（中）」「（迷你）」「（5块）」等）→ 去尾部英文括号 → 截断到首个中文括号。
    private static func image(for name: String) -> String? {
        if let url = imageByName[name] { return url }
        // 归一化：英文括号 → 中文，空格保留
        var variants: [String] = [name]
        // 去中文尺寸后缀 （小）（大）（中）（迷你）（5块）
        let cnSuffixes = ["（小）", "（中）", "（大）", "（迷你）", "（标准）"]
        var stripped = name
        for s in cnSuffixes { stripped = stripped.replacingOccurrences(of: s, with: "") }
        if stripped != name { variants.append(stripped) }
        // 去英文括号尾
        if let r = name.range(of: "\\(.*\\)$", options: .regularExpression) {
            variants.append(String(name[name.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces))
        }
        // 去中文括号尾（尺寸/块数）
        if let r = stripped.range(of: "（[^）]*）$", options: .regularExpression) {
            variants.append(String(stripped[stripped.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces))
        }
        // 去所有中文括号里的内容
        var allParens = name
        while let r = allParens.range(of: "（[^）]*）", options: .regularExpression) {
            allParens.replaceSubrange(r, with: "")
        }
        variants.append(allParens.trimmingCharacters(in: .whitespaces))
        // 去所有英文括号里的内容
        var allEnParens = name
        while let r = allEnParens.range(of: "\\([^)]*\\)", options: .regularExpression) {
            allEnParens.replaceSubrange(r, with: "")
        }
        variants.append(allEnParens.trimmingCharacters(in: .whitespaces))

        for v in variants {
            if let url = imageByName[v] { return url }
        }
        return nil
    }

    private struct GroupSeed {
        let id: String
        let name: String
        let sortOrder: Int
        let items: [ItemSeed]
        /// 是否为系统维护的品牌分组（麦当劳 / 瑞幸等）。true 时 UI 上只读，不允许增删食物 / 重命名 / 删除分组。
        let isBuiltin: Bool
    }

    private static let builtinGroups: [GroupSeed] = [
        GroupSeed(id: "group.mcd.breakfast", name: "麦当劳早餐", sortOrder: 0, items: [
            ItemSeed(id: "mcd.15.43", name: "猪柳麦满分", keywords: ["猪柳麦满分", "猪柳", "麦满分"], portion: "1 个 / 107g", nutrition: IntakeNutrition(energyKcal: 308, carbsG: 24, proteinG: 16, fatG: 16, sodiumMg: 781)),
            ItemSeed(id: "mcd.17.53", name: "猪柳蛋麦满分", keywords: ["猪柳蛋麦满分", "猪柳蛋", "麦满分"], portion: "1 个 / 155g", nutrition: IntakeNutrition(energyKcal: 387, carbsG: 25, proteinG: 23, fatG: 21, sodiumMg: 846)),
            ItemSeed(id: "mcd.321.402", name: "双层猪柳蛋麦满分", keywords: ["双层猪柳蛋麦满分", "双层猪柳蛋"], portion: "1 个 / 193g", nutrition: IntakeNutrition(energyKcal: 513, carbsG: 26, proteinG: 29, fatG: 32, sodiumMg: 1210)),
            ItemSeed(id: "mcd.20.46", name: "火腿扒麦满分", keywords: ["火腿扒麦满分", "火腿扒", "麦满分"], portion: "1 个 / 116g", nutrition: IntakeNutrition(energyKcal: 261, carbsG: 24, proteinG: 14, fatG: 12, sodiumMg: 608)),
            ItemSeed(id: "mcd.39.54", name: "大脆鸡扒麦满分", keywords: ["大脆鸡扒麦满分", "鸡扒麦满分", "大脆鸡扒", "麦满分"], portion: "1 个 / 136g", nutrition: IntakeNutrition(energyKcal: 361, carbsG: 35, proteinG: 16, fatG: 17, sodiumMg: 804)),
            ItemSeed(id: "mcd.40.55", name: "原味板烧鸡腿麦满分", keywords: ["原味板烧鸡腿麦满分", "板烧鸡腿", "麦满分"], portion: "1 个 / 121g", nutrition: IntakeNutrition(energyKcal: 246, carbsG: 25, proteinG: 15, fatG: 9, sodiumMg: 611)),
            ItemSeed(id: "mcd.41.56", name: "双层原味板烧鸡腿麦满分", keywords: ["双层原味板烧鸡腿麦满分", "双层板烧"], portion: "1 个 / 172g", nutrition: IntakeNutrition(energyKcal: 355, carbsG: 27, proteinG: 23, fatG: 17, sodiumMg: 984)),
            ItemSeed(id: "mcd.320.401", name: "原味板烧鸡腿炒双蛋堡", keywords: ["原味板烧鸡腿炒双蛋堡", "板烧炒双蛋", "炒双蛋堡"], portion: "1 个 / 201g", nutrition: IntakeNutrition(energyKcal: 419, carbsG: 30, proteinG: 27, fatG: 21, sodiumMg: 715)),
            ItemSeed(id: "mcd.172.198", name: "猪柳炒双蛋堡", keywords: ["猪柳炒双蛋堡", "猪柳炒双蛋", "炒双蛋堡"], portion: "1 个 / 188g", nutrition: IntakeNutrition(energyKcal: 437, carbsG: 29, proteinG: 25, fatG: 24, sodiumMg: 705)),
            ItemSeed(id: "mcd.209.220", name: "火腿扒早安营养卷", keywords: ["火腿扒早安营养卷", "火腿扒营养卷", "早安营养卷"], portion: "1 个 / 184g", nutrition: IntakeNutrition(energyKcal: 444, carbsG: 39, proteinG: 16, fatG: 24, sodiumMg: 1065)),
            ItemSeed(id: "mcd.221.222", name: "图林根香肠早安营养卷", keywords: ["图林根香肠早安营养卷", "图林根营养卷", "早安营养卷"], portion: "1 个 / 174g", nutrition: IntakeNutrition(energyKcal: 425, carbsG: 38, proteinG: 14, fatG: 23, sodiumMg: 977)),
            ItemSeed(id: "mcd.168.194", name: "皮蛋鸡肉粥", keywords: ["皮蛋鸡肉粥", "皮蛋粥"], portion: "1 份 / 72g", nutrition: IntakeNutrition(energyKcal: 133, carbsG: 20, proteinG: 6, fatG: 3, sodiumMg: 611)),
            ItemSeed(id: "mcd.169.195", name: "雪菜脆笋鸡肉粥", keywords: ["雪菜脆笋鸡肉粥", "雪菜脆笋粥", "脆笋粥"], portion: "1 份 / 62g", nutrition: IntakeNutrition(energyKcal: 120, carbsG: 22, proteinG: 4, fatG: 2, sodiumMg: 552)),
            ItemSeed(id: "mcd.107.38", name: "脆薯饼", keywords: ["脆薯饼", "薯饼"], portion: "1 个 / 54g", nutrition: IntakeNutrition(energyKcal: 146, carbsG: 14, proteinG: 1, fatG: 9, sodiumMg: 311)),
            ItemSeed(id: "mcd.108.39", name: "脆香油条", keywords: ["脆香油条", "油条"], portion: "1 个 / 49g", nutrition: IntakeNutrition(energyKcal: 202, carbsG: 19, proteinG: 5, fatG: 12, sodiumMg: 230)),
            ItemSeed(id: "mcd.220.221", name: "德式图林根香肠", keywords: ["德式图林根香肠", "图林根香肠", "德式香肠"], portion: "1 个 / 40g", nutrition: IntakeNutrition(energyKcal: 87, carbsG: 2, proteinG: 5, fatG: 6, sodiumMg: 293)),
            ItemSeed(id: "mcd.250.257", name: "优品豆浆（小）", keywords: ["优品豆浆", "豆浆", "豆奶"], portion: "1 杯（小） / 218ml", nutrition: IntakeNutrition(energyKcal: 151, carbsG: 25, proteinG: 6, fatG: 3, sodiumMg: 32)),
            ItemSeed(id: "mcd.250.258", name: "优品豆浆（大）", keywords: ["优品豆浆", "豆浆", "豆奶"], portion: "1 杯（大） / 291ml", nutrition: IntakeNutrition(energyKcal: 202, carbsG: 33, proteinG: 8, fatG: 4, sodiumMg: 43)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.burger", name: "麦当劳汉堡和卷", sortOrder: 1, items: [
            ItemSeed(id: "mcd.49.28", name: "巨无霸", keywords: ["巨无霸"], portion: "1 个 / 220g", nutrition: IntakeNutrition(energyKcal: 513, carbsG: 42, proteinG: 27, fatG: 26, sodiumMg: 961)),
            ItemSeed(id: "mcd.42.1", name: "汉堡包", keywords: ["汉堡包", "汉堡"], portion: "1 个 / 104g", nutrition: IntakeNutrition(energyKcal: 248, carbsG: 29, proteinG: 13, fatG: 8, sodiumMg: 492)),
            ItemSeed(id: "mcd.47.26", name: "麦辣鸡腿汉堡", keywords: ["麦辣鸡腿汉堡", "麦辣鸡腿", "辣鸡腿堡"], portion: "1 个 / 208g", nutrition: IntakeNutrition(energyKcal: 485, carbsG: 42, proteinG: 24, fatG: 24, sodiumMg: 1208)),
            ItemSeed(id: "mcd.48.29", name: "板烧鸡腿堡", keywords: ["板烧鸡腿堡", "板烧"], portion: "1 个 / 192g", nutrition: IntakeNutrition(energyKcal: 391, carbsG: 35, proteinG: 23, fatG: 17, sodiumMg: 1041)),
            ItemSeed(id: "mcd.45.24", name: "麦香鸡", keywords: ["麦香鸡"], portion: "1 个 / 163g", nutrition: IntakeNutrition(energyKcal: 370, carbsG: 39, proteinG: 15, fatG: 17, sodiumMg: 731)),
            ItemSeed(id: "mcd.46.25", name: "麦香鱼", keywords: ["麦香鱼"], portion: "1 个 / 140g", nutrition: IntakeNutrition(energyKcal: 325, carbsG: 35, proteinG: 16, fatG: 13, sodiumMg: 556)),
            ItemSeed(id: "mcd.43.10", name: "吉士汉堡包", keywords: ["吉士汉堡包", "吉士汉堡"], portion: "1 个 / 118g", nutrition: IntakeNutrition(energyKcal: 294, carbsG: 30, proteinG: 16, fatG: 12, sodiumMg: 673)),
            ItemSeed(id: "mcd.44.23", name: "双层吉士汉堡", keywords: ["双层吉士汉堡", "双层吉士"], portion: "1 个 / 168g", nutrition: IntakeNutrition(energyKcal: 429, carbsG: 31, proteinG: 27, fatG: 22, sodiumMg: 1017)),
            ItemSeed(id: "mcd.145.173", name: "不素之霸双层牛堡", keywords: ["不素之霸双层牛堡", "不素之霸"], portion: "1 个 / 177g", nutrition: IntakeNutrition(energyKcal: 493, carbsG: 34, proteinG: 28, fatG: 27, sodiumMg: 1012)),
            ItemSeed(id: "mcd.146.174", name: "双层深海鳕鱼堡", keywords: ["双层深海鳕鱼堡", "鳕鱼堡", "深海鳕鱼"], portion: "1 个 / 209g", nutrition: IntakeNutrition(energyKcal: 485, carbsG: 46, proteinG: 28, fatG: 21, sodiumMg: 917)),
            ItemSeed(id: "mcd.161.188", name: "培根安格斯厚牛堡", keywords: ["培根安格斯厚牛堡", "培根安格斯", "安格斯厚牛堡"], portion: "1 个 / 216g", nutrition: IntakeNutrition(energyKcal: 707, carbsG: 43, proteinG: 34, fatG: 44, sodiumMg: 1037)),
            ItemSeed(id: "mcd.162.191", name: "芝士安格斯厚牛堡", keywords: ["芝士安格斯厚牛堡", "芝士安格斯", "安格斯厚牛堡"], portion: "1 个 / 218g", nutrition: IntakeNutrition(energyKcal: 696, carbsG: 43, proteinG: 32, fatG: 44, sodiumMg: 897)),
            ItemSeed(id: "mcd.50.27", name: "培根蔬萃双层牛堡", keywords: ["培根蔬萃双层牛堡", "培根蔬萃"], portion: "1 个 / 184g", nutrition: IntakeNutrition(energyKcal: 442, carbsG: 34, proteinG: 24, fatG: 23, sodiumMg: 728)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.snacks", name: "麦当劳小食", sortOrder: 2, items: [
            ItemSeed(id: "mcd.21.422", name: "薯条（迷你）", keywords: ["薯条"], portion: "1 份（迷你） / 40g", nutrition: IntakeNutrition(energyKcal: 106, carbsG: 14, proteinG: 2, fatG: 4, sodiumMg: 61)),
            ItemSeed(id: "mcd.21.11", name: "薯条（小）", keywords: ["薯条"], portion: "1 份（小） / 79g", nutrition: IntakeNutrition(energyKcal: 210, carbsG: 28, proteinG: 3, fatG: 9, sodiumMg: 120)),
            ItemSeed(id: "mcd.21.12", name: "薯条（中）", keywords: ["薯条"], portion: "1 份（中） / 109g", nutrition: IntakeNutrition(energyKcal: 289, carbsG: 38, proteinG: 4, fatG: 12, sodiumMg: 165)),
            ItemSeed(id: "mcd.21.14", name: "薯条（大）", keywords: ["薯条"], portion: "1 份（大） / 143g", nutrition: IntakeNutrition(energyKcal: 379, carbsG: 50, proteinG: 6, fatG: 16, sodiumMg: 216)),
            ItemSeed(id: "mcd.326.410", name: "脆脆薯条（中）", keywords: ["脆脆薯条"], portion: "1 份（中） / 103g", nutrition: IntakeNutrition(energyKcal: 279, carbsG: 32, proteinG: 4, fatG: 14, sodiumMg: 540)),
            ItemSeed(id: "mcd.26.19", name: "麦辣鸡翅", keywords: ["麦辣鸡翅", "鸡翅"], portion: "2 块 / 73g", nutrition: IntakeNutrition(energyKcal: 224, carbsG: 9, proteinG: 13, fatG: 15, sodiumMg: 537)),
            ItemSeed(id: "mcd.329.413", name: "薄皮焦香V翅", keywords: ["薄皮焦香V翅", "V翅", "焦香V翅"], portion: "2 块 / 85g", nutrition: IntakeNutrition(energyKcal: 192, carbsG: 6, proteinG: 17, fatG: 11, sodiumMg: 594)),
            ItemSeed(id: "mcd.23.15", name: "麦乐鸡（5块）", keywords: ["麦乐鸡", "鸡块"], portion: "5 块 / 82g", nutrition: IntakeNutrition(energyKcal: 213, carbsG: 13, proteinG: 12, fatG: 12, sodiumMg: 422)),
            ItemSeed(id: "mcd.101.22", name: "那么大鸡排（椒盐风味）", keywords: ["那么大鸡排", "鸡排"], portion: "1 个 / 154g", nutrition: IntakeNutrition(energyKcal: 385, carbsG: 24, proteinG: 24, fatG: 21, sodiumMg: 996)),
            ItemSeed(id: "mcd.24.16", name: "玉米杯（小）", keywords: ["玉米杯", "玉米"], portion: "1 份（小） / 72g", nutrition: IntakeNutrition(energyKcal: 53, carbsG: 7, proteinG: 2, fatG: 1, sodiumMg: 1)),
            ItemSeed(id: "mcd.24.17", name: "玉米杯（大）", keywords: ["玉米杯", "玉米"], portion: "1 份（大） / 118g", nutrition: IntakeNutrition(energyKcal: 87, carbsG: 12, proteinG: 4, fatG: 1, sodiumMg: 2)),
            ItemSeed(id: "mcd.136.161", name: "苹果片", keywords: ["苹果片"], portion: "1 份 / 66g", nutrition: IntakeNutrition(energyKcal: 32, carbsG: 7, proteinG: 0, fatG: 0, sodiumMg: 0)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.dessert", name: "麦当劳甜品", sortOrder: 3, items: [
            ItemSeed(id: "mcd.22.31", name: "圆筒冰淇淋", keywords: ["圆筒冰淇淋", "圆筒", "冰淇淋", "甜筒"], portion: "1 个 / 63g", nutrition: IntakeNutrition(energyKcal: 93, carbsG: 14, proteinG: 2, fatG: 3, sodiumMg: 36)),
            ItemSeed(id: "mcd.34.34", name: "奥利奥麦旋风", keywords: ["奥利奥麦旋风", "麦旋风"], portion: "1 个 / 159g", nutrition: IntakeNutrition(energyKcal: 266, carbsG: 40, proteinG: 5, fatG: 9, sodiumMg: 116)),
            ItemSeed(id: "mcd.35.35", name: "草莓麦旋风", keywords: ["草莓麦旋风", "麦旋风"], portion: "1 个 / 173g", nutrition: IntakeNutrition(energyKcal: 295, carbsG: 47, proteinG: 6, fatG: 9, sodiumMg: 122)),
            ItemSeed(id: "mcd.32.32", name: "朱古力新地", keywords: ["朱古力新地", "新地"], portion: "1 个 / 156g", nutrition: IntakeNutrition(energyKcal: 282, carbsG: 44, proteinG: 5, fatG: 9, sodiumMg: 126)),
            ItemSeed(id: "mcd.33.33", name: "草莓新地", keywords: ["草莓新地", "新地"], portion: "1 个 / 156g", nutrition: IntakeNutrition(energyKcal: 245, carbsG: 43, proteinG: 4, fatG: 6, sodiumMg: 84)),
            ItemSeed(id: "mcd.340.423", name: "迷你朱古力新地", keywords: ["迷你朱古力新地"], portion: "1 份 / 78g", nutrition: IntakeNutrition(energyKcal: 140, carbsG: 22, proteinG: 3, fatG: 4, sodiumMg: 63)),
            ItemSeed(id: "mcd.341.424", name: "迷你草莓新地", keywords: ["迷你草莓新地"], portion: "1 份 / 78g", nutrition: IntakeNutrition(energyKcal: 122, carbsG: 21, proteinG: 2, fatG: 3, sodiumMg: 42)),
            ItemSeed(id: "mcd.36.36", name: "香芋派", keywords: ["香芋派"], portion: "1 个 / 84g", nutrition: IntakeNutrition(energyKcal: 232, carbsG: 28, proteinG: 2, fatG: 12, sodiumMg: 159)),
            ItemSeed(id: "mcd.37.37", name: "菠萝派", keywords: ["菠萝派"], portion: "1 个 / 84g", nutrition: IntakeNutrition(energyKcal: 221, carbsG: 27, proteinG: 2, fatG: 11, sodiumMg: 147)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.beverage", name: "麦当劳饮品", sortOrder: 4, items: [
            ItemSeed(id: "mcd.51.72", name: "可口可乐（小）", keywords: ["可口可乐", "可乐"], portion: "1 杯（小） / 326ml", nutrition: IntakeNutrition(energyKcal: 107, carbsG: 26, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.51.73", name: "可口可乐（中）", keywords: ["可口可乐", "可乐"], portion: "1 杯（中） / 443ml", nutrition: IntakeNutrition(energyKcal: 147, carbsG: 36, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.51.74", name: "可口可乐（大）", keywords: ["可口可乐", "可乐"], portion: "1 杯（大） / 642ml", nutrition: IntakeNutrition(energyKcal: 224, carbsG: 55, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.53.82", name: "无糖可口可乐（小）", keywords: ["无糖可口可乐", "无糖可乐", "零度可乐"], portion: "1 杯（小） / 326ml", nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0, sodiumMg: 25)),
            ItemSeed(id: "mcd.53.83", name: "无糖可口可乐（中）", keywords: ["无糖可口可乐", "无糖可乐", "零度可乐"], portion: "1 杯（中） / 443ml", nutrition: IntakeNutrition(energyKcal: 0, carbsG: 1, proteinG: 0, fatG: 0, sodiumMg: 35)),
            ItemSeed(id: "mcd.53.84", name: "无糖可口可乐（大）", keywords: ["无糖可口可乐", "无糖可乐", "零度可乐"], portion: "1 杯（大） / 642ml", nutrition: IntakeNutrition(energyKcal: 0, carbsG: 1, proteinG: 0, fatG: 0, sodiumMg: 53)),
            ItemSeed(id: "mcd.102.78", name: "阳光柠檬红茶（小）", keywords: ["阳光柠檬红茶", "柠檬红茶"], portion: "1 杯（小） / 249ml", nutrition: IntakeNutrition(energyKcal: 85, carbsG: 21, proteinG: 0, fatG: 0, sodiumMg: 12)),
            ItemSeed(id: "mcd.102.79", name: "阳光柠檬红茶（中）", keywords: ["阳光柠檬红茶", "柠檬红茶"], portion: "1 杯（中） / 244ml", nutrition: IntakeNutrition(energyKcal: 117, carbsG: 29, proteinG: 0, fatG: 0, sodiumMg: 17)),
            ItemSeed(id: "mcd.102.80", name: "阳光柠檬红茶（大）", keywords: ["阳光柠檬红茶", "柠檬红茶"], portion: "1 杯（大） / 523ml", nutrition: IntakeNutrition(energyKcal: 178, carbsG: 43, proteinG: 0, fatG: 0, sodiumMg: 25)),
            ItemSeed(id: "mcd.52.85", name: "雪碧（小）", keywords: ["雪碧"], portion: "1 杯（小） / 326ml", nutrition: IntakeNutrition(energyKcal: 76, carbsG: 19, proteinG: 0, fatG: 0, sodiumMg: 21)),
            ItemSeed(id: "mcd.52.86", name: "雪碧（中）", keywords: ["雪碧"], portion: "1 杯（中） / 443ml", nutrition: IntakeNutrition(energyKcal: 105, carbsG: 26, proteinG: 0, fatG: 0, sodiumMg: 29)),
            ItemSeed(id: "mcd.52.87", name: "雪碧（大）", keywords: ["雪碧"], portion: "1 杯（大） / 642ml", nutrition: IntakeNutrition(energyKcal: 160, carbsG: 39, proteinG: 0, fatG: 0, sodiumMg: 45)),
            ItemSeed(id: "mcd.344.427", name: "怡泉+C（中）", keywords: ["怡泉+C", "怡泉"], portion: "1 杯（中） / 443ml", nutrition: IntakeNutrition(energyKcal: 110, carbsG: 27, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.344.428", name: "怡泉+C（大）", keywords: ["怡泉+C", "怡泉"], portion: "1 杯（大） / 642ml", nutrition: IntakeNutrition(energyKcal: 168, carbsG: 41, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.66.160", name: "阳光橙麦炫酷", keywords: ["阳光橙麦炫酷", "麦炫酷", "阳光橙"], portion: "1 杯 / 486ml", nutrition: IntakeNutrition(energyKcal: 228, carbsG: 50, proteinG: 1, fatG: 2, sodiumMg: 77)),
            ItemSeed(id: "mcd.248.243", name: "美汁源黄金橙橙（中）", keywords: ["黄金橙橙", "美汁源", "橙汁"], portion: "1 杯（中） / 443ml", nutrition: IntakeNutrition(energyKcal: 165, carbsG: 41, proteinG: 0, fatG: 0, sodiumMg: 53)),
            ItemSeed(id: "mcd.111.88", name: "100%苹果汁", keywords: ["100%苹果汁", "苹果汁"], portion: "1 盒 / 200ml", nutrition: IntakeNutrition(energyKcal: 88, carbsG: 21, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.62.90", name: "优品豆浆（小）", keywords: ["优品豆浆", "豆浆", "豆奶"], portion: "1 杯（小） / 218ml", nutrition: IntakeNutrition(energyKcal: 151, carbsG: 25, proteinG: 6, fatG: 3, sodiumMg: 32)),
            ItemSeed(id: "mcd.62.91", name: "优品豆浆（大）", keywords: ["优品豆浆", "豆浆", "豆奶"], portion: "1 杯（大） / 291ml", nutrition: IntakeNutrition(energyKcal: 202, carbsG: 33, proteinG: 8, fatG: 4, sodiumMg: 43)),
            ItemSeed(id: "mcd.61.178", name: "纯牛奶（盒装）", keywords: ["纯牛奶", "牛奶"], portion: "1 盒 / 200ml", nutrition: IntakeNutrition(energyKcal: 129, carbsG: 10, proteinG: 7, fatG: 7, sodiumMg: 73)),
            ItemSeed(id: "mcd.57.93", name: "锡兰红茶", keywords: ["锡兰红茶", "红茶"], portion: "1 杯 / 274ml", nutrition: IntakeNutrition(energyKcal: 2, carbsG: 0, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.63.81", name: "纯悦", keywords: ["纯悦", "矿泉水", "水"], portion: "1 瓶 / 550ml", nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0, sodiumMg: 0, waterMl: 550)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.mccafe", name: "麦当劳麦咖啡", sortOrder: 5, items: [
            ItemSeed(id: "mcd.287.329", name: "冰奶铁（小）", keywords: ["冰奶铁", "奶铁", "拿铁"], portion: "1 杯（小） / 215ml", nutrition: IntakeNutrition(energyKcal: 86, carbsG: 8, proteinG: 5, fatG: 4, sodiumMg: 44)),
            ItemSeed(id: "mcd.287.330", name: "冰奶铁（中）", keywords: ["冰奶铁", "奶铁", "拿铁"], portion: "1 杯（中） / 340ml", nutrition: IntakeNutrition(energyKcal: 148, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 77)),
            ItemSeed(id: "mcd.287.331", name: "冰奶铁（大）", keywords: ["冰奶铁", "奶铁", "拿铁"], portion: "1 杯（大） / 380ml", nutrition: IntakeNutrition(energyKcal: 162, carbsG: 15, proteinG: 9, fatG: 7, sodiumMg: 85)),
            ItemSeed(id: "mcd.288.332", name: "热奶铁（小）", keywords: ["热奶铁", "奶铁", "拿铁"], portion: "1 杯（小） / 215ml", nutrition: IntakeNutrition(energyKcal: 134, carbsG: 12, proteinG: 8, fatG: 6, sodiumMg: 72)),
            ItemSeed(id: "mcd.288.333", name: "热奶铁（中）", keywords: ["热奶铁", "奶铁", "拿铁"], portion: "1 杯（中） / 300ml", nutrition: IntakeNutrition(energyKcal: 186, carbsG: 17, proteinG: 11, fatG: 8, sodiumMg: 99)),
            ItemSeed(id: "mcd.288.334", name: "热奶铁（大）", keywords: ["热奶铁", "奶铁", "拿铁"], portion: "1 杯（大） / 415ml", nutrition: IntakeNutrition(energyKcal: 249, carbsG: 22, proteinG: 14, fatG: 11, sodiumMg: 134)),
            ItemSeed(id: "mcd.289.335", name: "冰燕麦奶铁（小）", keywords: ["冰燕麦奶铁", "燕麦奶铁", "燕麦拿铁"], portion: "1 杯（小） / 215ml", nutrition: IntakeNutrition(energyKcal: 77, carbsG: 10, proteinG: 2, fatG: 3, sodiumMg: 50)),
            ItemSeed(id: "mcd.289.336", name: "冰燕麦奶铁（中）", keywords: ["冰燕麦奶铁", "燕麦奶铁", "燕麦拿铁"], portion: "1 杯（中） / 340ml", nutrition: IntakeNutrition(energyKcal: 132, carbsG: 17, proteinG: 3, fatG: 5, sodiumMg: 87)),
            ItemSeed(id: "mcd.289.337", name: "冰燕麦奶铁（大）", keywords: ["冰燕麦奶铁", "燕麦奶铁", "燕麦拿铁"], portion: "1 杯（大） / 380ml", nutrition: IntakeNutrition(energyKcal: 145, carbsG: 19, proteinG: 4, fatG: 5, sodiumMg: 96)),
            ItemSeed(id: "mcd.290.338", name: "热燕麦奶铁（小）", keywords: ["热燕麦奶铁", "燕麦奶铁", "燕麦拿铁"], portion: "1 杯（小） / 215ml", nutrition: IntakeNutrition(energyKcal: 120, carbsG: 16, proteinG: 3, fatG: 5, sodiumMg: 81)),
            ItemSeed(id: "mcd.290.339", name: "热燕麦奶铁（中）", keywords: ["热燕麦奶铁", "燕麦奶铁", "燕麦拿铁"], portion: "1 杯（中） / 300ml", nutrition: IntakeNutrition(energyKcal: 167, carbsG: 22, proteinG: 4, fatG: 6, sodiumMg: 112)),
            ItemSeed(id: "mcd.290.340", name: "热燕麦奶铁（大）", keywords: ["热燕麦奶铁", "燕麦奶铁", "燕麦拿铁"], portion: "1 杯（大） / 415ml", nutrition: IntakeNutrition(energyKcal: 222, carbsG: 29, proteinG: 5, fatG: 8, sodiumMg: 152)),
            ItemSeed(id: "mcd.293.353", name: "冰美式（小）", keywords: ["冰美式", "美式", "黑咖啡"], portion: "1 杯（小） / 240ml", nutrition: IntakeNutrition(energyKcal: 10, carbsG: 1, proteinG: 1, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.293.354", name: "冰美式（中）", keywords: ["冰美式", "美式", "黑咖啡"], portion: "1 杯（中） / 330ml", nutrition: IntakeNutrition(energyKcal: 13, carbsG: 2, proteinG: 1, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.293.355", name: "冰美式（大）", keywords: ["冰美式", "美式", "黑咖啡"], portion: "1 杯（大） / 450ml", nutrition: IntakeNutrition(energyKcal: 14, carbsG: 2, proteinG: 1, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.294.356", name: "热美式（小）", keywords: ["热美式", "美式", "黑咖啡"], portion: "1 杯（小） / 240ml", nutrition: IntakeNutrition(energyKcal: 10, carbsG: 1, proteinG: 1, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.294.357", name: "热美式（中）", keywords: ["热美式", "美式", "黑咖啡"], portion: "1 杯（中） / 330ml", nutrition: IntakeNutrition(energyKcal: 13, carbsG: 2, proteinG: 1, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.294.358", name: "热美式（大）", keywords: ["热美式", "美式", "黑咖啡"], portion: "1 杯（大） / 450ml", nutrition: IntakeNutrition(energyKcal: 14, carbsG: 2, proteinG: 1, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.295.406", name: "冰焦糖玛奇朵（中）", keywords: ["冰焦糖玛奇朵", "焦糖玛奇朵", "玛奇朵"], portion: "1 杯（中） / 315ml", nutrition: IntakeNutrition(energyKcal: 148, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 77)),
            ItemSeed(id: "mcd.298.408", name: "热焦糖玛奇朵（中）", keywords: ["热焦糖玛奇朵", "焦糖玛奇朵", "玛奇朵"], portion: "1 杯（中） / 270ml", nutrition: IntakeNutrition(energyKcal: 167, carbsG: 15, proteinG: 9, fatG: 7, sodiumMg: 88)),
            ItemSeed(id: "mcd.299.359", name: "卡布奇诺（中）", keywords: ["卡布奇诺"], portion: "1 杯（中） / 270ml", nutrition: IntakeNutrition(energyKcal: 167, carbsG: 15, proteinG: 9, fatG: 7, sodiumMg: 88)),
            ItemSeed(id: "mcd.299.360", name: "卡布奇诺（大）", keywords: ["卡布奇诺"], portion: "1 杯（大） / 375ml", nutrition: IntakeNutrition(energyKcal: 223, carbsG: 20, proteinG: 13, fatG: 10, sodiumMg: 120)),
            ItemSeed(id: "mcd.303.367", name: "冰浓浓燕麦黑巧（中）", keywords: ["冰浓浓燕麦黑巧", "燕麦黑巧"], portion: "1 杯（中） / 285ml", nutrition: IntakeNutrition(energyKcal: 120, carbsG: 16, proteinG: 2, fatG: 5, sodiumMg: 87)),
            ItemSeed(id: "mcd.303.368", name: "冰浓浓燕麦黑巧（大）", keywords: ["冰浓浓燕麦黑巧", "燕麦黑巧"], portion: "1 杯（大） / 306ml", nutrition: IntakeNutrition(energyKcal: 131, carbsG: 17, proteinG: 3, fatG: 5, sodiumMg: 95)),
            ItemSeed(id: "mcd.314.372", name: "热浓浓燕麦黑巧（中）", keywords: ["热浓浓燕麦黑巧", "燕麦黑巧"], portion: "1 杯（中） / 275ml", nutrition: IntakeNutrition(energyKcal: 157, carbsG: 21, proteinG: 3, fatG: 6, sodiumMg: 114)),
            ItemSeed(id: "mcd.314.373", name: "热浓浓燕麦黑巧（大）", keywords: ["热浓浓燕麦黑巧", "燕麦黑巧"], portion: "1 杯（大） / 375ml", nutrition: IntakeNutrition(energyKcal: 213, carbsG: 28, proteinG: 4, fatG: 8, sodiumMg: 156)),
            ItemSeed(id: "mcd.306.378", name: "冰浓浓抹茶牛奶（中）", keywords: ["冰浓浓抹茶牛奶", "抹茶牛奶"], portion: "1 杯（中） / 311ml", nutrition: IntakeNutrition(energyKcal: 196, carbsG: 25, proteinG: 8, fatG: 6, sodiumMg: 80)),
            ItemSeed(id: "mcd.306.379", name: "冰浓浓抹茶牛奶（大）", keywords: ["冰浓浓抹茶牛奶", "抹茶牛奶"], portion: "1 杯（大） / 344ml", nutrition: IntakeNutrition(energyKcal: 240, carbsG: 33, proteinG: 9, fatG: 7, sodiumMg: 89)),
            ItemSeed(id: "mcd.307.380", name: "热浓浓抹茶牛奶（中）", keywords: ["热浓浓抹茶牛奶", "抹茶牛奶"], portion: "1 杯（中） / 301ml", nutrition: IntakeNutrition(energyKcal: 238, carbsG: 29, proteinG: 11, fatG: 8, sodiumMg: 104)),
            ItemSeed(id: "mcd.307.381", name: "热浓浓抹茶牛奶（大）", keywords: ["热浓浓抹茶牛奶", "抹茶牛奶"], portion: "1 杯（大） / 414ml", nutrition: IntakeNutrition(energyKcal: 333, carbsG: 41, proteinG: 14, fatG: 12, sodiumMg: 142)),
            ItemSeed(id: "mcd.304.369", name: "冰燕麦奶（小）", keywords: ["冰燕麦奶", "燕麦奶"], portion: "1 杯（小） / 230ml", nutrition: IntakeNutrition(energyKcal: 131, carbsG: 17, proteinG: 3, fatG: 5, sodiumMg: 95)),
            ItemSeed(id: "mcd.304.370", name: "冰燕麦奶（中）", keywords: ["冰燕麦奶", "燕麦奶"], portion: "1 杯（中） / 350ml", nutrition: IntakeNutrition(energyKcal: 199, carbsG: 26, proteinG: 4, fatG: 8, sodiumMg: 145)),
            ItemSeed(id: "mcd.304.371", name: "冰燕麦奶（大）", keywords: ["冰燕麦奶", "燕麦奶"], portion: "1 杯（大） / 420ml", nutrition: IntakeNutrition(energyKcal: 239, carbsG: 32, proteinG: 5, fatG: 9, sodiumMg: 174)),
            ItemSeed(id: "mcd.305.374", name: "热燕麦奶（小）", keywords: ["热燕麦奶", "燕麦奶"], portion: "1 杯（小） / 230ml", nutrition: IntakeNutrition(energyKcal: 131, carbsG: 17, proteinG: 3, fatG: 5, sodiumMg: 95)),
            ItemSeed(id: "mcd.305.375", name: "热燕麦奶（中）", keywords: ["热燕麦奶", "燕麦奶"], portion: "1 杯（中） / 275ml", nutrition: IntakeNutrition(energyKcal: 157, carbsG: 21, proteinG: 3, fatG: 6, sodiumMg: 114)),
            ItemSeed(id: "mcd.305.376", name: "热燕麦奶（大）", keywords: ["热燕麦奶", "燕麦奶"], portion: "1 杯（大） / 375ml", nutrition: IntakeNutrition(energyKcal: 213, carbsG: 28, proteinG: 4, fatG: 8, sodiumMg: 156)),
            ItemSeed(id: "mcd.308.382", name: "冰浓浓黑巧（中）", keywords: ["冰浓浓黑巧", "黑巧"], portion: "1 杯（中） / 285ml", nutrition: IntakeNutrition(energyKcal: 135, carbsG: 12, proteinG: 8, fatG: 6, sodiumMg: 77)),
            ItemSeed(id: "mcd.308.383", name: "冰浓浓黑巧（大）", keywords: ["冰浓浓黑巧", "黑巧"], portion: "1 杯（大） / 305ml", nutrition: IntakeNutrition(energyKcal: 147, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 84)),
            ItemSeed(id: "mcd.309.384", name: "热浓浓黑巧（中）", keywords: ["热浓浓黑巧", "黑巧"], portion: "1 杯（中） / 275ml", nutrition: IntakeNutrition(energyKcal: 176, carbsG: 15, proteinG: 10, fatG: 8, sodiumMg: 101)),
            ItemSeed(id: "mcd.309.385", name: "热浓浓黑巧（大）", keywords: ["热浓浓黑巧", "黑巧"], portion: "1 杯（大） / 375ml", nutrition: IntakeNutrition(energyKcal: 240, carbsG: 21, proteinG: 13, fatG: 11, sodiumMg: 137)),
            ItemSeed(id: "mcd.277.388", name: "冰牛奶（小）", keywords: ["冰牛奶", "牛奶"], portion: "1 杯（小） / 230ml", nutrition: IntakeNutrition(energyKcal: 147, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 84)),
            ItemSeed(id: "mcd.277.323", name: "冰牛奶（中）", keywords: ["冰牛奶", "牛奶"], portion: "1 杯（中） / 350ml", nutrition: IntakeNutrition(energyKcal: 224, carbsG: 19, proteinG: 13, fatG: 11, sodiumMg: 128)),
            ItemSeed(id: "mcd.277.324", name: "冰牛奶（大）", keywords: ["冰牛奶", "牛奶"], portion: "1 杯（大） / 420ml", nutrition: IntakeNutrition(energyKcal: 269, carbsG: 23, proteinG: 15, fatG: 13, sodiumMg: 154)),
            ItemSeed(id: "mcd.276.389", name: "热牛奶（小）", keywords: ["热牛奶", "牛奶"], portion: "1 杯（小） / 230ml", nutrition: IntakeNutrition(energyKcal: 147, carbsG: 13, proteinG: 8, fatG: 7, sodiumMg: 84)),
            ItemSeed(id: "mcd.276.321", name: "热牛奶（中）", keywords: ["热牛奶", "牛奶"], portion: "1 杯（中） / 275ml", nutrition: IntakeNutrition(energyKcal: 176, carbsG: 15, proteinG: 10, fatG: 8, sodiumMg: 101)),
            ItemSeed(id: "mcd.276.322", name: "热牛奶（大）", keywords: ["热牛奶", "牛奶"], portion: "1 杯（大） / 375ml", nutrition: IntakeNutrition(energyKcal: 240, carbsG: 21, proteinG: 13, fatG: 11, sodiumMg: 137)),
            ItemSeed(id: "mcd.271.391", name: "浓浓抹茶雪冰（中）", keywords: ["浓浓抹茶雪冰", "抹茶雪冰"], portion: "1 杯（中） / 276ml", nutrition: IntakeNutrition(energyKcal: 289, carbsG: 39, proteinG: 7, fatG: 11, sodiumMg: 181)),
            ItemSeed(id: "mcd.271.392", name: "浓浓抹茶雪冰（大）", keywords: ["浓浓抹茶雪冰", "抹茶雪冰"], portion: "1 杯（大） / 319ml", nutrition: IntakeNutrition(energyKcal: 339, carbsG: 48, proteinG: 8, fatG: 12, sodiumMg: 194)),
            ItemSeed(id: "mcd.269.315", name: "浓浓黑巧雪冰（中）", keywords: ["浓浓黑巧雪冰", "黑巧雪冰"], portion: "1 杯（中） / 290ml", nutrition: IntakeNutrition(energyKcal: 359, carbsG: 51, proteinG: 8, fatG: 12, sodiumMg: 224)),
            ItemSeed(id: "mcd.269.316", name: "浓浓黑巧雪冰（大）", keywords: ["浓浓黑巧雪冰", "黑巧雪冰"], portion: "1 杯（大） / 340ml", nutrition: IntakeNutrition(energyKcal: 444, carbsG: 65, proteinG: 11, fatG: 14, sodiumMg: 258)),
            ItemSeed(id: "mcd.312.398", name: "抹茶阿芙佳朵", keywords: ["抹茶阿芙佳朵", "阿芙佳朵"], portion: "1 杯 / 92ml", nutrition: IntakeNutrition(energyKcal: 147, carbsG: 23, proteinG: 3, fatG: 4, sodiumMg: 50)),
            ItemSeed(id: "mcd.313.399", name: "咖啡阿芙佳朵", keywords: ["咖啡阿芙佳朵", "阿芙佳朵"], portion: "1 杯 / 116ml", nutrition: IntakeNutrition(energyKcal: 139, carbsG: 21, proteinG: 4, fatG: 4, sodiumMg: 49)),
            // 2026-11-18 官网 McCafé 列表核对补录的两款；官网详情页未公示营养表，数值按公开口径推算：
            // 浓缩咖啡 = 单份 espresso（约 5kcal / 40ml）；鲜萃咖啡 = 滴滤黑咖（参考麦当劳美式 5kcal / 中杯 330ml）。
            ItemSeed(id: "mcd.287.900", name: "浓缩咖啡", keywords: ["浓缩咖啡", "浓缩", "espresso"], portion: "1 杯 / 40ml", nutrition: IntakeNutrition(energyKcal: 5, carbsG: 1, proteinG: 0.3, fatG: 0, sodiumMg: 5)),
            ItemSeed(id: "mcd.287.901", name: "鲜萃咖啡", keywords: ["鲜萃咖啡", "鲜萃", "滴滤", "黑咖啡"], portion: "1 杯（中） / 330ml", nutrition: IntakeNutrition(energyKcal: 5, carbsG: 1, proteinG: 0.5, fatG: 0, sodiumMg: 10)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.meal500", name: "麦当劳500大卡套餐", sortOrder: 6, items: [
            ItemSeed(id: "mcd.335.417", name: "苹板支撑Pro", keywords: ["苹板支撑Pro", "苹板"], portion: "1 份 / 773g", nutrition: IntakeNutrition(energyKcal: 476, carbsG: 50, proteinG: 25, fatG: 18, sodiumMg: 1077)),
            ItemSeed(id: "mcd.338.420", name: "牛气满满", keywords: ["牛气满满"], portion: "1 份 / 699g", nutrition: IntakeNutrition(energyKcal: 495, carbsG: 42, proteinG: 26, fatG: 24, sodiumMg: 764)),
        ], isBuiltin: true),
        GroupSeed(id: "group.mcd.happymeal", name: "麦当劳开心乐园餐", sortOrder: 7, items: [
            ItemSeed(id: "mcd.154.179", name: "儿童鱼排堡", keywords: ["儿童鱼排堡", "鱼排堡"], portion: "1 个 / 140g", nutrition: IntakeNutrition(energyKcal: 269, carbsG: 36, proteinG: 15, fatG: 6, sodiumMg: 442)),
            ItemSeed(id: "mcd.119.61", name: "汉堡包", keywords: ["汉堡包", "汉堡"], portion: "1 个 / 104g", nutrition: IntakeNutrition(energyKcal: 248, carbsG: 29, proteinG: 13, fatG: 8, sodiumMg: 492)),
            ItemSeed(id: "mcd.121.63", name: "麦乐鸡（4块）", keywords: ["麦乐鸡", "鸡块"], portion: "4 块 / 68g", nutrition: IntakeNutrition(energyKcal: 170, carbsG: 11, proteinG: 10, fatG: 10, sodiumMg: 337)),
            ItemSeed(id: "mcd.153.180", name: "薯条（迷你）", keywords: ["薯条"], portion: "1 份（迷你） / 40g", nutrition: IntakeNutrition(energyKcal: 106, carbsG: 14, proteinG: 2, fatG: 4, sodiumMg: 61)),
            ItemSeed(id: "mcd.122.64", name: "玉米杯（小）", keywords: ["玉米杯", "玉米"], portion: "1 份（小） / 72g", nutrition: IntakeNutrition(energyKcal: 53, carbsG: 7, proteinG: 2, fatG: 1, sodiumMg: 1)),
            ItemSeed(id: "mcd.155.181", name: "苹果片", keywords: ["苹果片"], portion: "1 份 / 66g", nutrition: IntakeNutrition(energyKcal: 32, carbsG: 7, proteinG: 0, fatG: 0, sodiumMg: 0)),
            ItemSeed(id: "mcd.125.67", name: "纯牛奶（盒装）", keywords: ["纯牛奶", "牛奶"], portion: "1 盒 / 200ml", nutrition: IntakeNutrition(energyKcal: 129, carbsG: 10, proteinG: 7, fatG: 7, sodiumMg: 73)),
            ItemSeed(id: "mcd.129.71", name: "纯悦", keywords: ["纯悦", "矿泉水", "水"], portion: "1 瓶 / 550ml", nutrition: IntakeNutrition(energyKcal: 0, carbsG: 0, proteinG: 0, fatG: 0, sodiumMg: 0, waterMl: 550)),
            ItemSeed(id: "mcd.141.168", name: "美汁源100%苹果汁（小）", keywords: ["美汁源100%苹果汁", "苹果汁", "美汁源"], portion: "1 杯（小） / 200ml", nutrition: IntakeNutrition(energyKcal: 88, carbsG: 21, proteinG: 0, fatG: 0, sodiumMg: 0)),
        ], isBuiltin: true),
        // 瑞幸咖啡：产品数据统一由 Support/LuckinCatalog 提供，
        // 营养库预置分组与咖啡因打卡的「瑞幸咖啡」快捷入口共用同一份，避免两处硬编码。
        // 份量按「咖啡因… · 1 大杯 / 450ml」顺序书写：末尾必须是容量，
        // parsePortion 取最后一个「数字+单位」时才会得到 450ml 而非咖啡因的 mg。
        GroupSeed(
            id: "group.luckin.coffee", name: "瑞幸咖啡", sortOrder: 8,
            items: LuckinCatalog.drinks.map { drink in
                // 官网公示的咖啡因与杯容量补齐到营养字段里，预置数据同样覆盖全部苹果健康指标。
                var nutrition = drink.nutrition
                nutrition.caffeineMg = drink.caffeineMg
                nutrition.waterMl = drink.waterMl
                return ItemSeed(id: drink.id, name: drink.name, keywords: drink.keywords,
                                portion: drink.portion, nutrition: nutrition)
            },
            isBuiltin: true
        ),
    ]
}
