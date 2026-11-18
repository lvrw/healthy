import Foundation
import Testing

struct BriefingTests {
    @Test func parseAcceptsFencedJSON() throws {
        let content = """
        ```json
        {"summary":"今天状态一般","readiness":{"level":"一般","interpretation":"睡眠偏短。"},"stress":{"level":"中低","analysis":"HRV 略低于基线。"},"suggestions":[{"title":"早点睡","detail":"今晚 23 点前上床。","category":"sleep"}],"cautions":[],"dataCaveats":[],"disclaimer":""}
        ```
        """
        let report = try BriefingReport.parse(content)
        #expect(report.summary == "今天状态一般")
        #expect(report.suggestions.count == 1)
        #expect(report.disclaimer.isEmpty == false)
    }

    @Test func parseRejectsPlainText() {
        #expect(throws: LLMError.self) {
            try BriefingReport.parse("今天状态不错，建议早点休息。")
        }
    }

    @Test func parseFillsMissingOptionalFields() throws {
        let content = """
        {"summary":"摘要","readiness":{"level":"一般","interpretation":"解释"},"stress":{"level":"中低","analysis":"分析"},"suggestions":[{"title":"早点睡","detail":"23 点前上床。"}]}
        """
        let report = try BriefingReport.parse(content)
        #expect(report.cautions.isEmpty)
        #expect(report.dataCaveats.isEmpty)
        #expect(report.disclaimer.isEmpty == false)
        #expect(report.suggestions.first?.category == "other")
    }

    @Test func parseCapsSuggestionsAndNormalizesCategory() throws {
        let suggestions = (1...7).map {
            "{\"title\":\"建议\($0)\",\"detail\":\"今天可以做。\",\"category\":\"unknown\"}"
        }.joined(separator: ",")
        let content = """
        {"summary":"摘要","readiness":{"level":"一般","interpretation":"解释"},"stress":{"level":"中低","analysis":"分析"},"suggestions":[\(suggestions)],"cautions":["注意"],"dataCaveats":[],"disclaimer":"免责"}
        """
        let report = try BriefingReport.parse(content)
        #expect(report.suggestions.count == 5)
        #expect(report.suggestions.allSatisfy { $0.category == "other" })
    }

    @Test func promptMentionsRequiredSchema() {
        let prompt = PromptBuilder.systemPrompt
        #expect(prompt.contains("JSON"))
        #expect(prompt.contains("suggestions"))
        #expect(prompt.contains("dataCaveats"))
        #expect(PromptBuilder.userPrompt(payloadJSON: "{}").contains("{}"))
    }

    @Test func payloadRoundTrips() throws {
        let payload = BriefingPayload(
            date: "2026-10-30",
            baselineDays: 21,
            scores: .init(
                readiness: 72.5,
                stress: 41.2,
                readinessComponents: ReadinessComponents(sleep: 80, autonomic: 65, load: 90, vitals: 100),
                stressComponents: StressComponents(hrv: 60, restingHR: 45, sleep: 30, vitals: 50),
                completeness: 5,
                missing: [],
                confidence: "full"
            ),
            autonomic: .init(
                hrvDailyAvg: 44,
                hrvLatest: 42,
                zHRV: -0.8,
                hrvBaselineMs: 47,
                restingHR: 59,
                zRestingHR: 0.3,
                restingHRBaseline: 58
            ),
            sleep: .init(totalH: 7.2, deepH: 1.1, remH: 1.5, efficiency: 0.93, avg7dH: 7.1),
            activity: .init(steps: 8200, activeEnergy: 480, exerciseMinutes: 32, load7d: 810, load28d: 790),
            vitals: .init(respiratoryRate: 14.4, spo2: 97.5, wristTempC: 36.2, zRespiratoryRate: 0.1, zWristTemp: -0.2),
            trend7d: .init(days: 7, readinessAvg: 70, stressAvg: 38, sleepAvgH: 7.1),
            caveats: [],
            fitness: .init(
                vo2max: 42,
                vo2maxBaseline: 41,
                walkingSpeedKmh: 4.9,
                walkingSteadinessPct: 85,
                walkingAsymmetryPct: 2.1,
                flightsClimbed: 8,
                distanceWalkingKm: 5.5
            ),
            bodyComposition: .init(
                weightKg: 70.4,
                weight7dAvgKg: 70.1,
                bodyFatPct: 18,
                leanMassKg: 57,
                bmi: 22.5,
                waistCm: 82
            ),
            cardio: .init(
                systolic: nil,
                diastolic: nil,
                glucoseMgDl: nil,
                basalTempC: 36.5
            ),
            lifestyle: .init(
                daylightMin: 30,
                mindfulMin: 5,
                moodValence: -0.2,
                sleepMidpointMin: 180,
                sleepMidpointSdMin: 22
            )
        )
        let json = try payload.jsonString()
        let decoded = try JSONDecoder().decode(BriefingPayload.self, from: Data(json.utf8))
        #expect(decoded == payload)
        #expect(json.contains("\"date\":\"2026-10-30\""))
        #expect(json.contains("\"fitness\""))
        #expect(json.contains("\"lifestyle\""))
    }
}
