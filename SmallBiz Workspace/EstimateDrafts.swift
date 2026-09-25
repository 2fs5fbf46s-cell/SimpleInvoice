//
//  EstimateDrafts.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftData

/// Makes a new draft estimate with the business's estimate defaults: how
/// long it's valid, payment terms, notes, thank-you, terms and tax rate.
/// Shared by the Estimates list, Create and the client screen, which each
/// had their own copy of these rules.
@MainActor
enum EstimateDrafts {
    static func make(
        name: String,
        client: Client?,
        businessID: UUID,
        context: ModelContext
    ) throws -> Invoice {
        let profile = try context.fetch(
            FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == businessID })
        ).first
        let business = try context.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let validityDays = max(1, business?.defaultEstimateValidityDays ?? 14)
        let termsRaw = profile?.defaultEstimatePaymentTerms.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let estimate = Invoice(
            businessID: businessID,
            invoiceNumber: trimmedName.isEmpty ? defaultNumber() : trimmedName,
            issueDate: .now,
            dueDate: Calendar.current.date(byAdding: .day, value: validityDays, to: .now) ?? .now,
            paymentTerms: termsRaw.isEmpty ? "Valid for \(validityDays) day\(validityDays == 1 ? "" : "s")" : termsRaw,
            notes: profile?.defaultEstimateNotes ?? "",
            thankYou: profile?.defaultEstimateThankYou ?? "",
            termsAndConditions: profile?.defaultEstimateTerms ?? "",
            taxRate: max(0, NSDecimalNumber(decimal: business?.defaultTaxRate ?? 0).doubleValue),
            discountAmount: 0,
            isPaid: false,
            documentType: "estimate",
            client: client,
            job: nil,
            items: []
        )
        estimate.estimateStatus = "draft"
        estimate.estimateAcceptedAt = nil

        context.insert(estimate)
        try context.save()
        return estimate
    }

    static func defaultNumber(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "EST-\(formatter.string(from: date))"
    }
}
