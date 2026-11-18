import Foundation
import HealthKit
import SwiftData

/// 按「喝水 / 咖啡因记录页」同一口径批量读取每日合计。
///
/// 背景：行动页卡片和历史详情页原来读 `DailyMetrics.waterTotalMl` 快照，
/// 快照的 `nutritionByDay` 会把「本 App 回写但本地已删的孤儿样本」排除，
/// 而记录页 `IntakeEntryMerger.merge` 规则 4 会保留孤儿，于是同一天出现
/// 卡片 250 / 记录页 850 的不一致。这里把记录页口径抽成公共入口，
/// 行动页卡片、详情页、洞察页共用，彻底消除口径漂移。
@MainActor
enum IntakeTotalsLoader {
    /// 一次查询 `days` 覆盖范围内的 HealthKit 样本，按 dayKey 分组返回每日合计。
    /// 返回的字典只含读取成功的 kind；HealthKit 不可用时返回空，调用方回退快照值。
    static func totals(
        for days: [Date],
        checkIns: [ActionCheckIn],
        context: ModelContext,
        kinds: [SyncableCheckInKind] = [.water, .caffeine],
        calendar: Calendar = .current
    ) async -> [String: [String: Double]] {
        guard let first = days.min(), let last = days.max() else { return [:] }
        // 老打卡缺 syncID 时先补齐，否则记录页口径会把它们排除掉。
        _ = try? WaterMerge.localRecords(in: context)

        let start = calendar.startOfDay(for: first)
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) ?? .now
        let wantedKeys = Set(days.map { DayKey.key(for: $0, calendar: calendar) })
        let service = HealthKitService()
        var result: [String: [String: Double]] = [:]

        for kind in kinds {
            do {
                let remote = try await service.fetchIntakeEntries(kind: kind.rawValue, from: start, to: end)
                let remoteByDay = Dictionary(grouping: remote) {
                    DayKey.key(for: $0.date, calendar: calendar)
                }
                let local = checkIns.filter { check in
                    wantedKeys.contains(check.dayKey) && check.kindRaw == kind.rawValue
                }
                let localByDay = Dictionary(grouping: local) { $0.dayKey }

                for key in wantedKeys {
                    let entries = IntakeEntryMerger.merge(
                        remote: remoteByDay[key] ?? [],
                        local: (localByDay[key] ?? []).compactMap { check in
                            guard let syncID = check.syncID, !syncID.isEmpty else { return nil }
                            return IntakeEntry(
                                id: "local-\(syncID)",
                                date: check.createdAt,
                                amount: check.amount,
                                origin: .local,
                                syncID: syncID
                            )
                        }
                    )
                    result[key, default: [:]][kind.rawValue] = IntakeEntryMerger.total(entries)
                }
            } catch {
                // 单项读取失败不影响另一项；调用方对缺失值保留快照兜底。
            }
        }
        return result
    }
}
