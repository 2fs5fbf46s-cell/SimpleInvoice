import Foundation
import SwiftData

enum JobStage: String, Codable {
    case booked
    case inProgress
    case completed
    case canceled
}

/// A single structured measurement taken at the job site (e.g. "Fence
/// length" / 200 / "ft"). Free-text unit rather than a fixed enum — this
/// app spans many trades (linear feet, square feet, gallons, ...) and a
/// closed list would fight half of them.
struct JobMeasurement: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var label: String = ""
    var value: Double = 0
    var unit: String = ""
}

@Model
final class Job {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = Foundation.UUID()
    var clientID: UUID? = nil

    var title: String = ""
    var notes: String = ""

    var startDate: Date = Foundation.Date()
    var endDate: Date = Foundation.Date()

    var locationName: String = ""
    var latitude: Double? = nil
    var longitude: Double? = nil

    // Legacy compatibility only. UI/state should rely on `stage`.
    var status: String = "scheduled"
    var stageRaw: String = JobStage.booked.rawValue
    var sourceBookingRequestId: String? = nil
    // Set when this Job was materialized from an accepted estimate (see
    // EstimateAcceptancePullService). Matched against on every materialize
    // call so a repeat pull (or the old foreground-poll fallback still
    // running alongside it) can never create a duplicate Job for the same
    // estimate — mirrors the sourceBookingRequestId idempotency pattern.
    var sourceEstimateId: String? = nil
    var calendarEventId: String? = nil

    /// Deposit tracking, decoupled from contract signing — surfaced as a
    /// soft reminder ("Deposit due before starting"), never a gate. Copied
    /// from the bundled Contract's depositAmountCents at acceptance time;
    /// depositInvoiceId/depositPaidAtMs are set once
    /// EstimateAcceptancePullService.materialize creates the actual deposit
    /// Invoice and, later, once it's paid.
    var depositAmountCents: Int? = nil
    /// The agreed price, when it wasn't priced by an estimate (a booking's
    /// total). "Bill for it" invoices this, less any deposit paid.
    var quotedTotalCents: Int? = nil
    var depositInvoiceId: String? = nil
    var depositPaidAtMs: Int64? = nil
    /// A booking deposit the owner gave back (they canceled the booking).
    /// Deposits are non-refundable otherwise, so they count as money in.
    var depositRefundedAt: Date? = nil

    /// No real date yet. A job made from an accepted estimate used to borrow
    /// the estimate's issue/due dates — in the past — and show as
    /// "Scheduled". It now waits here, off the calendar, until the owner
    /// picks a date. startDate/endDate still hold placeholders because
    /// they're non-optional; nothing should read them while this is true.
    var needsScheduling: Bool = false

    /// When the owner tapped Start / Complete / Cancel on the job screen.
    var startedAt: Date? = nil
    var completedAt: Date? = nil
    var canceledAt: Date? = nil

    /// JSON-encoded `[JobMeasurement]` — a snapshot, not a live relationship,
    /// same reasoning and same idiom as
    /// `RecurringInvoiceSchedule.lineItemsData`/`Expense.categoryRaw`:
    /// measurements are always edited as a whole alongside the job, never
    /// queried independently, so no separate `@Model` + relationship is
    /// warranted.
    var measurementsData: Data = Data()

    var measurements: [JobMeasurement] {
        get {
            (try? JSONDecoder().decode([JobMeasurement].self, from: measurementsData)) ?? []
        }
        set {
            measurementsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    var stage: JobStage {
        get { JobStage(rawValue: stageRaw) ?? .booked }
        set { stageRaw = newValue.rawValue }
    }

    /// ✅ New: workspace folder key (Folder.id.uuidString)
    var workspaceFolderKey: String? = nil
    
    @Relationship(inverse: \Invoice.job)
    var invoices: [Invoice]? = []

    // Cascade: a join row exists only to link this record to a file. Left to
    // nullify (the default) it survives its owner as an invisible orphan that
    // accumulates forever and syncs to CloudKit. The FileItem itself is not
    // cascaded — it lives in the folder workspace and other records may use it.
    @Relationship(deleteRule: .cascade, inverse: \JobAttachment.job)
    var attachments: [JobAttachment]? = nil
    
    @Relationship(inverse: \Contract.job)
    var contracts: [Contract]? = []
    

    init(
        id: UUID = Foundation.UUID(),
        businessID: UUID,
        clientID: UUID? = nil,
        title: String = "",
        notes: String = "",
        startDate: Date,
        endDate: Date,
        locationName: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        status: String = "scheduled",
        stageRaw: String = JobStage.booked.rawValue,
        sourceBookingRequestId: String? = nil,
        sourceEstimateId: String? = nil,
        calendarEventId: String? = nil,
        workspaceFolderKey: String? = nil
    ) {
        self.id = id
        self.businessID = businessID
        self.clientID = clientID
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.locationName = locationName
        self.latitude = latitude
        self.longitude = longitude
        self.status = status
        self.stageRaw = stageRaw
        self.sourceBookingRequestId = sourceBookingRequestId
        self.sourceEstimateId = sourceEstimateId
        self.calendarEventId = calendarEventId
        self.workspaceFolderKey = workspaceFolderKey
    }
}

@Model
final class Blockout {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = Foundation.UUID()

    var title: String = "Blocked"
    var startDate: Date = Foundation.Date()
    var endDate: Date = Foundation.Date()

    init(
        id: UUID = Foundation.UUID(),
        businessID: UUID,
        title: String = "Blocked",
        startDate: Date,
        endDate: Date
    ) {
        self.id = id
        self.businessID = businessID
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
    }
}
