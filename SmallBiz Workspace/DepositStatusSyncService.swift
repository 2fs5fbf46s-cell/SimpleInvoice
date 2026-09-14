import Foundation
import SwiftData

/// Checks whether a Job's deposit invoice has been paid. Deliberately a
/// plain poll of the invoice's own payment status (the same generic
/// endpoint the manual "Refresh Payment Status" button in InvoiceDetailView
/// already uses) rather than a new push/pull pair like
/// EstimateAcceptancePullService — a deposit is a soft reminder, not a
/// gate, so it doesn't carry the same reliability requirement, and the
/// backend already durably records the payment (see
/// stripeWebhookHandler.syncDepositContractReady) independent of whether
/// any device ever asks.
@MainActor
enum DepositStatusSyncService {
    static func refreshPendingDeposits(context: ModelContext, businessID: UUID?) async {
        guard let businessID else { return }

        let descriptor = FetchDescriptor<Job>(
            predicate: #Predicate<Job> {
                $0.businessID == businessID && $0.depositInvoiceId != nil && $0.depositPaidAtMs == nil
            }
        )
        let pending = (try? context.fetch(descriptor)) ?? []
        guard !pending.isEmpty else { return }

        var changed = false
        for job in pending {
            guard let invoiceIdString = job.depositInvoiceId else { continue }
            do {
                let status = try await PortalBackend.shared.fetchPaymentStatus(
                    businessId: businessID.uuidString,
                    invoiceId: invoiceIdString
                )
                guard status.paid else { continue }

                job.depositPaidAtMs = Int64((Date().timeIntervalSince1970 * 1000).rounded())
                changed = true

                if let invoiceUUID = UUID(uuidString: invoiceIdString),
                   let invoice = (try? context.fetch(
                       FetchDescriptor<Invoice>(predicate: #Predicate<Invoice> { $0.id == invoiceUUID })
                   ))?.first {
                    invoice.isPaid = true
                }
            } catch {
                SBWLog.ui.problem("[DepositStatus] payment-status check failed for job \(job.id): \(error)")
            }
        }

        if changed {
            try? context.save()
        }
    }
}
