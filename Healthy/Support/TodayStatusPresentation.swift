import Foundation

struct TodayStatusPresentation: Equatable, Sendable {
    var word: String
    var level: StressLevel?
    var bandPosition: Double?
    var bandSegments: [Double]

    static func make(stress: Double?, config: ScoringConfig = ScoringConfig()) -> TodayStatusPresentation {
        let segments = [
            config.stressLowUpperBound / 100,
            config.stressModerateUpperBound / 100,
            config.stressElevatedUpperBound / 100,
            1.0,
        ]
        guard let stress else {
            return TodayStatusPresentation(word: "积累中", level: nil, bandPosition: nil, bandSegments: segments)
        }
        let level = StressEngine.level(for: stress, config: config)
        let word: String
        switch level {
        case .low: word = "放松"
        case .moderateLow: word = "平稳"
        case .elevated: word = "注意"
        case .high: word = "过载"
        }
        let position = min(max(stress, 0), 100) / 100
        return TodayStatusPresentation(word: word, level: level, bandPosition: position, bandSegments: segments)
    }
}

// configured by qoder