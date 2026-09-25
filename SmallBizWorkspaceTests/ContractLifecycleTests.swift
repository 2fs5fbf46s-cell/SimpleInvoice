import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// The contract lifecycle on the device: signatures coming back from the
/// portal, the owner's own state changes, what can be deleted, and a bundled
/// contract being linked to the job its estimate's acceptance creates.
///
/// Contracts here have no client, so every republish is ineligible and
/// nothing touches the network.
@MainActor
final class ContractLifecycleTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeContract(status: ContractStatus = .sent, body: String = "The terms.") throws -> Contract {
        let contract = Contract(businessID: businessID, title: "Deck build agreement", statusRaw: status.rawValue)
        contract.renderedBody = body
        context.insert(contract)
        try context.save()
        return contract
    }

    private func signedItem(
        for contract: Contract,
        name: String = "Maria Reyes",
        signedAtMs: Double = 1_790_000_000_000,
        hash: String? = "abc123",
        pdf: String? = "https://blob.example.test/signed.pdf"
    ) -> PortalBackend.ContractActivityDTO {
        PortalBackend.ContractActivityDTO(
            contractId: contract.id.uuidString,
            status: "signed",
            signedAtMs: signedAtMs,
            signedName: name,
            signedBodyHash: hash,
            signedPdfUrl: pdf,
            signedMethod: "portal",
            sentAtMs: nil,
            lastReminderAtMs: nil,
            updatedAtMs: signedAtMs
        )
    }

    // MARK: - Signatures from the portal

    func testAPortalSignatureMarksTheContractSigned() throws {
        let contract = try makeContract()

        ContractActivityPullService.apply(signedItem(for: contract), businessID: businessID, context: context)

        XCTAssertEqual(contract.status, .signed)
        XCTAssertEqual(contract.signedByName, "Maria Reyes")
        XCTAssertEqual(contract.signedAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(contract.signedBodyHash, "abc123", "the server's hash is of what the client actually saw")
        XCTAssertEqual(contract.signedPDFURL, "https://blob.example.test/signed.pdf")
        XCTAssertEqual(contract.signedMethod, "portal")
        XCTAssertFalse(contract.portalNeedsUpload)
    }

    func testApplyingTheSameSignatureTwiceChangesNothing() throws {
        let contract = try makeContract()
        let item = signedItem(for: contract)

        ContractActivityPullService.apply(item, businessID: businessID, context: context)
        let firstSignedAt = contract.signedAt
        ContractActivityPullService.apply(signedItem(for: contract, signedAtMs: 1_800_000_000_000), businessID: businessID, context: context)

        XCTAssertEqual(contract.signedAt, firstSignedAt, "a signature's date never moves")
    }

    func testTheSignedPDFArrivesInALaterPull() throws {
        let contract = try makeContract()

        ContractActivityPullService.apply(signedItem(for: contract, pdf: nil), businessID: businessID, context: context)
        XCTAssertNil(contract.signedPDFURL)
        ContractActivityPullService.apply(signedItem(for: contract), businessID: businessID, context: context)

        XCTAssertEqual(contract.signedPDFURL, "https://blob.example.test/signed.pdf")
    }

    func testASignatureWinsOverALocalCancelThatHadNotSynced() throws {
        let contract = try makeContract(status: .cancelled)
        contract.canceledAt = .now

        ContractActivityPullService.apply(signedItem(for: contract), businessID: businessID, context: context)

        XCTAssertEqual(contract.status, .signed)
        XCTAssertNil(contract.canceledAt)
    }

    func testAnotherBusinessesContractIsIgnored() throws {
        let contract = try makeContract()

        ContractActivityPullService.apply(signedItem(for: contract), businessID: UUID(), context: context)

        XCTAssertEqual(contract.status, .sent)
    }

    func testEmailActivityIsRecorded() throws {
        let contract = try makeContract()
        let item = PortalBackend.ContractActivityDTO(
            contractId: contract.id.uuidString,
            status: "sent",
            signedAtMs: nil,
            signedName: nil,
            signedBodyHash: nil,
            signedPdfUrl: nil,
            signedMethod: nil,
            sentAtMs: 1_790_000_000_000,
            lastReminderAtMs: 1_790_100_000_000,
            updatedAtMs: 1_790_100_000_000
        )

        ContractActivityPullService.apply(item, businessID: businessID, context: context)

        XCTAssertEqual(contract.status, .sent)
        XCTAssertEqual(contract.sentAt, Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertEqual(contract.lastReminderAt, Date(timeIntervalSince1970: 1_790_100_000))
    }

    // MARK: - The owner's changes

    func testRevisingASentContractMakesItAnEditableDraft() async throws {
        let contract = try makeContract(status: .sent)

        await ContractLifecycle.revise(contract, context: context)

        XCTAssertEqual(contract.status, .draft)
        XCTAssertTrue(ContractSignLock.canEditBody(status: contract.status))
    }

    func testCancelRecordsWhenAndReopenClearsIt() async throws {
        let contract = try makeContract(status: .sent)

        await ContractLifecycle.cancel(contract, context: context)
        XCTAssertEqual(contract.status, .cancelled)
        XCTAssertNotNil(contract.canceledAt)

        await ContractLifecycle.reopen(contract, context: context)
        XCTAssertEqual(contract.status, .draft)
        XCTAssertNil(contract.canceledAt)
    }

    func testASignedContractCantBeCanceled() async throws {
        let contract = try makeContract(status: .sent)
        contract.markSigned(byName: "Maria Reyes")

        await ContractLifecycle.cancel(contract, context: context)

        XCTAssertEqual(contract.status, .signed)
    }

    func testMarkingSignedInPersonLocksTheTerms() async throws {
        let contract = try makeContract(status: .sent)
        let when = Date(timeIntervalSince1970: 1_790_000_000)

        await ContractLifecycle.markSignedInPerson(contract, signerName: " Maria Reyes ", signedAt: when, context: context)

        XCTAssertEqual(contract.status, .signed)
        XCTAssertEqual(contract.signedByName, "Maria Reyes")
        XCTAssertEqual(contract.signedAt, when)
        XCTAssertEqual(contract.signedMethod, "in_person")
        XCTAssertFalse(ContractSignLock.canEditBody(status: contract.status))
        XCTAssertEqual(contract.signatureIntegrity, .intact)
    }

    func testOnlyANeverSentDraftCanBeDeleted() throws {
        let draft = try makeContract(status: .draft)
        XCTAssertTrue(ContractLifecycle.canDelete(draft))

        draft.sentAt = .now
        XCTAssertFalse(ContractLifecycle.canDelete(draft), "a revised contract the client has seen is canceled, not deleted")

        let sent = try makeContract(status: .sent)
        XCTAssertFalse(ContractLifecycle.canDelete(sent))
    }

    func testStatusNamesAreTheSameEverywhere() throws {
        XCTAssertEqual(ContractDisplayStatus(try makeContract(status: .draft)).label, "Draft")
        XCTAssertEqual(ContractDisplayStatus(try makeContract(status: .sent)).label, "Sent")
        XCTAssertEqual(ContractDisplayStatus(try makeContract(status: .signed)).label, "Signed")
        XCTAssertEqual(ContractDisplayStatus(try makeContract(status: .cancelled)).label, "Canceled")
    }

    // MARK: - Bundled contracts

    func testAcceptingTheEstimateLinksItsContractToTheNewJob() throws {
        let client = Client(businessID: businessID, name: "Ada Lovelace", email: "ada@example.com")
        context.insert(client)
        let estimate = Invoice(businessID: businessID, invoiceNumber: "EST-1", documentType: "estimate", client: client)
        estimate.estimateStatus = "sent"
        context.insert(estimate)
        let template = ContractTemplate(name: "Standard", category: "General", body: "Agreed.")
        context.insert(template)
        try context.save()
        let contract = try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: client,
            invoice: estimate
        )

        let event = EstimateDecisionDTO(
            estimateId: estimate.id.uuidString,
            businessId: businessID.uuidString,
            clientId: client.id.uuidString,
            status: "accepted",
            decidedAtMs: Date().timeIntervalSince1970 * 1000,
            updatedAtMs: Date().timeIntervalSince1970 * 1000
        )
        EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)

        let job = try XCTUnwrap(estimate.job)
        XCTAssertEqual(contract.job?.id, job.id)
        XCTAssertTrue(contract.linkedJobIDsCSV.contains(job.id.uuidString))
    }

    // The PDF's client signature block: blank until signed, then the
    // signer's name, how they signed, and the date.
    func testTheSignatureBlockIsBlankUntilSigned() throws {
        let contract = try makeContract()
        XCTAssertNil(ContractPDFGenerator.clientSignature(for: contract))
    }

    func testASignedContractFillsTheClientSignatureBlock() throws {
        let contract = try makeContract()
        contract.markSigned(byName: "Maria Reyes", at: Date(timeIntervalSince1970: 1_790_000_000))
        contract.signedMethod = "portal"
        let block = try XCTUnwrap(ContractPDFGenerator.clientSignature(for: contract))
        XCTAssertEqual(block.name, "Maria Reyes")
        XCTAssertEqual(block.method, "Signed electronically")
        XCTAssertFalse(block.date.isEmpty)

        contract.signedMethod = "in_person"
        XCTAssertEqual(ContractPDFGenerator.clientSignature(for: contract)?.method, "Signed in person")
    }

    func testTheContractPDFFitsOnePageWithoutAFooterPage() throws {
        let contract = try makeContract()
        contract.markSigned(byName: "Maria Reyes")
        let data = ContractPDFGenerator.makePDFData(contract: contract, business: nil)
        let doc = try XCTUnwrap(CGPDFDocument(CGDataProvider(data: data as CFData)!))
        XCTAssertEqual(doc.numberOfPages, 1)
    }
}
