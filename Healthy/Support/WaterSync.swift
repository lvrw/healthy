import Foundation

/// 支持双向同步到健康 App 的打卡类型。值与 ActionCheckIn.kindRaw 一致。
enum SyncableCheckInKind: String, Sendable, CaseIterable {
    case water
    case caffeine

    /// 设置页/说明文案使用。
    var title: String {
        switch self {
        case .water: return "喝水量"
        case .caffeine: return "咖啡因摄入"
        }
    }

    /// 写入 HealthKit 时的数量单位说明。
    var unitLabel: String {
        switch self {
        case .water: return "毫升"
        case .caffeine: return "毫克"
        }
    }
}

/// 本 App 写回 HealthKit 的打卡样本标记，以及两侧对账的纯逻辑。
/// 这里刻意不 import HealthKit：读写样本由 HealthKitService 负责，
/// 判定规则全部收敛成可单元测试的纯函数。
enum WaterSyncMetadata {
    /// 喝水样本沿用最初的常量，保证已写入真机的样本仍能被识别/对账。
    static let syncIdentifierPrefix = "cn.rw.healthy.water."
    static let originKey = "cn.rw.healthy.water.origin"
    static let originValue = "HealthyWaterCheckIn"
    /// 咖啡因打卡使用独立前缀与来源标记，和喝水互不干扰。
    static let caffeineSyncIdentifierPrefix = "cn.rw.healthy.caffeine."
    static let caffeineOriginKey = "cn.rw.healthy.caffeine.origin"
    static let caffeineOriginValue = "HealthyCaffeineCheckIn"
    /// 食物识别写回使用独立前缀与来源标记，和喝水 / 咖啡因互不干扰。
    static let mealSyncIdentifierPrefix = "cn.rw.healthy.meal."
    static let mealOriginKey = "cn.rw.healthy.meal.origin"
    static let mealOriginValue = "HealthyMealCheckIn"
    /// 用户原始文字描述（含拍照备注）写回样本 metadata，便于在健康 App 回溯来源。
    static let mealNoteKey = "cn.rw.healthy.meal.note"
    /// HKMetadataKeySyncVersion 的起始值；金额被本地修改后重写时递增。
    static let initialSyncVersion = 1

    static func prefix(for kind: String) -> String {
        if kind == SyncableCheckInKind.caffeine.rawValue { return caffeineSyncIdentifierPrefix }
        if kind == "meal" { return mealSyncIdentifierPrefix }
        return syncIdentifierPrefix
    }

    static func originKey(for kind: String) -> String {
        if kind == SyncableCheckInKind.caffeine.rawValue { return caffeineOriginKey }
        if kind == "meal" { return mealOriginKey }
        return originKey
    }

    static func originValue(for kind: String) -> String {
        if kind == SyncableCheckInKind.caffeine.rawValue { return caffeineOriginValue }
        if kind == "meal" { return mealOriginValue }
        return originValue
    }

    /// 由本地打卡 ID 生成幂等的同步标识。
    static func syncIdentifier(
        for localID: String,
        kind: String = SyncableCheckInKind.water.rawValue
    ) -> String {
        prefix(for: kind) + localID
    }

    /// 从样本 metadata 中还原本地打卡 ID；非本 App 样本返回 nil。
    static func localID(
        from syncIdentifier: String?,
        kind: String = SyncableCheckInKind.water.rawValue
    ) -> String? {
        let key = prefix(for: kind)
        guard let syncIdentifier, syncIdentifier.hasPrefix(key) else { return nil }
        let id = String(syncIdentifier.dropFirst(key.count))
        return id.isEmpty ? nil : id
    }

    /// 由自定义来源标记反查打卡类型，用于读取时排除本 App 回写的样本。
    static func kind(from origin: String?) -> String? {
        if origin == originValue { return SyncableCheckInKind.water.rawValue }
        if origin == caffeineOriginValue { return SyncableCheckInKind.caffeine.rawValue }
        if origin == mealOriginValue { return "meal" }
        return nil
    }

    /// 是否为「本 App 写回 HealthKit」的样本。
    /// 读取健康 App 的水量/咖啡因时必须排除这类样本，否则 A→B→A 会重复计入。
    static func isSelfEcho(origin: String?, sourceBundleID: String?, appBundleID: String?) -> Bool {
        if kind(from: origin) != nil { return true }
        guard let appBundleID, !appBundleID.isEmpty else { return false }
        return sourceBundleID == appBundleID
    }
}

/// 一条本地打卡（本 App 记录是这一侧的权威）。
struct WaterSyncRecord: Sendable, Equatable, Identifiable {
    /// 本地持久化 ID，同时用作 HealthKit 同步标识后缀。
    var syncID: String
    /// 本次数量：喝水为毫升，咖啡因为毫克。
    var amountMl: Double
    /// 打卡发生时间。
    var date: Date
    /// ActionCheckIn.kindRaw，默认沿用历史喝水行为。
    var kind: String = SyncableCheckInKind.water.rawValue
    /// 咖啡因饮品附带的碳水 / 蛋白质 / 脂肪（克）；喝水与手动输入为 nil。
    /// 写回健康 App 时会与主样本一起生成同 syncID 的营养样本，删除时一并清理。
    var nutrition: IntakeNutrition? = nil

    var id: String { syncID }
}

/// HealthKit 里一条「本 App 写回」的样本。
struct WaterSyncSample: Sendable, Equatable, Identifiable {
    /// 从 HKMetadataKeySyncIdentifier 还原出来的本地打卡 ID。
    var syncID: String
    /// 样本记录的数量（毫升 / 毫克）。
    var amountMl: Double
    /// 样本开始时间。
    var date: Date
    /// HKObject.uuid 的字符串形式，删除时据此找回样本对象。
    var uuid: String
    /// HKMetadataKeySyncVersion，用于重写时递增。
    var syncVersion: Int
    var kind: String = SyncableCheckInKind.water.rawValue

    var id: String { uuid }
}

/// 对账结果：先执行 toDelete，再执行 toSave，避免同一 syncID 短暂重复。
struct WaterSyncPlan: Sendable, Equatable {
    /// 本地有、HealthKit 缺少或金额/时间已变化的打卡，需要写入（重写时先删后写）。
    var toSave: [WaterSyncRecord] = []
    /// 需要删除的 HealthKit 样本：孤儿、重复、或与本地不一致的旧值。
    var toDelete: [WaterSyncSample] = []
    /// 两侧完全一致的记录条数。
    var unchangedCount: Int = 0
    /// 因金额/时间变化被替换的条数（统计用）。
    var replacedCount: Int = 0
    /// 被清理的重复样本条数（统计用）。
    var duplicateCount: Int = 0

    var isEmpty: Bool { toSave.isEmpty && toDelete.isEmpty }

    /// 供 UI 展示的一行结果摘要。
    var summary: String {
        if isEmpty { return "两侧一致（\(unchangedCount) 条）" }
        return "写入 \(toSave.count) 条 · 删除 \(toDelete.count) 条 · 一致 \(unchangedCount) 条"
    }
}

enum WaterSyncReconciler {
    /// 浮点容差：HealthKit 会把毫升换算成升再取回，允许 0.5 级误差。
    private static let amountToleranceMl = 0.5
    /// 时间容差（秒）：同一条打卡允许系统时间取整带来的偏差。
    private static let dateToleranceSeconds: TimeInterval = 1.0

    /// 生成本地打卡与 HealthKit 回写样本之间的差异计划。
    ///
    /// 冲突规则：
    /// 1. 本地打卡是「本 App 记录」的唯一权威，金额/时间不一致时以本地为准（删旧 + 写新）；
    /// 2. HealthKit 里有、本地已删除的样本视为孤儿，直接删除；
    /// 3. 同一 syncID 出现多条样本时保留一条，其余删除，消除重复记录；
    /// 4. 不带本 App 同步标识的外部样本（健康 App 手动录入 / 第三方）不在这里处理，
    ///    它们只参与「外部量」读取，永远不会被修改或删除。
    static func reconcile(
        local: [WaterSyncRecord],
        remote: [WaterSyncSample]
    ) -> WaterSyncPlan {
        var plan = WaterSyncPlan()
        let localByID = Dictionary(local.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })

        var grouped: [String: [WaterSyncSample]] = [:]
        for sample in remote {
            grouped[sample.syncID, default: []].append(sample)
        }

        for (syncID, samples) in grouped {
            let ordered = samples.sorted { lhs, rhs in
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.uuid < rhs.uuid
            }
            guard let record = localByID[syncID] else {
                // 本地已删除：所有同名样本都是孤儿。
                plan.toDelete.append(contentsOf: ordered)
                continue
            }

            // 优先保留与本地值一致的那条；否则保留最后一条并在下面整体重写。
            let matching = ordered.filter { matches($0, record) }
            let keeper = matching.last ?? ordered.last
            let duplicates = ordered.filter { $0.uuid != keeper?.uuid }
            plan.toDelete.append(contentsOf: duplicates)
            plan.duplicateCount += duplicates.count

            if matching.isEmpty, let keeper {
                // 值不一致：删掉唯一保留的旧样本，按本地值重写。
                plan.toDelete.append(keeper)
                plan.replacedCount += 1
                plan.toSave.append(record)
            } else {
                plan.unchangedCount += 1
            }
        }

        for record in local where grouped[record.syncID] == nil {
            plan.toSave.append(record)
        }

        // 同一 UUID 只能删一次：按 UUID 去重可以保证 plan 幂等。
        var seen: Set<String> = []
        plan.toDelete = plan.toDelete.filter { seen.insert($0.uuid).inserted }
        return plan
    }

    /// 样本与本地打卡是否等价（金额、时间都在容差内）。
    static func matches(_ sample: WaterSyncSample, _ record: WaterSyncRecord) -> Bool {
        abs(sample.amountMl - record.amountMl) <= amountToleranceMl
            && abs(sample.date.timeIntervalSince(record.date)) <= dateToleranceSeconds
    }

    /// 重写同一条记录时应写入的 syncVersion（避免与刚删除的旧版本混淆）。
    static func nextSyncVersion(after samples: [WaterSyncSample]) -> Int {
        max(WaterSyncMetadata.initialSyncVersion, (samples.map(\.syncVersion).max() ?? 0) + 1)
    }
}

// MARK: - 食物识别写回类型

/// 一顿饭写回 HealthKit 的本地权威记录（本 App 的 ActionCheckIn 是唯一来源）。
/// 与 WaterSyncRecord 不同：一顿饭没有「单一数量」，而是 7 类膳食样本，
/// 全部共用 syncID / origin 标记，删除时按 syncID 一并清理。
struct MealSyncRecord: Sendable, Equatable, Identifiable {
    /// 本地打卡 ID，同时用作 7 类样本的 syncID 后缀。
    var syncID: String
    /// 用餐发生时间（作为 7 类样本的 startDate）。
    var date: Date
    /// 完整 7 项营养（能量 / 碳水 / 蛋白 / 脂肪 / 纤维 / 糖 / 钠）。
    var nutrition: IntakeNutrition
    /// 识别来源：ai / local，仅作记录与 UI 展示。
    var source: String = "local"
    /// 用户原始文字描述（含拍照时的备注），回写到样本 metadata 便于回溯。
    var note: String?
    var kind: String = "meal"

    var id: String { syncID }
}

/// HealthKit 里一条「本 App 写回」的膳食样本（一组 7 类样本聚合后的视图）。
struct MealSyncSample: Sendable, Equatable, Identifiable {
    /// 由 syncID 聚合出的本地打卡 ID。
    var syncID: String
    /// 该 syncID 下全部 7 类样本的 uuid，删除时据此一并清理。
    var uuids: [String]
    /// 样本开始时间（取能量样本的时间）。
    var date: Date
    /// 7 类样本的聚合营养值。
    var nutrition: IntakeNutrition
    /// HKMetadataKeySyncVersion，重写时递增。
    var syncVersion: Int
    var kind: String = "meal"

    var id: String { syncID }
}

/// 膳食对账计划：先删后写，避免同一 syncID 短暂重复。
struct MealSyncPlan: Sendable, Equatable {
    /// 本地有、HealthKit 缺少或营养值已变化的打卡，需要写入（重写时先删后写）。
    var toSave: [MealSyncRecord] = []
    /// 需要删除的 HealthKit 样本组：孤儿、重复、或与本地不一致的旧值。
    var toDelete: [MealSyncSample] = []
    /// 两侧完全一致的记录条数。
    var unchangedCount: Int = 0
    /// 被清理的重复样本组数（统计用）。
    var duplicateCount: Int = 0

    var isEmpty: Bool { toSave.isEmpty && toDelete.isEmpty }

    var summary: String {
        if isEmpty { return "两侧一致（\(unchangedCount) 条）" }
        return "写入 \(toSave.count) 条 · 删除 \(toDelete.count) 组 · 一致 \(unchangedCount) 条"
    }
}

enum MealSyncReconciler {
    /// 各营养字段的容差：HealthKit 会按单位取整回取，允许小幅误差。
    private static let energyToleranceKcal = 1.0
    private static let gramTolerance = 0.5
    private static let sodiumToleranceMg = 5.0
    private static let dateToleranceSeconds: TimeInterval = 1.0

    /// 生成本地膳食打卡与 HealthKit 回写之间的对账计划。规则与 WaterSyncReconciler 一致：
    /// 本地是唯一权威；孤儿删、重复删、值变化重写、缺失补写。
    static func reconcile(
        local: [MealSyncRecord],
        remote: [MealSyncSample]
    ) -> MealSyncPlan {
        var plan = MealSyncPlan()
        let localByID = Dictionary(local.map { ($0.syncID, $0) }, uniquingKeysWith: { first, _ in first })

        var grouped: [String: [MealSyncSample]] = [:]
        for sample in remote {
            grouped[sample.syncID, default: []].append(sample)
        }

        for (syncID, samples) in grouped {
            guard let record = localByID[syncID] else {
                plan.toDelete.append(contentsOf: samples)
                continue
            }
            // 重复样本组：保留最后一条，其余视为重复清理。
            let ordered = samples.sorted { $0.syncVersion < $1.syncVersion || ($0.syncVersion == $1.syncVersion && $0.uuids.joined() < $1.uuids.joined()) }
            let keeper = ordered.last
            let duplicates = ordered.dropLast()
            plan.toDelete.append(contentsOf: duplicates)
            plan.duplicateCount += duplicates.count

            if let keeper, !matches(keeper, record) {
                plan.toDelete.append(keeper)
                plan.toSave.append(record)
            } else if keeper == nil {
                plan.toSave.append(record)
            } else {
                plan.unchangedCount += 1
            }
        }

        for record in local where grouped[record.syncID] == nil {
            plan.toSave.append(record)
        }

        // 同一 uuid 只能删一次：去重保证幂等。
        var seen: Set<String> = []
        plan.toDelete = plan.toDelete.compactMap { group in
            let kept = group.uuids.filter { seen.insert($0).inserted }
            return kept.isEmpty ? nil : MealSyncSample(
                syncID: group.syncID,
                uuids: kept,
                date: group.date,
                nutrition: group.nutrition,
                syncVersion: group.syncVersion
            )
        }
        return plan
    }

    /// 膳食样本与本地打卡是否等价（7 项营养与时间都在容差内）。
    static func matches(_ sample: MealSyncSample, _ record: MealSyncRecord) -> Bool {
        abs(sample.nutrition.energyKcal - record.nutrition.energyKcal) <= energyToleranceKcal
            && abs(sample.nutrition.carbsG - record.nutrition.carbsG) <= gramTolerance
            && abs(sample.nutrition.proteinG - record.nutrition.proteinG) <= gramTolerance
            && abs(sample.nutrition.fatG - record.nutrition.fatG) <= gramTolerance
            && abs(sample.nutrition.fiberG - record.nutrition.fiberG) <= gramTolerance
            && abs(sample.nutrition.sugarG - record.nutrition.sugarG) <= gramTolerance
            && abs(sample.nutrition.sodiumMg - record.nutrition.sodiumMg) <= sodiumToleranceMg
            && abs(sample.date.timeIntervalSince(record.date)) <= dateToleranceSeconds
    }

    /// 重写同一 syncID 时应写入的 syncVersion。
    static func nextSyncVersion(after samples: [MealSyncSample]) -> Int {
        max(WaterSyncMetadata.initialSyncVersion, (samples.map(\.syncVersion).max() ?? 0) + 1)
    }
}

// configured by qoder
