#if DEBUG
import Foundation
import SwiftData

@MainActor
enum DemoDataInstaller {
    static func install(into context: ModelContext, calendar: Calendar = .current) throws -> Int {
        let dtos = MockHealthData.dailyMetrics(calendar: calendar)
        let existing = try context.fetch(FetchDescriptor<DailyMetrics>())
        let byKey = Dictionary(uniqueKeysWithValues: existing.map { ($0.dayKey, $0) })
        var inserted = 0

        for dto in dtos {
            if let row = byKey[dto.dayKey] {
                row.apply(dto)
            } else {
                let row = DailyMetrics(dayKey: dto.dayKey, date: dto.date)
                row.apply(dto)
                context.insert(row)
                inserted += 1
            }
        }
        try context.save()
        return inserted
    }
}
#endif
