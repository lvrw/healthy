import Foundation
import Testing

struct TodayStatusPresentationTests {
    @Test func lowStressMapsToRelaxed() {
        let presentation = TodayStatusPresentation.make(stress: 20)
        #expect(presentation.word == "放松")
        #expect(presentation.level == .low)
        #expect(presentation.bandPosition == 0.2)
    }

    @Test func levelBoundariesMatchStressEngine() {
        #expect(TodayStatusPresentation.make(stress: 29.9).level == .low)
        #expect(TodayStatusPresentation.make(stress: 30).level == .moderateLow)
        #expect(TodayStatusPresentation.make(stress: 30).word == "平稳")
        #expect(TodayStatusPresentation.make(stress: 50).level == .elevated)
        #expect(TodayStatusPresentation.make(stress: 50).word == "注意")
        #expect(TodayStatusPresentation.make(stress: 70).level == .high)
        #expect(TodayStatusPresentation.make(stress: 70).word == "过载")
        #expect(TodayStatusPresentation.make(stress: 100).level == .high)
    }

    @Test func missingStressShowsAccumulating() {
        let presentation = TodayStatusPresentation.make(stress: nil)
        #expect(presentation.word == "积累中")
        #expect(presentation.level == nil)
        #expect(presentation.bandPosition == nil)
    }

    @Test func bandSegmentsFollowConfig() {
        let presentation = TodayStatusPresentation.make(stress: 40)
        #expect(presentation.bandSegments == [0.3, 0.5, 0.7, 1.0])
        var config = ScoringConfig()
        config.stressLowUpperBound = 40
        let custom = TodayStatusPresentation.make(stress: 35, config: config)
        #expect(custom.level == .low)
        #expect(custom.bandSegments == [0.4, 0.5, 0.7, 1.0])
    }

    @Test func bandPositionCoversUnitRange() {
        #expect(TodayStatusPresentation.make(stress: 0).bandPosition == 0)
        #expect(TodayStatusPresentation.make(stress: 100).bandPosition == 1)
    }
}

// configured by qoder