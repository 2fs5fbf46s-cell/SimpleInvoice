import Foundation
import SwiftData

@MainActor
enum EstimateToInvoiceConverter {
    static func convert(estimate: Invoice, profiles: [BusinessProfile], context: ModelContext) throws -> Invoice {
        guard estimate.documentType == "estimate" else { return estimate }
        let status = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard status == "accepted" else { return estimate }

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
        let newInvoiceNumber = "\(prefix)-\(year)-\(String(format: "%04d", next))"
        profile.nextInvoiceNumber += 1

        let copiedItems: [LineItem] = (estimate.items ?? []).map { item in
            LineItem(
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            )
        }

        let invoice = Invoice(
            businessID: estimate.businessID,
            businessSnapshotData: estimate.businessSnapshotData,
            invoiceNumber: newInvoiceNumber,
            issueDate: estimate.issueDate,
            dueDate: estimate.dueDate,
            paymentTerms: estimate.paymentTerms,
            notes: estimate.notes,
            thankYou: estimate.thankYou,
            termsAndConditions: estimate.termsAndConditions,
            taxRate: estimate.taxRate,
            discountAmount: estimate.discountAmount,
            isPaid: false,
            documentType: "invoice",
            sourceBookingRequestId: estimate.sourceBookingRequestId,
            sourceEstimateId: estimate.id.uuidString,
            pdfRelativePath: "",
            invoiceTemplateKeyOverride: estimate.invoiceTemplateKeyOverride,
            portalNeedsUpload: true,
            portalUploadInFlight: false,
            portalLastUploadedAtMs: nil,
            portalLastUploadError: nil,
            portalLastUploadedBlobUrl: nil,
            portalLastUploadedHash: nil,
            client: estimate.client,
            job: estimate.job,
            items: copiedItems
        )
        invoice.sourceBookingDepositAmountCents = estimate.sourceBookingDepositAmountCents
        invoice.sourceBookingDepositPaidAtMs = estimate.sourceBookingDepositPaidAtMs
        invoice.sourceBookingDepositInvoiceId = estimate.sourceBookingDepositInvoiceId

        context.insert(invoice)

        _ = InvoicePDFService.lockBusinessSnapshotIfNeeded(
            invoice: invoice,
            profiles: profilesForSnapshot,
            context: context
        )

        try context.save()
        return invoice
    }
}
