import Foundation
import WatchConnectivity

/// 把 iPhone 上的喝水目标单向推给手表伴侣 App。
///
/// 通道用 `WCSession.updateApplicationContext`：不需要两端都在前台，
/// 手表未激活时只保留最后一次值 —— 目标这类「快照型配置」正合适。
/// 手表侧只读、不在手表上改目标，因此不存在双向覆盖的问题。
final class WaterGoalWatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WaterGoalWatchSync()

    /// applicationContext 的键名；手表侧 `WatchGoalReceiver.waterTargetKey` 用同一个字符串。
    static let waterTargetKey = "waterTargetMl"

    private override init() {
        super.init()
    }

    /// App 启动时调用一次：激活会话，激活成功后再把当前目标推过去。
    /// 重复调用是安全的，已激活时系统会忽略重复的 activate()。
    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// 目标变化后调用：立即把新值推给手表。
    func push(_ ml: Double) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext([Self.waterTargetKey: ml])
        } catch {
            // 手表未配对 / 未安装 / 暂时不可达：推送失败不影响本机配置，
            // 下次启动或下次改动会重新推送，因此这里不提示用户。
            #if DEBUG
            print("[WaterGoalWatchSync] push \(Int(ml)) ml failed: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }
        // 读的是与行动页、详情页同一份偏好，避免把默认值当成用户配置发过去。
        push(IntakeGoal.waterTargetMl())
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// 换配对的手表后系统会让会话失效，必须重新激活，否则新表永远收不到配置。
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
