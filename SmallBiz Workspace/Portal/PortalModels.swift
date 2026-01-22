import Foundation
import SwiftData

// MARK: - Portal Constants (CloudKit-safe String "enums")

enum PortalActionOrigin {
    static let internalApp = "internal"
    static let portal = "portal"
}

enum PortalSessionState {
    static let active = "active"
    static let revoked = "revoked"
    static let expired = "expired"
}

enum PortalInviteState {
    static let draft = "draft"       // created, not yet sent
    static let sent = "sent"         // sent at least once
    static let accepted = "accepted" // invite consumed/activated
    static let revoked = "revoked"   // manually disabled
    static let expired = "expired"   // time-based expiry
}

enum PortalInviteDelivery {
    static let none = "none"
    static let email = "email"
    static let sms = "sms"
    static let manual = "manual"     // copy/paste
}

// MARK: - Portal Identity (1 per Client)

@Model
final class PortalIdentity {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()


    // Link to Client.id (kept as UUID to avoid relationship inverses)
    var clientID: UUID = Foundation.UUID()

    // Status
    var isEnabled: Bool = false
    var createdAt: Date = Foundation.Date()
    var lastInviteSentAt: Date? = nil
    var lastLoginAt: Date? = nil

    // Future (Sign in with Apple / web): store stable auth subject/identifier
    var externalAuthSubject: String? = nil

    // Public handle (for future portal URLs). Non-guessable.
    var publicHandle: String = ""

    init(clientID: UUID, businessID: UUID) {
        self.clientID = clientID
        self.businessID = businessID
        self.createdAt = .now
        self.publicHandle = Self.makeHandle()
    }

    static func makeHandle() -> String {
        // 32 hex chars
        Foundation.UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }
}

// MARK: - Portal Invite (no backend yet)

@Model
final class PortalInvite {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()


    var clientID: UUID = Foundation.UUID()
    var portalIdentityID: UUID = Foundation.UUID()

    // Store ONLY the hash. Raw code is shown once at creation time.
    var codeHash: String = ""

    var createdAt: Date = Foundation.Date()
    var expiresAt: Date = Foundation.Date()

    // State (PortalInviteState.*)
    var state: String = PortalInviteState.draft

    // Delivery metadata
    var deliveryMethod: String = PortalInviteDelivery.none
    var lastSentAt: Date? = nil
    var sendCount: Int = 0

    // Acceptance metadata
    var acceptedAt: Date? = nil
    var acceptedSessionID: UUID? = nil

    // Revocation metadata
    var revokedAt: Date? = nil

    var note: String? = nil

    init(
        clientID: UUID,
        businessID: UUID,
        portalIdentityID: UUID,
        codeHash: String,
        expiresAt: Date,
        deliveryMethod: String = PortalInviteDelivery.none,
        note: String? = nil
    ) {
        self.clientID = clientID
        self.businessID = businessID
        self.portalIdentityID = portalIdentityID
        self.codeHash = codeHash
        self.createdAt = .now
        self.expiresAt = expiresAt
        self.state = PortalInviteState.draft
        self.deliveryMethod = deliveryMethod
        self.note = note
    }
}

// MARK: - Portal Session (token-based)

@Model
final class PortalSession {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()


    var clientID: UUID = Foundation.UUID()
    var portalIdentityID: UUID = Foundation.UUID()

    // Store ONLY the hash. Raw token is shown once at creation time.
    var tokenHash: String = ""

    var createdAt: Date = Foundation.Date()
    var expiresAt: Date = Foundation.Date()
    var revokedAt: Date? = nil

    // PortalSessionState.*
    var state: String = PortalSessionState.active

    // e.g. "Portal Preview", "Web", "iPhone"
    var deviceLabel: String? = nil

    init(
        clientID: UUID,
        businessID: UUID,
        portalIdentityID: UUID,
        tokenHash: String,
        expiresAt: Date,
        deviceLabel: String? = nil
    ) {
        self.clientID = clientID
        self.businessID = businessID
        self.portalIdentityID = portalIdentityID
        self.tokenHash = tokenHash
        self.createdAt = .now
        self.expiresAt = expiresAt
        self.state = PortalSessionState.active
        self.deviceLabel = deviceLabel
    }
}

// MARK: - Portal Audit Event (recommended)

@Model
final class PortalAuditEvent {
    var id: UUID = Foundation.UUID()
    var businessID: UUID = UUID()

    // Who/where
    var clientID: UUID = Foundation.UUID()
    var sessionID: UUID? = nil
    var origin: String = PortalActionOrigin.internalApp

    // What happened
    // Examples: "estimate.viewed", "estimate.accepted", "contract.signed"
    var eventType: String = ""
    var entityType: String? = nil
    var entityID: UUID? = nil

    var createdAt: Date = Foundation.Date()
    var summary: String? = nil

    init(
        clientID: UUID,
        businessID: UUID,
        sessionID: UUID?,
        origin: String,
        eventType: String,
        entityType: String? = nil,
        entityID: UUID? = nil,
        summary: String? = nil
    ) {
        self.clientID = clientID
        self.businessID = businessID
        self.sessionID = sessionID
        self.origin = origin
        self.eventType = eventType
        self.entityType = entityType
        self.entityID = entityID
        self.createdAt = .now
        self.summary = summary
    }
}
