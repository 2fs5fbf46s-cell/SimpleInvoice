import Foundation
import SwiftData

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

    var status: String = "scheduled"
    var sourceBookingRequestId: String? = nil

    /// ✅ New: workspace folder key (Folder.id.uuidString)
    var workspaceFolderKey: String? = nil
    
    @Relationship(inverse: \Invoice.job)
    var invoices: [Invoice]? = []

    @Relationship(inverse: \JobAttachment.job) var attachments: [JobAttachment]? = nil
    
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
        sourceBookingRequestId: String? = nil,
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
        self.sourceBookingRequestId = sourceBookingRequestId
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
