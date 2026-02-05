import Foundation
import SwiftData

enum InvoicePDFService {

    static func resolvedBusinessProfile(for invoice: Invoice, profiles: [BusinessProfile]) -> BusinessProfile? {
        if let match = profiles.first(where: { $0.businessID == invoice.businessID }) {
            return match
        }
        return profiles.first
    }

    @MainActor
    static func lockBusinessSnapshotIfNeeded(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext?
    ) -> BusinessSnapshot {
        if let snapshot = invoice.businessSnapshot {
            return snapshot
        }

        let profile = resolvedBusinessProfile(for: invoice, profiles: profiles)
        let snapshot = BusinessSnapshot(profile: profile)

        invoice.businessSnapshot = snapshot
        try? context?.save()

        return snapshot
    }

    @MainActor
    static func makePDFData(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext?
    ) -> Data {
        let snapshot = lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profiles,
            context: context
        )
        return InvoicePDFGenerator.makePDFData(invoice: invoice, business: snapshot)
    }
}
