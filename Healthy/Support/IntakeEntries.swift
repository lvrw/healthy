import Foundation

/// 一条摄入记录来自哪里。
/// - healthKit：健康 App 数据库里的样本（健康 App 手动录入、第三方 App、本 App 回写都算）；
/// - local：本 App 的 SwiftData 打卡，但尚未写回健康 App（例如没有写入权限）。
enum IntakeEntryOrigin: Sendable, Equatable {
    case healthKit(sourceName: String, isOwnApp: Bool)
    case local
}

/// 喝水 / 咖啡因「当日记录」列表与总量共用的展示模型。
/// 刻意只依赖 Foundation，让 HealthKit 读取层与 UI 层共享同一份去重口径，也便于单元测试。
struct IntakeEntry: Sendable, Equatable, Identifiable {
    /// HealthKit 样本用 `hk-<uuid>`，本地打卡用 `local-<syncID>`，保证列表身份稳定。
    var id: String
    /// 记录发生时间。
    var date: Date
    /// 数量：喝水为毫升，咖啡因为毫克。
    var amount: Double
    var origin: IntakeEntryOrigin
    /// 本 App 打卡的稳定同步 ID；只有本 App 创建的记录有值，也据此决定能否删除。
    var syncID: String?
    /// 本地打卡是否已写回健康 App，用于列表来源文案。
    var isSyncedToHealthKit: Bool = false

    /// 列表里展示的来源名。健康 App / 第三方样本显示真实来源，本 App 样本明确标注。
    var sourceLabel: String {
        switch origin {
        case .healthKit(let name, let isOwnApp):
            return isOwnApp ? "本 App · \(name)" : name
        case .local:
            return "本 App（仅本机）"
        }
    }

    /// HealthKit 只允许删除由本 App 写入的样本；外部记录只读展示。
    var canDelete: Bool { syncID != nil }
}

enum IntakeEntryMerger {
    /// 合并健康 App 当日全量样本与本 App 本地打卡，保证同一条记录只出现一次。
    ///
    /// 规则：
    /// 1. 不带本 App 同步 ID 的 HealthKit 样本（健康 App / 第三方 / Watch）全部保留；
    /// 2. 带同步 ID 的 HealthKit 样本若本地还有对应打卡，则丢弃这份「回写镜像」，用本地记录；
    /// 3. 本地打卡全部保留，并标注是否已同步；
    /// 4. 本地已删但健康 App 里还残留的回写样本（孤儿）保留，仍可按 syncID 删除。
    /// 最后按时间倒序，最新记录在最上面。
    static func merge(remote: [IntakeEntry], local: [IntakeEntry]) -> [IntakeEntry] {
        let localSyncIDs = Set(local.compactMap(\.syncID))
        let remoteSyncIDs = Set(remote.compactMap(\.syncID))

        var result = remote.filter { entry in
            guard let syncID = entry.syncID else { return true }
            return !localSyncIDs.contains(syncID)
        }
        for var entry in local {
            if let syncID = entry.syncID {
                entry.isSyncedToHealthKit = remoteSyncIDs.contains(syncID)
            }
            result.append(entry)
        }
        return result.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date > rhs.date }
            return lhs.id < rhs.id
        }
    }

    /// 合并后记录的总量，与 WaterMerge 的「外部 + 本 App 打卡」口径一致。
    static func total(_ entries: [IntakeEntry]) -> Double {
        entries.reduce(0) { $0 + max(0, $1.amount) }
    }
}

/// 打卡页展示用的每日目标 / 上限，存本机偏好。
/// 评分引擎仍使用 ScoringConfig 里的标准值，这里只影响本页展示与差额计算。
enum IntakeGoal {
    /// 与 ScoringConfig.nutritionWaterTargetMl 一致。
    static let defaultWaterTargetMl = 1_500.0
    /// 与 ScoringConfig.nutritionCaffeineLimitMg 一致。
    static let defaultCaffeineLimitMg = 200.0

    static let waterRange: ClosedRange<Double> = 100...10_000
    static let caffeineRange: ClosedRange<Double> = 10...1_000

    /// 对 @AppStorage 暴露：行动页需要跟随用户配置实时刷新，不能只在 body 里裸读 UserDefaults。
    static let waterDefaultsKey = "healthy.intake.waterTargetMl"
    static let caffeineDefaultsKey = "healthy.intake.caffeineLimitMg"

    static func waterTargetMl(defaults: UserDefaults = .standard) -> Double {
        clamp(defaults.object(forKey: waterDefaultsKey) as? Double ?? defaultWaterTargetMl, in: waterRange)
    }

    static func caffeineLimitMg(defaults: UserDefaults = .standard) -> Double {
        clamp(defaults.object(forKey: caffeineDefaultsKey) as? Double ?? defaultCaffeineLimitMg, in: caffeineRange)
    }

    static func setWaterTargetMl(_ value: Double, defaults: UserDefaults = .standard) -> Double {
        let clamped = clamp(value, in: waterRange)
        defaults.set(clamped, forKey: waterDefaultsKey)
        // 手表伴侣 App 的目标与这里同源：改完立刻推过去，手表不用等下次启动。
        // 只推本机偏好（默认 suite）的改动，测试用的临时 suite 不触发推送。
        if defaults === UserDefaults.standard {
            WaterGoalWatchSync.shared.push(clamped)
        }
        return clamped
    }

    static func setCaffeineLimitMg(_ value: Double, defaults: UserDefaults = .standard) -> Double {
        let clamped = clamp(value, in: caffeineRange)
        defaults.set(clamped, forKey: caffeineDefaultsKey)
        return clamped
    }

    static func clamp(_ value: Double, in range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}
