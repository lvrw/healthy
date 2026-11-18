import AppIntents
import Foundation

/// 小组件上的交互意图：点一下记录一杯水（300 ml），不打开 App。
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "记录一杯水"
    static let description: IntentDescription? = IntentDescription("记录 300 ml 饮水")

    func perform() async throws -> some IntentResult {
        let syncId = UUID().uuidString

        // 1) 先入队兜底（扩展可能没有 HealthKit 授权，手表主 App 启动时会补写）
        WaterShared.enqueue(id: syncId)

        // 2) 尝试在扩展内直接写入 HealthKit；成功后撤销兜底。
        // 小组件已不展示今日饮水量，无需再乐观更新共享缓存。
        do {
            try await WaterShared.saveCup(syncId: syncId)
            WaterShared.removePending(id: syncId)
        } catch {
            // 保留队列，交给手表主 App 补写
        }

        return .result()
    }
}
