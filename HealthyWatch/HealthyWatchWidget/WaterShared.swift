import Foundation
import HealthKit

/// 手表主 App 与 Widget 扩展之间的本机共享层（App Group）。
/// 小组件点击后立即写入 HealthKit；若扩展未获授权，则把请求留在队列里，
/// 由手表主 App 启动时补写，保证「点一下就喝一杯水」不会丢数据。
/// 小组件不再展示今日饮水量，因此这里不缓存任何总量，避免残留与手机不一致的假进度。
enum WaterShared {
    static let suiteName = "group.cn.rw.healthy.watch"
    static let widgetKind = "WaterQuickWidget"
    static let cupMl: Double = 300

    private static let pendingKey = "pendingWaterIds"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    /// 待补写队列（扩展写入失败时保留，手表主 App 消费后清空）。
    static func enqueue(id: String) {
        guard let defaults else { return }
        var ids = defaults.stringArray(forKey: pendingKey) ?? []
        ids.append(id)
        defaults.set(ids, forKey: pendingKey)
    }

    static func removePending(id: String) {
        guard let defaults else { return }
        var ids = defaults.stringArray(forKey: pendingKey) ?? []
        ids.removeAll { $0 == id }
        defaults.set(ids, forKey: pendingKey)
    }

    static func takePending() -> [String] {
        guard let defaults else { return [] }
        let ids = defaults.stringArray(forKey: pendingKey) ?? []
        defaults.set([String](), forKey: pendingKey)
        return ids
    }

    /// 写入一杯 300ml 的饮水样本。
    /// metadata 带 Apple 标准的 syncIdentifier：扩展与主 App 用同一 id 重复写入时，
    /// HealthKit 会合并为同一条样本，不会重复计数。
    static func saveCup(syncId: String, at date: Date = .now) async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKQuantityType.quantityType(forIdentifier: .dietaryWater) else {
            throw WaterSharedError.unavailable
        }
        let unit = HKUnit.literUnit(with: .milli)
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: unit, doubleValue: cupMl),
            start: date,
            end: date,
            metadata: [
                HKMetadataKeySyncIdentifier: syncId,
                HKMetadataKeySyncVersion: 1,
            ]
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let store = HKHealthStore()
            store.save(sample) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(throwing: WaterSharedError.saveFailed)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

enum WaterSharedError: LocalizedError {
    case unavailable
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .unavailable: return "此设备暂不支持健康数据。"
        case .saveFailed: return "写入健康数据失败。"
        }
    }
}
