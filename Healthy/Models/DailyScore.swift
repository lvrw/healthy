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
    /// 被跳过的评分项（自动不全 + 手动标记）编码后的 JSON，元素为 SourceSkip。
    /// 新增可选字段，旧库经 SwiftData 轻量迁移后为 nil，展示侧按空数组处理。
    var skippedJSON: String?
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
