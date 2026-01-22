import Foundation
import SwiftData

enum AuditAction: String, Codable {
    case create, update, delete, statusChange, paymentSync, fileAdded, fileRemoved
}

@Model
final class AuditEvent {
    var id: UUID = UUID()
    var businessID: UUID = UUID()

    var entityType: String = ""
    var entityID: UUID = UUID()
    var actionRaw: String = AuditAction.update.rawValue

    var summary: String = ""
    var diffJSON: String? = nil

    var deviceID: String = "unknown-device"
    var createdAt: Date = Foundation.Date()


    var action: AuditAction {
        get { AuditAction(rawValue: actionRaw) ?? .update }
        set { actionRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        businessID: UUID,
        entityType: String,
        entityID: UUID,
        action: AuditAction,
        summary: String,
        diffJSON: String? = nil,
        deviceID: String,
        createdAt: Date = .now
    ) {
        self.id = id
        self.businessID = businessID
        self.entityType = entityType
        self.entityID = entityID
        self.actionRaw = action.rawValue
        self.summary = summary
        self.diffJSON = diffJSON
        self.deviceID = deviceID
        self.createdAt = createdAt
    }
}
