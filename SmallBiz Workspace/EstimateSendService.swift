//
//  EstimateSendService.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Send Estimate: the one action that makes an estimate "sent".
///
/// It publishes the estimate to the client's portal (PDF + listing, through
/// the same upload Done uses) and has the server email the client a link to
/// it. Before this, nothing marked an estimate sent — emailing and sharing
/// the PDF didn't — while drafts reached the portal through side doors: the
/// portal buttons, Done, and the PDF upload menu. Those now refuse drafts
/// (`Invoice.isUnsentEstimate`), so this is the only way in.
@MainActor
enum EstimateSendService {
    enum Outcome {
        case emailed(to: String)
        /// Published and marked sent, but the email didn't go out. `link`
        /// opens the estimate, when the server returned one, so it can be
        /// shared another way.
        case publishedNotEmailed(link: String?, reason: String)
    }

    enum SendError: LocalizedError {
        case alreadyDecided
        case noClient
        case noClientEmail
        case portalDisabled
        case notReady(String)
        case publishFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyDecided:
                return "The client already responded to this estimate."
            case .noClient:
                return "Choose a client for this estimate before sending it."
            case .noClientEmail:
                return "Add an email address to this client to send them the estimate."
            case .portalDisabled:
                return "Turn on the client portal for this client to send them the estimate."
            case .notReady(let reason):
                return reason
            case .publishFailed(let message):
                return "Couldn't send the estimate: \(message)"
            }
        }
    }

    /// The name the client knows the business by — the locked snapshot once
    /// there is one, so the email matches the PDF.
    static func businessName(for estimate: Invoice, profiles: [BusinessProfile]) -> String? {
        if estimate.isBusinessInfoLocked {
            let snapshot = (estimate.businessSnapshot?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !snapshot.isEmpty { return snapshot }
        }
        let name = (InvoicePDFService.resolvedBusinessProfile(for: estimate, profiles: profiles)?.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// What the confirmation asks, naming who's about to get an email.
    static func confirmationMessage(for estimate: Invoice) -> String {
        let email = (estimate.client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = email.isEmpty ? "your client" : email
        return "Emails \(recipient) a link to review and accept or decline this estimate. It also appears in their client portal."
    }

    static func send(
        estimate: Invoice,
        context: ModelContext,
        businessName: String?
    ) async throws -> Outcome {
        let status = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status != "accepted", status != "declined" else { throw SendError.alreadyDecided }
        guard let client = estimate.client else { throw SendError.noClient }
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { throw SendError.noClientEmail }
        guard client.portalEnabled else { throw SendError.portalDisabled }
        if let reason = estimate.cannotBeSentReason { throw SendError.notReady(reason) }

        let previousStatus = estimate.estimateStatus
        if status != "sent" {
            estimate.estimateStatus = "sent"
            let profiles = (try? context.fetch(FetchDescriptor<BusinessProfile>())) ?? []
            _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                invoice: estimate,
                profiles: profiles.filter { $0.businessID == estimate.businessID },
                context: context,
                reason: .sent,
                replaceExistingUnlockedSnapshot: true
            )
        }
        // Republish even when nothing changed since the last upload, so the
        // client opens exactly what the email describes.
        estimate.portalNeedsUpload = true
        try? context.save()

        switch await PortalAutoSyncService.uploadInvoice(invoiceId: estimate.id, context: context) {
        case .uploaded, .skippedUnchanged:
            break
        case .ineligible:
            estimate.estimateStatus = previousStatus
            try? context.save()
            throw SendError.publishFailed("this estimate can't be published to the client portal.")
        case .failed(let message):
            estimate.estimateStatus = previousStatus
            try? context.save()
            throw SendError.publishFailed(message)
        }

        // Published: from here the estimate is sent whether or not the email
        // goes out, because the client can already open it.
        do {
            switch try await PortalBackend.shared.sendEstimateEmail(
                estimateId: estimate.id.uuidString,
                clientEmail: email,
                businessName: businessName
            ) {
            case .emailed:
                return .emailed(to: email)
            case .emailFailed(let link, let reason):
                return .publishedNotEmailed(link: link, reason: reason)
            }
        } catch {
            return .publishedNotEmailed(link: nil, reason: error.localizedDescription)
        }
    }
}
