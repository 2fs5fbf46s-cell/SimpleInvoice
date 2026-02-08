import XCTest
import SwiftData
@testable import SmallBizWorkspace

@MainActor
final class RoutingAcceptanceTests: XCTestCase {
    private var testFileStoreBaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SBWTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        testFileStoreBaseURL = root
        setenv("SBW_FILESTORE_BASE_URL", root.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("SBW_FILESTORE_BASE_URL")
        if let testFileStoreBaseURL {
            try? FileManager.default.removeItem(at: testFileStoreBaseURL)
        }
        testFileStoreBaseURL = nil
        try super.tearDownWithError()
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Business.self,
            BusinessProfile.self,
            Client.self,
            Invoice.self,
            LineItem.self,
            CatalogItem.self,
            Contract.self,
            ClientAttachment.self,
            JobAttachment.self,
            AuditEvent.self,
            PortalIdentity.self,
            PortalSession.self,
            PortalInvite.self,
            PortalAuditEvent.self,
            EstimateDecisionRecord.self,
            ContractTemplate.self,
            Folder.self,
            FileItem.self,
            InvoiceAttachment.self,
            ContractAttachment.self,
            Job.self,
            Blockout.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeBusiness(in context: ModelContext, name: String = "Test Biz") throws -> Business {
        let business = Business(name: name, isActive: true)
        context.insert(business)
        try context.save()
        return business
    }

    private func makeClient(in context: ModelContext, business: Business, name: String = "Client A") throws -> Client {
        let client = Client(businessID: business.id, name: name, email: "c@example.com", phone: "5551112222")
        context.insert(client)
        try context.save()
        return client
    }

    private func makeJob(in context: ModelContext, business: Business, client: Client, title: String = "Job A") throws -> Job {
        let now = Date()
        let job = Job(
            businessID: business.id,
            clientID: client.id,
            title: title,
            startDate: now,
            endDate: now.addingTimeInterval(3600),
            status: "scheduled"
        )
        context.insert(job)
        try context.save()
        return job
    }

    private func fetchAllFileItems(_ context: ModelContext) throws -> [FileItem] {
        try context.fetch(FetchDescriptor<FileItem>())
    }

    private func fetchAllFolders(_ context: ModelContext) throws -> [Folder] {
        try context.fetch(FetchDescriptor<Folder>())
    }

    func testInvoicePDFRoutesToJobInvoices() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let business = try makeBusiness(in: context)
        let client = try makeClient(in: context, business: business)
        let job = try makeJob(in: context, business: business, client: client)

        let invoice = Invoice(businessID: business.id, invoiceNumber: "INV-1", documentType: "invoice", client: client, job: job)
        context.insert(invoice)
        try context.save()

        _ = try DocumentFileIndexService.persistInvoicePDF(invoice: invoice, profiles: [], context: context)

        let files = try fetchAllFileItems(context)
        guard let indexed = files.first(where: { $0.relativePath == invoice.pdfRelativePath }) else {
            return XCTFail("Expected indexed invoice file")
        }
        XCTAssertTrue(indexed.relativePath.lowercased().contains("/invoices/"))
    }

    func testEstimatePDFRoutesToJobEstimates() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let business = try makeBusiness(in: context)
        let client = try makeClient(in: context, business: business)
        let job = try makeJob(in: context, business: business, client: client)

        let estimate = Invoice(businessID: business.id, invoiceNumber: "EST-1", documentType: "estimate", client: client, job: job)
        context.insert(estimate)
        try context.save()

        _ = try DocumentFileIndexService.persistInvoicePDF(invoice: estimate, profiles: [], context: context)

        let files = try fetchAllFileItems(context)
        guard let indexed = files.first(where: { $0.relativePath == estimate.pdfRelativePath }) else {
            return XCTFail("Expected indexed estimate file")
        }
        XCTAssertTrue(indexed.relativePath.lowercased().contains("/estimates/"))
    }

    func testContractPDFRoutesToJobContracts() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let business = try makeBusiness(in: context)
        let client = try makeClient(in: context, business: business)
        let job = try makeJob(in: context, business: business, client: client)

        let contract = Contract(
            businessID: business.id,
            title: "Contract A",
            templateName: "T",
            templateCategory: "General",
            renderedBody: "Body",
            client: client
        )
        contract.job = job
        context.insert(contract)
        try context.save()

        _ = try DocumentFileIndexService.persistContractPDF(contract: contract, business: nil, context: context)

        let files = try fetchAllFileItems(context)
        guard let indexed = files.first(where: { $0.relativePath == contract.pdfRelativePath }) else {
            return XCTFail("Expected indexed contract file")
        }
        XCTAssertTrue(indexed.relativePath.lowercased().contains("/contracts/"))
    }

    func testPhotoImportDefaultFolderResolvesToJobPhotos() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let business = try makeBusiness(in: context)
        let client = try makeClient(in: context, business: business)
        let job = try makeJob(in: context, business: business, client: client)

        let folder = try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: client,
            job: job,
            kind: .photos,
            context: context
        )
        XCTAssertEqual(folder.name, "Photos")
        XCTAssertTrue(folder.relativePath.lowercased().contains("/photos"))
    }

    func testEstimateWithoutJobFallsBackToClientEstimates() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let business = try makeBusiness(in: context)
        let client = try makeClient(in: context, business: business)

        let estimate = Invoice(businessID: business.id, invoiceNumber: "EST-2", documentType: "estimate", client: client, job: nil)
        context.insert(estimate)
        try context.save()

        _ = try DocumentFileIndexService.persistInvoicePDF(invoice: estimate, profiles: [], context: context)

        let files = try fetchAllFileItems(context)
        guard let indexed = files.first(where: { $0.relativePath == estimate.pdfRelativePath }) else {
            return XCTFail("Expected indexed fallback estimate file")
        }
        XCTAssertTrue(indexed.relativePath.lowercased().contains("/estimates/"))
        XCTAssertTrue(indexed.relativePath.lowercased().contains("/clients/"))
    }

    func testRepeatedExportsAreIdempotentForFolderAndFileIndex() throws {
        let container = try makeContainer()
        let context = container.mainContext

        let business = try makeBusiness(in: context)
        let client = try makeClient(in: context, business: business)
        let job = try makeJob(in: context, business: business, client: client)

        let invoice = Invoice(businessID: business.id, invoiceNumber: "INV-IDEMP", documentType: "invoice", client: client, job: job)
        context.insert(invoice)
        try context.save()

        _ = try DocumentFileIndexService.persistInvoicePDF(invoice: invoice, profiles: [], context: context)
        _ = try DocumentFileIndexService.persistInvoicePDF(invoice: invoice, profiles: [], context: context)

        let files = try fetchAllFileItems(context).filter { $0.relativePath == invoice.pdfRelativePath }
        XCTAssertEqual(files.count, 1, "Expected one indexed file record for same invoice path")

        let folders = try fetchAllFolders(context)
        let invoiceFolders = folders.filter { $0.folderKey == "job:\(job.id.uuidString):invoices" }
        XCTAssertEqual(invoiceFolders.count, 1, "Expected one invoices folder for job")
    }
}
