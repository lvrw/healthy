import Foundation
import SwiftData

enum ReportStatus: String {
    case pending
    case success
    case failed
}

@Model
final class DailyReport {
    @Attribute(.unique) var dayKey: String
    var statusRaw: String
    var providerID: String?
    var model: String?
    var payloadJSON: String?
    var inputHash: String?
    var errorKind: String?
    var errorMessage: String?
    var generatedAt: Date

    init(dayKey: String) {
        self.dayKey = dayKey
        self.statusRaw = ReportStatus.pending.rawValue
        self.generatedAt = .now
    }

    var status: ReportStatus {
        get { ReportStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }
}
