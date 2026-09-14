import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers the "bundle a contract with the estimate" redesign: a contract
/// drafted via `ContractCreation.create` while the estimate is still being
/// put together, before the client ever sees either. See
/// `InvoiceDetailView.draftBundledContract` (uses this exact helper) and
/// `PortalBackend.isContractReadyForDirectory` (the guard that keeps a
/// draft contract out of the portal directory until it's activated).
@MainActor
final class ContractBundlingTests: XCTestCase {

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

    private func makeEstimate(businessID: UUID, client: Client) -> Invoice {
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
            items: [LineItem(itemDescription: "Fence repair", quantity: 1, unitPrice: 500)]
        )
        context.insert(estimate)
        return estimate
    }

    // MARK: - ContractCreation.create, used for bundling

    func testBundlingAnEstimateProducesADraftContractLinkedToIt() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Ada Lovelace")
        context.insert(client)
        let estimate = makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Agreed with {{Client.Name}} for {{Invoice.Total}}.")
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

        XCTAssertEqual(contract.status, .draft, "a bundled contract must not be visible to the client until the estimate is accepted")
        XCTAssertEqual(contract.invoice?.id, estimate.id, "the bundling path links via Contract.invoice, not the legacy Contract.estimate field")
    }

    func testBundledContractIsRenderedFromTheTemplateNotLeftBlank() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Ada Lovelace")
        context.insert(client)
        let estimate = makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Agreed with {{Client.Name}} for {{Invoice.Total}}.")
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

        XCTAssertTrue(
            contract.renderedBody.contains("Ada Lovelace"),
            "the old bare Contract() path left renderedBody empty — bundling must use the real template engine"
        )
        XCTAssertFalse(contract.renderedBody.contains("{{"), "no placeholder should survive rendering")
    }

    func testEstimateSeesTheBundledContractThroughTheInvoiceInverse() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Ada Lovelace")
        context.insert(client)
        let estimate = makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body text.")
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
        try context.save()

        XCTAssertEqual(estimate.contracts?.count, 1)
        XCTAssertEqual(estimate.contracts?.first?.id, contract.id)
    }

    func testBundlingDoesNotRequireAJobToExistYet() throws {
        // Unlike the old createContractFromEstimate(), which refused to run
        // without invoice.job already set, bundling happens while drafting
        // the estimate — a Job may not exist until acceptance.
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Ada Lovelace")
        context.insert(client)
        let estimate = makeEstimate(businessID: businessID, client: client)
        XCTAssertNil(estimate.job)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body text.")
        context.insert(template)
        try context.save()

        XCTAssertNoThrow(try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: client,
            invoice: estimate
        ))
    }

    // MARK: - Portal directory eligibility gate

    func testADraftContractIsNotReadyForTheDirectory() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Ada Lovelace")
        context.insert(client)
        let estimate = makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body text.")
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

        XCTAssertFalse(
            PortalBackend.isContractReadyForDirectory(contract),
            "a bundled draft contract must never reach the client's portal directory before the estimate is accepted"
        )
    }

    func testActivatingTheContractMakesItReadyForTheDirectory() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Ada Lovelace")
        context.insert(client)
        let estimate = makeEstimate(businessID: businessID, client: client)
        let template = ContractTemplate(name: "Standard Service", category: "General", body: "Body text.")
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

        contract.status = .sent
        XCTAssertTrue(PortalBackend.isContractReadyForDirectory(contract))

        contract.status = .signed
        XCTAssertTrue(PortalBackend.isContractReadyForDirectory(contract))

        contract.status = .cancelled
        XCTAssertTrue(PortalBackend.isContractReadyForDirectory(contract), "even a cancelled contract should be visible, just not a fresh unsent draft")
    }
}
