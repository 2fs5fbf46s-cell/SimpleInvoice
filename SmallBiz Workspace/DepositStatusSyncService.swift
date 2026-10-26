import Foundation
import SwiftData

/// Marks a Job's deposit paid once its deposit invoice is. The invoice's own
/// paid state arrives through InvoiceActivityPullService, which runs just
/// before this at launch and on foreground, so this only reads local data.
///
/// It used to ask /api/payment-status per invoice, but that endpoint now
/// requires the client's portal-link token, which the app never sent, so
/// every check failed and no deposit was ever marked paid.
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
            guard let invoiceIdString = job.depositInvoiceId,
                  let invoiceUUID = UUID(uuidString: invoiceIdString),
                  let invoice = (try? context.fetch(
                      FetchDescriptor<Invoice>(predicate: #Predicate<Invoice> { $0.id == invoiceUUID })
                  ))?.first,
                  invoice.isPaid
            else { continue }

            let paidAt = (invoice.payments ?? []).map(\.paidAt).max() ?? .now
            job.depositPaidAtMs = Int64((paidAt.timeIntervalSince1970 * 1000).rounded())
            changed = true
        }

        if changed {
            try? context.save()
        }
    }
}
