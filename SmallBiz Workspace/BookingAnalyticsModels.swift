import Foundation

enum BookingAnalyticsRange: String, CaseIterable, Identifiable {
    case days7
    case days30
    case days90
    case ytd

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .days7: return "7D"
        case .days30: return "30D"
        case .days90: return "90D"
        case .ytd: return "YTD"
        }
    }

    var subtitle: String {
        switch self {
        case .days7: return "last 7 days"
        case .days30: return "last 30 days"
        case .days90: return "last 90 days"
        case .ytd: return "year to date"
        }
    }

    var usesWeeklyBuckets: Bool {
        self == .days90 || self == .ytd
    }

    func periodStart(now: Date = .now, calendar: Calendar = .current) -> Date {
        switch self {
        case .days7:
            return calendar.date(byAdding: .day, value: -7, to: now) ?? now
        case .days30:
            return calendar.date(byAdding: .day, value: -30, to: now) ?? now
        case .days90:
            return calendar.date(byAdding: .day, value: -90, to: now) ?? now
        case .ytd:
            let year = calendar.component(.year, from: now)
            return calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? now
        }
    }
}

enum BookingAnalyticsDetailFilter: Equatable {
    case all
    case pending
    case approved
    case declined
    case depositRequested
    case depositPaid
    case serviceType(String)
}

struct BookingTrendPoint: Identifiable, Equatable {
    let date: Date
    let requests: Int
    let approved: Int

    var id: Date { date }
}

struct BookingFunnelRow: Identifiable, Equatable {
    let id: String
    let title: String
    let count: Int
    let ratio: Double
}

struct BookingServiceStat: Identifiable, Equatable {
    let id: String
    let name: String
    let count: Int
    let ratio: Double
}

struct BookingAnalyticsDelta: Equatable {
    let requests: Int
    let approved: Int
    let declined: Int
    let depositRequested: Int
    let depositsPaid: Int
    let revenueCents: Int
}

struct BookingAnalyticsSnapshot: Equatable {
    let range: BookingAnalyticsRange
    let generatedAt: Date

    let totalRequests: Int
    let pendingCount: Int
    let approvedCount: Int
    let declinedCount: Int
    let depositRequestedCount: Int
    let depositsPaidCount: Int

    let conversionRate: Double
    let depositConversionRate: Double

    let depositRevenueCents: Int
    let paidInvoiceRevenueCents: Int
    let totalRevenueCents: Int

    let trend: [BookingTrendPoint]
    let funnel: [BookingFunnelRow]
    let topServices: [BookingServiceStat]
    let recentActivity: [BookingRequestItem]
    let inRangeBookings: [BookingRequestItem]

    let delta: BookingAnalyticsDelta?
}
