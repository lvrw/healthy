import Foundation
import Testing

/// 瑞幸共享目录：本地营养库预置分组与咖啡因快捷入口的一致性。
struct LuckinCatalogTests {

    @Test func catalogCoversOfficialMenu() {
        #expect(LuckinCatalog.drinks.count == 53)
        #expect(LuckinCatalog.categories.count == 7)
        #expect(Set(LuckinCatalog.drinks.map(\.id)).count == 53)
        // 全部产品都参与咖啡因快捷选择；无咖啡因产品记 0，其余在合法打卡范围内。
        #expect(LuckinCatalog.drinks.allSatisfy {
            $0.caffeineMg == 0 || IntakeQuickActionStore.caffeineAmountRange.contains($0.caffeineMg)
        })
        // 图中标「—」但库里已有公示值的保留原值；仅未公示产品带推算标记。
        #expect(LuckinCatalog.drinks.filter { !$0.caffeineEstimated }.count == 45)
        #expect(Set(LuckinCatalog.drinks.filter { $0.caffeineEstimated }.map(\.id))
            == ["lk.velvet", "lk.minicheese", "lk.cocoalatte", "lk.saltedthai", "lk.matchacheese", "lk.geishawhite", "lk.kale", "lk.lactobacillus"])
        // 每张卡片都要有官方 CDN 图，不留空图标。
        #expect(LuckinCatalog.drinks.allSatisfy {
            guard let url = $0.imageURL else { return false }
            return url.hasPrefix("https://img.luckincoffeecdn.com/")
        })
    }

    @Test func groupedKeepsOfficialOrderAndFiltersByQuery() {
        let groups = LuckinCatalog.grouped()
        #expect(groups.reduce(0) { $0 + $1.drinks.count } == 53)
        #expect(groups.first?.category == "拿铁类")
        #expect(groups.last?.category == "冷萃类")
        #expect(LuckinCatalog.grouped(query: "生椰").reduce(0) { $0 + $1.drinks.count } >= 2)
        #expect(!LuckinCatalog.grouped(query: " 美式 ").isEmpty)
        #expect(!LuckinCatalog.grouped(query: "黑巧").isEmpty)
        #expect(LuckinCatalog.grouped(query: "不存在的饮品").isEmpty)
        // 搜索支持空白分词（含中文全角空格）与别名：不再要求整串连续命中。
        #expect(LuckinCatalog.grouped(query: "乳酸菌").flatMap(\.drinks).map(\.id) == ["lk.lactobacillus"])
        #expect(LuckinCatalog.grouped(query: "乳酸菌 美式").flatMap(\.drinks).map(\.id) == ["lk.lactobacillus"])
        #expect(LuckinCatalog.grouped(query: "乳酸菌　美式").flatMap(\.drinks).map(\.id) == ["lk.lactobacillus"])
        #expect(LuckinCatalog.grouped(query: "生椰 拿铁").flatMap(\.drinks).contains { $0.id == "lk.coconut" })
        #expect(LuckinCatalog.grouped(query: "冰美式").flatMap(\.drinks).contains { $0.id == "lk.americano" })
    }

    @Test func quickActionUsesOfficialCaffeineAndCupVolume() throws {
        let coconut = try #require(LuckinCatalog.drinks.first { $0.id == "lk.coconut" })
        let action = LuckinCatalog.quickAction(for: coconut)
        #expect(action.id == "luckin-lk.coconut")
        #expect(action.title == "生椰拿铁")
        #expect(action.amount == 118.4)
        #expect(action.nutrition?.energyKcal == 179)
        #expect(action.nutrition?.waterMl == 385) // 450 ml 生椰拿铁按成分折算含水约 385 ml
        #expect(action.nutrition?.carbsG == 7.4)
        #expect(action.nutrition?.fatG == 13.7)

        let thaiDrink = try #require(LuckinCatalog.drinks.first { $0.id == "lk.thaiyuanyeung" })
        let thai = LuckinCatalog.quickAction(for: thaiDrink)
        #expect(thai.amount == 143.1)
        #expect(thai.nutrition?.proteinG == 6.5)
        #expect(thai.nutrition?.energyKcal == 300) // 图中标「—」，保留原推算值

        let largeDrink = try #require(LuckinCatalog.drinks.first { $0.id == "lk.freshlemonc" })
        let large = LuckinCatalog.quickAction(for: largeDrink)
        #expect(large.nutrition?.waterMl == 570) // 596 ml 超大杯，果味美式含水约 570 ml

        // 图中标「—」的项按用户裁决保留原值。
        let preserved = try #require(LuckinCatalog.drinks.first { $0.id == "lk.mangopomelo" })
        #expect(preserved.caffeineMg == 14.9)
        let classicThai = try #require(LuckinCatalog.drinks.first { $0.id == "lk.classicthai" })
        #expect(classicThai.nutrition.energyKcal == 330)
        let velvet = try #require(LuckinCatalog.drinks.first { $0.id == "lk.velvet" })
        #expect(velvet.caffeineMg == 98.6)
        #expect(velvet.caffeineEstimated)

        // 新增可可系列：热量取大杯/冰/不另外加糖，无咖啡款记 0。
        let cocoaLatte = try #require(LuckinCatalog.drinks.first { $0.id == "lk.cocoalatte" })
        #expect(cocoaLatte.nutrition.energyKcal == 393)
        let cocoaPure = try #require(LuckinCatalog.drinks.first { $0.id == "lk.cocoapure" })
        #expect(cocoaPure.caffeineMg == 0)
        #expect(cocoaPure.nutrition.energyKcal == 397)

        // 乳酸菌美式：官网已下架，热量取官方新闻稿；咖啡因按标准美式推算并显式标记。
        let lactobacillus = try #require(LuckinCatalog.drinks.first { $0.id == "lk.lactobacillus" })
        #expect(lactobacillus.caffeineEstimated)
        let lactoAction = LuckinCatalog.quickAction(for: lactobacillus)
        #expect(lactoAction.amount == 164.3)
        #expect(lactoAction.nutrition?.energyKcal == 108)
        #expect(lactoAction.nutrition?.waterMl == 425)
    }

    @Test func fixedEntryDoesNotConsumeEditableSlots() {
        // 瑞幸产品只在点击时构造快捷加量，不写 UserDefaults，也不改默认 4 项 / 上限 6 项。
        #expect(IntakeQuickActionStore.defaults(for: "caffeine").count == 4)
        #expect(IntakeQuickActionStore.maxCount == 6)
        #expect(IntakeQuickActionStore.defaults(for: "caffeine").allSatisfy {
            !$0.id.hasPrefix("luckin-")
        })
    }

    /// 含水量口径回归（2026-11-20）：waterMl 是「这杯实际含的水」，
    /// 必须小于杯容量；牛奶为基的饮品明显低于水基饮品。
    @Test func waterIsNetWaterNotCupVolume() throws {
        for drink in LuckinCatalog.drinks {
            let volume = FoodDatabase.parsePortion(from: drink.portion).amount
            #expect(volume > 0)
            #expect(drink.waterMl > 0)
            #expect(drink.waterMl < volume)
        }

        let latte = try #require(LuckinCatalog.drinks.first { $0.id == "lk.latte" })
        let americano = try #require(LuckinCatalog.drinks.first { $0.id == "lk.americano" })
        // 同样 450 ml：拿铁 395 ml，美式 445 ml，奶咖含水率明显更低。
        #expect(latte.waterMl == 395)
        #expect(americano.waterMl == 445)
        #expect(latte.waterMl < americano.waterMl)
        #expect(latte.waterMl / 450 <= 0.90)
        #expect(americano.waterMl / 450 >= 0.95)

        // 泰奶（炼乳 + 糖浆）比标准拿铁更低，生椰（椰乳）介于两者之间。
        let thai = try #require(LuckinCatalog.drinks.first { $0.id == "lk.classicthai" })
        let coconut = try #require(LuckinCatalog.drinks.first { $0.id == "lk.coconut" })
        #expect(thai.waterMl < coconut.waterMl)
        #expect(coconut.waterMl < latte.waterMl)
    }
}
