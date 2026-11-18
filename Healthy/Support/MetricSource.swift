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
}
