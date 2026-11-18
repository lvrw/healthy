import Foundation

/// 单日训练在各心率区间的累计分钟数（Z1–Z5）。
///
/// 区间按最大心率百分比（%HRmax）划分，无需静息心率即可计算：
/// Z1 恢复 `<60%`、Z2 燃脂 `60–70%`、Z3 有氧 `70–80%`、Z4 无氧 `80–90%`、Z5 极限 `≥90%`。
/// 分钟来自 workouts 时间窗内的心率采样，按相邻样本时长积分得到。
struct WorkoutZoneMinutes: Sendable, Equatable, Codable {
    /// 索引 0..<5 对应 Z1..Z5 的累计分钟。
    private(set) var minutes: [Double]

    init(minutes: [Double] = [0, 0, 0, 0, 0]) {
        precondition(minutes.count == WorkoutZoneMinutes.zoneCount,
                      "minutes 必须包含 \(WorkoutZoneMinutes.zoneCount) 个区间")
        self.minutes = minutes
    }

    var total: Double { minutes.reduce(0, +) }

    static let zoneCount = 5

    /// Z1 恢复 / Z2 燃脂 / Z3 有氧 / Z4 无氧 / Z5 极限。
    static let labels = ["恢复", "燃脂", "有氧", "无氧", "极限"]

    /// 把一次心率读数归入区间：先折算为 %HRmax，再按阈值落区。
    static func zoneIndex(heartRate: Double, maxHeartRate: Double) -> Int {
        guard maxHeartRate > 0, heartRate.isFinite else { return 0 }
        let pct = heartRate / maxHeartRate * 100
        switch pct {
        case ..<60: return 0
        case ..<70: return 1
        case ..<80: return 2
        case ..<90: return 3
        default: return 4
        }
    }
}
