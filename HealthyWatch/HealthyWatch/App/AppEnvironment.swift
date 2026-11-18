import Foundation
import SwiftUI
import HealthKit
import WidgetKit
import Combine

/// 全局可观察的环境对象：持有 HealthKit 读取/写入的结果，并驱动各视图刷新。
/// 与 iOS 端 Healthy App 共享同一套数据口径（HRV/喝水/咖啡因）。
@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var healthAvailable = HKHealthStore.isHealthDataAvailable()
    @Published private(set) var authorized = false
    @Published private(set) var isLoading = false

    @Published private(set) var latestHRVms: Double?
    @Published private(set) var latestHRVAt: Date?
    @Published private(set) var todayHRVms: Double?
    @Published private(set) var hrvTrend: [HRVDaily] = []

    @Published private(set) var stress: StressEstimate =
        StressEstimator.estimate(latestHRVms: nil, dailyHRVms: [])

    @Published private(set) var waterMlToday: Double = 0
    @Published private(set) var caffeineMgToday: Double = 0
    @Published private(set) var canWriteWater = false
    @Published private(set) var canWriteCaffeine = false
    /// 喝水目标：由 iPhone 通过 WatchConnectivity 推过来，存在手表 App Group 里。
    /// 收到推送前先用默认值，避免 Gauge 出现 0 上限。
    @Published private(set) var waterTargetMl: Double = WatchGoalReceiver.defaultTargetMl

    @Published var errorMessage: String?

    private let store = WatchHealthStore()
    /// 目标变化通知的订阅；只在首次 onAppear 建立一次。
    private var goalObserver: AnyCancellable?

    func onAppear() {
        healthAvailable = HKHealthStore.isHealthDataAvailable()
        // 升级到「不展示饮水量」的版本后，主动刷新一次已添加的小组件，
        // 避免智能叠放里残留旧版带进度数字的缓存 entry。
        WidgetCenter.shared.reloadTimelines(ofKind: WaterShared.widgetKind)
        startGoalSync()
        guard healthAvailable else { return }
        Task { await refresh() }
    }

    /// 激活与 iPhone 的会话，并把本机缓存的目标读进界面；之后跟随推送实时刷新。
    private func startGoalSync() {
        WatchGoalReceiver.shared.start()
        waterTargetMl = WatchGoalReceiver.shared.currentWaterTargetMl()
        guard goalObserver == nil else { return }
        goalObserver = NotificationCenter.default
            .publisher(for: WatchGoalReceiver.didChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.waterTargetMl = WatchGoalReceiver.shared.currentWaterTargetMl()
                }
            }
    }

    /// 补写小组件点击时未成功写入 HealthKit 的请求（扩展未授权时的兜底）。
    /// 使用同一个 syncIdentifier，HealthKit 会合并重复样本，不会重复计数。
    private func drainPendingWater() async {
        let ids = WaterShared.takePending()
        guard !ids.isEmpty else { return }
        for id in ids {
            try? await WaterShared.saveCup(syncId: id)
        }
    }

    func requestAccess() async {
        healthAvailable = HKHealthStore.isHealthDataAvailable()
        guard healthAvailable else { return }
        let granted = await store.requestAuthorization()
        authorized = granted
        if granted {
            await refresh()
        }
    }

    func refresh() async {
        guard healthAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        // 先补写小组件点击时未成功落库的请求，再拉取最新数据，
        // 保证「同步」一次就能让 App / HealthKit / 小组件三者一致。
        await drainPendingWater()
        do {
            let snapshot = try await store.fetchDashboard()
            self.latestHRVms = snapshot.latestHRVms
            self.latestHRVAt = snapshot.latestHRVAt
            self.todayHRVms = snapshot.todayHRVms
            self.hrvTrend = snapshot.dailyHRV
            self.waterMlToday = snapshot.waterMlToday
            self.caffeineMgToday = snapshot.caffeineMgToday
            self.canWriteWater = snapshot.canWriteWater
            self.canWriteCaffeine = snapshot.canWriteCaffeine
            self.authorized = true
            self.errorMessage = nil
            // 小组件只做「点按记录一杯水」，不展示总量，无需回写共享缓存
            let baselineDaily = snapshot.dailyHRV.map(\.sdnn)
            self.stress = StressEstimator.estimate(
                latestHRVms: snapshot.latestHRVms,
                dailyHRVms: baselineDaily
            )
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func addWater(_ ml: Double) async {
        do {
            try await store.addWater(ml: ml)
            await refresh()
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    func addCaffeine(_ mg: Double) async {
        do {
            try await store.addCaffeine(mg: mg)
            await refresh()
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}
