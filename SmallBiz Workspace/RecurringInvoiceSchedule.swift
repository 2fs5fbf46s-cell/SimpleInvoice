import Foundation
import SwiftData

enum RecurringCadence: String, Codable, CaseIterable, Identifiable {
    case weekly
    case biweekly
    case monthly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .biweekly: return "Every 2 Weeks"
        case .monthly: return "Monthly"
        }
    }

    /// Mirrors the backend's `advanceNextRun` exactly (see recurringSchedules.ts)
    /// so a locally-previewed "next run" date always matches what the server
    /// will actually compute after generating.
    func advancing(from date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .biweekly:
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        }
    }
}

struct RecurringScheduleLineItem: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var itemDescription: String = ""
    var quantity: Double = 1
    var unitPrice: Double = 0

    var lineTotal: Double { quantity * unitPrice }
}

@Model
final class RecurringInvoiceSchedule {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = Foundation.UUID()
    var clientID: UUID = Foundation.UUID()

    var active: Bool = true
    var cadenceRaw: String = RecurringCadence.monthly.rawValue
    var nextRunAt: Date = Foundation.Date()

    /// Days after generation the invoice is due — mirrors the schedule's own
    /// "payment terms" without needing to parse free text like "Net 14".
    var netDays: Int = 14
    var invoiceNumberPrefix: String = "REC"
    var taxRatePercent: Double = 0
    var discountAmount: Double = 0
    var notes: String = ""

    /// JSON-encoded `[RecurringScheduleLineItem]` — a snapshot, not a live
    /// relationship, since a schedule's items are edited independently of
    /// any one invoice. Bridged via `lineItems` below the same way `Expense`
    /// bridges `category` over `categoryRaw`.
    var lineItemsData: Data = Data()

    var createdAt: Date = Foundation.Date()
    var updatedAt: Date = Foundation.Date()
    var lastGeneratedAt: Date? = nil
    var needsBackendSync: Bool = true

    var cadence: RecurringCadence {
        get { RecurringCadence(rawValue: cadenceRaw) ?? .monthly }
        set { cadenceRaw = newValue.rawValue }
    }

    var lineItems: [RecurringScheduleLineItem] {
        get {
            (try? JSONDecoder().decode([RecurringScheduleLineItem].self, from: lineItemsData)) ?? []
        }
        set {
            lineItemsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var subtotal: Double {
        lineItems.reduce(0) { $0 + $1.lineTotal }
    }

    var discountedSubtotal: Double {
        max(0, subtotal - discountAmount)
    }

    var taxAmount: Double {
        max(0, discountedSubtotal * (taxRatePercent / 100))
    }

    var total: Double {
        discountedSubtotal + taxAmount
    }

    init(
        businessID: UUID,
        clientID: UUID,
        cadence: RecurringCadence = .monthly,
        nextRunAt: Date = Foundation.Date()
    ) {
        self.businessID = businessID
        self.clientID = clientID
        self.cadenceRaw = cadence.rawValue
        self.nextRunAt = nextRunAt
    }
}
