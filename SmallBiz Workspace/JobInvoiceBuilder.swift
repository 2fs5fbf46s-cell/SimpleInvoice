//
//  JobInvoiceBuilder.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// The invoice you send when a job is done.
///
/// "Create Invoice" on a job used to make an empty invoice. When the job came
/// from an accepted estimate, the work is already priced there: copy its line
/// items, and take off the deposit the client already paid as its own line,
/// so the invoice asks only for what's still owed.
@MainActor
enum JobInvoiceBuilder {
    /// The estimate the job was priced from: the one it was created from, or
    /// else an accepted estimate linked to it.
    static func sourceEstimate(for job: Job, in context: ModelContext) -> Invoice? {
        if let sourceID = job.sourceEstimateId,
           let uuid = UUID(uuidString: sourceID),
           let estimate = try? context.fetch(
               FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == uuid })
           ).first {
            return estimate
        }
        return (job.invoices ?? []).first {
            $0.documentType == "estimate"
                && $0.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "accepted"
        }
    }

    static func makeInvoice(
        for job: Job,
        client: Client?,
        profile: BusinessProfile?,
        context: ModelContext
    ) throws -> Invoice {
        let number = profile.map { InvoiceNumberGenerator.generateNextNumber(profile: $0) }
            ?? "INV-\(Int(Date().timeIntervalSince1970))"

        var items: [LineItem] = []
        let estimate = sourceEstimate(for: job, in: context)
        for item in estimate?.items ?? [] {
            items.append(LineItem(
                itemDescription: item.itemDescription,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            ))
        }
        if job.depositPaidAtMs != nil, let depositCents = job.depositAmountCents, depositCents > 0 {
            items.append(LineItem(
                itemDescription: "Less deposit paid",
                quantity: 1,
                unitPrice: -Double(depositCents) / 100.0
            ))
        }

        let invoice = Invoice(
            businessID: job.businessID,
            invoiceNumber: number,
            issueDate: Date(),
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
            isPaid: false,
            documentType: "invoice",
            client: client,
            job: job,
            items: items
        )
        if let estimate {
            invoice.taxRate = estimate.taxRate
            invoice.discountAmount = estimate.discountAmount
            invoice.sourceEstimateId = estimate.id.uuidString
        }

        context.insert(invoice)
        try context.save()
        return invoice
    }
}
