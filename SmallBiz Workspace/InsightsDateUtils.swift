import Foundation

enum InsightsDateUtils {
    static let calendar = Calendar(identifier: .gregorian)

    static func startOfWeek(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func startOfMonth(for date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}
