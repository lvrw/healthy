import Foundation

/// 一份食物 / 一杯饮品的完整营养素，字段与苹果健康 App「营养摄入」40 项一一对应
/// （见 `NutritionField`）。所有字段默认 0：官网未公示、AI 无法判断、旧数据缺失时一律为 0。
/// 喝水的水量单独走打卡合并路径，不参与 hasAny 判定，避免纯饮水被当成一顿饭。
struct IntakeNutrition: Sendable, Equatable, Encodable {
    // MARK: 主要指标（与旧版 JSON 字段完全同名，保证已落库数据可解码）
    /// 膳食能量（千卡）。
    var energyKcal: Double = 0
    /// 碳水化合物（克）。
    var carbsG: Double = 0
    /// 蛋白质（克）。
    var proteinG: Double = 0
    /// 总脂肪（克）。
    var fatG: Double = 0
    /// 纤维（克）。
    var fiberG: Double = 0
    /// 膳食糖（克）。
    var sugarG: Double = 0
    /// 钠（毫克）。
    var sodiumMg: Double = 0
    /// 水（毫升）。仅本地配置与展示，不单独写回健康 App 的饮水量。
    var waterMl: Double = 0
    /// 咖啡因（毫克）。
    var caffeineMg: Double = 0

    // MARK: 脂肪细分 / 胆固醇
    /// 饱和脂肪（克）。
    var saturatedFatG: Double = 0
    /// 单元不饱和脂肪（克）。
    var monounsaturatedFatG: Double = 0
    /// 多元不饱和脂肪（克）。
    var polyunsaturatedFatG: Double = 0
    /// 膳食胆固醇（毫克）。
    var cholesterolMg: Double = 0

    // MARK: 矿物质（毫克 / 微克）
    var iodineMcg: Double = 0
    var calciumMg: Double = 0
    var chromiumMcg: Double = 0
    var potassiumMg: Double = 0
    var phosphorusMg: Double = 0
    var chlorideMg: Double = 0
    var magnesiumMg: Double = 0
    var manganeseMg: Double = 0
    var molybdenumMcg: Double = 0
    var ironMg: Double = 0
    var copperMg: Double = 0
    var seleniumMcg: Double = 0
    var zincMg: Double = 0

    // MARK: 维生素（毫克 / 微克）
    var pantothenicAcidMg: Double = 0
    var riboflavinMg: Double = 0
    var thiaminMg: Double = 0
    var biotinMcg: Double = 0
    var vitaminAMcg: Double = 0
    var vitaminB6Mg: Double = 0
    var vitaminB12Mcg: Double = 0
    var vitaminCMg: Double = 0
    var vitaminDMcg: Double = 0
    var vitaminEMg: Double = 0
    var vitaminKMcg: Double = 0
    var niacinMg: Double = 0
    var folateMcg: Double = 0

    /// 酒精摄入量（标准杯，对应 HealthKit numberOfAlcoholicBeverages）。
    var alcoholServings: Double = 0

    /// 按指标枚举读写数值，供 AI 解析与 UI 编辑统一驱动。
    subscript(field: NutritionField) -> Double {
        get { self[keyPath: field.keyPath] }
        set { self[keyPath: field.keyPath] = newValue }
    }

    /// 是否携带任意一项非零营养；水单独走打卡，全 0（或只有水）视为「无营养记录」。
    var hasAny: Bool {
        NutritionField.allCases.contains { field in
            field != .water && self[field] > 0
        }
    }

    /// 按份数缩放（用于用户调整一餐里某样食物的份量），40 项一并缩放。
    func scaled(by factor: Double) -> IntakeNutrition {
        var result = IntakeNutrition()
        for field in NutritionField.allCases {
            result[field] = self[field] * factor
        }
        return result
    }

    static var zero: IntakeNutrition { IntakeNutrition() }

    static func + (lhs: IntakeNutrition, rhs: IntakeNutrition) -> IntakeNutrition {
        var result = IntakeNutrition()
        for field in NutritionField.allCases {
            result[field] = lhs[field] + rhs[field]
        }
        return result
    }
}

/// 解码实现放在 extension 里，避免抑制编译器的逐成员初始化器
/// （FoodSeed / FoodDatabase / 打卡配置都在用 `IntakeNutrition(energyKcal:…)` 这种写法）。
/// 旧版本只存了 8 个字段；AI 也可能漏字段。任何缺失 / 类型不匹配的项按 0 处理，
/// 不能让整条记录解码失败变成零营养。
extension IntakeNutrition: Decodable {
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: NutritionCodingKey.self)
        for field in NutritionField.allCases {
            let key = NutritionCodingKey(field.jsonKey)
            // decode（而非 decodeIfPresent）配合 try?：缺字段 / 类型不符一律落到默认 0。
            if let value = try? container.decode(Double.self, forKey: key) {
                self[field] = value
            }
        }
    }
}

/// 打卡页的一个快捷按键。喝水只有数量；咖啡因额外带碳水/蛋白质/脂肪。
struct IntakeQuickAction: Sendable, Equatable, Identifiable, Codable {
    var id: String
    /// 按钮文字：喝水默认「+50 ml」，咖啡因默认「一杯美式」这类饮品名。
    var title: String
    /// 数量：喝水为毫升，咖啡因为毫克。
    var amount: Double
    /// 仅咖啡因快捷项使用；nil 表示只写咖啡因。
    var nutrition: IntakeNutrition?

    static func new(kind: String) -> IntakeQuickAction {
        let isWater = kind == SyncableCheckInKind.water.rawValue
        return IntakeQuickAction(
            id: UUID().uuidString,
            title: isWater ? "+200 ml" : "自定义饮品",
            amount: isWater ? 200 : 100,
            nutrition: isWater ? nil : IntakeNutrition()
        )
    }
}

/// 咖啡因饮品的容量换算：快捷项里配置的「水（ml）」就是该杯基准容量，
/// 用户本次实际喝的毫升数不同时，咖啡因与全部营养按 `实际 / 基准` 等比缩放，
/// 联动生成的喝水记录也随所选容量变化。用于打卡页点饮品后先选容量的交互。
extension IntakeQuickAction {
    /// 该饮品的基准容量（ml）；<= 0 表示没有配置容量，打卡页保持原「按固定 mg 直接打卡」。
    var baseVolumeMl: Double { nutrition?.waterMl ?? 0 }

    /// 按本次实际容量等比缩放出一份用于打卡的快捷项。
    /// - Parameter volumeMl: 用户选择的实际容量（ml）。
    /// - Returns: 缩放后的新项；基准容量或目标容量无效时返回 nil。
    func scaled(toVolumeMl volumeMl: Double) -> IntakeQuickAction? {
        let base = baseVolumeMl
        guard base > 0, volumeMl.isFinite,
              IntakeQuickActionStore.drinkVolumeRange.contains(volumeMl) else { return nil }
        let factor = volumeMl / base
        var result = self
        result.amount = amount * factor
        // 记录备注带上本次实际容量，旧标题里若已有「（300ml）」先去掉，避免重复。
        let plainTitle = title.replacingOccurrences(
            of: "（[0-9]+ml）", with: "", options: .regularExpression
        )
        result.title = "\(plainTitle)（\(Int(volumeMl.rounded()))ml）"
        if let nutrition {
            // scaled(by:) 会连同 waterMl 一起缩放，联动水量自然等于所选容量。
            result.nutrition = nutrition.scaled(by: factor)
        }
        return result
    }
}

/// 打卡页容量选择范围，与喝水快捷项共用同一上限口径。
extension IntakeQuickActionStore {
    static let drinkVolumeRange: ClosedRange<Double> = 1...5_000
}

/// 快捷按键配置，按喝水 / 咖啡因分开存到 UserDefaults。
/// 纯 Foundation 实现，便于单元测试；配置页直接编辑这份数组。
enum IntakeQuickActionStore {
    static let maxCount = 6

    static let waterAmountRange: ClosedRange<Double> = 1...5_000
    static let caffeineAmountRange: ClosedRange<Double> = 1...1_000
    static let nutritionRange: ClosedRange<Double> = 0...500
    /// 含水量单独放宽：大杯饮品（642 ml 可乐含水约 595 ml）会超过宏量营养的 500 上限。
    static let waterIntakeRange: ClosedRange<Double> = 0...2_000

    static func key(for kind: String) -> String {
        "healthy.intake.quickActions.\(kind)"
    }

    /// 喝水按钮文字由容量派生：配置页只编辑一行容量，不单独维护名称。
    static func waterTitle(for amount: Double) -> String {
        "+\(Int(amount.rounded())) ml"
    }

    /// 快捷按键配置的一次性迁移标记：旧版带「一杯 / 一罐 /（300ml）」的默认名字统一改为
    /// 简短品类名，并清理旧版本误加的「麦咖啡」快捷项（麦咖啡改为固定入口，不占可编辑名额）。
    private static let caffeineMigrationKey = "healthy.intake.quickActions.caffeine.migrated.v4"

    /// 旧默认名 → 新短名。只改完全同名的项，用户自己改过的名字不动。
    private static let legacyDrinkTitles: [String: String] = [
        "一杯美式": "美式", "美式咖啡": "美式",
        "一杯拿铁": "拿铁",
        "一杯茶（300ml）": "茶水", "一杯茶": "茶水", "一杯红茶": "茶水",
        "一罐可乐": "可乐",
    ]

    static func defaults(for kind: String) -> [IntakeQuickAction] {
        if kind == SyncableCheckInKind.caffeine.rawValue {
            return [
                drink("drink-americano", "美式", 150, 0, 0, 0, energyKcal: 5, waterMl: 300),
                drink("drink-latte", "拿铁", 75, 8.7, 8, 7, energyKcal: 105, waterMl: 300),
                drink("drink-tea", "茶水", 50, 0, 0, 0, waterMl: 300),
                drink("drink-cola", "可乐", 35, 35, 0, 0, waterMl: 300),
            ]
        }
        return [50, 100, 200, 250, 300, 500].map { value in
            IntakeQuickAction(
                id: "water-\(Int(value))",
                title: waterTitle(for: value),
                amount: value
            )
        }
    }

    /// 仅「从未存过配置」时用预设初始化；已存配置（含空数组）原样返回，不再自动补回默认项。
    /// 老版本升级时做一次迁移：红茶改名 + 移除自动追加的麦咖啡，之后用户删改都不再干预。
    static func load(kind: String, defaults: UserDefaults = .standard) -> [IntakeQuickAction] {
        guard let data = defaults.data(forKey: key(for: kind)),
              let decoded = try? JSONDecoder().decode([IntakeQuickAction].self, from: data) else {
            return self.defaults(for: kind)
        }
        var actions = sanitize(decoded, kind: kind)
        if kind == SyncableCheckInKind.caffeine.rawValue,
           !defaults.bool(forKey: caffeineMigrationKey) {
            // 旧版本把麦咖啡写进了快捷项；现在改为营养库分组固定入口，这里只清理自动生成的那一条，
            // 用户自己手动改过名称 / 数值的同名项保持不动。
            actions.removeAll { action in
                action.id == "drink-mccafe" && action.title == "麦咖啡"
            }
            for index in actions.indices {
                if let shortName = legacyDrinkTitles[actions[index].title] {
                    actions[index].title = shortName
                }
            }
            actions = save(actions, kind: kind, defaults: defaults)
            defaults.set(true, forKey: caffeineMigrationKey)
        }
        return actions
    }

    static func save(
        _ actions: [IntakeQuickAction],
        kind: String,
        defaults: UserDefaults = .standard
    ) -> [IntakeQuickAction] {
        let sanitized = sanitize(actions, kind: kind)
        if let data = try? JSONEncoder().encode(sanitized) {
            defaults.set(data, forKey: key(for: kind))
        }
        return sanitized
    }

    static func reset(kind: String, defaults: UserDefaults = .standard) -> [IntakeQuickAction] {
        let presets = self.defaults(for: kind)
        defaults.removeObject(forKey: key(for: kind))
        return presets
    }

    /// 配置页写入前统一清洗：喝水标题按容量派生、饮品去空标题、补 ID、钳制数值、最多 6 个。
    static func sanitize(_ actions: [IntakeQuickAction], kind: String) -> [IntakeQuickAction] {
        let isWater = kind == SyncableCheckInKind.water.rawValue
        let amountRange = isWater ? waterAmountRange : caffeineAmountRange
        var seen: Set<String> = []
        var result: [IntakeQuickAction] = []
        for var action in actions {
            // 先过滤无效项再截断，否则一个空标题会白占一个名额。
            guard result.count < maxCount else { break }
            action.amount = IntakeGoal.clamp(action.amount, in: amountRange)
            if isWater {
                // 喝水配置页只编辑一行容量，按钮文字统一由钳制后的容量派生。
                action.nutrition = nil
                action.title = waterTitle(for: action.amount)
            } else {
                let title = action.title.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                action.title = title
                var nutrition = action.nutrition ?? IntakeNutrition()
                nutrition.carbsG = IntakeGoal.clamp(nutrition.carbsG, in: nutritionRange)
                nutrition.proteinG = IntakeGoal.clamp(nutrition.proteinG, in: nutritionRange)
                nutrition.fatG = IntakeGoal.clamp(nutrition.fatG, in: nutritionRange)
                nutrition.waterMl = IntakeGoal.clamp(nutrition.waterMl, in: waterIntakeRange)
                action.nutrition = nutrition
            }
            if action.id.isEmpty || seen.contains(action.id) {
                action.id = UUID().uuidString
            }
            seen.insert(action.id)
            result.append(action)
        }
        return result
    }

    private static func drink(
        _ id: String,
        _ title: String,
        _ caffeineMg: Double,
        _ carbsG: Double,
        _ proteinG: Double,
        _ fatG: Double,
        energyKcal: Double = 0,
        waterMl: Double = 0
    ) -> IntakeQuickAction {
        IntakeQuickAction(
            id: id,
            title: title,
            amount: caffeineMg,
            nutrition: IntakeNutrition(
                energyKcal: energyKcal,
                carbsG: carbsG,
                proteinG: proteinG,
                fatG: fatG,
                waterMl: waterMl
            )
        )
    }
}
