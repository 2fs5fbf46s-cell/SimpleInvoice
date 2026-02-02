import Foundation
import SwiftData

/// PortalService manages local portal identities/invites/sessions (SwiftData)
/// and (for Portal Preview tooling) can mint a *web* portal session token by calling
/// the Vercel backend seed endpoint.
@MainActor
final class PortalService {

    let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Helpers

    private func businessID(for clientID: UUID) throws -> UUID {
        let allClients = try modelContext.fetch(FetchDescriptor<Client>())
        guard let c = allClients.first(where: { $0.id == clientID }) else {
            throw Self.err("Client not found.")
        }
        return c.businessID
    }

    private static func err(_ message: String) -> NSError {
        NSError(domain: "PortalService", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
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

    /// Enable/disable portal for a client.
    /// - When disabling, we revoke all active sessions (state = revoked, revokedAt set).
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
        for p in matches { p.isEnabled = false }
        try? modelContext.save()

        // Hard lockout: revoke any active sessions immediately
        try revokeAllActiveSessions(clientID: clientID)

        log(
            clientID: clientID,
            sessionID: nil,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.disabled",
            entityType: "PortalIdentity",
            entityID: matches.sorted(by: { $0.createdAt > $1.createdAt }).first?.id,
            summary: "Portal disabled for client."
        )
    }

    /// Ensures a portal identity exists and is enabled. Returns the canonical identity.
    private func forceEnablePortalIdentity(clientID: UUID) throws -> PortalIdentity {
        let all = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        let matches = all.filter { $0.clientID == clientID }
        let bizID = try businessID(for: clientID)

        if matches.isEmpty {
            let created = PortalIdentity(clientID: clientID, businessID: bizID)
            created.isEnabled = true
            modelContext.insert(created)
            try? modelContext.save()
            return created
        }

        // Enable them all to avoid "wrong one fetched" edge cases, then return newest.
        for p in matches {
            p.isEnabled = true
            p.businessID = bizID
        }
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

    /// Creates a local SwiftData portal session (used for internal tracking/audit).
    /// Note: this local token is not the same as the web portal token. The raw token is shown once.
    func createSession(
        clientID: UUID,
        deviceLabel: String? = nil,
        ttlDays: Int = 30
    ) throws -> (session: PortalSession, rawToken: String) {

        let identity = try ensureIdentity(for: clientID)
        guard identity.isEnabled else { throw Self.err("Portal is disabled for this client.") }

        let expiresAt =
        Calendar.current.date(byAdding: .day, value: ttlDays, to: Date())
        ?? Date().addingTimeInterval(60 * 60 * 24 * Double(ttlDays))

        let rawToken = PortalCrypto.randomInviteCode()
        let tokenHash = PortalCrypto.sha256(rawToken)

        let session = PortalSession(
            clientID: clientID,
            businessID: identity.businessID,
            portalIdentityID: identity.id,
            tokenHash: tokenHash,
            expiresAt: expiresAt,
            deviceLabel: deviceLabel
        )

        modelContext.insert(session)
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

    /// Revokes all currently active (non-expired, non-revoked) sessions for the client.
    func revokeAllActiveSessions(clientID: UUID) throws {
        let all = try modelContext.fetch(FetchDescriptor<PortalSession>())
        let active = all.filter { s in
            s.clientID == clientID &&
            s.revokedAt == nil &&
            s.expiresAt > Date() &&
            s.state == PortalSessionState.active
        }

        for s in active {
            s.state = PortalSessionState.revoked
            s.revokedAt = Date()
        }
        try? modelContext.save()

        if let first = active.first {
            log(
                clientID: clientID,
                sessionID: first.id,
                origin: PortalActionOrigin.internalApp,
                eventType: "portal.session.revoked.all",
                entityType: "PortalSession",
                entityID: first.id,
                summary: "Revoked \(active.count) session(s)."
            )
        }
    }

    // MARK: - Contract signing (Portal)

    enum PortalSignatureType: String, Codable {
        case drawn
        case typed
    }

    func signContractFromPortal(
        contractID: UUID,
        session: PortalSession,
        signerName: String,
        signatureType: PortalSignatureType,
        signatureImageData: Data?,
        signatureText: String?,
        consentVersion: String,
        deviceLabel: String?
    ) throws {

        let all = try modelContext.fetch(FetchDescriptor<Contract>())
        guard let contract = all.first(where: { $0.id == contractID }) else {
            throw Self.err("Contract not found.")
        }

        contract.statusRaw = "signed"
        try? modelContext.save()

        log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.portal,
            eventType: "portal.contract.signed",
            entityType: "Contract",
            entityID: contractID,
            summary: "Signed by \(signerName) (\(signatureType.rawValue)). Consent=\(consentVersion)."
        )
    }

    // MARK: - Token validation (Local preview)

    func validate(rawToken: String) throws -> PortalSession? {
        let hash = PortalCrypto.sha256(rawToken)

        let all = try modelContext.fetch(FetchDescriptor<PortalSession>())
        guard let s = all.first(where: { $0.tokenHash == hash }) else { return nil }

        guard s.expiresAt > Date() else { return nil }
        guard s.revokedAt == nil else { return nil }
        guard s.state == PortalSessionState.active else { return nil }

        return s
    }

    // MARK: - Estimate accept (Portal)

    @discardableResult
    func acceptEstimateFromPortal(estimateID: UUID, session: PortalSession) throws -> Invoice {
        let allInvoices = try modelContext.fetch(FetchDescriptor<Invoice>())
        guard let inv = allInvoices.first(where: { $0.id == estimateID }) else {
            throw Self.err("Estimate not found.")
        }

        if let client = inv.client, client.id != session.clientID {
            throw Self.err("Estimate does not belong to this client.")
        }
        if inv.businessID != session.businessID {
            throw Self.err("Estimate does not belong to this business.")
        }

        inv.estimateStatus = "accepted"
        try? modelContext.save()

        log(
            clientID: session.clientID,
            sessionID: session.id,
            origin: PortalActionOrigin.portal,
            eventType: "portal.estimate.accepted",
            entityType: "Invoice",
            entityID: inv.id,
            summary: "Estimate accepted from preview."
        )

        return inv
    }

    // MARK: - Invites

    func createInvite(
        clientID: UUID,
        ttlDays: Int = 7,
        deliveryMethod: String = "none",
        note: String? = nil
    ) throws -> (invite: PortalInvite, rawCode: String) {

        let identity = try forceEnablePortalIdentity(clientID: clientID)

        // Revoke existing active invites to keep "one active invite" behavior.
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
        let matches = all.filter { $0.codeHash == hash }

        guard let invite = matches.sorted(by: { $0.createdAt > $1.createdAt }).first else { return nil }

        guard invite.state == PortalInviteState.draft || invite.state == PortalInviteState.sent else { return nil }
        guard invite.expiresAt > Date() else { return nil }

        let identities = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        guard let identity = identities.first(where: { $0.id == invite.portalIdentityID }) else { return nil }
        guard identity.isEnabled else { return nil }

        return invite
    }

    private func revokeActiveInvites(clientID: UUID) throws {
        let all = try modelContext.fetch(FetchDescriptor<PortalInvite>())
        let active = all.filter {
            $0.clientID == clientID &&
            ($0.state == PortalInviteState.draft || $0.state == PortalInviteState.sent) &&
            $0.expiresAt > Date()
        }
        for i in active {
            i.state = PortalInviteState.revoked
            i.revokedAt = Date()
        }
        try? modelContext.save()
    }

    func acceptInviteAndCreateSession(
        rawInviteCode: String,
        deviceLabel: String? = "Portal Preview",
        sessionTTLDays: Int = 30
    ) throws -> (session: PortalSession, rawToken: String)? {

        guard let invite = try validateInvite(rawCode: rawInviteCode) else { return nil }

        invite.state = PortalInviteState.accepted
        invite.acceptedAt = Date()
        try? modelContext.save()

        let allIdentities = try modelContext.fetch(FetchDescriptor<PortalIdentity>())
        guard let identity = allIdentities.first(where: { $0.id == invite.portalIdentityID }) else {
            throw Self.err("Portal identity missing for this invite.")
        }
        guard identity.isEnabled else { throw Self.err("Portal is disabled for this client.") }

        let expectedBizID = try businessID(for: invite.clientID)
        guard invite.businessID == expectedBizID else { throw Self.err("Invite business mismatch.") }

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

    // MARK: - Portal Directory indexing hooks

    @MainActor
    func markContractSentAndIndex(_ contract: Contract) throws {
        let wasSent = (contract.statusRaw == ContractStatus.sent.rawValue)

        contract.statusRaw = ContractStatus.sent.rawValue
        try modelContext.save()

        if !wasSent {
            Task {
                do {
                    try await PortalBackend.shared.indexContractForPortalDirectory(contract: contract)
                } catch {
                    print("🌐 portal contract index failed:", error.localizedDescription)
                }
            }
        }
    }

    /// Index when invoice *transitions* into a finalized state.
    /// This version requires a `forceIndex` boolean from the caller (recommended),
    /// because this service cannot reliably infer “finalization” across all your flows.
    @MainActor
    func finalizeInvoiceAndIndex(_ invoice: Invoice, forceIndex: Bool = false) throws {
        let number = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !number.isEmpty else {
            throw NSError(domain: "Invoice", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invoice number not set (not finalized)."])
        }

        try modelContext.save()

        if forceIndex {
            Task {
                do {
                    try await PortalBackend.shared.indexInvoiceForPortalDirectory(invoice: invoice)
                } catch {
                    print("🌐 portal invoice index failed:", error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Web Seed (Vercel backend)

    struct WebSeedResponse: Decodable {
        let token: String
        let session: WebSeedSession?
    }

    struct WebSeedSession: Decodable {
        let businessId: String?
        let clientId: String?
        let scope: String?
        let exp: Double?
    }

    struct WebSeedRequest: Encodable {
        let businessId: String
        let clientId: String
        let scope: String
    }

    func acceptInviteAndCreateRemoteSession(
        rawInviteCode: String,
        backendBaseURL: String,
        adminKey: String,
        scope: String = "directory"
    ) async throws -> (session: PortalSession, token: String)? {

        guard let local = try acceptInviteAndCreateSession(rawInviteCode: rawInviteCode) else {
            return nil
        }

        let bizID = try businessID(for: local.session.clientID)

        var base = backendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }

        guard let url = URL(string: "\(base)/api/portal-session/seed") else {
            throw Self.err("Invalid Portal Backend Base URL.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let body = WebSeedRequest(
            businessId: bizID.uuidString,
            clientId: local.session.clientID.uuidString,
            scope: scope
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw Self.err("No HTTP response from portal backend.")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw Self.err("Seed failed: \(msg)")
        }

        let decoded = try JSONDecoder().decode(WebSeedResponse.self, from: data)

        log(
            clientID: local.session.clientID,
            sessionID: local.session.id,
            origin: PortalActionOrigin.internalApp,
            eventType: "portal.webSession.created",
            entityType: "PortalSession",
            entityID: local.session.id,
            summary: "Minted web token via seed endpoint."
        )

        return (local.session, decoded.token)
    }
}

// MARK: - Compatibility wrappers (keep older call sites compiling)

extension PortalService {

    /// Back-compat: older code may call this name.
    func ensurePortalIdentity(clientID: UUID) throws -> PortalIdentity {
        try ensureIdentity(for: clientID)
    }

    /// Back-compat: older preview code may call this.
    func createInviteCode(clientID: UUID, ttlDays: Int = 7) throws -> String {
        let result = try createInvite(clientID: clientID, ttlDays: ttlDays)
        return result.rawCode
    }
}
