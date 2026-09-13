import Foundation
import SwiftData

/// How the business's documents are doing at reaching the client portal.
///
/// Per-document sync errors were already shown on the invoice or contract itself,
/// in red, with the message — better than most apps manage. But it was only ever
/// per-document: someone whose key expired had no single place telling them six
/// documents had failed. They found out one invoice at a time, by opening each.
struct PortalSyncHealth: Equatable {
    /// Documents that tried to reach the portal and failed.
    let failedCount: Int
    /// Documents still waiting to go, with no error yet.
    let pendingCount: Int
    /// The most recent failure message, to show rather than a bare count.
    let latestMessage: String?

    static let healthy = PortalSyncHealth(failedCount: 0, pendingCount: 0, latestMessage: nil)

    var hasFailures: Bool { failedCount > 0 }

    /// What the dashboard says. Plural handled so it never reads "1 documents".
    var summary: String {
        switch failedCount {
        case 0: return pendingCount == 1 ? "1 document waiting to sync" : "\(pendingCount) documents waiting to sync"
        case 1: return "1 document didn't sync"
        default: return "\(failedCount) documents didn't sync"
        }
    }

    // MARK: - Derivation

    /// Counts unsynced work for one business.
    ///
    /// Fetches on the `portalNeedsUpload` flag, which is a Bool and so usable in a
    /// predicate, then inspects the error in Swift. SwiftData cannot compile
    /// `optional != nil` into a predicate — it traps at runtime — and the set of
    /// documents still needing upload is small by definition.
    @MainActor
    static func current(businessID: UUID?, context: ModelContext) -> PortalSyncHealth {
        guard let businessID else { return .healthy }

        let invoices = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID && invoice.portalNeedsUpload
            }
        )
        let contracts = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { contract in
                contract.businessID == businessID && contract.portalNeedsUpload
            }
        )

        let invoiceErrors = ((try? context.fetch(invoices)) ?? []).map(\.portalLastUploadError)
        let contractErrors = ((try? context.fetch(contracts)) ?? []).map(\.portalLastUploadError)

        return tally(messages: invoiceErrors + contractErrors)
    }

    /// The counting itself, separated so it can be tested without a container.
    static func tally(messages: [String?]) -> PortalSyncHealth {
        var failed = 0
        var pending = 0
        var latest: String?

        for message in messages {
            let text = (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                pending += 1
            } else {
                failed += 1
                if latest == nil { latest = text }
            }
        }

        return PortalSyncHealth(failedCount: failed, pendingCount: pending, latestMessage: latest)
    }
}
