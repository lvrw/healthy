import Foundation
import HealthKit
import SwiftData

@MainActor
@Observable
final class AppModel {
    enum SyncPhase: Equatable {
        case idle
        case syncing
        case done(Int)
        case failed(String)
    }

    var phase: SyncPhase = .idle
    private let coordinator: SyncCoordinator
    /// 前台观察喝水数据变化的任务；HealthKit 变化回调只在 App 运行期间投递。
    private var waterObservationTask: Task<Void, Never>?
    /// 观察回调节流：本 App 自己写回也会触发回调，避免刚写完又立刻跑一轮同步。
    private var lastWaterChangeSyncAt: Date = .distantPast
    /// 今日步数轻量刷新的节流：回前台 / 激活时最多 30 秒查一次，避免频繁打 HealthKit。
    private var lastStepRefreshAt: Date = .distantPast

    init(context: ModelContext, calendar: Calendar = .current) {
        coordinator = SyncCoordinator(context: context, calendar: calendar)
    }

    func requestHealthAuthorization() async {
        phase = .idle
        do {
            _ = try await coordinator.requestAuthorization()
        } catch {
            appLog(.error, "Auth", "健康数据授权失败: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// 带结果反馈的授权请求，供设置页展示：
    /// - 系统判定无需再次请求（.unnecessary）时不弹窗，提示去系统设置检查；
    /// - 需要请求时弹出系统授权界面并返回结果。
    func requestHealthAuthorizationWithFeedback() async -> (ok: Bool, message: String) {
        guard HKHealthStore.isHealthDataAvailable() else {
            return (false, "这台设备不支持健康数据。")
        }
        do {
            let status = try await HealthKitService().authorizationRequestStatus()
            let storedAuth = UserDefaults.standard.integer(forKey: SyncCoordinator.authVersionKey)
            // 新增写入类型（碳水 / 蛋白质 / 脂肪）时读权限没变，
            // getRequestStatusForAuthorization 仍会返回 .unnecessary；
            // 此时必须按授权版本继续请求，否则新类型永远停在 notDetermined。
            if status == .unnecessary && storedAuth >= SyncCoordinator.currentAuthVersion {
                return (true, "之前已完成授权。如果数据一直是空的，请到系统「设置 → 隐私与安全性 → 健康」检查本 App 的读取权限，或直接重新同步。")
            }
            _ = try await coordinator.requestAuthorization()
            UserDefaults.standard.set(
                SyncCoordinator.currentAuthVersion,
                forKey: SyncCoordinator.authVersionKey
            )
            // 授权刚拿到写权限时，把之前攒下的喝水打卡补写回健康 App。
            await coordinator.reconcileWaterAfterAuthorization()
            return (true, "授权完成。可以点击下方「立刻同步」读取健康数据，喝水 / 咖啡因及饮品营养记录会双向同步。")
        } catch {
            appLog(.error, "Auth", "授权请求（设置页）失败: \(error.localizedDescription)")
            return (false, error.localizedDescription)
        }
    }

    /// 回前台 / 激活时先走轻量刷新（步数 + 健身三环），不受整体同步的 10 分钟节流限制。
    func refreshTodayStepsIfNeeded() async {
        guard Date.now.timeIntervalSince(lastStepRefreshAt) >= 30 else { return }
        lastStepRefreshAt = .now
        await coordinator.refreshTodaySteps()
        await coordinator.refreshTodayActivityRings()
    }

    func syncIfNeeded() async {
        await refreshTodayStepsIfNeeded()
        let storedAuth = UserDefaults.standard.integer(forKey: SyncCoordinator.authVersionKey)
        if storedAuth < SyncCoordinator.currentAuthVersion {
            _ = try? await coordinator.requestAuthorization()
            UserDefaults.standard.set(SyncCoordinator.currentAuthVersion, forKey: SyncCoordinator.authVersionKey)
        }
        let stored = UserDefaults.standard.integer(forKey: SyncCoordinator.schemaVersionKey)
        if stored < SyncCoordinator.currentSchemaVersion {
            await upgradeSchema()
            startWaterObservation()
            return
        }
        guard coordinator.shouldSyncOnActivate() else {
            startWaterObservation()
            return
        }
        await sync()
        startWaterObservation()
    }

    /// 前台观察健康 App / 第三方写入的喝水量变化，触发轻量饮食同步。
    /// 不注册后台投递（避免引入 UIBackgroundModes），App 未运行期间的变化
    /// 由下次启动/回前台、手动同步或全量同步补齐。
    func startWaterObservation() {
        guard waterObservationTask == nil else { return }
        let service = HealthKitService()
        waterObservationTask = Task { [weak self] in
            let stream = await service.waterChangeStream()
            for await _ in stream {
                guard let self, !Task.isCancelled else { return }
                await self.syncFromWaterChange()
            }
        }
    }

    private func syncFromWaterChange() async {
        let gap = Date.now.timeIntervalSince(lastWaterChangeSyncAt)
        guard gap >= 30 else {
            appLog(.debug, "Sync", "喝水观察回调被节流，距上次 \(Int(gap))s")
            return
        }
        lastWaterChangeSyncAt = .now
        guard phase != .syncing else { return }
        phase = .syncing
        appLog(.info, "Sync", "喝水变化触发轻量同步（只重读营养/饮水，不含步数）")
        do {
            try await coordinator.syncNutritionOnly()
            phase = .done(0)
        } catch {
            appLog(.error, "Sync", "轻量同步失败: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    func upgradeSchema() async {
        guard phase != .syncing else { return }
        phase = .syncing
        do {
            _ = try await coordinator.requestAuthorization()
            let inserted = try await coordinator.sync(reason: .fullBackfill)
            phase = .done(inserted)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func sync() async {
        guard phase != .syncing else { return }
        phase = .syncing
        appLog(.info, "Sync", "触发常规同步")
        do {
            let inserted = try await coordinator.sync(reason: .launch)
            phase = .done(inserted)
        } catch {
            appLog(.error, "Sync", "常规同步失败: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// 下拉刷新统一入口：iOS 标准样式下只负责执行页面各自的刷新动作。
    /// 视觉（原生 spinner）与手势全部交给系统 `.refreshable`，
    /// 不再维护自定义状态、自定义圈或任何自定义震动。
    /// - Parameter work: 页面自定义的刷新逻辑（如首页还要刷新此刻状态 / 日内压力）。
    @MainActor
    func pullToRefresh(work: @MainActor @escaping () async -> Void) async {
        await work()
    }

    /// 设置页手动触发喝水双向对账（补写 / 去重 / 清理孤儿）。
    func reconcileWaterNow() async {
        await coordinator.reconcileWaterNow()
    }

    func resyncAll() async {
        guard phase != .syncing else { return }
        phase = .syncing
        appLog(.info, "Sync", "触发全量同步（118 天）")
        do {
            let inserted = try await coordinator.sync(reason: .manual)
            phase = .done(inserted)
        } catch {
            appLog(.error, "Sync", "全量同步失败: \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }
}
