//
//  ContractLifecycle.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Draft → Sent → Signed, or Canceled: one set of names for every screen.
/// They used to disagree ("CANCELLED", "EXPIRED", "Canceled", "Cancelled").
enum ContractDisplayStatus: Equatable {
    case draft
    case sent
    case signed
    case canceled

    init(_ contract: Contract) {
        switch contract.status {
        case .draft: self = .draft
        case .sent: self = .sent
        case .signed: self = .signed
        case .cancelled: self = .canceled
        }
    }

    var label: String {
        switch self {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .signed: return "Signed"
        case .canceled: return "Canceled"
        }
    }

    var foreground: Color {
        switch self {
        case .draft: return .secondary
        case .sent: return SBWTheme.brand
        case .signed: return SBWTheme.success
        case .canceled: return .red
        }
    }
}

/// The name the client knows the business by, for emails and the portal
/// header, from the contract's own business (not whichever profile is first).
@MainActor
enum ContractBusiness {
    static func profile(for contract: Contract, in context: ModelContext) -> BusinessProfile? {
        let businessID = contract.businessID
        return try? context.fetch(
            FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == businessID })
        ).first
    }

    static func name(for contract: Contract, in context: ModelContext) -> String? {
        let name = (profile(for: contract, in: context)?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

/// Send for Signature and Send Reminder.
///
/// Contracts had no real send: "Send" on the summary marked it sent and
/// opened a share sheet with the PDF, and nothing reached the portal unless
/// the checkmark was tapped afterwards. A contract bundled with an estimate
/// went "sent" on acceptance without the client being told. This publishes
/// the contract to the client's portal and has the server email them a link
/// to sign, like estimates and invoices.
@MainActor
enum ContractSendService {
    enum Kind: String {
        case send
        case reminder
    }

    enum Outcome {
        case emailed(to: String)
        /// In the client's portal, but the email didn't go out; `link`
        /// opens it, when the server returned one, to share another way.
        case publishedNotEmailed(link: String?, reason: String)
    }

    enum SendError: LocalizedError {
        case alreadySigned
        case canceled
        case noClient
        case noClientEmail
        case portalDisabled
        case emptyBody
        case hasBlanks([String])
        case publishFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadySigned: return "This contract is already signed."
            case .canceled: return "This contract was canceled. Reopen it to send it again."
            case .noClient: return "Choose a client for this contract before sending it."
            case .noClientEmail: return "Add an email address to this client to send them the contract."
            case .portalDisabled: return "Turn on the client portal for this client to send them the contract."
            case .emptyBody: return "The contract has no terms yet. Add them before sending."
            case .hasBlanks(let blanks): return "Fill in \(blanks.map { "[add \($0)]" }.joined(separator: ", ")) in the terms before sending."
            case .publishFailed(let message): return "Couldn't send the contract: \(message)"
            }
        }
    }

    static func confirmationMessage(for contract: Contract, kind: Kind) -> String {
        let email = (contract.resolvedClient?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = email.isEmpty ? "your client" : email
        switch kind {
        case .send:
            return "Emails \(recipient) a link to review and sign. The terms lock while it's out; you can revise them later, which takes it back until you send again."
        case .reminder:
            return "Emails \(recipient) a reminder to sign, with the link."
        }
    }

    static func send(
        _ contract: Contract,
        kind: Kind,
        context: ModelContext
    ) async throws -> Outcome {
        switch contract.status {
        case .signed: throw SendError.alreadySigned
        case .cancelled: throw SendError.canceled
        case .draft, .sent: break
        }
        guard let client = contract.resolvedClient else { throw SendError.noClient }
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { throw SendError.noClientEmail }
        guard client.portalEnabled else { throw SendError.portalDisabled }
        guard !contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SendError.emptyBody
        }
        let blanks = ContractTemplateEngine.blanks(in: contract.renderedBody)
        guard blanks.isEmpty else { throw SendError.hasBlanks(blanks) }

        let previousStatus = contract.statusRaw
        let previousSentAt = contract.sentAt
        if contract.client == nil {
            contract.client = client
        }
        contract.captureClientSnapshotIfNeeded()
        contract.statusRaw = ContractStatus.sent.rawValue
        if kind == .send { contract.sentAt = .now }
        contract.canceledAt = nil
        contract.updatedAt = .now
        // Republish so the client opens exactly what the email describes.
        contract.portalNeedsUpload = true
        try? context.save()

        switch await PortalAutoSyncService.uploadContract(contractId: contract.id, context: context) {
        case .uploaded, .skippedUnchanged:
            break
        case .ineligible:
            contract.statusRaw = previousStatus
            contract.sentAt = previousSentAt
            try? context.save()
            throw SendError.publishFailed("this contract can't be published to the client portal.")
        case .failed(let message):
            contract.statusRaw = previousStatus
            contract.sentAt = previousSentAt
            try? context.save()
            throw SendError.publishFailed(message)
        }

        do {
            switch try await PortalBackend.shared.sendContractEmail(
                contractId: PortalBackend.shared.contractIdString(contract),
                clientEmail: email,
                businessName: ContractBusiness.name(for: contract, in: context),
                kind: kind.rawValue
            ) {
            case .emailed:
                if kind == .reminder { contract.lastReminderAt = .now }
                try? context.save()
                return .emailed(to: email)
            case .emailFailed(let link, let reason):
                return .publishedNotEmailed(link: link, reason: reason)
            }
        } catch {
            return .publishedNotEmailed(link: nil, reason: error.localizedDescription)
        }
    }
}

/// The owner's own changes of state, each republishing so the portal agrees.
@MainActor
enum ContractLifecycle {
    /// "Revise terms": back to a draft so the text can change. The server
    /// takes it off the client's list and refuses a signature until it's
    /// sent again, so nobody signs words that changed under them.
    static func revise(_ contract: Contract, context: ModelContext) async {
        guard contract.status == .sent else { return }
        contract.statusRaw = ContractStatus.draft.rawValue
        contract.updatedAt = .now
        contract.portalNeedsUpload = true
        try? context.save()
        _ = await PortalAutoSyncService.uploadContract(contractId: contract.id, context: context)
    }

    /// Stays in the client's portal marked canceled, and can't be signed.
    static func cancel(_ contract: Contract, context: ModelContext) async {
        guard contract.status != .signed, contract.status != .cancelled else { return }
        let wasPublished = contract.status == .sent || contract.sentAt != nil
        contract.statusRaw = ContractStatus.cancelled.rawValue
        contract.canceledAt = .now
        contract.updatedAt = .now
        contract.portalNeedsUpload = wasPublished
        try? context.save()
        if wasPublished {
            _ = await PortalAutoSyncService.uploadContract(contractId: contract.id, context: context)
        }
    }

    /// A canceled contract back to a draft, to edit and send again.
    static func reopen(_ contract: Contract, context: ModelContext) async {
        guard contract.status == .cancelled else { return }
        contract.statusRaw = ContractStatus.draft.rawValue
        contract.canceledAt = nil
        contract.updatedAt = .now
        contract.portalNeedsUpload = true
        try? context.save()
        _ = await PortalAutoSyncService.uploadContract(contractId: contract.id, context: context)
    }

    /// Signed on paper or in person. Locks the terms like a portal signature
    /// and tells the portal, so the client's copy shows it signed too.
    static func markSignedInPerson(
        _ contract: Contract,
        signerName: String,
        signedAt: Date,
        context: ModelContext
    ) async {
        guard contract.status != .signed else { return }
        let name = signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        contract.markSigned(byName: name, at: signedAt)
        contract.signedMethod = "in_person"
        contract.canceledAt = nil
        contract.updatedAt = .now
        contract.portalNeedsUpload = true
        try? context.save()
        _ = await PortalAutoSyncService.uploadContract(contractId: contract.id, context: context)
    }

    /// Only a contract that never left the device can be deleted; anything
    /// the client has seen is canceled instead, so their copy says so.
    static func canDelete(_ contract: Contract) -> Bool {
        contract.status == .draft && contract.sentAt == nil && contract.portalLastUploadedAtMs == nil
    }
}

/// Brings portal signatures into the app.
///
/// Nothing did before: a contract signed in the portal stayed "Sent" and
/// editable here, and the next save republished it over the signed copy.
/// Pulled on the "contract signed" push, at launch and on foreground, like
/// InvoiceActivityPullService.
@MainActor
enum ContractActivityPullService {
    private static func watermarkKey(businessID: UUID) -> String {
        "sbw.contractActivity.pullWatermarkMs.\(businessID.uuidString)"
    }

    static func pull(context: ModelContext, businessID: UUID?) async {
        guard let businessID else { return }
        let defaults = UserDefaults.standard
        let key = watermarkKey(businessID: businessID)
        var watermarkMs = defaults.double(forKey: key)

        for _ in 0..<20 {
            let page: PortalBackend.ContractActivityPage
            do {
                page = try await PortalBackend.shared.pullContractActivity(
                    since: Date(timeIntervalSince1970: max(watermarkMs, 0) / 1000)
                )
            } catch {
                SBWLog.ui.problem("[ContractActivity] pull failed: \(error)")
                return
            }
            guard !page.items.isEmpty else { return }

            for item in page.items.sorted(by: { $0.updatedAtMs < $1.updatedAtMs }) {
                apply(item, businessID: businessID, context: context)
                watermarkMs = max(watermarkMs, item.updatedAtMs)
            }
            try? context.save()
            defaults.set(watermarkMs, forKey: key)

            guard page.hasMore == true else { return }
        }
    }

    /// Idempotent: applying the same item twice changes nothing.
    static func apply(_ item: PortalBackend.ContractActivityDTO, businessID: UUID, context: ModelContext) {
        guard let id = UUID(uuidString: item.contractId),
              let contract = try? context.fetch(
                  FetchDescriptor<Contract>(predicate: #Predicate { $0.id == id })
              ).first,
              contract.businessID == businessID
        else { return }

        if let ms = item.sentAtMs, ms > 0, contract.sentAt == nil {
            contract.sentAt = Date(timeIntervalSince1970: ms / 1000)
        }
        if let ms = item.lastReminderAtMs, ms > 0 {
            let date = Date(timeIntervalSince1970: ms / 1000)
            if (contract.lastReminderAt ?? .distantPast) < date { contract.lastReminderAt = date }
        }

        guard item.status == "signed" else { return }

        // A signature is a fact the client created; it wins over a local
        // cancel or draft that hadn't reached the server yet.
        if contract.status != .signed {
            let signedAt = item.signedAtMs.map { Date(timeIntervalSince1970: $0 / 1000) } ?? .now
            contract.markSigned(byName: item.signedName ?? "", at: signedAt)
            contract.canceledAt = nil
        }
        // The server hashed what the client actually saw.
        if let hash = item.signedBodyHash, !hash.isEmpty {
            contract.signedBodyHash = hash
        }
        if contract.signedMethod == nil {
            contract.signedMethod = item.signedMethod ?? "portal"
        }
        if let url = item.signedPdfUrl, !url.isEmpty {
            contract.signedPDFURL = url
        }
        // Nothing to republish: the server already holds the signed copy.
        contract.portalNeedsUpload = false
    }
}
