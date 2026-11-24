import Foundation

enum MetricSource: Int, CaseIterable, Sendable, Codable {
    case sleep = 1
    case hrv = 2
    case restingHR = 4
    case activity = 8
    case vitals = 16
    case circadian = 32
    case fitnessBody = 64
    /// 健康 App 同步的饮食指标 + 两侧合并后的喝水量。
    case nutrition = 128

    var label: String {
        switch self {
        case .sleep: return "睡眠"
        case .hrv: return "HRV"
        case .restingHR: return "静息心率"
        case .activity: return "活动"
        case .vitals: return "生命体征"
        case .circadian: return "生活节律"
        case .fitnessBody: return "体能身体"
        case .nutrition: return "饮食饮水"
        }
    }

    /// 系统判定该类数据不全时，向用户说明需要哪些读数。
    var requirement: String {
        switch self {
        case .sleep: return "需要当晚的睡眠时长或睡眠中点读数。"
        case .hrv: return "需要当天由 Apple Watch 记录的 HRV 读数。"
        case .restingHR: return "需要当天的静息心率读数。"
        case .activity: return "需要步数、活动能量、步行距离或爬楼任一读数。"
        case .vitals: return "需要呼吸频率、血氧、手腕温度，或手动记录的血压 / 血糖。"
        case .circadian: return "需要日照、正念、心情或睡眠中点任一读数。"
        case .fitnessBody: return "需要近 28 天的 VO2max、步行速度 / 稳定性，或体重 / 体脂 / 瘦体重读数；步数与活动能量不计入。"
        case .nutrition: return "需要健康 App 同步的饮食记录，或本 App 的饮食 / 饮水打卡。"
        }
    }
}
