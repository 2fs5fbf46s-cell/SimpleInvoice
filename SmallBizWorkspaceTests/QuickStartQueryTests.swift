import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// The SwiftData half of the Quick Start checklist.
///
/// `QuickStartChecklistTests` covers the decision; these cover the four queries
/// that feed it, which is where the subtle mistakes live — scoping to the wrong
/// business, or counting a draft as a sent invoice.
///
/// Note the container is held in a property for the life of each test. A
/// `ModelContainer` created and discarded in the same expression
/// (`makeContainer().mainContext`) deallocates immediately and the surviving
/// context traps on `save()`.
@MainActor
final class QuickStartQueryTests: XCTestCase {

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

    @discardableResult
    private func makeBusiness(name: String = "Test Biz") throws -> Business {
        let business = Business(name: name, isActive: true)
        context.insert(business)
        try context.save()
        return business
    }

    private func checklist(for businessID: UUID?, notifications: Bool = false) -> QuickStartChecklist {
        QuickStartChecklist.fromStoredData(
            businessID: businessID,
            context: context,
            notificationsEnabled: notifications
        )
    }

    // MARK: - Empty

    func testABrandNewBusinessHasNothingComplete() throws {
        let business = try makeBusiness()

        let result = checklist(for: business.id)

        XCTAssertEqual(result.completedCount, 0)
        XCTAssertEqual(result.nextStep, .addClient)
    }

    func testNoBusinessMeansNothingComplete() {
        XCTAssertEqual(checklist(for: nil).completedCount, 0)
    }

    // MARK: - Clients

    func testAddingAClientCompletesThatStep() throws {
        let business = try makeBusiness()

        context.insert(Client(businessID: business.id, name: "Ada"))
        try context.save()

        XCTAssertTrue(checklist(for: business.id).isComplete(.addClient))
    }

    func testAnotherBusinessesClientDoesNotCount() throws {
        let mine = try makeBusiness(name: "Mine")
        let theirs = try makeBusiness(name: "Theirs")

        context.insert(Client(businessID: theirs.id, name: "Not mine"))
        try context.save()

        XCTAssertFalse(
            checklist(for: mine.id).isComplete(.addClient),
            "the query must be scoped to the business being asked about"
        )
        XCTAssertTrue(checklist(for: theirs.id).isComplete(.addClient))
    }

    // MARK: - Sent invoices

    func testADraftInvoiceIsNotASentInvoice() throws {
        let business = try makeBusiness()

        context.insert(Invoice(businessID: business.id, invoiceNumber: "INV-1"))
        try context.save()

        XCTAssertFalse(
            checklist(for: business.id).isComplete(.sendInvoice),
            "a draft nobody has seen is not the milestone"
        )
    }

    func testAnUploadedInvoiceCountsAsSent() throws {
        let business = try makeBusiness()

        let invoice = Invoice(businessID: business.id, invoiceNumber: "INV-1")
        invoice.portalLastUploadedAtMs = 1_700_000_000_000
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(checklist(for: business.id).isComplete(.sendInvoice))
    }

    func testAPaidInvoiceCountsAsSent() throws {
        let business = try makeBusiness()

        context.insert(Invoice(businessID: business.id, invoiceNumber: "INV-1", isPaid: true))
        try context.save()

        XCTAssertTrue(checklist(for: business.id).isComplete(.sendInvoice))
    }

    func testAnEstimateDoesNotCountAsASentInvoice() throws {
        let business = try makeBusiness()

        let estimate = Invoice(
            businessID: business.id,
            invoiceNumber: "EST-1",
            isPaid: true,
            documentType: "estimate"
        )
        context.insert(estimate)
        try context.save()

        XCTAssertFalse(
            checklist(for: business.id).isComplete(.sendInvoice),
            "estimates are Invoices too; documentType has to be part of the query"
        )
    }

    func testAnotherBusinessesSentInvoiceDoesNotCount() throws {
        let mine = try makeBusiness(name: "Mine")
        let theirs = try makeBusiness(name: "Theirs")

        let invoice = Invoice(businessID: theirs.id, invoiceNumber: "INV-1", isPaid: true)
        context.insert(invoice)
        try context.save()

        XCTAssertFalse(checklist(for: mine.id).isComplete(.sendInvoice))
    }

    // MARK: - Payments

    func testEnablingAnyPaymentMethodCompletesThatStep() throws {
        let business = try makeBusiness()
        XCTAssertFalse(checklist(for: business.id).isComplete(.setUpPayments))

        business.cashAppEnabled = true
        try context.save()

        XCTAssertTrue(checklist(for: business.id).isComplete(.setUpPayments))
    }

    func testConnectingStripeCompletesThePaymentStep() throws {
        let business = try makeBusiness()

        business.stripeAccountId = "acct_123"
        try context.save()

        XCTAssertTrue(checklist(for: business.id).isComplete(.setUpPayments))
    }

    func testAnEmptyStripeAccountIdIsNotConnected() throws {
        let business = try makeBusiness()

        business.stripeAccountId = ""
        try context.save()

        XCTAssertFalse(checklist(for: business.id).isComplete(.setUpPayments))
    }

    func testAnotherBusinessesPaymentSetupDoesNotCount() throws {
        let mine = try makeBusiness(name: "Mine")
        let theirs = try makeBusiness(name: "Theirs")

        theirs.venmoEnabled = true
        try context.save()

        XCTAssertFalse(checklist(for: mine.id).isComplete(.setUpPayments))
    }

    // MARK: - Everything

    func testDoingEverythingCompletesTheChecklist() throws {
        let business = try makeBusiness()

        context.insert(Client(businessID: business.id, name: "Ada"))
        let invoice = Invoice(businessID: business.id, invoiceNumber: "INV-1")
        invoice.portalLastUploadedAtMs = 1
        context.insert(invoice)
        business.achEnabled = true
        try context.save()

        let result = checklist(for: business.id, notifications: true)

        XCTAssertTrue(result.isFullyComplete)
        XCTAssertNil(result.nextStep)
    }
}
