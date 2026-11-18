import Foundation
import HealthKit
import Testing

struct IntakeQuickActionsTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "intake-quick-\(UUID().uuidString)")!
    }

    @Test func defaultWaterPresetsAreSixAmounts() {
        let actions = IntakeQuickActionStore.defaults(for: "water")
        #expect(actions.count == 6)
        #expect(actions.map(\.amount) == [50, 100, 200, 250, 300, 500])
        #expect(actions.allSatisfy { $0.nutrition == nil })
        #expect(actions.first?.title == "+50 ml")
    }

    @Test func defaultCaffeinePresetsIncludeAmericanoAndLatteWithNutrition() {
        let actions = IntakeQuickActionStore.defaults(for: "caffeine")
        #expect(actions.count == 4)
        #expect(actions[0].title == "美式")
        #expect(actions[1].title == "拿铁")
        #expect(actions[2].title == "茶水")
        #expect(actions[3].title == "可乐")
        #expect(actions[0].amount == 150)
        #expect(actions[1].amount == 75)
        // 拿铁必须带碳蛋脂与热量，美式也带营养结构（糖分 0、热量 5kcal）。
        // 两者默认含水量均为 300ml（计入喝水总额）。
        #expect(actions[1].nutrition == IntakeNutrition(energyKcal: 105, carbsG: 8.7, proteinG: 8, fatG: 7, waterMl: 300))
        #expect(actions[0].nutrition == IntakeNutrition(energyKcal: 5, waterMl: 300))
        // 红茶 / 可乐默认含水量同样 300ml，但无碳蛋脂。
        #expect(actions[2].nutrition == IntakeNutrition(waterMl: 300))
        #expect(actions[3].nutrition == IntakeNutrition(carbsG: 35, waterMl: 300))
        #expect(actions.allSatisfy { $0.nutrition != nil })
    }

    @Test func legacyDefaultTitlesMigrateToShortNamesOnce() {
        let store = defaults()
        let legacy = [
            IntakeQuickAction(id: "drink-americano", title: "一杯美式", amount: 150,
                              nutrition: IntakeNutrition(waterMl: 300)),
            IntakeQuickAction(id: "drink-tea", title: "一杯茶（300ml）", amount: 50,
                              nutrition: IntakeNutrition(waterMl: 300)),
            // 用户自己改过的名字不能被迁移覆盖。
            IntakeQuickAction(id: "custom", title: "我的特调", amount: 80,
                              nutrition: IntakeNutrition(waterMl: 300)),
        ]
        _ = IntakeQuickActionStore.save(legacy, kind: "caffeine", defaults: store)
        let migrated = IntakeQuickActionStore.load(kind: "caffeine", defaults: store)
        #expect(migrated.map(\.title) == ["美式", "茶水", "我的特调"])
        // 第二次加载不再重复迁移，且不再写回配置。
        #expect(IntakeQuickActionStore.load(kind: "caffeine", defaults: store) == migrated)
    }

    @Test func drinkScalesCaffeineNutritionWaterByChosenVolume() {
        let latte = IntakeQuickActionStore.defaults(for: "caffeine")[1]
        // 基准 300ml / 75mg；选 450ml → 1.5 倍：112.5mg、碳水 13.05g、联动水 450ml。
        let scaled = latte.scaled(toVolumeMl: 450)!
        #expect(scaled.amount == 112.5)
        #expect(abs((scaled.nutrition?.carbsG ?? 0) - 13.05) < 0.0001)
        #expect(scaled.nutrition?.proteinG == 12)
        #expect(scaled.nutrition?.energyKcal == 157.5)
        #expect(scaled.nutrition?.waterMl == 450)
        // 原项不被改动，备注带上本次实际容量。
        #expect(latte.amount == 75)
        #expect(scaled.title == "拿铁（450ml）")

        // 茶 / 美式 / 可乐同样按容量换算，标题里已有的容量说明不重复叠加。
        let defaults = IntakeQuickActionStore.defaults(for: "caffeine")
        let tea = defaults[2].scaled(toVolumeMl: 150)!
        #expect(tea.amount == 25)
        #expect(tea.nutrition?.waterMl == 150)
        #expect(tea.title == "茶水（150ml）")
        let americano = defaults[0].scaled(toVolumeMl: 300)!
        #expect(americano.amount == 150)
        #expect(americano.title == "美式（300ml）")
        let cola = defaults[3].scaled(toVolumeMl: 600)!
        #expect(cola.amount == 70)
        #expect(cola.nutrition?.carbsG == 70)
    }

    @Test func drinkScalingRejectsInvalidVolumesAndMissingBase() {
        let americano = IntakeQuickActionStore.defaults(for: "caffeine")[0]
        #expect(americano.scaled(toVolumeMl: 0) == nil)
        #expect(americano.scaled(toVolumeMl: -1) == nil)
        #expect(americano.scaled(toVolumeMl: .infinity) == nil)
        #expect(americano.scaled(toVolumeMl: 5_001) == nil)
        // 用户自定义但没配基准容量的项保持原行为：不弹容量选择。
        let noBase = IntakeQuickAction(id: "x", title: "浓缩", amount: 60)
        #expect(noBase.baseVolumeMl <= 0)
        #expect(noBase.scaled(toVolumeMl: 300) == nil)
    }

    @Test func loadFallsBackToDefaultsWithoutStoredConfig() {
        let store = defaults()
        let loaded = IntakeQuickActionStore.load(kind: "caffeine", defaults: store)
        #expect(loaded == IntakeQuickActionStore.defaults(for: "caffeine"))
    }

    @Test func customActionsRoundTrip() {
        let store = defaults()
        let custom = [
            IntakeQuickAction(id: "a", title: "双倍浓缩", amount: 180,
                              nutrition: IntakeNutrition(carbsG: 0, proteinG: 0, fatG: 0)),
            IntakeQuickAction(id: "b", title: "燕麦拿铁", amount: 90,
                              nutrition: IntakeNutrition(carbsG: 18, proteinG: 6, fatG: 5)),
        ]
        let saved = IntakeQuickActionStore.save(custom, kind: "caffeine", defaults: store)
        let loaded = IntakeQuickActionStore.load(kind: "caffeine", defaults: store)
        #expect(saved == custom)
        #expect(loaded == custom)
        #expect(loaded[1].nutrition?.carbsG == 18)
        // 两类配置互不影响。
        #expect(IntakeQuickActionStore.load(kind: "water", defaults: store)
            == IntakeQuickActionStore.defaults(for: "water"))
    }

    @Test func sanitizeClampsValuesDropsEmptyTitlesAndCapsCount() {
        var actions = [
            IntakeQuickAction(id: "x", title: "  ", amount: 100),
            IntakeQuickAction(id: "", title: "超大杯", amount: 99_999,
                              nutrition: IntakeNutrition(carbsG: -5, proteinG: 999, fatG: 3)),
        ]
        actions.append(contentsOf: (0..<8).map { index in
            IntakeQuickAction(id: "d\(index)", title: "饮品\(index)", amount: 50)
        })
        let sanitized = IntakeQuickActionStore.sanitize(actions, kind: "caffeine")
        #expect(sanitized.count == IntakeQuickActionStore.maxCount)
        #expect(sanitized.allSatisfy { !$0.title.isEmpty })
        #expect(sanitized.allSatisfy { $0.amount <= IntakeQuickActionStore.caffeineAmountRange.upperBound })
        #expect(sanitized[0].nutrition?.carbsG == 0)
        #expect(sanitized[0].nutrition?.proteinG == IntakeQuickActionStore.nutritionRange.upperBound)
        #expect(!sanitized[0].id.isEmpty)
    }

    @Test func waterActionsDropNutrition() {
        let actions = [
            IntakeQuickAction(id: "w", title: "+300 ml", amount: 300,
                              nutrition: IntakeNutrition(carbsG: 9, proteinG: 2, fatG: 1)),
        ]
        let sanitized = IntakeQuickActionStore.sanitize(actions, kind: "water")
        #expect(sanitized[0].nutrition == nil)
    }

    @Test func waterTitlesFollowClampedAmount() {
        // 配置页只编辑一行容量：标题按钳制后的容量派生，旧名称与空标题都不影响。
        let actions = [
            IntakeQuickAction(id: "w1", title: "自定义名称", amount: 350),
            IntakeQuickAction(id: "w2", title: "", amount: 99_999),
        ]
        let sanitized = IntakeQuickActionStore.sanitize(actions, kind: "water")
        #expect(sanitized.count == 2)
        #expect(sanitized[0].title == "+350 ml")
        #expect(sanitized[1].amount == IntakeQuickActionStore.waterAmountRange.upperBound)
        #expect(sanitized[1].title == "+5000 ml")
        // 饮品名称仍由用户填写，不被容量覆盖。
        let caffeine = IntakeQuickActionStore.sanitize(
            [IntakeQuickAction(id: "c", title: "一杯美式", amount: 150)],
            kind: "caffeine"
        )
        #expect(caffeine[0].title == "一杯美式")
    }

    @Test func emptyStoredConfigStaysEmpty() {
        let store = defaults()
        // 从未配置过：仍用预设初始化。
        #expect(IntakeQuickActionStore.load(kind: "water", defaults: store)
                == IntakeQuickActionStore.defaults(for: "water"))
        // 已存的空配置原样保留，不再隐式补回默认 6 项。
        let saved = IntakeQuickActionStore.save([], kind: "water", defaults: store)
        #expect(saved.isEmpty)
        #expect(IntakeQuickActionStore.load(kind: "water", defaults: store).isEmpty)
        // 想回预设只能由用户点「恢复默认」显式触发。
        let reset = IntakeQuickActionStore.reset(kind: "water", defaults: store)
        #expect(reset == IntakeQuickActionStore.defaults(for: "water"))
        #expect(IntakeQuickActionStore.load(kind: "water", defaults: store) == reset)
    }

    @Test func resetReturnsDefaults() {
        let store = defaults()
        _ = IntakeQuickActionStore.save(
            [IntakeQuickAction(id: "z", title: "自定义", amount: 42)],
            kind: "water",
            defaults: store
        )
        let reset = IntakeQuickActionStore.reset(kind: "water", defaults: store)
        #expect(reset == IntakeQuickActionStore.defaults(for: "water"))
        #expect(store.data(forKey: IntakeQuickActionStore.key(for: "water")) == nil)
        #expect(IntakeQuickActionStore.load(kind: "water", defaults: store) == reset)
    }

    @Test func nutritionSurvivesJSONRoundTrip() throws {
        let nutrition = IntakeNutrition(carbsG: 12, proteinG: 8, fatG: 7)
        let data = try JSONEncoder().encode(nutrition)
        let json = String(data: data, encoding: .utf8)
        #expect(json != nil)
        let decoded = try JSONDecoder().decode(IntakeNutrition.self, from: data)
        #expect(decoded == nutrition)
    }

    @Test func writeTypesCoverDrinkNutrition() {
        let types = HealthKitTypes.writeTypes
        // 饮品 / 喝水写回核心 5 类。
        #expect(types.contains(HealthKitTypes.dietaryWater))
        #expect(types.contains(HealthKitTypes.dietaryCaffeine))
        #expect(types.contains(HealthKitTypes.dietaryCarbs))
        #expect(types.contains(HealthKitTypes.dietaryProtein))
        #expect(types.contains(HealthKitTypes.dietaryFat))
        // 另有能量 / 膳食纤维 / 糖 / 钠共 4 类，供食物识别写回；
        // 再加感受记录回写的心理状态，合计 10 类。
        #expect(types.contains(HealthKitTypes.stateOfMind))
        #expect(types.count == 10)
    }

    @Test func recordCarriesNutritionWithoutChangingReconcileMatching() {
        let record = WaterSyncRecord(
            syncID: "A1",
            amountMl: 75,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            kind: "caffeine",
            nutrition: IntakeNutrition(carbsG: 12, proteinG: 8, fatG: 7)
        )
        let sample = WaterSyncSample(
            syncID: "A1",
            amountMl: 75,
            date: record.date,
            uuid: "u1",
            syncVersion: 1,
            kind: "caffeine"
        )
        #expect(record.nutrition?.carbsG == 12)
        // 对账只按主样本的数量 / 时间比对，营养附属样本不参与。
        #expect(WaterSyncReconciler.matches(sample, record))
        #expect(WaterSyncReconciler.reconcile(local: [record], remote: [sample]).isEmpty)
    }
}
