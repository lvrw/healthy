import Foundation
import Testing

struct StressTierPresentationTests {
    @Test func tiersFollowConfigBoundaries() {
        let tiers = StressTierPresentation.tiers(config: ScoringConfig())
        #expect(tiers.count == 4)
        #expect(tiers.map(\.lower) == [0, 30, 50, 70])
        #expect(tiers.map(\.upper) == [30, 50, 70, 100])
        #expect(tiers.map(\.level) == [.low, .moderateLow, .elevated, .high])
        #expect(tiers[0].rangeText == "0–30")
        #expect(tiers[3].rangeText == "70–100")
    }

    @Test func customConfigShiftsBoundaries() {
        var config = ScoringConfig()
        config.stressLowUpperBound = 40
        let tiers = StressTierPresentation.tiers(config: config)
        #expect(tiers[0].upper == 40)
        #expect(tiers[1].lower == 40)
        #expect(tiers[0].rangeText == "0–40")
    }

    @Test func zBoundsInvertHourlyFormulaAndClamp() {
        // 小时压力 = 50 − 16×z（clamp ±2.5）反推：压力 0 → z=3.125 截到 2.5；30 → 1.25
        let tiers = StressTierPresentation.tiers(config: ScoringConfig())
        #expect(tiers[0].zLowerBound == 1.25)
        #expect(tiers[0].zUpperBound == 2.5)
        #expect(tiers[1].zLowerBound == 0)
        #expect(tiers[1].zUpperBound == 1.25)
        #expect(tiers[2].zLowerBound == -1.25)
        #expect(tiers[2].zUpperBound == 0)
        #expect(tiers[3].zLowerBound == -2.5)
        #expect(tiers[3].zUpperBound == -1.25)
    }

    @Test func tierLookupMatchesStressEngineLevel() {
        let config = ScoringConfig()
        let tiers = StressTierPresentation.tiers(config: config)
        func tier(for stress: Double) -> StressTier? {
            tiers.first { stress >= $0.lower && stress < $0.upper } ?? tiers.last { stress >= $0.lower }
        }
        #expect(tier(for: 20)?.level == .low)
        #expect(tier(for: 30)?.level == .moderateLow)
        #expect(tier(for: 70)?.level == .high)
        #expect(tier(for: 100)?.level == .high)
        #expect(tiers.allSatisfy { StressEngine.level(for: ($0.lower + $0.upper) / 2, config: config) == $0.level })
    }
}

// configured by qoder