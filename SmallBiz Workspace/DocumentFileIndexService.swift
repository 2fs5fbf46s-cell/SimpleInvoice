import Foundation
import SwiftData
import UniformTypeIdentifiers

enum DocumentFileIndexService {

    @MainActor
    static func persistInvoicePDF(
        invoice: Invoice,
        profiles: [BusinessProfile],
        context: ModelContext
    ) throws -> URL {
        let pdfData = InvoicePDFService.makePDFData(
            invoice: invoice,
            profiles: profiles,
            context: context
        )

        let business = try fetchBusiness(for: invoice.businessID, context: context)
        let folderKind: FolderDestinationKind = invoice.documentType == "estimate" ? .estimates : .invoices
        let destination = try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: invoice.client,
            job: invoice.job,
            kind: folderKind,
            context: context
        )

        let relativePath = "\(destination.relativePath)/\(invoice.id.uuidString).pdf"
        _ = try AppFileStore.writeData(pdfData, toRelativePath: relativePath)

        if invoice.pdfRelativePath != relativePath {
            invoice.pdfRelativePath = relativePath
        }

        try context.save()
        try upsertInvoicePDF(invoice: invoice, context: context)

        return try AppFileStore.absoluteURL(forRelativePath: relativePath)
    }

    @MainActor
    static func persistContractPDF(
        contract: Contract,
        business: BusinessProfile?,
        context: ModelContext
    ) throws -> URL {
        let pdfData = ContractPDFGenerator.makePDFData(
            contract: contract,
            business: business
        )

        _ = business // preserved for API compatibility
        let resolvedClient = contract.resolvedClient
        let businessID = resolvedClient?.businessID ?? contract.businessID
        let resolvedBusiness = try fetchBusiness(for: businessID, context: context)
        let destination = try WorkspaceProvisioningService.resolveFolder(
            business: resolvedBusiness,
            client: resolvedClient,
            job: contract.job,
            kind: .contracts,
            context: context
        )

        let relativePath = "\(destination.relativePath)/\(contract.id.uuidString).pdf"
        _ = try AppFileStore.writeData(pdfData, toRelativePath: relativePath)

        if contract.pdfRelativePath != relativePath {
            contract.pdfRelativePath = relativePath
        }

        try context.save()
        try upsertContractPDF(contract: contract, context: context)

        return try AppFileStore.absoluteURL(forRelativePath: relativePath)
    }

    @MainActor
    static func upsertInvoicePDF(invoice: Invoice, context: ModelContext) throws {
        let pdfRel = invoice.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdfRel.isEmpty else { return }

        let business = try fetchBusiness(for: invoice.businessID, context: context)
        let folderKind: FolderDestinationKind = invoice.documentType == "estimate" ? .estimates : .invoices
        let destination = try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: invoice.client,
            job: invoice.job,
            kind: folderKind,
            context: context
        )

        let fileName = makeInvoiceFileName(invoice: invoice)
        try upsertFileItem(
            relativePath: pdfRel,
            displayName: fileName.replacingOccurrences(of: ".pdf", with: ""),
            originalFileName: fileName,
            byteCount: 0,
            folder: destination,
            context: context
        )
    }

    @MainActor
    static func upsertContractPDF(contract: Contract, context: ModelContext) throws {
        let pdfRel = contract.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdfRel.isEmpty else { return }

        let resolvedClient = contract.resolvedClient
        let businessID = resolvedClient?.businessID ?? contract.businessID
        let resolvedBusiness = try fetchBusiness(for: businessID, context: context)
        let destination = try WorkspaceProvisioningService.resolveFolder(
            business: resolvedBusiness,
            client: resolvedClient,
            job: contract.job,
            kind: .contracts,
            context: context
        )

        let fileName = makeContractFileName(contract: contract)
        try upsertFileItem(
            relativePath: pdfRel,
            displayName: fileName.replacingOccurrences(of: ".pdf", with: ""),
            originalFileName: fileName,
            byteCount: 0,
            folder: destination,
            context: context
        )
    }

    @MainActor
    static func syncJobDocuments(job: Job, context: ModelContext) throws {
        let invoices = try fetchInvoices(for: job, context: context)
        for invoice in invoices where !invoice.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try upsertInvoicePDF(invoice: invoice, context: context)
        }

        let contracts = try fetchContracts(for: job, context: context)
        for contract in contracts where !contract.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try upsertContractPDF(contract: contract, context: context)
        }
    }

    // MARK: - Private

    private static func upsertFileItem(
        relativePath: String,
        displayName: String,
        originalFileName: String,
        byteCount: Int64,
        folder: Folder,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<FileItem>(
            predicate: #Predicate<FileItem> { item in
                item.relativePath == relativePath
            }
        )

        let ext = "pdf"
        let uti = UTType.pdf.identifier
        let folderKey = folder.id.uuidString

        if let existing = try context.fetch(descriptor).first {
            existing.displayName = displayName
            existing.originalFileName = originalFileName
            existing.fileExtension = ext
            existing.uti = uti
            if byteCount > 0 { existing.byteCount = byteCount }
            existing.folderKey = folderKey
            existing.folder = folder
            existing.updatedAt = .now
            try context.save()
            return
        }

        let item = FileItem(
            displayName: displayName,
            originalFileName: originalFileName,
            relativePath: relativePath,
            fileExtension: ext,
            uti: uti,
            byteCount: byteCount,
            folderKey: folderKey,
            folder: folder
        )
        context.insert(item)
        try context.save()
    }

    private static func fetchInvoices(for job: Job, context: ModelContext) throws -> [Invoice] {
        let all = try context.fetch(FetchDescriptor<Invoice>())
        return all.filter { $0.job?.id == job.id }
    }

    private static func fetchContracts(for job: Job, context: ModelContext) throws -> [Contract] {
        let all = try context.fetch(FetchDescriptor<Contract>())
        return all.filter {
            if $0.job?.id == job.id { return true }
            if $0.invoice?.job?.id == job.id { return true }
            if $0.estimate?.job?.id == job.id { return true }
            return false
        }
    }

    private static func fetchBusiness(for businessID: UUID, context: ModelContext) throws -> Business {
        if let match = try context.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first {
            return match
        }
        return try ActiveBusinessProvider.getOrCreateActiveBusiness(in: context)
    }

    private static func makeInvoiceFileName(invoice: Invoice) -> String {
        let prefix = invoice.documentType == "estimate" ? "Estimate" : "Invoice"
        let trimmedNumber = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = invoice.id.uuidString
        let number = trimmedNumber.isEmpty ? String(fallback.prefix(8)) : trimmedNumber
        let safeNumber = number.replacingOccurrences(of: "/", with: "-")
        return "\(prefix)-\(safeNumber).pdf"
    }

    private static func makeContractFileName(contract: Contract) -> String {
        let trimmedTitle = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = contract.id.uuidString
        let shortID = String(fallback.prefix(8))
        let base = trimmedTitle.isEmpty ? "Contract-\(shortID)" : "Contract-\(trimmedTitle)"
        let safe = base.replacingOccurrences(of: "/", with: "-")
        return "\(safe).pdf"
    }

}
