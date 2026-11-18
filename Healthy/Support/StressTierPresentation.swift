import Foundation

struct StressTier: Sendable, Equatable {
    var level: StressLevel
    var lower: Double
    var upper: Double
    var rangeText: String
    var zLowerBound: Double
    var zUpperBound: Double
}

enum StressTierPresentation {
    /// 四档 = StressEngine 等级边界；HRV z 区间由小时压力公式 压力 = 50 − 16×z 反推并按 ±zClamp 截断。
    /// 注：这是日内小时口径的反推展示，与日级 StressEngine 多源加权不同。
    static func tiers(config: ScoringConfig = ScoringConfig()) -> [StressTier] {
        let bounds: [(StressLevel, Double, Double)] = [
            (.low, 0, config.stressLowUpperBound),
            (.moderateLow, config.stressLowUpperBound, config.stressModerateUpperBound),
            (.elevated, config.stressModerateUpperBound, config.stressElevatedUpperBound),
            (.high, config.stressElevatedUpperBound, 100),
        ]
        return bounds.map { level, lower, upper in
            StressTier(
                level: level,
                lower: lower,
                upper: upper,
                rangeText: "\(Int(lower))–\(Int(upper))",
                zLowerBound: zBound(stress: upper, config: config),
                zUpperBound: zBound(stress: lower, config: config)
            )
        }
    }

    static func zBound(stress: Double, config: ScoringConfig = ScoringConfig()) -> Double {
        let raw = (50 - stress) / 16
        return ScoreSupport.clampZ(raw, config.zClamp)
    }
}

// configured by qoder