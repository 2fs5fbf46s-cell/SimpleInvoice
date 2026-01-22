import Foundation
import SwiftData

@MainActor
final class PortalService {

    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    private func businessID(for clientID: UUID) throws -> UUID {
        let allClients = try modelContext.fetch(FetchDescriptor<Client>())
        guard let c = allClients.first(where: { $0.id == clientID }) else {
            throw Self.err("Client not found.")
        }
        return c.businessID
    }


    // MARK: - Identity

    func ensureIdentity(for clientID: UUID) throws -> PortalIdentity {
        let all = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        let matches = all.filter { $0.clientID == clientID }

        if let enabled = matches.first(where: { $0.isEnabled }) {
            return enabled
        }
        if let newest = matches.sorted(by: { $0.createdAt > $1.createdAt }).first {
            return newest
        }

        let bizID = try businessID(for: clientID)
        let created = PortalIdentity(clientID: clientID, businessID: bizID)
        modelContext.insert(created)
        try? modelContext.save()
        return created
    }

    /// Used by Portal Preview UI.
    /// - enable: ensures identity exists + is enabled
    /// - disable: disables identity + revokes all active sessions immediately
    func setEnabled(_ enabled: Bool, clientID: UUID) throws {
        if enabled {
            let identity = try forceEnablePortalIdentity(clientID: clientID)

            log(
                clientID: clientID,
                sessionID: nil,
                origin: PortalActionOrigin.internalApp,
                eventType: "portal.enabled",
                entityType: "PortalIdentity",
                entityID: identity.id,
                summary: "Portal enabled for client."
            )
            return
        }

        // Disable all identities for this client (defensive if duplicates exist)
        let all = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        let matches = all.filter { $0.clientID == clientID }

        for p in matches {
            p.isEnabled = false
        }
        try? modelContext.save()

        // ✅ Hard lockout: revoke any active sessions immediately
        try revokeAllActiveSessions(clientID: clientID, reason: "portal.disabled")

        log(
            clientID: clientID,
            sessionID: nil,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.disabled",
            entityType: "PortalIdentity",
            entityID: matches.first?.id,
            summary: "Portal disabled for client."
        )
    }

    /// Ensures a portal identity exists and is enabled. Returns the "canonical" identity.
    private func forceEnablePortalIdentity(clientID: UUID) throws -> PortalIdentity {
        let all = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        let matches = all.filter { $0.clientID == clientID }
                

        if matches.isEmpty {
            let bizID = try businessID(for: clientID)
            let created = PortalIdentity(clientID: clientID, businessID: bizID)
            created.isEnabled = true
            modelContext.insert(created)
            try? modelContext.save()
            return created
        }
        
        
        let bizID = try businessID(for: clientID)
        // Enable them all to avoid "wrong one fetched" issues, then return newest
        for p in matches { p.isEnabled = true; p.businessID = bizID }

        try? modelContext.save()

        return matches.sorted(by: { $0.createdAt > $1.createdAt }).first!
    }

    // MARK: - Audit

    func log(
        clientID: UUID,
        sessionID: UUID?,
        origin: String,
        eventType: String,
        entityType: String? = nil,
        entityID: UUID? = nil,
        summary: String? = nil
    ) {
        let bizID = (try? businessID(for: clientID)) ?? UUID()

        let event = PortalAuditEvent(
            clientID: clientID,
            businessID: bizID,
            sessionID: sessionID,
            origin: origin,
            eventType: eventType,
            entityType: entityType,
            entityID: entityID,
            summary: summary
        )
        modelContext.insert(event)
        try? modelContext.save()
    }

    // MARK: - Sessions

    /// Creates a session and returns the raw token ONCE.
    func createSession(
        clientID: UUID,
        deviceLabel: String? = "Portal Preview",
        ttlDays: Int = 30
    ) throws -> (session: PortalSession, rawToken: String) {

        let identity = try forceEnablePortalIdentity(clientID: clientID)

        let rawToken = PortalCrypto.randomToken()
        let tokenHash = PortalCrypto.sha256(rawToken)

        let expiresAt =
        Calendar.current.date(byAdding: .day, value: ttlDays, to: Date())
        ?? Date().addingTimeInterval(60 * 60 * 24 * Double(ttlDays))

        let bizID = try businessID(for: clientID)

        let session = PortalSession(
            clientID: clientID,
            businessID: bizID,
            portalIdentityID: identity.id,
            tokenHash: tokenHash,
            expiresAt: expiresAt,
            deviceLabel: deviceLabel
        )


        modelContext.insert(session)
        identity.lastLoginAt = Date()
        try? modelContext.save()

        log(
            clientID: clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.session.created",
            entityType: "PortalSession",
            entityID: session.id
        )

        return (session, rawToken)
    }

    func revokeSession(_ session: PortalSession) throws {
        session.state = PortalSessionState.revoked
        session.revokedAt = Date()
        try? modelContext.save()

        log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.session.revoked",
            entityType: "PortalSession",
            entityID: session.id
        )
    }

    // MARK: - Session Admin

    /// Revokes all non-expired, non-revoked sessions for the client.
    func revokeAllActiveSessions(clientID: UUID, reason: String = "portal.disabled") throws {
        let all = try modelContext.fetch(FetchDescriptor<PortalSession>())
        let active = all.filter {
            $0.clientID == clientID &&
            $0.state != PortalSessionState.revoked &&
            $0.state != PortalSessionState.expired
        }

        guard !active.isEmpty else { return }

        for s in active {
            s.state = PortalSessionState.revoked
            s.revokedAt = Date()
        }

        try? modelContext.save()

        log(
            clientID: clientID,
            sessionID: nil,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.sessions.revoked",
            entityType: "PortalSession",
            entityID: nil,
            summary: "Revoked \(active.count) session(s). Reason: \(reason)"
        )
    }

    /// Validates raw token -> returns session if valid AND portal identity is enabled.
    func validate(rawToken: String) throws -> PortalSession? {
        let hash = PortalCrypto.sha256(rawToken)

        let allSessions = try modelContext.fetch(FetchDescriptor<PortalSession>())
        guard let session = allSessions.first(where: { $0.tokenHash == hash }) else { return nil }

        if session.state == PortalSessionState.revoked { return nil }

        if session.expiresAt < Date() {
            session.state = PortalSessionState.expired
            try? modelContext.save()
            return nil
        }
        let expectedBizID = try businessID(for: session.clientID)
        if session.businessID != expectedBizID {
            session.state = PortalSessionState.revoked
            session.revokedAt = .now
            try? modelContext.save()

            log(
                clientID: session.clientID,
                sessionID: session.id,
                origin: PortalActionOrigin.internalApp,
                eventType: "portal.session.revoked_business_mismatch",
                entityType: "PortalSession",
                entityID: session.id,
                summary: "Session business mismatch; revoked."
            )
            return nil
        }
        

        // ✅ Immediate lockout if portal identity is disabled
        let identities = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        if let identity = identities.first(where: { $0.id == session.portalIdentityID }) {

            // disabled identity lockout
            if identity.isEnabled == false {
                session.state = PortalSessionState.revoked
                session.revokedAt = Date()
                try? modelContext.save()

                log(
                    clientID: session.clientID,
                    sessionID: session.id,
                    origin: PortalActionOrigin.internalApp,
                    eventType: "portal.session.blocked_disabled_identity",
                    entityType: "PortalSession",
                    entityID: session.id,
                    summary: "Token rejected because portal is disabled for this client."
                )
                return nil
            }

            // business mismatch identity <-> session
            if identity.businessID != session.businessID {
                session.state = PortalSessionState.revoked
                session.revokedAt = .now
                try? modelContext.save()

                log(
                    clientID: session.clientID,
                    sessionID: session.id,
                    origin: PortalActionOrigin.internalApp,
                    eventType: "portal.session.revoked_identity_business_mismatch",
                    entityType: "PortalSession",
                    entityID: session.id,
                    summary: "Identity/session business mismatch; revoked."
                )
                return nil
            }
        }
       
        return session
    }
    
    

    // MARK: - Invites

    /// Creates an invite and returns the raw code ONCE.
    func createInvite(
        clientID: UUID,
        ttlDays: Int = 7,
        deliveryMethod: String = "none",
        note: String? = nil
    ) throws -> (invite: PortalInvite, rawCode: String) {

        let identity = try forceEnablePortalIdentity(clientID: clientID)

        // Revoke existing draft/sent invites (keeps "one active invite" behavior)
        try revokeActiveInvites(clientID: clientID)

        let rawCode = PortalCrypto.randomInviteCode()
        let codeHash = PortalCrypto.sha256(rawCode)

        let expiresAt =
        Calendar.current.date(byAdding: .day, value: ttlDays, to: Date())
        ?? Date().addingTimeInterval(60 * 60 * 24 * Double(ttlDays))

        let bizID = try businessID(for: clientID)

        let invite = PortalInvite(
            clientID: clientID,
            businessID: bizID,
            portalIdentityID: identity.id,
            codeHash: codeHash,
            expiresAt: expiresAt,
            deliveryMethod: deliveryMethod,
            note: note
        )

        modelContext.insert(invite)
        try? modelContext.save()

        log(
            clientID: clientID,
            sessionID: nil,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.invite.created",
            entityType: "PortalInvite",
            entityID: invite.id
        )

        return (invite, rawCode)
    }

    func markInviteSent(_ invite: PortalInvite) throws {
        invite.state = PortalInviteState.sent
        invite.lastSentAt = Date()
        invite.sendCount += 1
        try? modelContext.save()

        log(
            clientID: invite.clientID,
            sessionID: nil,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.invite.sent",
            entityType: "PortalInvite",
            entityID: invite.id
        )
    }

    func revokeInvite(_ invite: PortalInvite) throws {
        invite.state = PortalInviteState.revoked
        invite.revokedAt = Date()
        try? modelContext.save()

        log(
            clientID: invite.clientID,
            sessionID: nil,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.invite.revoked",
            entityType: "PortalInvite",
            entityID: invite.id
        )
    }

    func validateInvite(rawCode: String) throws -> PortalInvite? {
        let hash = PortalCrypto.sha256(rawCode)

        let all = try modelContext.fetch(FetchDescriptor<PortalInvite>())
        guard let invite = all.first(where: { $0.codeHash == hash }) else { return nil }

        if invite.state == PortalInviteState.revoked { return nil }
        if invite.state == PortalInviteState.accepted { return nil }

        if invite.expiresAt < Date() {
            invite.state = PortalInviteState.expired
            try? modelContext.save()
            return nil
        }

        return invite
    }

    /// Accept invite -> marks invite accepted -> creates portal session token
    func acceptInviteAndCreateSession(
        rawInviteCode: String,
        deviceLabel: String? = "Portal Preview",
        sessionTTLDays: Int = 30
    ) throws -> (session: PortalSession, rawToken: String)? {

        guard let invite = try validateInvite(rawCode: rawInviteCode) else { return nil }

        // Mark invite accepted
        invite.state = PortalInviteState.accepted
        invite.acceptedAt = Date()
        try? modelContext.save()

        // Ensure identity exists + enabled
        let allIdentities = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        guard let identity = allIdentities.first(where: { $0.id == invite.portalIdentityID }) else {
            throw Self.err("Portal identity missing for this invite.")
        }
        
        let expectedBizID = try businessID(for: invite.clientID)
        guard invite.businessID == expectedBizID else {
            throw Self.err("Invite business mismatch.")
        }


        guard identity.isEnabled else {
            throw Self.err("Portal is disabled for this client.")
        }

        // Create session
        let result = try createSession(
            clientID: invite.clientID,
            deviceLabel: deviceLabel,
            ttlDays: sessionTTLDays
        )

        invite.acceptedSessionID = result.session.id
        try? modelContext.save()

        log(
            clientID: invite.clientID,
            sessionID: result.session.id,
            origin: PortalActionOrigin.portal,
            eventType: "portal.invite.accepted",
            entityType: "PortalInvite",
            entityID: invite.id
        )

        return result
    }

    // MARK: - Step 2: Portal-side Accept Estimate (NO job creation)

    enum PortalActionError: LocalizedError {
        case sessionInvalid
        case estimateNotFound
        case notYourClient
        case notAnEstimate
        case alreadyFinal(String)
        case lockedBySignedContract

        var errorDescription: String? {
            switch self {
            case .sessionInvalid: return "Portal session is invalid or expired."
            case .estimateNotFound: return "Estimate not found."
            case .notYourClient: return "This estimate does not belong to this client."
            case .notAnEstimate: return "This record is not an estimate."
            case .alreadyFinal(let s): return "Estimate is already \(s)."
            case .lockedBySignedContract: return "Estimate is locked due to a signed contract."
            }
        }
    }
    enum PortalSignatureType: String {
        case drawn
        case typed
    }


    func acceptEstimateFromPortal(
        estimateID: UUID,
        session: PortalSession
    ) throws {

        // Session sanity
        if session.state == PortalSessionState.revoked { throw PortalActionError.sessionInvalid }
        if session.expiresAt <= Date() { throw PortalActionError.sessionInvalid }

        // Find estimate safely
        let allInvoices = try modelContext.fetch(FetchDescriptor<Invoice>())
        guard let estimate = allInvoices.first(where: { $0.id == estimateID }) else {
            throw PortalActionError.estimateNotFound
        }

        guard estimate.documentType == "estimate" else {
            throw PortalActionError.notAnEstimate
        }

        guard estimate.client?.id == session.clientID else {
            throw PortalActionError.notYourClient
        }

        // Lock if signed contract exists
        let signedExists = (estimate.estimateContracts ?? []).contains {
            $0.statusRaw == ContractStatus.signed.rawValue
        }
        if signedExists { throw PortalActionError.lockedBySignedContract }

        // Prevent re-finalization
        if estimate.estimateStatus == "accepted" {
            throw PortalActionError.alreadyFinal("accepted")
        }
        if estimate.estimateStatus == "declined" {
            throw PortalActionError.alreadyFinal("declined")
        }

        estimate.estimateStatus = "accepted"
        estimate.estimateAcceptedAt = Date()

        try? modelContext.save()

        log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.portal,
            eventType: "estimate.accepted.portal",
            entityType: "Invoice",
            entityID: estimate.id,
            summary: "Estimate accepted via client portal."
        )
    }
    
    func signContractFromPortal(
        contractID: UUID,
        session: PortalSession,
        signerName: String,
        signatureType: PortalSignatureType,
        signatureImageData: Data?,
        signatureText: String?,
        consentVersion: String = "portal-consent-v1",
        deviceLabel: String? = nil
    ) throws {

        // Session sanity (mirror acceptEstimateFromPortal)
        if session.state == PortalSessionState.revoked { throw PortalActionError.sessionInvalid }
        if session.expiresAt <= Date() { throw PortalActionError.sessionInvalid }

        // Fetch contract
        let allContracts = try modelContext.fetch(FetchDescriptor<Contract>())
        guard let contract = allContracts.first(where: { $0.id == contractID }) else {
            throw Self.err("Contract not found.")
        }

        // Ownership boundaries
        guard contract.businessID == session.businessID else {
            log(
                clientID: session.clientID,
                sessionID: session.id,
                origin: PortalActionOrigin.portal,
                eventType: "contract.sign.blocked.portal",
                entityType: "Contract",
                entityID: contractID,
                summary: "Business mismatch."
            )
            throw Self.err("Not authorized.")
        }

        guard contract.client?.id == session.clientID else {
            log(
                clientID: session.clientID,
                sessionID: session.id,
                origin: PortalActionOrigin.portal,
                eventType: "contract.sign.blocked.portal",
                entityType: "Contract",
                entityID: contractID,
                summary: "Client mismatch."
            )
            throw Self.err("Not authorized.")
        }

        // Step 4 rule: only sign when SENT
        let status = ContractStatus(rawValue: contract.statusRaw) ?? .draft
        guard status == .sent else {
            log(
                clientID: session.clientID,
                sessionID: session.id,
                origin: PortalActionOrigin.portal,
                eventType: "contract.sign.blocked.portal",
                entityType: "Contract",
                entityID: contractID,
                summary: "Contract must be 'sent' to sign. Current: \(status.rawValue)"
            )
            throw Self.err("Contract must be sent before it can be signed.")
        }

        // Prevent double-sign
        if isClientAlreadySigned(contract) {
            log(
                clientID: session.clientID,
                sessionID: session.id,
                origin: PortalActionOrigin.portal,
                eventType: "contract.sign.blocked.portal",
                entityType: "Contract",
                entityID: contractID,
                summary: "Client signature already exists."
            )
            throw Self.err("Contract is already signed.")
        }

        // Validate payload
        let cleanName = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw Self.err("Signer name is required.") }

        switch signatureType {
        case .drawn:
            guard let data = signatureImageData, !data.isEmpty else {
                throw Self.err("Drawn signature data is required.")
            }
        case .typed:
            let t = (signatureText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else {
                throw Self.err("Typed signature text is required.")
            }
        }

        // Audit: submission
        log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.portal,
            eventType: "contract.sign.submitted.portal",
            entityType: "Contract",
            entityID: contractID,
            summary: "Signature submitted (\(signatureType.rawValue))."
        )

        // Create signature (append-only artifact)
        let sig = ContractSignature(
            businessID: session.businessID,
            clientID: session.clientID,
            contract: contract,
            sessionID: session.id,
            signerRole: "client",
            signerName: cleanName,
            signatureType: signatureType.rawValue,
            signatureImageData: signatureType == .drawn ? signatureImageData : nil,
            signatureText: signatureType == .typed ? signatureText : nil,
            consentVersion: consentVersion,
            contractBodyHash: contractBodyHash(for: contract),
            deviceLabel: deviceLabel ?? session.deviceLabel
        )

        modelContext.insert(sig)

        // Update contract (Step 4.2 fields should exist now)
        contract.statusRaw = ContractStatus.signed.rawValue
        contract.signedAt = Date()
        contract.signedByName = cleanName
        contract.updatedAt = Date()

        try modelContext.save()

        // Audit: signed
        log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.portal,
            eventType: "contract.signed.portal",
            entityType: "Contract",
            entityID: contractID,
            summary: "Contract signed by client."
        )
    }


    // MARK: - Helpers

    private func revokeActiveInvites(clientID: UUID) throws {
        let all = try modelContext.fetch(FetchDescriptor<PortalInvite>())
        let matches = all.filter {
            $0.clientID == clientID &&
            ($0.state == PortalInviteState.draft || $0.state == PortalInviteState.sent)
        }

        guard !matches.isEmpty else { return }

        for inv in matches {
            inv.state = PortalInviteState.revoked
            inv.revokedAt = Date()
        }
        try? modelContext.save()
    }

    private static func err(_ message: String) -> NSError {
        NSError(domain: "PortalService", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private func contractBodyHash(for contract: Contract) -> String {
        // Hash what matters legally. Keep stable: title + rendered body.
        let raw = (contract.title + "\n" + contract.renderedBody)
        return PortalCrypto.sha256(raw)
    }

    private func isClientAlreadySigned(_ contract: Contract) -> Bool {
        let sigs = contract.signatures ?? []
        return sigs.contains(where: { $0.signerRole == "client" })
    }
}
