import Foundation

/// 健康 App 里「非本 App 写入」的每日饮食与饮水汇总。
/// 本 App 回写到 HealthKit 的喝水样本带同步标识，读取时会被排除，
/// 因此这里的 externalWaterMl 只包含健康 App 手动录入和第三方 App 的数据。
struct NutritionDay: Sendable, Equatable {
    /// 外部来源的喝水量（毫升）。
    var externalWaterMl: Double? = nil
    /// 膳食热量（千卡）。
    var energyKcal: Double? = nil
    /// 碳水化合物（克）。
    var carbsG: Double? = nil
    /// 蛋白质（克）。
    var proteinG: Double? = nil
    /// 总脂肪（克）。
    var fatG: Double? = nil
    /// 膳食纤维（克）。
    var fiberG: Double? = nil
    /// 糖（克）。
    var sugarG: Double? = nil
    /// 钠（毫克）。
    var sodiumMg: Double? = nil
    /// 咖啡因（毫克）。
    var caffeineMg: Double? = nil

    /// 当天是否有任意一项「评分白名单」内的饮水/饮食数据。
    /// 能量、钠只在 App 内留档，不算评分数据源。
    var hasData: Bool {
        externalWaterMl != nil || carbsG != nil || proteinG != nil
            || fatG != nil || sugarG != nil || fiberG != nil || caffeineMg != nil
    }
}

/// 评分层使用的饮水与饮食输入，单位为 ml / kcal / g / mg。
/// waterTotalMl = 健康 App 同步来的外部水量 + 本 App 打卡水量，两侧不会重复计入。
struct NutritionValues: Sendable, Equatable {
    /// 当日合并后的总喝水量（毫升）。
    var waterTotalMl: Double? = nil
    /// 膳食热量（千卡）。
    var energyKcal: Double? = nil
    /// 碳水化合物（克）。
    var carbsG: Double? = nil
    /// 蛋白质（克）。
    var proteinG: Double? = nil
    /// 总脂肪（克）。
    var fatG: Double? = nil
    /// 膳食纤维（克）。
    var fiberG: Double? = nil
    /// 糖（克）。
    var sugarG: Double? = nil
    /// 钠（毫克）。
    var sodiumMg: Double? = nil
    /// 咖啡因（毫克）。
    var caffeineMg: Double? = nil

    /// 是否有任意一项白名单数据；无数据时评分引擎必须完全跳过该维度。
    /// 认碳水、蛋白质、脂肪、糖、纤维、水、咖啡因（见 NutritionField.scoringFields）；
    /// 饱和脂肪只在单餐打卡的 IntakeNutrition 中提供，每日汇总里没有该字段。
    var hasData: Bool {
        waterTotalMl != nil || carbsG != nil || proteinG != nil
            || fatG != nil || sugarG != nil || fiberG != nil || caffeineMg != nil
    }

    /// 是否只有外部同步来的饮水、没有任何白名单内的膳食记录。
    var hasDietData: Bool {
        carbsG != nil || proteinG != nil || fatG != nil
            || sugarG != nil || fiberG != nil || caffeineMg != nil
    }

    init(
        waterTotalMl: Double? = nil,
        energyKcal: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        fiberG: Double? = nil,
        sugarG: Double? = nil,
        sodiumMg: Double? = nil,
        caffeineMg: Double? = nil
    ) {
        self.waterTotalMl = waterTotalMl
        self.energyKcal = energyKcal
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sugarG = sugarG
        self.sodiumMg = sodiumMg
        self.caffeineMg = caffeineMg
    }

    /// 从每日快照取值。DailySnapshot 与 Scoring 源码同属主/测试 target。
    /// 合并字段尚未落库时（例如刚 apply 完 DTO、还没跑合并），用两侧拆分值兜底。
    static func from(_ snapshot: DailySnapshot) -> NutritionValues {
        let water: Double?
        if let total = snapshot.waterTotalMl {
            water = total
        } else if snapshot.externalWaterMl != nil || snapshot.localWaterMl != nil {
            water = (snapshot.externalWaterMl ?? 0) + (snapshot.localWaterMl ?? 0)
        } else {
            water = nil
        }
        return NutritionValues(
            waterTotalMl: water,
            energyKcal: snapshot.dietaryEnergyKcal,
            carbsG: snapshot.dietaryCarbsG,
            proteinG: snapshot.dietaryProteinG,
            fatG: snapshot.dietaryFatG,
            fiberG: snapshot.dietaryFiberG,
            sugarG: snapshot.dietarySugarG,
            sodiumMg: snapshot.dietarySodiumMg,
            caffeineMg: snapshot.dietaryCaffeineMg
        )
    }

    /// 多个每日值的均值，用于身体年龄的 7 日窗口；缺失项不参与平均。
    static func average(_ values: [NutritionValues]) -> NutritionValues {
        func mean(_ extract: (NutritionValues) -> Double?) -> Double? {
            let usable = values.compactMap(extract)
            guard !usable.isEmpty else { return nil }
            return usable.reduce(0, +) / Double(usable.count)
        }
        return NutritionValues(
            waterTotalMl: mean(\.waterTotalMl),
            energyKcal: mean(\.energyKcal),
            carbsG: mean(\.carbsG),
            proteinG: mean(\.proteinG),
            fatG: mean(\.fatG),
            fiberG: mean(\.fiberG),
            sugarG: mean(\.sugarG),
            sodiumMg: mean(\.sodiumMg),
            caffeineMg: mean(\.caffeineMg)
        )
    }
}

/// 膳食营养合并口径（纯逻辑，供 WaterMerge 与回归测试共用）。
/// `stored` 有两种可能来源：上一轮的「外部 + 本地」合并总量，或同步链路刚写入的纯外部量。
enum NutritionMerge {
    /// 把存储值还原成纯外部量，再加回本轮本 App 的 meal 打卡量。
    /// - Parameters:
    ///   - stored: DailyMetrics 里当前存的膳食字段，可能为 nil（无数据）。
    ///   - previousLocal: 上一轮合并进该字段的本地 meal 量。
    ///   - currentLocal: 本轮从 meal 打卡重新聚合出来的本地量。
    /// - Returns: 合并后的总量；小于等于 0 时返回 nil，表示当天没有该指标。
    static func total(stored: Double?, previousLocal: Double, currentLocal: Double) -> Double? {
        let base = stored ?? 0
        let external = base - previousLocal
        // 外部量不可能为负：为负说明 stored 已是纯外部量（同步覆盖过、快照未清），
        // 不能再扣一次本地量，否则本 App 记录的热量会被抵消成 0。
        let result = (external < 0 ? base : external) + currentLocal
        return result > 0 ? result : nil
    }
}

// configured by qoder
