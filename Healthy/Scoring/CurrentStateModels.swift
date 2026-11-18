import Foundation

struct CurrentSignals: Sendable, Equatable {
    var heartRate: Double?
    var heartRateAt: Date?
    var hrv: Double?
    var hrvAt: Date?
    var lastWorkoutEndAt: Date?
}

enum CurrentStateConfidence: String, Sendable, Codable {
    case fresh
    case fair
    case stale
    case unavailable

    var label: String {
        switch self {
        case .fresh: return "数据新鲜"
        case .fair: return "数据一般"
        case .stale: return "数据陈旧"
        case .unavailable: return "暂无数据"
        }
    }
}

struct CurrentStateSnapshot: Sendable, Equatable {
    var instantStress: Double?
    var instantStressLevel: StressLevel?
    var currentState: Double?
    var heartRate: Double?
    var heartRateAt: Date?
    var confidence: CurrentStateConfidence
    var note: String?
}
