import Foundation
import SwiftData

@MainActor
enum InvoiceDuplicationService {
    static func duplicate(
        invoice source: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext
    ) throws -> Invoice {
        let profile = profileForDuplication(
            businessID: source.businessID,
            profiles: profiles,
            context: context
        )
        let newInvoiceNumber = InvoiceNumberGenerator.generateNextNumber(profile: profile)
        let now = Date()

        let copiedItems = (source.items ?? []).map { item in
            LineItem(
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            )
        }

        let copy = Invoice(
            businessID: source.businessID,
            businessSnapshotData: nil,
            invoiceNumber: newInvoiceNumber,
            issueDate: now,
            dueDate: dueDateForDuplicate(source: source, issueDate: now),
            paymentTerms: source.paymentTerms,
            notes: source.notes,
            thankYou: source.thankYou,
            termsAndConditions: source.termsAndConditions,
            taxRate: source.taxRate,
            discountAmount: source.discountAmount,
            isPaid: false,
            documentType: source.documentType,
            sourceBookingRequestId: nil,
            sourceEstimateId: nil,
            pdfRelativePath: "",
            invoiceTemplateKeyOverride: source.invoiceTemplateKeyOverride,
            portalNeedsUpload: true,
            portalUploadInFlight: false,
            portalLastUploadedAtMs: nil,
            portalLastUploadError: nil,
            portalLastUploadedBlobUrl: nil,
            portalLastUploadedHash: nil,
            client: validClientForDuplicate(source.client, businessID: source.businessID),
            job: validJobForDuplicate(source.job, businessID: source.businessID),
            items: copiedItems
        )

        copy.estimateStatus = "draft"
        copy.estimateAcceptedAt = nil
        copy.estimateDeclinedAt = nil
        copy.sourceBookingDepositAmountCents = nil
        copy.sourceBookingDepositPaidAtMs = nil
        copy.sourceBookingDepositInvoiceId = nil

        context.insert(copy)
        try context.save()
        return copy
    }

    private static func profileForDuplication(
        businessID: UUID,
        profiles: [BusinessProfile],
        context: ModelContext
    ) -> BusinessProfile {
        if let existing = profiles.first(where: { $0.businessID == businessID }) {
            return existing
        }

        let created = BusinessProfile(businessID: businessID)
        context.insert(created)
        return created
    }

    private static func dueDateForDuplicate(source: Invoice, issueDate: Date) -> Date {
        let sourceInterval = source.dueDate.timeIntervalSince(source.issueDate)
        if sourceInterval.isFinite, sourceInterval > 0 {
            return issueDate.addingTimeInterval(sourceInterval)
        }

        return Calendar.current.date(byAdding: .day, value: 14, to: issueDate) ?? issueDate
    }

    private static func validClientForDuplicate(_ client: Client?, businessID: UUID) -> Client? {
        guard let client, client.businessID == businessID else { return nil }
        return client
    }

    private static func validJobForDuplicate(_ job: Job?, businessID: UUID) -> Job? {
        guard let job, job.businessID == businessID else { return nil }
        return job
    }
}
