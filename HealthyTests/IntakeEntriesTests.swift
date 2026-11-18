import Foundation
import Testing

struct IntakeEntriesTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var baseDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: 9))!
    }

    private func remote(
        uuid: String,
        amount: Double,
        hour: Int = 9,
        syncID: String? = nil,
        sourceName: String = "健康",
        isOwnApp: Bool = false
    ) -> IntakeEntry {
        IntakeEntry(
            id: "hk-\(uuid)",
            date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour))!,
            amount: amount,
            origin: .healthKit(sourceName: sourceName, isOwnApp: isOwnApp),
            syncID: syncID,
            isSyncedToHealthKit: true
        )
    }

    private func local(_ syncID: String, amount: Double, hour: Int = 10) -> IntakeEntry {
        IntakeEntry(
            id: "local-\(syncID)",
            date: calendar.date(from: DateComponents(year: 2026, month: 11, day: 11, hour: hour))!,
            amount: amount,
            origin: .local,
            syncID: syncID
        )
    }

    @Test func healthKitExternalSamplesAreKeptAndReadOnly() {
        let entries = IntakeEntryMerger.merge(
            remote: [
                remote(uuid: "u1", amount: 300, hour: 8, sourceName: "健康"),
                remote(uuid: "u2", amount: 120, hour: 11, sourceName: "WaterMinder"),
            ],
            local: []
        )
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { !$0.canDelete })
        #expect(entries.contains { $0.sourceLabel == "WaterMinder" })
        #expect(IntakeEntryMerger.total(entries) == 420)
    }

    @Test func localCheckInReplacesItsHealthKitEcho() {
        let entries = IntakeEntryMerger.merge(
            remote: [
                remote(uuid: "echo", amount: 250, hour: 10, syncID: "A1", isOwnApp: true),
                remote(uuid: "ext", amount: 400, hour: 8, sourceName: "健康"),
            ],
            local: [local("A1", amount: 250, hour: 10)]
        )
        #expect(entries.count == 2)
        #expect(entries.filter { $0.id == "hk-echo" }.isEmpty)
        #expect(entries.contains { $0.id == "local-A1" && $0.isSyncedToHealthKit })
        #expect(IntakeEntryMerger.total(entries) == 650)
    }

    @Test func unsyncedLocalCheckInIsKeptAsLocalOnly() {
        let entries = IntakeEntryMerger.merge(
            remote: [],
            local: [local("B2", amount: 500)]
        )
        #expect(entries.count == 1)
        #expect(entries[0].sourceLabel == "本 App（仅本机）")
        #expect(!entries[0].isSyncedToHealthKit)
        #expect(entries[0].canDelete)
    }

    @Test func orphanHealthKitEchoStaysDeletable() {
        let entries = IntakeEntryMerger.merge(
            remote: [remote(uuid: "orphan", amount: 250, syncID: "C3", isOwnApp: true)],
            local: []
        )
        #expect(entries.count == 1)
        #expect(entries[0].id == "hk-orphan")
        #expect(entries[0].canDelete)
        #expect(entries[0].sourceLabel.contains("本 App"))
    }

    /// 回归：行动页 250 / 记录页 850 的差异场景。
    /// 健康 App 里残留两条本 App 回写样本（孤儿 + 已同步打卡镜像），
    /// 本地只剩一条 250ml 打卡。nutritionByDay 会把两条回写样本都排除，
    /// 快照口径只剩 250；记录页口径按 syncID 去重后仍计入孤儿，合计 850。
    /// 行动页改为复用记录页口径后，两页都应是 850。
    @Test func orphanEchoesAreCountedInRecordPageTotal() {
        let entries = IntakeEntryMerger.merge(
            remote: [
                remote(uuid: "orphan-600", amount: 600, hour: 8, syncID: "GONE", isOwnApp: true),
                remote(uuid: "echo-250", amount: 250, hour: 10, syncID: "A1", isOwnApp: true),
            ],
            local: [local("A1", amount: 250, hour: 10)]
        )
        #expect(entries.count == 2)
        #expect(IntakeEntryMerger.total(entries) == 850)
    }

    @Test func mergedRecordsAreNewestFirst() {
        let entries = IntakeEntryMerger.merge(
            remote: [remote(uuid: "early", amount: 100, hour: 7)],
            local: [local("late", amount: 200, hour: 15)]
        )
        #expect(entries.map(\.id) == ["local-late", "hk-early"])
    }

    @Test func goalReadWriteIsClamped() {
        let defaults = UserDefaults(suiteName: "intake-goal-\(UUID().uuidString)")!
        #expect(IntakeGoal.waterTargetMl(defaults: defaults) == IntakeGoal.defaultWaterTargetMl)
        #expect(IntakeGoal.caffeineLimitMg(defaults: defaults) == IntakeGoal.defaultCaffeineLimitMg)

        #expect(IntakeGoal.setWaterTargetMl(2_670, defaults: defaults) == 2_670)
        #expect(IntakeGoal.waterTargetMl(defaults: defaults) == 2_670)
        #expect(IntakeGoal.setWaterTargetMl(99_999, defaults: defaults) == IntakeGoal.waterRange.upperBound)
        #expect(IntakeGoal.setWaterTargetMl(-1, defaults: defaults) == IntakeGoal.waterRange.lowerBound)

        #expect(IntakeGoal.setCaffeineLimitMg(300, defaults: defaults) == 300)
        #expect(IntakeGoal.setCaffeineLimitMg(0, defaults: defaults) == IntakeGoal.caffeineRange.lowerBound)
    }
}
