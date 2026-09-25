//
//  InvoiceSendService.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Send Invoice and Remind Client.
///
/// Send publishes the invoice to the client's portal and has the server
/// email a link to view and pay; it's what makes an invoice "sent". Before,
/// "Send" opened a share sheet and nothing recorded that the client had it,
/// while any invoice was published to the portal the moment Done was
/// tapped. Remind emails the same link with overdue wording.
@MainActor
enum InvoiceSendService {
    enum Kind: String {
        case send
        case reminder
    }

    enum Outcome {
        case emailed(to: String)
        /// In the client's portal, but the email didn't go out. `link` opens
        /// it, when the server returned one, to share another way.
        case publishedNotEmailed(link: String?, reason: String)
    }

    enum SendError: LocalizedError {
        case alreadyPaid
        case noClient
        case noClientEmail
        case portalDisabled
        case notReady(String)
        case publishFailed(String)

        var errorDescription: String? {
            switch self {
            case .alreadyPaid: return "This invoice is already paid."
            case .noClient: return "Choose a client for this invoice before sending it."
            case .noClientEmail: return "Add an email address to this client to send them the invoice."
            case .portalDisabled: return "Turn on the client portal for this client to send them the invoice."
            case .notReady(let reason): return reason
            case .publishFailed(let message): return "Couldn't send the invoice: \(message)"
            }
        }
    }

    static func confirmationMessage(for invoice: Invoice, kind: Kind) -> String {
        let email = (invoice.client?.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recipient = email.isEmpty ? "your client" : email
        let balance = InvoicePaymentService.currency(invoice.balanceDueCents)
        switch kind {
        case .send:
            return "Emails \(recipient) a link to view and pay \(balance) online. It also appears in their client portal."
        case .reminder:
            return "Emails \(recipient) a reminder that \(balance) is \(invoice.isOverdue ? "overdue" : "due"), with the link to pay."
        }
    }

    static func send(
        _ invoice: Invoice,
        kind: Kind,
        context: ModelContext,
        businessName: String?
    ) async throws -> Outcome {
        guard !invoice.isPaid, invoice.balanceDueCents > 0 else { throw SendError.alreadyPaid }
        guard let client = invoice.client else { throw SendError.noClient }
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { throw SendError.noClientEmail }
        guard client.portalEnabled else { throw SendError.portalDisabled }
        if let reason = invoice.cannotBeSentReason { throw SendError.notReady(reason) }

        let wasSentBefore = invoice.sentAt
        if invoice.sentAt == nil {
            invoice.sentAt = .now
            let profiles = (try? context.fetch(FetchDescriptor<BusinessProfile>())) ?? []
            _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
                invoice: invoice,
                profiles: profiles.filter { $0.businessID == invoice.businessID },
                context: context,
                reason: .sent,
                replaceExistingUnlockedSnapshot: true
            )
        }
        // Republish so the client opens exactly what the email describes.
        invoice.portalNeedsUpload = true
        try? context.save()

        switch await PortalAutoSyncService.uploadInvoice(invoiceId: invoice.id, context: context) {
        case .uploaded, .skippedUnchanged:
            break
        case .ineligible:
            invoice.sentAt = wasSentBefore
            try? context.save()
            throw SendError.publishFailed("this invoice can't be published to the client portal.")
        case .failed(let message):
            invoice.sentAt = wasSentBefore
            try? context.save()
            throw SendError.publishFailed(message)
        }

        do {
            switch try await PortalBackend.shared.sendInvoiceEmail(
                invoiceId: invoice.id.uuidString,
                clientEmail: email,
                businessName: businessName,
                kind: kind.rawValue
            ) {
            case .emailed:
                if kind == .reminder { invoice.lastReminderAt = .now }
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
