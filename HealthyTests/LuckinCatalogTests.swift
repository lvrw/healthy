import Foundation
import Testing

/// 瑞幸共享目录：本地营养库预置分组与咖啡因快捷入口的一致性。
struct LuckinCatalogTests {

    @Test func catalogCoversOfficialMenu() {
        #expect(LuckinCatalog.drinks.count == 28)
        #expect(LuckinCatalog.categories.count == 7)
        #expect(Set(LuckinCatalog.drinks.map(\.id)).count == 28)
        // 全部产品都参与咖啡因快捷选择；公示值与推算值都在合法打卡范围内。
        #expect(LuckinCatalog.drinks.allSatisfy {
            IntakeQuickActionStore.caffeineAmountRange.contains($0.caffeineMg)
        })
        // 官网公示值不带推算标记，推算值仅限官网未公示咖啡因的 6 款。
        #expect(LuckinCatalog.drinks.filter { !$0.caffeineEstimated }.count == 22)
        #expect(Set(LuckinCatalog.drinks.filter { $0.caffeineEstimated }.map(\.id))
            == ["lk.velvet", "lk.minicheese", "lk.saltedthai", "lk.matchacheese", "lk.geishawhite", "lk.kale"])
    }

    @Test func groupedKeepsOfficialOrderAndFiltersByQuery() {
        let groups = LuckinCatalog.grouped()
        #expect(groups.reduce(0) { $0 + $1.drinks.count } == 28)
        #expect(groups.first?.category == "拿铁类")
        #expect(groups.last?.category == "冷萃类")
        #expect(LuckinCatalog.grouped(query: "生椰").reduce(0) { $0 + $1.drinks.count } == 2)
        #expect(!LuckinCatalog.grouped(query: " 美式 ").isEmpty)
        #expect(LuckinCatalog.grouped(query: "不存在的饮品").isEmpty)
    }

    @Test func quickActionUsesOfficialCaffeineAndCupVolume() throws {
        let coconut = try #require(LuckinCatalog.drinks.first { $0.id == "lk.coconut" })
        let action = LuckinCatalog.quickAction(for: coconut)
        #expect(action.id == "luckin-lk.coconut")
        #expect(action.title == "生椰拿铁")
        #expect(action.amount == 118.4)
        #expect(action.nutrition?.energyKcal == 179)
        #expect(action.nutrition?.waterMl == 450)
        // 官网未公示宏量营养，碳水/脂肪保持 0。
        #expect(action.nutrition?.carbsG == 7.4) // 碳蛋脂为按配方拆算的推算值
        #expect(action.nutrition?.fatG == 13.7)

        let thaiDrink = try #require(LuckinCatalog.drinks.first { $0.id == "lk.thaiyuanyeung" })
        let thai = LuckinCatalog.quickAction(for: thaiDrink)
        #expect(thai.amount == 143.1)
        #expect(thai.nutrition?.proteinG == 6.5)
        #expect(thai.nutrition?.energyKcal == 300) // 热量为推算值（官网未公示）

        let largeDrink = try #require(LuckinCatalog.drinks.first { $0.id == "lk.freshlemonc" })
        let large = LuckinCatalog.quickAction(for: largeDrink)
        #expect(large.nutrition?.waterMl == 596) // 超大杯
    }

    @Test func fixedEntryDoesNotConsumeEditableSlots() {
        // 瑞幸产品只在点击时构造快捷加量，不写 UserDefaults，也不改默认 4 项 / 上限 6 项。
        #expect(IntakeQuickActionStore.defaults(for: "caffeine").count == 4)
        #expect(IntakeQuickActionStore.maxCount == 6)
        #expect(IntakeQuickActionStore.defaults(for: "caffeine").allSatisfy {
            !$0.id.hasPrefix("luckin-")
        })
    }
}
