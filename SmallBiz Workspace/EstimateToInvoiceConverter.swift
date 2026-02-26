import Foundation
import SwiftData

@MainActor
enum EstimateToInvoiceConverter {
    static func convert(estimate: Invoice, profiles: [BusinessProfile], context: ModelContext) throws {
        guard estimate.documentType == "estimate" else { return }
        let status = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status == "accepted" else { return }

        var profilesForSnapshot = profiles
        let profile: BusinessProfile
        if let existing = profiles.first(where: { $0.businessID == estimate.businessID }) {
            profile = existing
        } else {
            let created = BusinessProfile(businessID: estimate.businessID)
            context.insert(created)
            try? context.save()
            profile = created
            profilesForSnapshot.append(created)
        }

        let year = Calendar.current.component(.year, from: .now)
        if profile.lastInvoiceYear != year {
            profile.lastInvoiceYear = year
            profile.nextInvoiceNumber = 1
        }

        let prefix = profile.invoicePrefix.isEmpty ? "SI" : profile.invoicePrefix
        let next = profile.nextInvoiceNumber
        estimate.invoiceNumber = "\(prefix)-\(year)-\(String(format: "%04d", next))"
        profile.nextInvoiceNumber += 1

        // Convert in place while preserving estimate-entered financial/date fields.
        // This prevents invoice defaults from being reapplied during conversion.
        estimate.documentType = "invoice"

        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: estimate,
            profiles: profilesForSnapshot,
            context: context
        )

        try context.save()
    }
}
