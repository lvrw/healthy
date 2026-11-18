import Foundation

enum DayKey {
    static func startOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func key(for date: Date, calendar: Calendar = .current) -> String {
        formatter(calendar: calendar).string(from: date)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        formatter(calendar: calendar).date(from: key)
    }

    static func addingDays(_ days: Int, to date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
