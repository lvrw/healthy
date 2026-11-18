import Foundation
import HealthKit
import SwiftData

@MainActor
final class SyncCoordinator {
    enum Reason {
        case launch
        case manual
        case fullBackfill
    }

    static let schemaVersionKey = "healthy.syncSchemaVersion"
    /// v6：新增饮水与饮食字段。
    /// v7：dietaryCaffeineMg 改为「外部 + 本 App 打卡」合并总量，新增 external/local
    /// 拆分字段，老用户需全量回填 118 天，避免历史咖啡因被误清零。
    /// v8：DailyMetrics 新增 basalEnergyKcal（静息能量），老用户需全量回填历史日
    /// 才能算出基础代谢的近 28 天均值。
    /// v9：活动 / 锻炼 / 站立改用 HKActivitySummary 官方圆环口径，并新增三个圆环目标
    /// 字段；老用户需全量回填历史日，让历史三环也和健身 App 对齐。
    static let currentSchemaVersion = 9
    static let authVersionKey = "healthy.authSchemaVersion"
    /// v4：readTypes 补上出生日期 / 性别两个 HKCharacteristicType。
    /// v5：readTypes 补上饮食 / 饮水类型，并首次申请 dietaryWater 写入权限。
    /// v6：writeTypes 增加 dietaryCaffeine，老用户需重新走一次授权请求
    /// （拒绝写入不影响只读同步）。
    /// v7：writeTypes 增加碳水 / 蛋白质 / 脂肪，饮品快捷项要一次写入 4 类样本。
    /// v8：writeTypes 增加膳食能量 / 膳食纤维 / 糖 / 钠，一顿饭要一次写入 7 类样本。
    /// v9：readTypes 增加 basalEnergyBurned（静息能量），老用户需重新授权一次。
    /// v10：readTypes 增加 HKActivitySummaryType（健身圆环摘要），老用户需重新授权一次。
    static let currentAuthVersion = 10

    private let service: HealthKitService
    private let context: ModelContext
    private let calendar: Calendar
    private let lastSyncKey = "healthy.lastSyncAt"

    init(service: HealthKitService = HealthKitService(), context: ModelContext, calendar: Calendar = .current) {
        self.service = service
        self.context = context
        self.calendar = calendar
    }

    func requestAuthorization() async throws -> Bool {
        try await service.requestAuthorization()
    }

    func shouldSyncOnActivate() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastSyncKey) as? Date else {
            return true
        }
        return Date.now.timeIntervalSince(last) > 600
    }

    func sync(reason: Reason) async throws -> Int {
        let perfToken = PerformanceTrace.shared.begin(
            "同步 · 全量 (\(reason == .manual ? "手动" : reason == .fullBackfill ? "回填" : "启动"))",
            category: .sync
        )
        defer { PerformanceTrace.shared.end(perfToken) }
        let status = await service.authorizationRequestStatus()
        guard status == .unnecessary else {
            throw HealthKitError.authorizationRequired
        }

        let days: Int
        switch reason {
        case .manual, .fullBackfill:
            days = 118
        case .launch:
            let count = try context.fetchCount(FetchDescriptor<DailyMetrics>())
            days = count == 0 ? 118 : 3
        }

        appLog(.info, "Sync", "开始同步 reason=\(reason) days=\(days) tz=\(calendar.timeZone.identifier)")
        // 训练心率区间需要最大心率：由本机/健康档案年龄推算（Tanaka 公式 208 − 0.7×年龄）。
        let maxHeartRate = UserProfile.load().effective(healthKitAge: nil, healthKitMale: nil).chronologicalAge
            .map { 208 - 0.7 * $0 }
        let dtos = try await service.fetchDailyMetrics(days: days, calendar: calendar, maxHeartRate: maxHeartRate)
        let existing = try context.fetch(FetchDescriptor<DailyMetrics>())
        var rowsByKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.dayKey, $0) })
        var inserted = 0

        for dto in dtos where dto.sourceFlags != 0 {
            if let row = rowsByKey[dto.dayKey] {
                row.apply(dto)
            } else {
                let row = DailyMetrics(dayKey: dto.dayKey, date: dto.date)
                row.apply(dto)
                context.insert(row)
                rowsByKey[dto.dayKey] = row
                inserted += 1
            }
            // DTO 的 dietary* 是纯外部量；清掉本地 meal 快照，
            // 让接下来的 WaterMerge 从「纯外部量 + 本轮本地量」重新合并。
            rowsByKey[dto.dayKey]?.clearLocalMealSnapshot()
        }

        try context.save()

        // 双向同步：先把本地打卡合并进每日快照，再与 HealthKit 做全量对账。
        // 对账失败（例如用户没有授予写入权限）不阻断只读同步与评分。
        try WaterMerge.merge(into: context, calendar: calendar)
        await reconcileWater()
        try await ScoreStore.recomputeAll(in: context, calendar: calendar)
        UserDefaults.standard.set(Date.now, forKey: lastSyncKey)
        UserDefaults.standard.set(Self.currentSchemaVersion, forKey: Self.schemaVersionKey)
        let todayKey = DayKey.key(for: DayKey.startOfDay(.now), calendar: calendar)
        appLog(
            .info, "Sync",
            "同步完成 reason=\(reason) dtos=\(dtos.count) inserted=\(inserted) "
            + "todaySteps=\(rowsByKey[todayKey]?.steps.map { Int($0.rounded()) }.map(String.init) ?? "nil")"
        )
        return inserted
    }

    /// 只刷新今日步数（回前台时走这条轻量通道，不读整套健康指标）。
    /// 步数是当天增长最快的累计型指标，不能等整体同步的 10 分钟节流。
    func refreshTodaySteps() async {
        let perfToken = PerformanceTrace.shared.begin("同步 · 今日步数刷新", category: .sync)
        defer { PerformanceTrace.shared.end(perfToken) }
        guard let steps = await service.todayStepCount(calendar: calendar) else {
            appLog(.debug, "Sync", "今日步数刷新：HealthKit 返回 nil（可能未授权或今日无数据）")
            return
        }
        let key = DayKey.key(for: DayKey.startOfDay(.now, calendar: calendar), calendar: calendar)
        do {
            let rows = try context.fetch(FetchDescriptor<DailyMetrics>())
            guard let row = rows.first(where: { $0.dayKey == key }) else {
                appLog(.warning, "Sync", "今日步数刷新：本地尚无 \(key) 行，跳过（等下次同步建行）")
                return
            }
            let old = row.steps
            row.steps = steps
            row.updatedAt = .now
            try context.save()
            appLog(
                .info, "Sync",
                "今日步数刷新 \(key): \(old.map { Int($0.rounded()) }.map(String.init) ?? "nil") → \(Int(steps.rounded()))"
            )
            try await ScoreStore.recomputeAll(in: context, calendar: calendar)
        } catch {
            appLog(.error, "Sync", "今日步数刷新失败: \(error.localizedDescription)")
        }
    }

    /// 只刷新今日健身三环（活动 / 锻炼 / 站立）与圆环目标：与健身 App 官方摘要同源。
    /// 三环增长最快且用户最常和健身 App 对数，不能等整体同步的 10 分钟节流。
    func refreshTodayActivityRings() async {
        let perfToken = PerformanceTrace.shared.begin("同步 · 今日三环刷新", category: .sync)
        defer { PerformanceTrace.shared.end(perfToken) }
        guard let ring = await service.todayActivitySummary(calendar: calendar) else {
            appLog(.debug, "Sync", "今日三环刷新：无活动摘要（可能未授权或今天没有健身记录）")
            return
        }
        let key = DayKey.key(for: DayKey.startOfDay(.now, calendar: calendar), calendar: calendar)
        do {
            let rows = try context.fetch(FetchDescriptor<DailyMetrics>())
            guard let row = rows.first(where: { $0.dayKey == key }) else {
                appLog(.warning, "Sync", "今日三环刷新：本地尚无 \(key) 行，跳过")
                return
            }
            row.activeEnergy = ring.activeEnergyKcal
            row.exerciseMinutes = ring.exerciseMinutes
            row.standMinutes = ring.standHours * 60
            row.activeEnergyGoal = ring.activeGoalKcal
            row.exerciseGoalMinutes = ring.exerciseGoalMinutes
            row.standGoalHours = ring.standGoalHours
            row.updatedAt = .now
            try context.save()
            appLog(
                .info, "Sync",
                "今日三环刷新 \(key): 能量=\(Int(ring.activeEnergyKcal)) 卡 锻炼=\(Int(ring.exerciseMinutes)) 分 站立=\(Int(ring.standHours)) 小时"
            )
            try await ScoreStore.recomputeAll(in: context, calendar: calendar)
        } catch {
            appLog(.error, "Sync", "今日三环刷新失败: \(error.localizedDescription)")
        }
    }

    /// 授权完成后补一次对账：把授权前攒下的打卡写回健康 App。
    func reconcileWaterAfterAuthorization() async {
        do {
            try WaterMerge.merge(into: context, calendar: calendar)
        } catch {
            WaterSyncStatus.set("本地汇总失败：\(error.localizedDescription)")
        }
        await reconcileWater()
    }

    /// 设置页「立即对账」：不重读全部健康指标，只做本地合并 + 喝水双向对账 + 重算评分。
    func reconcileWaterNow() async {
        do {
            try WaterMerge.merge(into: context, calendar: calendar)
            await reconcileWater()
            try await ScoreStore.recomputeAll(in: context, calendar: calendar)
        } catch {
            WaterSyncStatus.set("喝水对账失败：\(error.localizedDescription)")
        }
    }

    /// 健康 App 侧喝水数据变化时的轻量刷新：只重读近 3 天饮食/饮水，
    /// 再合并本地打卡、全量对账、重算评分。窗口内被删掉的外部记录会同步清空，
    /// 避免健康 App 里撤销一笔水之后本 App 还留着旧值。
    func syncNutritionOnly(days: Int = 3) async throws {
        let perfToken = PerformanceTrace.shared.begin("同步 · 仅营养 \(days) 天", category: .sync)
        defer { PerformanceTrace.shared.end(perfToken) }
        let nutrition = try await service.fetchNutrition(days: days, calendar: calendar)
        let today = DayKey.startOfDay(.now, calendar: calendar)
        var windowKeys: Set<String> = []
        for index in 0..<days {
            let date = DayKey.addingDays(-index, to: today, calendar: calendar)
            windowKeys.insert(DayKey.key(for: date, calendar: calendar))
        }

        let rows = try context.fetch(FetchDescriptor<DailyMetrics>())
        var rowsByKey = Dictionary(uniqueKeysWithValues: rows.map { ($0.dayKey, $0) })
        for key in windowKeys {
            let row: DailyMetrics
            if let existing = rowsByKey[key] {
                row = existing
            } else {
                let date = DayKey.date(from: key, calendar: calendar) ?? today
                row = DailyMetrics(dayKey: key, date: date)
                context.insert(row)
                rowsByKey[key] = row
            }
            let day = nutrition[key]
            row.externalWaterMl = day?.externalWaterMl
            // 下面 7 项写入的是「健康 App 纯外部量」，不是上一轮的合并总量。
            // WaterMerge 会按「存储值 − 上一轮本地 meal 量 + 本轮本地 meal 量」重算，
            // 所以必须先清掉上一轮本地快照，否则外部量会被再扣一次，把本 App 食物打卡
            // 的热量抵消成 0（行动页饮食卡因此一直显示「—」）。
            row.clearLocalMealSnapshot()
            row.dietaryEnergyKcal = day?.energyKcal
            row.dietaryCarbsG = day?.carbsG
            row.dietaryProteinG = day?.proteinG
            row.dietaryFatG = day?.fatG
            row.dietaryFiberG = day?.fiberG
            row.dietarySugarG = day?.sugarG
            row.dietarySodiumMg = day?.sodiumMg
            row.externalCaffeineMg = day?.caffeineMg
            if day?.hasData == true {
                row.sourceFlags |= MetricSource.nutrition.rawValue
            } else {
                row.sourceFlags &= ~MetricSource.nutrition.rawValue
            }
            row.updatedAt = .now
        }
        try context.save()
        try WaterMerge.merge(into: context, calendar: calendar)
        await reconcileWater()
        try await ScoreStore.recomputeAll(in: context, calendar: calendar)
    }

    private func reconcileWater() async {
        do {
            let records = try WaterMerge.localRecords(in: context)
            let water = records.filter { $0.kind == SyncableCheckInKind.water.rawValue }
            let caffeine = records.filter { $0.kind == SyncableCheckInKind.caffeine.rawValue }
            let waterPlan = try await service.reconcileWater(localRecords: water)
            let caffeinePlan = try await service.reconcileCaffeine(localRecords: caffeine)
            var summary = "喝水：\(waterPlan.summary) · 咖啡因：\(caffeinePlan.summary)"
            if let mealPlan = try? await service.reconcileMeals(localRecords: WaterMerge.mealRecords(in: context)) {
                summary += " · 膳食：\(mealPlan.summary)"
            }
            WaterSyncStatus.set(summary)
        } catch let error as HealthKitError where error.isWriteAuthorizationRequired {
            WaterSyncStatus.set(error.localizedDescription)
        } catch {
            WaterSyncStatus.set("喝水对账失败：\(error.localizedDescription)")
        }
    }
}

extension HealthKitError {
    /// 写权限缺失是可预期的降级，不该被当成同步整体失败。
    var isWriteAuthorizationRequired: Bool {
        if case .writeAuthorizationRequired = self { return true }
        return false
    }
}
