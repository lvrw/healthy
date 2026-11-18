import Foundation
import WatchConnectivity

/// 手表伴侣 App 侧的接收端：把 iPhone 推过来的喝水目标落到本机 App Group。
/// 手表 App 与表盘小组件都从这里读，保证两处口径一致；
/// 没收到过手机配置时退回默认值，与 iOS 端 `IntakeGoal.defaultWaterTargetMl` 相同。
final class WatchGoalReceiver: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchGoalReceiver()

    /// 与 iPhone 侧 `WaterGoalWatchSync.waterTargetKey` 同名。
    static let waterTargetKey = "waterTargetMl"
    static let defaultTargetMl = 1_500.0
    static let minTargetMl = 100.0
    static let maxTargetMl = 10_000.0
    /// 目标变化后广播，供 `AppEnvironment` 刷新界面。
    static let didChangeNotification = Notification.Name("WatchGoalReceiver.didChange")

    private override init() {
        super.init()
    }

    /// 手表主 App 与小组件共用的 App Group 容器。
    private var defaults: UserDefaults? { UserDefaults(suiteName: WaterShared.suiteName) }

    /// 当前生效的喝水目标（毫升）；范围钳制与 iPhone 端保持一致。
    func currentWaterTargetMl() -> Double {
        guard let stored = defaults?.object(forKey: Self.waterTargetKey) as? Double else {
            return Self.defaultTargetMl
        }
        return min(max(stored, Self.minTargetMl), Self.maxTargetMl)
    }

    /// 手表启动时调用：激活会话，激活后系统会带回上一次的 applicationContext。
    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func store(_ ml: Double) {
        let clamped = min(max(ml, Self.minTargetMl), Self.maxTargetMl)
        guard let defaults else { return }
        defaults.set(clamped, forKey: Self.waterTargetKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// 从上下文字典里取值；没有该键（例如手表 App 还没收到过任何配置）时什么都不做。
    private func apply(_ context: [String: Any]) {
        guard let value = context[Self.waterTargetKey] as? Double else {
            // 手机可能以 NSNumber 形式投递，Double 桥接失败时再试一次。
            if let number = context[Self.waterTargetKey] as? NSNumber {
                store(number.doubleValue)
            }
            return
        }
        store(value)
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }
}
