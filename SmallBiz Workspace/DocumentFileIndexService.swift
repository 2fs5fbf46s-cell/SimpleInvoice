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

        let relativePath = invoicePDFRelativePath(invoiceID: invoice.id)
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

        let relativePath = contractPDFRelativePath(contractID: contract.id)
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
        guard let job = invoice.job else { return }
        let pdfRel = invoice.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdfRel.isEmpty else { return }

        let jobFolder = try WorkspaceProvisioningService.ensureJobWorkspace(
            job: job,
            context: context
        )

        let invoicesFolderRel = pathAppending(jobFolder.relativePath, "invoices")
        let destFolder = try fetchOrCreateJobSubfolder(
            businessID: job.businessID,
            relativePath: invoicesFolderRel,
            name: "Invoices",
            parentID: jobFolder.id,
            context: context
        )

        let fileName = makeInvoiceFileName(invoice: invoice)
        try upsertFileItem(
            relativePath: pdfRel,
            displayName: fileName.replacingOccurrences(of: ".pdf", with: ""),
            originalFileName: fileName,
            byteCount: 0,
            folder: destFolder,
            jobID: job.id,
            context: context
        )
    }

    @MainActor
    static func upsertContractPDF(contract: Contract, context: ModelContext) throws {
        guard let job = contract.job else { return }
        let pdfRel = contract.pdfRelativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pdfRel.isEmpty else { return }

        let jobFolder = try WorkspaceProvisioningService.ensureJobWorkspace(
            job: job,
            context: context
        )

        let contractsFolderRel = pathAppending(jobFolder.relativePath, "contracts")
        let destFolder = try fetchOrCreateJobSubfolder(
            businessID: job.businessID,
            relativePath: contractsFolderRel,
            name: "Contracts",
            parentID: jobFolder.id,
            context: context
        )

        let fileName = makeContractFileName(contract: contract)
        try upsertFileItem(
            relativePath: pdfRel,
            displayName: fileName.replacingOccurrences(of: ".pdf", with: ""),
            originalFileName: fileName,
            byteCount: 0,
            folder: destFolder,
            jobID: job.id,
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

    private static func fetchOrCreateJobSubfolder(
        businessID: UUID,
        relativePath: String,
        name: String,
        parentID: UUID,
        context: ModelContext
    ) throws -> Folder {
        if let existing = try FolderService.fetchFolder(
            businessID: businessID,
            relativePath: relativePath,
            context: context
        ) {
            if existing.parentFolderID != parentID {
                existing.parentFolderID = parentID
                existing.updatedAt = .now
                try context.save()
            }
            return existing
        }

        let folder = Folder(
            businessID: businessID,
            name: name,
            relativePath: relativePath,
            parentFolderID: parentID
        )
        context.insert(folder)
        try context.save()
        return folder
    }

    private static func upsertFileItem(
        relativePath: String,
        displayName: String,
        originalFileName: String,
        byteCount: Int64,
        folder: Folder,
        jobID: UUID,
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<FileItem>(
            predicate: #Predicate<FileItem> { item in
                item.relativePath == relativePath
            }
        )

        let ext = "pdf"
        let uti = UTType.pdf.identifier
        let folderKey = "job:\(jobID.uuidString)"

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
        return all.filter { $0.job?.id == job.id }
    }

    private static func invoicePDFRelativePath(invoiceID: UUID) -> String {
        "files/docs/invoices/\(invoiceID.uuidString).pdf"
    }

    private static func contractPDFRelativePath(contractID: UUID) -> String {
        "files/docs/contracts/\(contractID.uuidString).pdf"
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

    private static func pathAppending(_ base: String, _ component: String) -> String {
        let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let trimmedComponent = component.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedBase.isEmpty { return trimmedComponent }
        if trimmedComponent.isEmpty { return trimmedBase }
        return "\(trimmedBase)/\(trimmedComponent)"
    }
}
