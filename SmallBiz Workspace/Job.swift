import Foundation
import SwiftData

enum JobStage: String, Codable {
    case booked
    case inProgress
    case completed
    case canceled
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
    var depositInvoiceId: String? = nil
    var depositPaidAtMs: Int64? = nil

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
