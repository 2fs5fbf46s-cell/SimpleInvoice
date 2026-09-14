import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Deleting a client, for real, against a live container.
///
/// `ClientSnapshotTests` covers the policy; this covers the thing that actually
/// broke — `modelContext.delete(client)` followed by a render — because the
/// defect lived in the gap between the relationship and the document.
///
/// The container is held in a property for the life of each test: a
/// `ModelContainer` created and discarded in the same expression deallocates
/// immediately and the surviving context traps on `save()`.
@MainActor
final class ClientDeletionTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeClient(name: String = "Ada Lovelace") throws -> Client {
        let client = Client(
            businessID: UUID(),
            name: name,
            email: "ada@example.com",
            phone: "555-0100",
            address: "1 Analytical Way"
        )
        context.insert(client)
        try context.save()
        return client
    }

    private func makeInvoice(for client: Client, paid: Bool = false) throws -> Invoice {
        let invoice = Invoice(
            businessID: client.businessID,
            invoiceNumber: "INV-1",
            isPaid: paid,
            client: client
        )
        context.insert(invoice)
        try context.save()
        return invoice
    }

    // MARK: - The defect

    /// Before the snapshot, this rendered a blank bill-to block.
    func testAPaidInvoiceStillNamesItsClientAfterTheClientIsDeleted() throws {
        let client = try makeClient()
        let invoice = try makeInvoice(for: client, paid: true)

        context.delete(client)
        try context.save()

        XCTAssertNil(invoice.client, "the relationship really is gone")

        let rendered = InvoiceRenderModel(invoice: invoice)
        XCTAssertEqual(rendered.client?.name, "Ada Lovelace")
        XCTAssertEqual(rendered.client?.address, "1 Analytical Way")
        XCTAssertEqual(rendered.client?.email, "ada@example.com")
    }

    func testADraftInvoiceAlsoSurvivesTheDeletion() throws {
        let client = try makeClient()
        let invoice = try makeInvoice(for: client)

        context.delete(client)
        try context.save()

        XCTAssertEqual(InvoiceRenderModel(invoice: invoice).client?.name, "Ada Lovelace")
        XCTAssertEqual(invoice.displayClientName, "Ada Lovelace")
    }

    func testAnInvoiceThatNeverHadAClientStillReadsAsNoClient() throws {
        let invoice = Invoice(businessID: UUID(), invoiceNumber: "INV-2")
        context.insert(invoice)
        try context.save()

        XCTAssertNil(InvoiceRenderModel(invoice: invoice).client)
        XCTAssertEqual(invoice.displayClientName, "No Client")
    }

    // MARK: - Tracking while it can

    func testADraftFollowsACorrectedClientName() throws {
        let client = try makeClient()
        let invoice = try makeInvoice(for: client)

        client.name = "Ada Byron"
        invoice.captureClientSnapshotIfNeeded()
        try context.save()

        XCTAssertEqual(InvoiceRenderModel(invoice: invoice).client?.name, "Ada Byron")
    }

    /// The same asymmetry the business snapshot already has: once it is out the
    /// door it stops tracking.
    func testASentInvoiceDoesNotFollowARename() throws {
        let client = try makeClient()
        let invoice = try makeInvoice(for: client)
        invoice.portalLastUploadedAtMs = 1_700_000_000_000
        invoice.captureClientSnapshotIfNeeded()
        try context.save()

        client.name = "Ada Byron"
        invoice.captureClientSnapshotIfNeeded()
        try context.save()

        XCTAssertEqual(
            InvoiceRenderModel(invoice: invoice).client?.name,
            "Ada Lovelace",
            "a sent invoice keeps the name it was sent with"
        )
    }

    func testAnInvoiceFinalizedBeforeSnapshotsExistedIsBackfilled() throws {
        let client = try makeClient()
        let invoice = try makeInvoice(for: client, paid: true)

        // Simulate the pre-fix row: locked, with nothing recorded.
        invoice.clientSnapshotData = nil
        try context.save()

        XCTAssertTrue(invoice.captureClientSnapshotIfNeeded())
        XCTAssertEqual(invoice.clientSnapshot?.name, "Ada Lovelace")
    }

    // MARK: - Deletion impact

    func testTheImpactCountsInvoicesEstimatesAndJobsSeparately() throws {
        let client = try makeClient()
        _ = try makeInvoice(for: client)

        let estimate = Invoice(
            businessID: client.businessID,
            invoiceNumber: "EST-1",
            documentType: "estimate",
            client: client
        )
        context.insert(estimate)

        let job = Job(businessID: client.businessID, clientID: client.id, startDate: .now, endDate: .now)
        let unrelated = Job(businessID: client.businessID, clientID: UUID(), startDate: .now, endDate: .now)
        context.insert(job)
        context.insert(unrelated)
        try context.save()

        let impact = ClientDeletionImpact.forClient(client, jobs: [job, unrelated])

        XCTAssertEqual(impact.invoices, 1)
        XCTAssertEqual(impact.estimates, 1)
        XCTAssertEqual(impact.jobs, 1, "another client's job must not be counted")
        XCTAssertTrue(impact.hasHistory)
    }

    // MARK: - Orphans

    /// A join row exists only to link an owner to a file. Left to nullify it
    /// survives its owner as invisible garbage that accumulates forever and
    /// syncs to CloudKit. Exactly one of the schema's 29 relationships had a
    /// delete rule before this.
    func testDeletingAClientTakesItsAttachmentJoinRowsWithIt() throws {
        let client = try makeClient()
        let file = FileItem(
            displayName: "contract.pdf",
            originalFileName: "contract.pdf",
            relativePath: "files/contract.pdf",
            fileExtension: "pdf",
            uti: "com.adobe.pdf",
            byteCount: 1024,
            folderKey: ""
        )
        context.insert(file)
        let link = ClientAttachment(client: client, file: file)
        context.insert(link)
        try context.save()

        context.delete(client)
        try context.save()

        let orphans = try context.fetch(FetchDescriptor<ClientAttachment>())
        XCTAssertTrue(orphans.isEmpty, "the join row must not outlive its client")

        let files = try context.fetch(FetchDescriptor<FileItem>())
        XCTAssertEqual(
            files.count, 1,
            "the file itself lives in the folder workspace and must survive"
        )
    }

    func testDeletingAContractTakesItsSignaturesWithIt() throws {
        let contract = Contract(businessID: UUID(), title: "Service Agreement")
        context.insert(contract)

        let signature = ContractSignature(
            businessID: contract.businessID,
            clientID: UUID(),
            contract: contract,
            sessionID: nil,
            signerRole: "client",
            signerName: "Ada Lovelace",
            signatureType: "typed",
            signatureImageData: nil,
            signatureText: "Ada Lovelace",
            consentVersion: "1",
            contractBodyHash: ContractSignLock.bodyHash(contract.renderedBody),
            deviceLabel: nil
        )
        context.insert(signature)
        try context.save()

        context.delete(contract)
        try context.save()

        XCTAssertTrue(
            try context.fetch(FetchDescriptor<ContractSignature>()).isEmpty,
            "a signature nobody can trace back to a document is worse than none"
        )
    }

    // MARK: - Contracts keep their client too

    func testAContractStillNamesItsClientAfterTheClientIsDeleted() throws {
        let client = try makeClient()
        let contract = Contract(businessID: client.businessID, title: "Service Agreement", client: client)
        context.insert(contract)
        contract.captureClientSnapshotIfNeeded()
        try context.save()

        context.delete(client)
        try context.save()

        XCTAssertNil(contract.client)
        XCTAssertEqual(contract.displayClientName, "Ada Lovelace")
    }

    func testASignedContractKeepsThePartyItWasSignedWith() throws {
        let client = try makeClient()
        let contract = Contract(businessID: client.businessID, title: "Service Agreement", client: client)
        context.insert(contract)
        contract.markSigned(byName: "Ada Lovelace")
        try context.save()

        client.name = "Ada Byron"
        contract.captureClientSnapshotIfNeeded()
        try context.save()

        XCTAssertEqual(
            contract.displayClientName,
            "Ada Lovelace",
            "a signed contract does not get its counterparty renamed"
        )
    }

    func testAClientWithNothingAttachedHasNoImpact() throws {
        let client = try makeClient()

        let impact = ClientDeletionImpact.forClient(client, jobs: [])

        XCTAssertEqual(impact.total, 0)
        XCTAssertFalse(impact.hasHistory)
    }
}
