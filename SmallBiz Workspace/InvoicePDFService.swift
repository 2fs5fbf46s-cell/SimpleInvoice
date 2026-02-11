import Foundation
import SwiftData

enum InvoicePDFService {

    static func resolvedBusinessProfile(for invoice: Invoice, profiles: [BusinessProfile]) -> BusinessProfile? {
        if let match = profiles.first(where: { $0.businessID == invoice.businessID }) {
            return match
        }
        return profiles.first
    }

    static func resolvedBusiness(for invoice: Invoice, businesses: [Business]) -> Business? {
        if let match = businesses.first(where: { $0.id == invoice.businessID }) {
            return match
        }
        return businesses.first
    }

    static func effectiveInvoiceTemplateKey(invoice: Invoice, business: Business?) -> InvoiceTemplateKey {
        if let override = InvoiceTemplateKey.from(invoice.invoiceTemplateKeyOverride) {
            return override
        }
        if let business,
           let key = InvoiceTemplateKey.from(business.defaultInvoiceTemplateKey) {
            return key
        }
        return .modern_clean
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
        context: ModelContext?,
        businesses: [Business] = []
    ) -> Data {
        let snapshot = lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profiles,
            context: context
        )
        let business = resolvedBusiness(for: invoice, businesses: businesses)
        let templateKey = effectiveInvoiceTemplateKey(invoice: invoice, business: business)
        return InvoicePDFGenerator.makePDFData(
            invoice: invoice,
            business: snapshot,
            templateKey: templateKey
        )
    }
}
