import Foundation
import SwiftData

enum InvoicePDFService {

    static func resolvedBusinessProfile(for invoice: Invoice, profiles: [BusinessProfile]) -> BusinessProfile? {
        if let match = profiles.first(where: { $0.businessID == invoice.businessID }) {
            return match
        }
        return profiles.first
    }

    static func resolvedSnapshot(
        for invoice: Invoice,
        profiles: [BusinessProfile],
        lockIfMissing: Bool,
        context: ModelContext?
    ) -> BusinessSnapshot {
        if let snapshot = invoice.businessSnapshot {
            return snapshot
        }

        let profile = resolvedBusinessProfile(for: invoice, profiles: profiles)
        let snapshot = BusinessSnapshot(profile: profile)

        if lockIfMissing, profile != nil {
            invoice.businessSnapshot = snapshot
            try? context?.save()
        }

        return snapshot
    }

    static func makePDFData(
        invoice: Invoice,
        profiles: [BusinessProfile],
        lockSnapshot: Bool,
        context: ModelContext?
    ) -> Data {
        let snapshot = resolvedSnapshot(
            for: invoice,
            profiles: profiles,
            lockIfMissing: lockSnapshot,
            context: context
        )
        return InvoicePDFGenerator.makePDFData(invoice: invoice, business: snapshot)
    }
}
