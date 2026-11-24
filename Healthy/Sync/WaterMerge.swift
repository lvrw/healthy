import Foundation
import SwiftData

/// 最近一次打卡双向同步的结果，供设置页展示；只存本机偏好，不参与评分。
@MainActor
enum WaterSyncStatus {
    static let key = "healthy.waterSyncStatus"
    static let timeKey = "healthy.waterSyncStatusAt"

    static func set(_ message: String) {
        UserDefaults.standard.set(message, forKey: key)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: timeKey)
    }

    static func message() -> String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func timestamp() -> Date? {
        let value = UserDefaults.standard.double(forKey: timeKey)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }
}

/// 本地打卡（喝水 / 咖啡因）→ DailyMetrics 的合并逻辑。
/// 同步流程与「打卡即时刷新」共用同一份实现，避免两侧口径不一致。
@MainActor
enum WaterMerge {
    /// 所有可回写的本地打卡，按 HealthKit 对账需要的形状返回。
    /// 老版本留下来的记录没有 syncID，这里补齐并持久化，保证后续同步 ID 稳定。
    static func localRecords(in context: ModelContext) throws -> [WaterSyncRecord] {
        let checks = try context.fetch(FetchDescriptor<ActionCheckIn>())
        var needsSave = false
        var records: [WaterSyncRecord] = []
        for check in checks {
            guard let kind = SyncableCheckInKind(rawValue: check.kindRaw) else { continue }
            let missing = check.syncID == nil || check.syncID?.isEmpty == true
            let id = check.ensureSyncID()
            if missing { needsSave = true }
            // 饮品快捷项的碳蛋脂随打卡一起写回健康 App，对账/重写时不能丢。
            let nutrition = check.nutritionJSON.flatMap { json -> IntakeNutrition? in
                guard let data = json.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(IntakeNutrition.self, from: data)
            }
            records.append(WaterSyncRecord(
                syncID: id,
                amountMl: check.amount,
                date: check.createdAt,
                kind: kind.rawValue,
                nutrition: nutrition
            ))
        }
        if needsSave { try context.save() }
        return records
    }

    /// 食物识别打卡的本地记录，按 HealthKit 膳食对账需要的形状返回。
    /// 老记录没有 syncID 时在此补齐并持久化。
    static func mealRecords(in context: ModelContext) throws -> [MealSyncRecord] {
        let checks = try context.fetch(FetchDescriptor<ActionCheckIn>())
        var records: [MealSyncRecord] = []
        for check in checks where check.kindRaw == "meal" {
            let id = check.ensureSyncID()
            let nutrition = check.nutritionJSON.flatMap { json -> IntakeNutrition? in
                guard let data = json.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(IntakeNutrition.self, from: data)
            } ?? .zero
            records.append(MealSyncRecord(
                syncID: id,
                date: check.createdAt,
                nutrition: nutrition,
                source: check.recognitionSource ?? "local",
                note: check.note,
                kind: "meal"
            ))
        }
        return records
    }

    /// 全部饮食打卡转成评分引擎的输入（含餐次与已存评分）。
    /// 旧记录没有餐次时按 createdAt 推断；餐次/评分只在本地参与规律计算，不写回健康 App。
    static func mealEntries(in context: ModelContext) throws -> [MealEntry] {
        let checks = try context.fetch(
            FetchDescriptor<ActionCheckIn>(predicate: #Predicate<ActionCheckIn> { $0.kindRaw == "meal" })
        )
        return checks.compactMap { check in
            guard let slot = check.mealSlot else { return nil }
            return MealEntry(
                id: check.ensureSyncID(),
                date: check.createdAt,
                slot: slot,
                nutrition: check.nutrition,
                score: check.mealScore
            )
        }
    }

    /// 把「本 App 打卡量」与「健康 App 同步来的外部量」合并成总量字段。
    /// - 只有打卡、没有 HealthKit 数据的日子也会建行，保证评分层能拿到数据；
    /// - 两边数据相加而非互相覆盖，外部量权威在健康 App，打卡权威在本 App；
    /// - 删除打卡后重新合并会清掉本地量，不会留下幽灵总量。
    static func merge(into context: ModelContext, calendar: Calendar = .current) throws {
        let records = try localRecords(in: context)
        var waterByDay: [String: Double] = [:]
        var caffeineByDay: [String: Double] = [:]
        var datesByDay: [String: Date] = [:]
        for record in records {
            guard let kind = SyncableCheckInKind(rawValue: record.kind) else { continue }
            let key = DayKey.key(for: record.date, calendar: calendar)
            switch kind {
            case .water:
                waterByDay[key, default: 0] += record.amountMl
            case .caffeine:
                caffeineByDay[key, default: 0] += record.amountMl
            }
            datesByDay[key] = min(datesByDay[key] ?? record.date, record.date)
        }

        /// 食物识别：按天聚合营养。咖啡因随识别结果一起进入评分总量；
        // 其余指标只留本地记录，健康 App 回写仍走 MealSyncReconciler 的 9 类样本
        //（7 类膳食营养 + 水 + 咖啡因）。
        let meals = try mealRecords(in: context)
        var mealEnergy: [String: Double] = [:]
        var mealCarbs: [String: Double] = [:]
        var mealProtein: [String: Double] = [:]
        var mealFat: [String: Double] = [:]
        var mealFiber: [String: Double] = [:]
        var mealSugar: [String: Double] = [:]
        var mealSodium: [String: Double] = [:]
        var mealCaffeine: [String: Double] = [:]
        // 只有「单独饮用的饮品」的水并入当日饮水总量；饭菜 / 固体食物本身的水不记。
        var mealWater: [String: Double] = [:]
        for meal in meals {
            let key = DayKey.key(for: meal.date, calendar: calendar)
            mealEnergy[key, default: 0] += meal.nutrition.energyKcal
            mealCarbs[key, default: 0] += meal.nutrition.carbsG
            mealProtein[key, default: 0] += meal.nutrition.proteinG
            mealFat[key, default: 0] += meal.nutrition.fatG
            mealFiber[key, default: 0] += meal.nutrition.fiberG
            mealSugar[key, default: 0] += meal.nutrition.sugarG
            mealSodium[key, default: 0] += meal.nutrition.sodiumMg
            mealCaffeine[key, default: 0] += meal.nutrition.caffeineMg
            datesByDay[key] = min(datesByDay[key] ?? meal.date, meal.date)
        }
        // 按逐样食材过滤饮水：按克记的饭菜（咖啡蛋糕、茶叶蛋、水煮鱼…）即使名字里有饮品词，
        // 或营养字段里残留了食物含水量，都不计入饮水；旧记录无分项时用 mealItemsForDisplay 兜底。
        let mealChecksForWater = try context.fetch(
            FetchDescriptor<ActionCheckIn>(predicate: #Predicate<ActionCheckIn> { $0.kindRaw == "meal" })
        )
        for check in mealChecksForWater {
            let key = DayKey.key(for: check.createdAt, calendar: calendar)
            for item in check.mealItemsForDisplay where DrinkIntakeEstimator.isDrink(item) {
                mealWater[key, default: 0] += item.perPortion.waterMl
            }
        }

        // 餐次 / 每餐评分 / 规律饮食：按打卡时间归类，规律判断需要近 7 天数据，
        // 因此对「每一天」都基于全量打卡算一次，避免只算今天导致历史日缺值。
        let mealChecks = try mealEntries(in: context)
        let scoringConfig = ScoringConfig()
        var mealDayKeys = Set(mealEnergy.keys)
        // 咖啡因饮品的营养成分同样属于「饮食」：拿铁的热量 / 碳蛋脂等并入当日饮食汇总，
        // 但咖啡因本身已由 caffeineByDay 统计，这里不再重复累加，也不参与餐次规律判断。
        for record in records where record.kind == SyncableCheckInKind.caffeine.rawValue {
            guard let nutrition = record.nutrition else { continue }
            let key = DayKey.key(for: record.date, calendar: calendar)
            mealEnergy[key, default: 0] += nutrition.energyKcal
            mealCarbs[key, default: 0] += nutrition.carbsG
            mealProtein[key, default: 0] += nutrition.proteinG
            mealFat[key, default: 0] += nutrition.fatG
            mealFiber[key, default: 0] += nutrition.fiberG
            mealSugar[key, default: 0] += nutrition.sugarG
            mealSodium[key, default: 0] += nutrition.sodiumMg
        }
        var scoreSumByDay: [String: Double] = [:]
        var scoreCountByDay: [String: Int] = [:]
        for entry in mealChecks {
            let key = DayKey.key(for: entry.date, calendar: calendar)
            mealDayKeys.insert(key)
            // 旧记录没有存评分时按当前营养重算，保证历史日也有平均分。
            let score = entry.score ?? MealScoringEngine.evaluate(
                nutrition: entry.nutrition, slot: entry.slot, date: entry.date,
                config: scoringConfig, calendar: calendar
            ).score
            scoreSumByDay[key, default: 0] += score
            scoreCountByDay[key, default: 0] += 1
        }
        var regularityByDay: [String: MealRegularity] = [:]
        for key in mealDayKeys {
            guard let day = DayKey.date(from: key, calendar: calendar) else { continue }
            regularityByDay[key] = MealScoringEngine.regularity(
                entries: mealChecks, on: day, config: scoringConfig, calendar: calendar
            )
        }

        let rows = try context.fetch(FetchDescriptor<DailyMetrics>())
        var rowsByKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.dayKey, $0) })
        let allKeys = Set(rowsByKey.keys)
            .union(waterByDay.keys)
            .union(caffeineByDay.keys)
            .union(mealEnergy.keys)
            .union(mealCaffeine.keys)
            .union(mealDayKeys)

        for key in allKeys {
            let row: DailyMetrics
            if let existing = rowsByKey[key] {
                row = existing
            } else {
                let date = datesByDay[key]
                    ?? DayKey.date(from: key, calendar: calendar)
                    ?? .now
                row = DailyMetrics(dayKey: key, date: calendar.startOfDay(for: date))
                context.insert(row)
                rowsByKey[key] = row
            }

            let localWater = waterByDay[key]
            let localCaffeine = caffeineByDay[key]
            row.localWaterMl = localWater
            row.localCaffeineMg = localCaffeine

            let waterTotal = (row.externalWaterMl ?? 0) + (localWater ?? 0) + (mealWater[key] ?? 0)
            row.waterTotalMl = waterTotal > 0 ? waterTotal : nil
            // dietaryCaffeineMg 是评分/AI/展示统一消费的「合并总量」：
            // 健康 App 外部量 + 本 App 咖啡因打卡 + 食物识别附带的咖啡因。
            // 识别记录不会把咖啡因样本写回健康 App，因此三者不会重复计入。
            let caffeineTotal = (row.externalCaffeineMg ?? 0) + (localCaffeine ?? 0) + (mealCaffeine[key] ?? 0)
            row.dietaryCaffeineMg = caffeineTotal > 0 ? caffeineTotal : nil

            // 膳食营养：外部量（来自健康 App）先扣掉上一轮本地量，再加上本轮本地量，
            // 保证多次合并不会把本地meal重复累加（外部量权威在健康 App，本地量权威在本 App）。
            let newMeal = MealNutrition(
                energyKcal: mealEnergy[key] ?? 0,
                carbsG: mealCarbs[key] ?? 0,
                proteinG: mealProtein[key] ?? 0,
                fatG: mealFat[key] ?? 0,
                fiberG: mealFiber[key] ?? 0,
                sugarG: mealSugar[key] ?? 0,
                sodiumMg: mealSodium[key] ?? 0
            )
            let prevMeal = MealNutrition(
                energyKcal: row.localMealEnergyKcal ?? 0,
                carbsG: row.localMealCarbsG ?? 0,
                proteinG: row.localMealProteinG ?? 0,
                fatG: row.localMealFatG ?? 0,
                fiberG: row.localMealFiberG ?? 0,
                sugarG: row.localMealSugarG ?? 0,
                sodiumMg: row.localMealSodiumMg ?? 0
            )
            func mergeField(externalTotal: Double?, prevLocal: Double, newLocal: Double) -> Double? {
                NutritionMerge.total(stored: externalTotal, previousLocal: prevLocal, currentLocal: newLocal)
            }
            row.dietaryEnergyKcal = mergeField(externalTotal: row.dietaryEnergyKcal, prevLocal: prevMeal.energyKcal, newLocal: newMeal.energyKcal)
            row.dietaryCarbsG = mergeField(externalTotal: row.dietaryCarbsG, prevLocal: prevMeal.carbsG, newLocal: newMeal.carbsG)
            row.dietaryProteinG = mergeField(externalTotal: row.dietaryProteinG, prevLocal: prevMeal.proteinG, newLocal: newMeal.proteinG)
            row.dietaryFatG = mergeField(externalTotal: row.dietaryFatG, prevLocal: prevMeal.fatG, newLocal: newMeal.fatG)
            row.dietaryFiberG = mergeField(externalTotal: row.dietaryFiberG, prevLocal: prevMeal.fiberG, newLocal: newMeal.fiberG)
            row.dietarySugarG = mergeField(externalTotal: row.dietarySugarG, prevLocal: prevMeal.sugarG, newLocal: newMeal.sugarG)
            row.dietarySodiumMg = mergeField(externalTotal: row.dietarySodiumMg, prevLocal: prevMeal.sodiumMg, newLocal: newMeal.sodiumMg)
            row.localMealEnergyKcal = newMeal.energyKcal > 0 ? newMeal.energyKcal : nil
            row.localMealCarbsG = newMeal.carbsG > 0 ? newMeal.carbsG : nil
            row.localMealProteinG = newMeal.proteinG > 0 ? newMeal.proteinG : nil
            row.localMealFatG = newMeal.fatG > 0 ? newMeal.fatG : nil
            row.localMealFiberG = newMeal.fiberG > 0 ? newMeal.fiberG : nil
            row.localMealSugarG = newMeal.sugarG > 0 ? newMeal.sugarG : nil
            row.localMealSodiumMg = newMeal.sodiumMg > 0 ? newMeal.sodiumMg : nil

            // 餐次汇总：没有饮食打卡的日子清空，避免删除记录后留下旧的规律评分。
            if let count = scoreCountByDay[key], count > 0 {
                row.mealCount = count
                row.mealAverageScore = (scoreSumByDay[key] ?? 0) / Double(count)
                row.mealCoveredMainMeals = regularityByDay[key]?.coveredMainMeals.count ?? 0
                row.mealRegularityScore = regularityByDay[key]?.score
            } else {
                row.mealCount = nil
                row.mealAverageScore = nil
                row.mealCoveredMainMeals = nil
                row.mealRegularityScore = nil
            }

            // 饮食记录只带水量（纯水 / 无糖饮品）也算营养维度的数据源，
            // 否则当天会出现「有饮水量却没有营养数据」的空档。
            if localWater != nil || localCaffeine != nil || newMeal.hasAny
                || (mealWater[key] ?? 0) > 0 || (mealCaffeine[key] ?? 0) > 0
                || row.externalWaterMl != nil || row.externalCaffeineMg != nil {
                row.sourceFlags |= MetricSource.nutrition.rawValue
            }
            row.updatedAt = .now
        }
        try context.save()
    }
}

/// 7 项膳食营养的轻量聚合值，仅用于 WaterMerge 内部按天合并，不参与持久化。
struct MealNutrition: Sendable, Equatable {
    var energyKcal: Double
    var carbsG: Double
    var proteinG: Double
    var fatG: Double
    var fiberG: Double
    var sugarG: Double
    var sodiumMg: Double

    var hasAny: Bool {
        energyKcal > 0 || carbsG > 0 || proteinG > 0 || fatG > 0
            || fiberG > 0 || sugarG > 0 || sodiumMg > 0
    }
}

/// 打卡增/删后的即时同步入口：写回健康 App → 合并本地总量 → 重算评分。
@MainActor
enum WaterCheckInSync {
    /// 只接收 Sendable 的值对象，避免把 SwiftData model 跨并发域传递。
    static func push(
        record: WaterSyncRecord,
        context: ModelContext,
        calendar: Calendar = .current
    ) async {
        let service = HealthKitService()
        do {
            let written = try await service.saveCheckIn(record)
            let title = SyncableCheckInKind(rawValue: record.kind)?.title ?? "打卡"
            WaterSyncStatus.set(written ? "\(title)已写回健康 App" : "两侧已一致，无需重复写入")
        } catch {
            WaterSyncStatus.set("写回健康 App 失败：\(error.localizedDescription)")
        }
        await refresh(context: context, calendar: calendar)
    }

    static func remove(
        syncID: String?,
        kind: String,
        context: ModelContext,
        calendar: Calendar = .current
    ) async {
        if let syncID {
            let service = HealthKitService()
            do {
                try await service.deleteCheckIn(syncID: syncID, kind: kind)
                WaterSyncStatus.set("已从健康 App 删除对应记录")
            } catch {
                WaterSyncStatus.set("同步删除失败：\(error.localizedDescription)")
            }
        }
        await refresh(context: context, calendar: calendar)
    }

    /// 合并 + 全量重算，保证评分、AI 载荷读取到的始终是合并后的总量。
    /// 重算在后台执行且无变化时不落库，打卡后不会卡住主线程或触发全量重绘。
    static func refresh(context: ModelContext, calendar: Calendar = .current) async {
        do {
            try WaterMerge.merge(into: context, calendar: calendar)
            try await ScoreStore.recomputeAll(in: context, calendar: calendar)
        } catch {
            WaterSyncStatus.set("本地汇总失败：\(error.localizedDescription)")
        }
    }
}

/// 食物识别打卡的写回入口：写回健康 App → 合并本地总量 → 重算评分。
@MainActor
enum MealCheckInSync {
    static func push(
        record: MealSyncRecord,
        context: ModelContext,
        calendar: Calendar = .current
    ) async {
        let service = HealthKitService()
        do {
            let written = try await service.saveMeal(record)
            WaterSyncStatus.set(written ? "膳食已写回健康 App" : "两侧已一致，无需重复写入")
        } catch {
            WaterSyncStatus.set("写回健康 App 失败：\(error.localizedDescription)")
        }
        await WaterCheckInSync.refresh(context: context, calendar: calendar)
    }

    static func remove(
        syncID: String,
        context: ModelContext,
        calendar: Calendar = .current
    ) async {
        let service = HealthKitService()
        do {
            try await service.deleteMeal(syncID: syncID)
            WaterSyncStatus.set("已从健康 App 删除对应膳食记录")
        } catch {
            WaterSyncStatus.set("同步删除失败：\(error.localizedDescription)")
        }
        await WaterCheckInSync.refresh(context: context, calendar: calendar)
    }
}

// configured by qoder
