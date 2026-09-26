import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `ContractCreation.create` wiring a Job and a deposit through to
/// both the stored relationship/field AND the rendered body text — before
/// this, `contract.job`/`contract.depositAmountCents` were set by callers
/// *after* `create()` had already rendered the body, so neither ever
/// actually showed up in the document.
@MainActor
final class ContractCreationTests: XCTestCase {

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

    private func makeTemplate() -> ContractTemplate {
        ContractTemplate(
            name: "Test Template",
            category: "General",
            body: "Site: {{Job.Location}}. Deposit: {{Invoice.Deposit}}. Balance: {{Invoice.Balance}}.",
            isBuiltIn: false
        )
    }

    func testCreateWiresJobAndDepositIntoTheRenderedBodyAndTheContract() throws {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Testing Freeman")
        let invoice = Invoice(
            businessID: businessID,
            invoiceNumber: "SI-2026-004",
            client: client,
            items: [LineItem(itemDescription: "Deck staining", quantity: 1, unitPrice: 3250)]
        )
        let job = Job(
            businessID: businessID,
            title: "Deck staining",
            startDate: .now,
            endDate: .now.addingTimeInterval(3600),
            locationName: "1 Infinite Loop, Cupertino, CA"
        )
        let template = makeTemplate()
        let deposit = ContractCreation.defaultDepositCents(invoiceTotalCents: invoice.totalCents)

        let contract = try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: client,
            invoice: invoice,
            job: job,
            depositAmountCents: deposit
        )

        XCTAssertEqual(contract.job?.id, job.id)
        XCTAssertEqual(contract.depositAmountCents, deposit)
        XCTAssertTrue(contract.renderedBody.contains("1 Infinite Loop, Cupertino, CA"))
        XCTAssertTrue(contract.renderedBody.contains("$1,625.00"), contract.renderedBody)
        XCTAssertFalse(contract.renderedBody.contains("[add"))
    }

    func testCreateWithoutJobOrDepositStillWorks() throws {
        let businessID = UUID()
        let template = makeTemplate()

        let contract = try ContractCreation.create(
            context: context,
            template: template,
            businessID: businessID,
            business: nil,
            client: nil,
            invoice: nil
        )

        XCTAssertNil(contract.job)
        XCTAssertNil(contract.depositAmountCents)
        XCTAssertTrue(contract.renderedBody.contains("[add job site address]"))
    }
}
