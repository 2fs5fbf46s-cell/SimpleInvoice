//
//  PaymentRequestService.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// A link that asks the client to pay part of an invoice now — a booking
/// deposit, say — instead of the whole balance. The client opens the invoice
/// as usual and is charged exactly this amount, once; the rest stays owed.
///
/// On a draft invoice this also sends it: the client has a link to it, so it
/// is published to their portal and marked sent (InvoiceSendService), just
/// without the email.
@MainActor
enum PaymentRequestService {
    enum RequestError: LocalizedError {
        case alreadyPaid
        case estimate
        case noClient
        case portalDisabled
        case notReady(String)
        case notPositive
        case moreThanOwed(balance: String)

        var errorDescription: String? {
            switch self {
            case .alreadyPaid: return "This invoice is already paid."
            case .estimate: return "Payment links are for invoices. Turn this estimate into an invoice first."
            case .noClient: return "Choose a client for this invoice first."
            case .portalDisabled: return "Turn on the client portal for this client to send them a payment link."
            case .notReady(let reason): return reason
            case .notPositive: return "Enter the amount to ask for."
            case .moreThanOwed(let balance): return "That's more than the \(balance) still owed."
            }
        }
    }

    /// What can be asked for: anything up to the balance.
    static func validate(_ invoice: Invoice, amountCents: Int) throws {
        guard invoice.documentType != "estimate" else { throw RequestError.estimate }
        guard !invoice.isPaid, invoice.balanceDueCents > 0 else { throw RequestError.alreadyPaid }
        guard let client = invoice.client else { throw RequestError.noClient }
        guard client.portalEnabled else { throw RequestError.portalDisabled }
        if let reason = invoice.cannotBeSentReason { throw RequestError.notReady(reason) }
        guard amountCents > 0 else { throw RequestError.notPositive }
        guard amountCents <= invoice.balanceDueCents else {
            throw RequestError.moreThanOwed(balance: InvoicePaymentService.currency(invoice.balanceDueCents))
        }
    }

    static func createLink(
        for invoice: Invoice,
        amountCents: Int,
        label: String,
        context: ModelContext,
        businessName: String?
    ) async throws -> URL {
        try validate(invoice, amountCents: amountCents)

        if invoice.isUnsentDocument {
            try await InvoiceSendService.publishAsSent(invoice, context: context)
        }

        let businessID = invoice.businessID
        let business = try? context.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)

        let token: String
        do {
            token = try await PortalBackend.shared.createInvoicePortalToken(
                invoice: invoice,
                business: business,
                businessName: businessName,
                paymentRequest: (amountCents: amountCents, label: trimmedLabel.isEmpty ? "Payment" : trimmedLabel)
            )
        } catch PortalBackendError.http(_, let body, _) where serverCode(body) == "AMOUNT_EXCEEDS_BALANCE" {
            // The server knows about online payments the app hasn't pulled yet.
            let balance = serverBalance(body) ?? invoice.balanceDueCents
            throw RequestError.moreThanOwed(balance: InvoicePaymentService.currency(balance))
        } catch PortalBackendError.http(_, let body, _) where serverCode(body) == "ALREADY_PAID" {
            throw RequestError.alreadyPaid
        }

        return PortalBackend.shared.portalInvoiceURL(
            invoiceId: invoice.id.uuidString,
            token: token,
            mode: "live"
        )
    }

    /// What the owner pastes into a text or email alongside the link.
    static func shareMessage(for invoice: Invoice, amountCents: Int, label: String, businessName: String?, url: URL) -> String {
        let amount = InvoicePaymentService.currency(amountCents)
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let what = trimmed.isEmpty || trimmed.lowercased() == "payment" ? "payment" : trimmed.lowercased()
        let number = invoice.trimmedInvoiceNumber
        let forInvoice = number.isEmpty ? "" : " for invoice \(number)"
        let from = (businessName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sender = from.isEmpty ? "" : " from \(from)"
        return "Here's the link to pay your \(amount) \(what)\(forInvoice)\(sender):\n\(url.absoluteString)"
    }

    private static func serverJSON(_ body: String) -> [String: Any]? {
        guard let data = body.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func serverCode(_ body: String) -> String? {
        serverJSON(body)?["error"] as? String
    }

    private static func serverBalance(_ body: String) -> Int? {
        (serverJSON(body)?["balanceDueCents"] as? NSNumber)?.intValue
    }
}
