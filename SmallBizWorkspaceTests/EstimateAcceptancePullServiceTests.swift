import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `EstimateAcceptancePullService.materialize`: turning a durable
/// "estimate accepted" event (from GET /api/estimate/accepted/pull) into
/// local state — the local Invoice's estimateStatus, a Job via the existing
/// EstimateAcceptanceHandler, and flipping any bundled draft Contract to
/// .sent (see ContractBundlingTests for the bundling side). `materialize`
/// itself never touches the network — the portal upload happens afterward
/// in `pullAndMaterialize`, properly awaited — so these tests need no
/// network mocking and can't leak a background Task past teardown.
@MainActor
final class EstimateAcceptancePullServiceTests: XCTestCase {

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

    private func makeClient(businessID: UUID) throws -> Client {
        let client = Client(businessID: businessID, name: "Ada Lovelace", email: "ada@example.com")
        context.insert(client)
        try context.save()
        return client
    }

    private func makeEstimate(businessID: UUID, client: Client, status: String = "sent") throws -> Invoice {
        let estimate = Invoice(
            businessID: businessID,
            invoiceNumber: "EST-0001",
            issueDate: .now,
            dueDate: .now.addingTimeInterval(14 * 86400),
            paymentTerms: "Valid for 14 days",
            notes: "",
            thankYou: "",
            termsAndConditions: "",
            taxRate: 0,
            discountAmount: 0,
            isPaid: false,
            documentType: "estimate",
            client: client,
            job: nil,
            items: []
        )
        estimate.estimateStatus = status
        context.insert(estimate)
        try context.save()
        return estimate
    }

    private func makeAcceptedEvent(estimate: Invoice, businessID: UUID, clientID: UUID) -> AcceptedEstimateDTO {
        AcceptedEstimateDTO(
            estimateId: estimate.id.uuidString,
            businessId: businessID.uuidString,
            clientId: clientID.uuidString,
            decidedAtMs: Date().timeIntervalSince1970 * 1000,
            updatedAtMs: Date().timeIntervalSince1970 * 1000
        )
    }

    // MARK: - Core materialization

    func testMaterializeAcceptsTheEstimateAndCreatesAJob() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)

        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(estimate.estimateStatus, "accepted")
        XCTAssertNotNil(estimate.estimateAcceptedAt)
        XCTAssertNotNil(estimate.job, "the device must materialize a Job, same as the old foreground-poll path did")
        XCTAssertEqual(estimate.job?.sourceEstimateId, estimate.id.uuidString)
    }

    func testMaterializeIsIdempotentForRepeatedPulls() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)

        EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()
        let firstJobID = estimate.job?.id

        let secondResult = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        XCTAssertFalse(secondResult.didChange, "a repeat pull of the same acceptance must be a no-op")
        XCTAssertEqual(estimate.job?.id, firstJobID, "must never create a second Job for the same estimate")

        let jobs = try context.fetch(FetchDescriptor<Job>())
        XCTAssertEqual(jobs.count, 1)
    }

    func testMaterializeSkipsAnEstimateNotFoundLocally() throws {
        let businessID = UUID()
        let event = AcceptedEstimateDTO(
            estimateId: UUID().uuidString, // no such estimate exists on this device
            businessId: businessID.uuidString,
            clientId: UUID().uuidString,
            decidedAtMs: Date().timeIntervalSince1970 * 1000,
            updatedAtMs: Date().timeIntervalSince1970 * 1000
        )

        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        XCTAssertFalse(result.didChange)
        XCTAssertNil(result.activatedContractID)
    }

    func testMaterializeSkipsAMalformedEstimateId() throws {
        let businessID = UUID()
        let event = AcceptedEstimateDTO(
            estimateId: "not-a-uuid",
            businessId: businessID.uuidString,
            clientId: UUID().uuidString,
            decidedAtMs: Date().timeIntervalSince1970 * 1000,
            updatedAtMs: Date().timeIntervalSince1970 * 1000
        )

        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        XCTAssertFalse(result.didChange)
    }

    func testMaterializeIgnoresAnEstimateBelongingToAnotherBusiness() throws {
        let ownerBusinessID = UUID()
        let otherBusinessID = UUID()
        let client = try makeClient(businessID: ownerBusinessID)
        let estimate = try makeEstimate(businessID: ownerBusinessID, client: client)
        let event = makeAcceptedEvent(estimate: estimate, businessID: otherBusinessID, clientID: client.id)

        let result = EstimateAcceptancePullService.materialize(event, businessID: otherBusinessID, context: context)

        XCTAssertFalse(result.didChange)
        XCTAssertEqual(estimate.estimateStatus, "sent", "must not touch an estimate that belongs to a different business")
    }

    // MARK: - Bundled contract activation

    func testMaterializeActivatesABundledDraftContract() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Agreed with {{Client.Name}}.")
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
        XCTAssertEqual(contract.status, .draft)

        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)
        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        XCTAssertTrue(result.didChange)
        XCTAssertEqual(result.activatedContractID, contract.id)
        XCTAssertEqual(contract.status, .sent, "the bundled contract must be activated the moment the estimate is accepted")
        XCTAssertTrue(contract.portalNeedsUpload, "activation must queue it for the portal upload pullAndMaterialize awaits afterward")
    }

    func testMaterializeLeavesAnAlreadyActivatedContractAlone() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body.")
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
        contract.status = .signed
        try context.save()

        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)
        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        XCTAssertNil(result.activatedContractID, "a contract that's already moved past .draft must not be reactivated")
        XCTAssertEqual(contract.status, .signed)
    }

    func testMaterializeWithNoBundledContractStillCreatesTheJob() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)

        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)

        XCTAssertTrue(result.didChange)
        XCTAssertNil(result.activatedContractID)
        XCTAssertNotNil(estimate.job, "bundling a contract is optional — acceptance must still create the Job")
    }

    // MARK: - Deposit tracking

    func testMaterializeCreatesADepositInvoiceWhenTheContractConfiguresOne() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body.")
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
        contract.depositAmountCents = 15000 // $150
        try context.save()

        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)
        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        XCTAssertNotNil(result.depositInvoiceID, "a configured deposit must produce a real invoice to upload")
        let job = try XCTUnwrap(estimate.job)
        XCTAssertEqual(job.depositAmountCents, 15000)
        XCTAssertEqual(job.depositInvoiceId, result.depositInvoiceID?.uuidString)
        XCTAssertNil(job.depositPaidAtMs, "not paid yet — only DepositStatusSyncService sets this")

        let depositID = try XCTUnwrap(result.depositInvoiceID)
        let deposit = try XCTUnwrap((try context.fetch(
            FetchDescriptor<Invoice>(predicate: #Predicate { $0.id == depositID })
        )).first)
        XCTAssertEqual(deposit.documentType, "invoice")
        XCTAssertEqual(deposit.sourceContractId, contract.id.uuidString)
        XCTAssertEqual(deposit.client?.id, client.id)
        XCTAssertEqual(deposit.job?.id, job.id)
        XCTAssertEqual(deposit.items?.count, 1)
        let depositLineItem = try XCTUnwrap(deposit.items?.first)
        XCTAssertEqual(depositLineItem.itemDescription, "Deposit")
        XCTAssertEqual(depositLineItem.unitPrice, 150, accuracy: 0.001)
    }

    func testMaterializeCreatesNoDepositInvoiceWhenNoneIsConfigured() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body.")
        context.insert(template)
        try context.save()

        try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: client,
            invoice: estimate
        )
        // depositAmountCents left nil — no deposit configured.

        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)
        let result = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)

        XCTAssertNil(result.depositInvoiceID)
        XCTAssertNil(estimate.job?.depositInvoiceId)

        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        XCTAssertEqual(invoices.count, 1, "only the original estimate should exist — no deposit invoice")
    }

    func testMaterializeIsIdempotentForTheDepositInvoiceToo() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let estimate = try makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body.")
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
        contract.depositAmountCents = 5000
        try context.save()

        let event = makeAcceptedEvent(estimate: estimate, businessID: businessID, clientID: client.id)
        let first = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        let second = EstimateAcceptancePullService.materialize(event, businessID: businessID, context: context)
        try context.save()

        XCTAssertNil(second.depositInvoiceID, "a repeat pull must not create a second deposit invoice")
        XCTAssertEqual(estimate.job?.depositInvoiceId, first.depositInvoiceID?.uuidString)

        let deposits = try context.fetch(FetchDescriptor<Invoice>()).filter { $0.sourceContractId == contract.id.uuidString }
        XCTAssertEqual(deposits.count, 1)
    }
}
