import Foundation

/// 压力等级，与 iOS 端 StressLevel 的四档边界保持一致。
enum StressLevel: String, CaseIterable, Sendable {
    case low
    case moderateLow
    case elevated
    case high

    var title: String {
        switch self {
        case .low: return "低"
        case .moderateLow: return "偏低"
        case .elevated: return "偏高"
        case .high: return "高"
        }
    }
}

enum StressConfidence: Sendable {
    case insufficient
    case low
    case full
}

struct StressEstimate: Sendable {
    /// 0–100，基线不足时为 nil。
    var score: Double?
    var level: StressLevel
    var zScore: Double?
    var baselineDays: Int
    var confidence: StressConfidence
}

/// 由 HRV(SDNN) 推算压力的纯函数，复刻 iOS 端 Healthy App 的日内口径：
/// 基线取近 28 天 HRV 的对数域滑动统计（log(x+1)），
/// 压力 = clamp(50 − 16·z)，z = (log(最新HRV+1) − 基线均值) / 基线σ，z 截断在 ±2.5。
struct StressEstimator {
    static func estimate(latestHRVms: Double?, dailyHRVms: [Double]) -> StressEstimate {
        let logValues = dailyHRVms.compactMap { v -> Double? in
            guard v.isFinite, v > 0 else { return nil }
            return log(v + 1)
        }
        let minBaselineDays = 7
        let hrvLogSDFloor = 0.05
        let zClamp = 2.5

        guard logValues.count >= minBaselineDays else {
            return StressEstimate(
                score: nil,
                level: .low,
                zScore: nil,
                baselineDays: logValues.count,
                confidence: .insufficient
            )
        }

        let mean = logValues.reduce(0, +) / Double(logValues.count)
        let variance = logValues.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
            / Double(max(1, logValues.count - 1))
        let sd = max(sqrt(variance), hrvLogSDFloor)

        guard let latest = latestHRVms, latest.isFinite, latest > 0 else {
            return StressEstimate(
                score: nil,
                level: .low,
                zScore: nil,
                baselineDays: logValues.count,
                confidence: .low
            )
        }

        let z = (log(latest + 1) - mean) / sd
        let clampedZ = max(-zClamp, min(zClamp, z))
        let score = max(0, min(100, 50 - 16 * clampedZ))
        return StressEstimate(
            score: score,
            level: StressLevel.level(for: score),
            zScore: z,
            baselineDays: logValues.count,
            confidence: .full
        )
    }
}

extension StressLevel {
    static func level(for score: Double) -> StressLevel {
        if score < 30 { return .low }
        if score < 50 { return .moderateLow }
        if score < 70 { return .elevated }
        return .high
    }
}
