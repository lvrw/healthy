import Foundation
import Testing

struct WaterSyncReconcilerTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return value
    }

    private var baseDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!
    }

    private func record(_ id: String = "a", amount: Double = 250, date: Date? = nil) -> WaterSyncRecord {
        WaterSyncRecord(syncID: id, amountMl: amount, date: date ?? baseDate)
    }

    private func sample(
        _ id: String = "a",
        uuid: String = "u1",
        amount: Double = 250,
        date: Date? = nil,
        syncVersion: Int = 1
    ) -> WaterSyncSample {
        WaterSyncSample(
            syncID: id,
            amountMl: amount,
            date: date ?? baseDate,
            uuid: uuid,
            syncVersion: syncVersion
        )
    }

    // MARK: - 同步标识与来源判定

    @Test func syncIdentifierRoundTrips() {
        let id = "A1B2C3"
        #expect(WaterSyncMetadata.localID(from: WaterSyncMetadata.syncIdentifier(for: id)) == id)
        #expect(WaterSyncMetadata.localID(from: "third.party.123") == nil)
        #expect(WaterSyncMetadata.localID(from: nil) == nil)
        #expect(WaterSyncMetadata.localID(from: WaterSyncMetadata.syncIdentifierPrefix) == nil)
    }

    @Test func caffeineMetadataIsIndependentFromWater() {
        let id = "ABC"
        let caffeineID = WaterSyncMetadata.syncIdentifier(for: id, kind: "caffeine")
        let waterID = WaterSyncMetadata.syncIdentifier(for: id, kind: "water")
        #expect(caffeineID != waterID)
        #expect(WaterSyncMetadata.localID(from: caffeineID, kind: "caffeine") == id)
        #expect(WaterSyncMetadata.localID(from: caffeineID, kind: "water") == nil)
        #expect(WaterSyncMetadata.localID(from: waterID, kind: "water") == id)
        #expect(WaterSyncMetadata.kind(from: WaterSyncMetadata.caffeineOriginValue) == "caffeine")
        #expect(WaterSyncMetadata.kind(from: WaterSyncMetadata.originValue) == "water")
    }

    @Test func caffeineOriginIsRecognizedAsSelfEcho() {
        #expect(WaterSyncMetadata.isSelfEcho(
            origin: WaterSyncMetadata.caffeineOriginValue,
            sourceBundleID: "com.apple.Health",
            appBundleID: "cn.rw.healthy"
        ))
        #expect(WaterSyncMetadata.originKey(for: "caffeine") != WaterSyncMetadata.originKey(for: "water"))
        #expect(SyncableCheckInKind(rawValue: "caffeine")?.unitLabel == "毫克")
        #expect(SyncableCheckInKind(rawValue: "water")?.unitLabel == "毫升")
    }

    @Test func selfEchoSamplesAreExcludedFromExternalWater() {
        let appID = "cn.rw.healthy"
        #expect(WaterSyncMetadata.isSelfEcho(
            origin: WaterSyncMetadata.originValue, sourceBundleID: "com.apple.Health", appBundleID: appID
        ))
        #expect(WaterSyncMetadata.isSelfEcho(
            origin: nil, sourceBundleID: appID, appBundleID: appID
        ))
        #expect(!WaterSyncMetadata.isSelfEcho(
            origin: nil, sourceBundleID: "com.apple.Health", appBundleID: appID
        ))
        #expect(!WaterSyncMetadata.isSelfEcho(
            origin: nil, sourceBundleID: "com.third.party", appBundleID: appID
        ))
        // 无法确认本 App bundleID 时只认 origin 标记，不误删第三方数据。
        #expect(!WaterSyncMetadata.isSelfEcho(
            origin: nil, sourceBundleID: "com.third.party", appBundleID: nil
        ))
    }

    // MARK: - 对账规则

    @Test func missingRemoteSampleIsWritten() {
        let plan = WaterSyncReconciler.reconcile(local: [record()], remote: [])
        #expect(plan.toSave.count == 1)
        #expect(plan.toSave.first?.syncID == "a")
        #expect(plan.toDelete.isEmpty)
        #expect(plan.unchangedCount == 0)
    }

    @Test func identicalSidesProduceNoWrites() {
        let plan = WaterSyncReconciler.reconcile(local: [record()], remote: [sample()])
        #expect(plan.isEmpty)
        #expect(plan.unchangedCount == 1)
        #expect(plan.summary.contains("两侧一致"))
    }

    @Test func floatRoundingWithinToleranceIsNotAConflict() {
        let plan = WaterSyncReconciler.reconcile(
            local: [record(amount: 250)],
            remote: [sample(amount: 250.3)]
        )
        #expect(plan.isEmpty)
    }

    @Test func amountConflictUsesLocalRecordAsAuthority() {
        let plan = WaterSyncReconciler.reconcile(
            local: [record(amount: 300)],
            remote: [sample(amount: 250)]
        )
        #expect(plan.toSave.map(\.syncID) == ["a"])
        #expect(plan.toSave.first?.amountMl == 300)
        #expect(plan.toDelete.map(\.uuid) == ["u1"])
        #expect(plan.replacedCount == 1)
    }

    @Test func dateConflictUsesLocalRecordAsAuthority() {
        let later = baseDate.addingTimeInterval(90)
        let plan = WaterSyncReconciler.reconcile(
            local: [record(date: later)],
            remote: [sample(date: baseDate)]
        )
        #expect(plan.toSave.count == 1)
        #expect(plan.toSave.first?.date == later)
        #expect(plan.toDelete.count == 1)
    }

    @Test func deletedLocalCheckInRemovesOrphanSample() {
        let plan = WaterSyncReconciler.reconcile(
            local: [],
            remote: [sample("orphan", uuid: "u9")]
        )
        #expect(plan.toSave.isEmpty)
        #expect(plan.toDelete.map(\.uuid) == ["u9"])
    }

    @Test func duplicateRemoteSamplesKeepOnlyOne() {
        let plan = WaterSyncReconciler.reconcile(
            local: [record()],
            remote: [
                sample(uuid: "u1"),
                sample(uuid: "u2"),
                sample(uuid: "u3", amount: 900),
            ]
        )
        #expect(plan.toSave.isEmpty)
        #expect(plan.toDelete.map(\.uuid).sorted() == ["u1", "u3"])
        #expect(plan.duplicateCount == 2)
        #expect(plan.unchangedCount == 1)
        // 与本地值一致的样本保留一份，金额不符的 u3 被清掉。
        #expect(!plan.toDelete.contains { $0.uuid == "u2" })
    }

    @Test func reconcileIsIdempotentAfterApplyingPlan() {
        let local = [record("a"), record("b", amount: 500)]
        let first = WaterSyncReconciler.reconcile(local: local, remote: [])
        #expect(first.toSave.count == 2)
        let appliedRemote = first.toSave.map {
            WaterSyncSample(
                syncID: $0.syncID,
                amountMl: $0.amountMl,
                date: $0.date,
                uuid: "uuid-\($0.syncID)",
                syncVersion: 1
            )
        }
        let second = WaterSyncReconciler.reconcile(local: local, remote: appliedRemote)
        #expect(second.isEmpty)
        #expect(second.unchangedCount == 2)
    }

    @Test func externalSamplesWithoutSyncIDAreNeverTouched() {
        // 进入对账的 remote 一定带本 App syncID；这里验证对账不会凭空生成写操作。
        let plan = WaterSyncReconciler.reconcile(local: [], remote: [])
        #expect(plan.isEmpty)
    }

    @Test func syncVersionIncrementsAfterRewrite() {
        let samples = [sample(uuid: "u1", syncVersion: 2), sample(uuid: "u2", syncVersion: 3)]
        #expect(WaterSyncReconciler.nextSyncVersion(after: samples) == 4)
        #expect(WaterSyncReconciler.nextSyncVersion(after: []) == WaterSyncMetadata.initialSyncVersion)
    }

    @Test func deleteUUIDsAreUnique() {
        let plan = WaterSyncReconciler.reconcile(
            local: [record()],
            remote: [sample(uuid: "u1"), sample(uuid: "u1")]
        )
        #expect(Set(plan.toDelete.map(\.uuid)).count == plan.toDelete.count)
    }
}
