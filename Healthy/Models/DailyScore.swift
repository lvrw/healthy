import Foundation
import SwiftData

@Model
final class DailyScore {
    @Attribute(.unique) var dayKey: String
    var date: Date
    var readiness: Double?
    var stress: Double?
    var readinessComponentsJSON: String?
    var stressComponentsJSON: String?
    var completeness: Int
    var missing: String
    var baselineDays: Int
    var confidenceRaw: String
    var computedAt: Date

    init(dayKey: String, date: Date) {
        self.dayKey = dayKey
        self.date = date
        self.completeness = 0
        self.missing = ""
        self.baselineDays = 0
        self.confidenceRaw = ScoreConfidence.insufficient.rawValue
        self.computedAt = .now
    }
}
