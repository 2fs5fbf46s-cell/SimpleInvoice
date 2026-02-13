import Foundation
import SwiftData
import CryptoKit

enum PortalAutoSyncResult: Equatable {
    case ineligible
    case skippedUnchanged
    case uploaded
    case failed(String)
}

enum PortalAutoSyncService {

    @MainActor
    static func markInvoiceNeedsUploadIfChanged(invoice: Invoice, business: Business?) {
        let currentHash = invoiceHash(invoice: invoice, business: business)
        if invoice.portalLastUploadedHash != currentHash {
            invoice.portalNeedsUpload = true
        }
    }

    @MainActor
    static func markContractNeedsUploadIfChanged(contract: Contract) {
        let currentHash = contractHash(contract: contract)
        if contract.portalLastUploadedHash != currentHash {
            contract.portalNeedsUpload = true
        }
    }

    @MainActor
    static func uploadInvoice(
        invoiceId: UUID,
        context: ModelContext
    ) async -> PortalAutoSyncResult {
        guard let invoice = fetchInvoice(id: invoiceId, context: context) else {
            return .ineligible
        }
        guard isEligible(invoice: invoice) else {
            return .ineligible
        }

        let business = fetchBusiness(id: invoice.businessID, context: context)
        let currentHash = invoiceHash(invoice: invoice, business: business)

        if invoice.portalLastUploadedHash == currentHash {
            invoice.portalNeedsUpload = false
            try? context.save()
            return .skippedUnchanged
        }

        do {
            let profiles = fetchProfiles(businessID: invoice.businessID, context: context)
            let businesses: [Business] = business.map { [$0] } ?? []
            let pdfData = InvoicePDFService.makePDFData(
                invoice: invoice,
                profiles: profiles,
                context: context,
                businesses: businesses
            )

            let prefix = (invoice.documentType == "estimate") ? "Estimate" : "Invoice"
            let trimmed = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = String(invoice.id.uuidString.suffix(8))
            let namePart = trimmed.isEmpty ? fallback : trimmed.replacingOccurrences(of: "/", with: "-")
            let fileName = "\(prefix)-\(namePart).pdf"

            _ = try await PortalBackend.shared.uploadInvoicePDFToBlob(
                businessId: invoice.businessID.uuidString,
                invoiceId: invoice.id.uuidString,
                fileName: fileName,
                pdfData: pdfData
            )

            if invoice.documentType == "estimate" {
                try await PortalBackend.shared.indexEstimateForDirectory(estimate: invoice)
            } else {
                try await PortalBackend.shared.indexInvoiceForPortalDirectory(invoice: invoice)
            }

            invoice.portalNeedsUpload = false
            invoice.portalLastUploadedAtMs = nowMs()
            invoice.portalLastUploadedHash = currentHash
            try context.save()
            return .uploaded
        } catch {
            invoice.portalNeedsUpload = true
            try? context.save()
            return .failed(error.localizedDescription)
        }
    }

    @MainActor
    static func uploadContract(
        contractId: UUID,
        context: ModelContext
    ) async -> PortalAutoSyncResult {
        guard let contract = fetchContract(id: contractId, context: context) else {
            return .ineligible
        }
        guard isEligible(contract: contract) else {
            return .ineligible
        }

        let currentHash = contractHash(contract: contract)
        if contract.portalLastUploadedHash == currentHash {
            contract.portalNeedsUpload = false
            try? context.save()
            return .skippedUnchanged
        }

        guard let client = contract.resolvedClient else {
            return .ineligible
        }

        do {
            let businessProfile = fetchProfile(businessID: client.businessID, context: context)
            let pdfData = ContractPDFGenerator.makePDFData(contract: contract, business: businessProfile)

            let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = title.isEmpty ? "Contract-\(String(contract.id.uuidString.prefix(8)))" : "Contract-\(title)"
            let fileName = base.replacingOccurrences(of: "/", with: "-") + ".pdf"

            _ = try await PortalBackend.shared.uploadContractPDFToBlob(
                businessId: client.businessID.uuidString,
                contractId: contract.id.uuidString,
                fileName: fileName,
                pdfData: pdfData
            )
            try await PortalBackend.shared.indexContractForPortalDirectory(contract: contract)
            try DocumentFileIndexService.upsertContractPDF(contract: contract, context: context)

            contract.portalNeedsUpload = false
            contract.portalLastUploadedAtMs = nowMs()
            contract.portalLastUploadedHash = currentHash
            try context.save()
            return .uploaded
        } catch {
            contract.portalNeedsUpload = true
            try? context.save()
            return .failed(error.localizedDescription)
        }
    }

    @MainActor
    static func uploadEstimate(
        estimateId: UUID,
        context: ModelContext
    ) async -> PortalAutoSyncResult {
        // Estimates are stored in Invoice where documentType == "estimate".
        await uploadInvoice(invoiceId: estimateId, context: context)
    }

    @MainActor
    static func isEligible(invoice: Invoice) -> Bool {
        guard let client = invoice.client else { return false }
        return client.portalEnabled
    }

    @MainActor
    static func isEligible(contract: Contract) -> Bool {
        guard let client = contract.resolvedClient else { return false }
        return client.portalEnabled
    }

    // MARK: - Hashes

    @MainActor
    private static func invoiceHash(invoice: Invoice, business: Business?) -> String {
        var pieces: [String] = []
        pieces.append("type=\(invoice.documentType)")
        pieces.append("number=\(invoice.invoiceNumber)")
        pieces.append("issueMs=\(ms(invoice.issueDate))")
        pieces.append("dueMs=\(ms(invoice.dueDate))")
        pieces.append("client=\(invoice.client?.id.uuidString ?? "")")
        pieces.append("subtotal=\(invoice.subtotal)")
        pieces.append("discount=\(invoice.discountAmount)")
        pieces.append("taxRate=\(invoice.taxRate)")
        pieces.append("taxAmount=\(invoice.taxAmount)")
        pieces.append("total=\(invoice.total)")
        pieces.append("paid=\(invoice.isPaid)")
        pieces.append("status=\(invoice.estimateStatus)")
        pieces.append("notes=\(invoice.notes)")
        pieces.append("thankYou=\(invoice.thankYou)")
        pieces.append("terms=\(invoice.termsAndConditions)")
        pieces.append("paymentTerms=\(invoice.paymentTerms)")
        pieces.append("templateOverride=\(invoice.invoiceTemplateKeyOverride ?? "")")

        let effectiveTemplate = InvoicePDFService.effectiveInvoiceTemplateKey(invoice: invoice, business: business)
        pieces.append("effectiveTemplate=\(effectiveTemplate.rawValue)")

        let rows = (invoice.items ?? []).enumerated().map { index, item in
            "\(index)|\(item.itemDescription)|\(item.quantity)|\(item.unitPrice)|\(item.lineTotal)"
        }
        pieces.append(contentsOf: rows)

        return digest(pieces.joined(separator: "\n"))
    }

    @MainActor
    private static func contractHash(contract: Contract) -> String {
        var pieces: [String] = []
        pieces.append("title=\(contract.title)")
        pieces.append("body=\(contract.renderedBody)")
        pieces.append("status=\(contract.statusRaw)")
        pieces.append("client=\(contract.resolvedClient?.id.uuidString ?? "")")
        pieces.append("signedAtMs=\(contract.signedAt.map(ms) ?? 0)")
        pieces.append("signedBy=\(contract.signedByName)")
        pieces.append("template=\(contract.templateName)")
        pieces.append("templateCategory=\(contract.templateCategory)")
        return digest(pieces.joined(separator: "\n"))
    }

    private static func digest(_ text: String) -> String {
        let data = Data(text.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000.0).rounded())
    }

    private static func nowMs() -> Int64 {
        ms(Date())
    }

    // MARK: - Fetch helpers

    @MainActor
    private static func fetchInvoice(id: UUID, context: ModelContext) -> Invoice? {
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func fetchContract(id: UUID, context: ModelContext) -> Contract? {
        let descriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func fetchBusiness(id: UUID, context: ModelContext) -> Business? {
        let descriptor = FetchDescriptor<Business>(
            predicate: #Predicate<Business> { $0.id == id }
        )
        return try? context.fetch(descriptor).first
    }

    @MainActor
    private static func fetchProfiles(businessID: UUID, context: ModelContext) -> [BusinessProfile] {
        let descriptor = FetchDescriptor<BusinessProfile>(
            predicate: #Predicate<BusinessProfile> { $0.businessID == businessID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    @MainActor
    private static func fetchProfile(businessID: UUID, context: ModelContext) -> BusinessProfile? {
        fetchProfiles(businessID: businessID, context: context).first
    }
}
