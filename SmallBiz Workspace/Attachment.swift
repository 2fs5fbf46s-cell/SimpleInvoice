import Foundation
import SwiftData

enum AttachmentOwnerType: String, Codable {
    case client, invoice, contract, job
}

@Model
final class Attachment {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = Foundation.UUID()

    var ownerTypeRaw: String = AttachmentOwnerType.client.rawValue
    var ownerID: UUID = Foundation.UUID()

    var fileItemID: UUID = Foundation.UUID()
    var createdAt: Date = Foundation.Date()

    var ownerType: AttachmentOwnerType {
        get { AttachmentOwnerType(rawValue: ownerTypeRaw) ?? .client }
        set { ownerTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = Foundation.UUID(),
        businessID: UUID,
        ownerType: AttachmentOwnerType,
        ownerID: UUID,
        fileItemID: UUID,
        createdAt: Date = Foundation.Date()
    ) {
        self.id = id
        self.businessID = businessID
        self.ownerTypeRaw = ownerType.rawValue
        self.ownerID = ownerID
        self.fileItemID = fileItemID
        self.createdAt = createdAt
    }
}
