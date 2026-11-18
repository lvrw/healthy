import Foundation

struct BriefingPayload: Codable, Sendable, Equatable {
    struct Scores: Codable, Sendable, Equatable {
        var readiness: Double?
        var stress: Double?
        var readinessComponents: ReadinessComponents?
        var stressComponents: StressComponents?
        var completeness: Int
        var missing: [String]
        var confidence: String
    }

    struct Autonomic: Codable, Sendable, Equatable {
        var hrvDailyAvg: Double?
        var hrvLatest: Double?
        var zHRV: Double?
        var hrvBaselineMs: Double?
        var restingHR: Double?
        var zRestingHR: Double?
        var restingHRBaseline: Double?
    }

    struct Sleep: Codable, Sendable, Equatable {
        var totalH: Double?
        var deepH: Double?
        var remH: Double?
        var efficiency: Double?
        var avg7dH: Double?
    }

    struct Activity: Codable, Sendable, Equatable {
        var steps: Double?
        var activeEnergy: Double?
        var exerciseMinutes: Double?
        var load7d: Double?
        var load28d: Double?
    }

    struct Vitals: Codable, Sendable, Equatable {
        var respiratoryRate: Double?
        var spo2: Double?
        var wristTempC: Double?
        var zRespiratoryRate: Double?
        var zWristTemp: Double?
    }

    struct Trend: Codable, Sendable, Equatable {
        var days: Int
        var readinessAvg: Double?
        var stressAvg: Double?
        var sleepAvgH: Double?
    }

    struct Fitness: Codable, Sendable, Equatable {
        var vo2max: Double?
        var vo2maxBaseline: Double?
        var walkingSpeedKmh: Double?
        var walkingSteadinessPct: Double?
        var walkingAsymmetryPct: Double?
        var flightsClimbed: Double?
        var distanceWalkingKm: Double?
    }

    struct BodyComposition: Codable, Sendable, Equatable {
        var weightKg: Double?
        var weight7dAvgKg: Double?
        var bodyFatPct: Double?
        var leanMassKg: Double?
        var bmi: Double?
        var waistCm: Double?
    }

    struct Cardio: Codable, Sendable, Equatable {
        var systolic: Double?
        var diastolic: Double?
        var glucoseMgDl: Double?
        var basalTempC: Double?
    }

    struct Lifestyle: Codable, Sendable, Equatable {
        var daylightMin: Double?
        var mindfulMin: Double?
        var moodValence: Double?
        var sleepMidpointMin: Double?
        var sleepMidpointSdMin: Double?
    }

    /// 累计型指标的阶段目标与当前时刻窗口，供模型判断「今天还没过完」。
    struct DayContext: Codable, Sendable, Equatable {
        struct StageTargets: Codable, Sendable, Equatable {
            var waterMl: Double?
            var energyKcalLower: Double?
            var energyKcalUpper: Double?
            var proteinG: Double?
            var fiberG: Double?
            var daylightMin: Double?
            var mindfulMin: Double?
        }

        var observedAt: String
        var isPartialDay: Bool
        var activityProgress: Double
        var daylightProgress: Double
        var windowText: String
        var stageTargets: StageTargets
    }

    /// 饮水（两侧合并）与健康 App 同步来的饮食指标；缺失字段保持 nil。
    struct Nutrition: Codable, Sendable, Equatable {
        var waterTotalMl: Double?
        var externalWaterMl: Double?
        var localWaterMl: Double?
        var energyKcal: Double?
        var carbsG: Double?
        var proteinG: Double?
        var fatG: Double?
        var fiberG: Double?
        var sugarG: Double?
        var sodiumMg: Double?
        var caffeineMg: Double?
        /// 算法给出的饮食饮水分量评分。
        var score: Double?
    }

    var date: String
    var baselineDays: Int
    var scores: Scores
    var autonomic: Autonomic
    var sleep: Sleep
    var activity: Activity
    var vitals: Vitals
    var trend7d: Trend
    var caveats: [String]
    var fitness: Fitness? = nil
    var bodyComposition: BodyComposition? = nil
    var cardio: Cardio? = nil
    var lifestyle: Lifestyle? = nil
    var nutrition: Nutrition? = nil
    /// 历史日期为完整日；今天给出清醒 / 日光窗口进度与阶段目标。
    var dayContext: DayContext? = nil

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw LLMError(kind: .decoding, message: "无法生成请求数据")
        }
        return string
    }
}

struct BriefingReport: Codable, Sendable, Equatable {
    struct ReadinessSection: Codable, Sendable, Equatable {
        var level: String
        var interpretation: String
    }

    struct StressSection: Codable, Sendable, Equatable {
        var level: String
        var analysis: String
    }

    struct Suggestion: Codable, Sendable, Identifiable, Equatable {
        var title: String
        var detail: String
        var category: String

        var id: String { title + "|" + detail }

        private enum CodingKeys: String, CodingKey {
            case title
            case detail
            case category
        }

        init(title: String, detail: String, category: String) {
            self.title = title
            self.detail = detail
            self.category = category
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            detail = try container.decodeIfPresent(String.self, forKey: .detail) ?? ""
            category = try container.decodeIfPresent(String.self, forKey: .category) ?? "other"
        }
    }

    var summary: String
    var readiness: ReadinessSection
    var stress: StressSection
    var suggestions: [Suggestion]
    var cautions: [String]
    var dataCaveats: [String]
    var disclaimer: String

    private enum CodingKeys: String, CodingKey {
        case summary
        case readiness
        case stress
        case suggestions
        case cautions
        case dataCaveats
        case disclaimer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        readiness = try container.decode(ReadinessSection.self, forKey: .readiness)
        stress = try container.decode(StressSection.self, forKey: .stress)
        suggestions = try container.decode([Suggestion].self, forKey: .suggestions)
        cautions = try container.decodeIfPresent([String].self, forKey: .cautions) ?? []
        dataCaveats = try container.decodeIfPresent([String].self, forKey: .dataCaveats) ?? []
        disclaimer = try container.decodeIfPresent(String.self, forKey: .disclaimer) ?? ""
    }

    static func parse(_ content: String) throws -> BriefingReport {
        guard let json = extractJSONObject(from: content) else {
            throw LLMError(kind: .decoding, message: "AI 返回的内容不是 JSON")
        }
        let decoded: BriefingReport
        do {
            decoded = try JSONDecoder().decode(BriefingReport.self, from: Data(json.utf8))
        } catch {
            throw LLMError(kind: .decoding, message: "AI 返回的 JSON 结构不符合要求")
        }
        let report = decoded.sanitized()
        guard !report.summary.isEmpty else {
            throw LLMError(kind: .decoding, message: "AI 返回内容为空")
        }
        guard !report.suggestions.isEmpty else {
            throw LLMError(kind: .decoding, message: "AI 没有给出可执行建议")
        }
        return report
    }

    func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard let string = String(data: data, encoding: .utf8) else {
            throw LLMError(kind: .decoding, message: "无法保存晨报")
        }
        return string
    }

    private func sanitized() -> BriefingReport {
        let allowedCategories = ["sleep", "activity", "recovery", "nutrition", "other"]
        var copy = self
        copy.summary = String(summary.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        copy.readiness.level = String(readiness.level.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        copy.readiness.interpretation = String(readiness.interpretation.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        copy.stress.level = String(stress.level.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        copy.stress.analysis = String(stress.analysis.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        copy.suggestions = Array(
            suggestions
                .map {
                    Suggestion(
                        title: String($0.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24)),
                        detail: String($0.detail.trimmingCharacters(in: .whitespacesAndNewlines).prefix(160)),
                        category: allowedCategories.contains($0.category) ? $0.category : "other"
                    )
                }
                .filter { !$0.title.isEmpty && !$0.detail.isEmpty }
                .prefix(5)
        )
        copy.cautions = Array(
            cautions
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
                .filter { !$0.isEmpty }
                .prefix(3)
        )
        copy.dataCaveats = Array(
            dataCaveats
                .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80)) }
                .filter { !$0.isEmpty }
                .prefix(5)
        )
        let trimmedDisclaimer = disclaimer.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.disclaimer = trimmedDisclaimer.isEmpty
            ? "非医疗建议，如有不适请咨询医生。"
            : String(trimmedDisclaimer.prefix(120))
        return copy
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        return String(text[start...end])
    }
}

enum PayloadNumber {
    static func rounded(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return (value * 10).rounded() / 10
    }
}
