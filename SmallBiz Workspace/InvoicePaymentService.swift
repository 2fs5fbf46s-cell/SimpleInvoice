//
//  InvoicePaymentService.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Records and removes payments against an invoice and keeps `isPaid` and
/// the client's portal in step with the balance.
///
/// The portal matters: after a part payment its copy must show — and its
/// checkout charge — the balance, not the original total. Recording a
/// payment on a sent invoice republishes it for that reason.
@MainActor
enum InvoicePaymentService {
    enum PaymentError: LocalizedError {
        case notPositive
        case moreThanOwed(balance: String)

        var errorDescription: String? {
            switch self {
            case .notPositive: return "Enter the amount you received."
            case .moreThanOwed(let balance): return "That's more than the \(balance) still owed."
            }
        }
    }

    @discardableResult
    static func record(
        on invoice: Invoice,
        amountCents: Int,
        paidAt: Date,
        method: String,
        note: String = "",
        source: String = "manual",
        context: ModelContext
    ) throws -> InvoicePayment {
        guard amountCents > 0 else { throw PaymentError.notPositive }
        let balance = invoice.balanceDueCents
        if source == "manual", amountCents > balance {
            throw PaymentError.moreThanOwed(balance: currency(balance))
        }

        let payment = InvoicePayment(
            invoice: invoice,
            amountCents: amountCents,
            paidAt: paidAt,
            method: method,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            source: source
        )
        context.insert(payment)
        invoice.payments = (invoice.payments ?? []) + [payment]
        settle(invoice, context: context)
        return payment
    }

    static func remove(_ payment: InvoicePayment, from invoice: Invoice, context: ModelContext) {
        invoice.payments = (invoice.payments ?? []).filter { $0.id != payment.id }
        context.delete(payment)
        // A payment taken back makes the invoice owed again, even if it was
        // marked paid the old way.
        invoice.isPaid = false
        settle(invoice, context: context)
    }

    /// Marks it paid once nothing is owed (and unpaid again if a payment is
    /// removed), and flags a sent invoice for republishing so the portal
    /// agrees. The upload itself is `publishIfSent`, which the screens call —
    /// not started from here, where it would outlive whoever asked.
    static func settle(_ invoice: Invoice, context: ModelContext) {
        let recorded = (invoice.payments ?? []).reduce(0) { $0 + $1.amountCents }
        let depositPaid = (invoice.sourceBookingDepositPaidAtMs ?? 0) > 0 ? invoice.bookingDepositCents : 0
        let covered = recorded + depositPaid
        invoice.isPaid = invoice.totalCents > 0 && covered >= invoice.totalCents
        if invoice.wasSent { invoice.portalNeedsUpload = true }
        try? context.save()
    }

    /// Pushes the new balance to the client's portal, so its checkout charges
    /// what's still owed.
    static func publishIfSent(_ invoice: Invoice, context: ModelContext) async {
        guard invoice.wasSent, invoice.portalNeedsUpload else { return }
        _ = await PortalAutoSyncService.uploadInvoice(invoiceId: invoice.id, context: context)
    }

    static func currency(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }
}
