import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Today's whole pitch is that the feed only ever shows what's real. These
/// cover the filtering (what counts as overdue, what counts as awaiting
/// signature) and the ranking (critical before warning before info, and a
/// stable order within each) that `AttentionFeedService` is responsible for.
///
/// Container is held in a property for the test's lifetime — see
/// `QuickStartQueryTests` for why a container built and discarded in the same
/// expression traps on save.
@MainActor
final class AttentionFeedServiceTests: XCTestCase {

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

    private func emptyChecklist() -> QuickStartChecklist {
        QuickStartChecklist(completed: Set(QuickStartChecklist.Step.allCases))
    }

    private func items(
        for businessID: UUID?,
        checklist: QuickStartChecklist? = nil,
        pendingApprovalBookingCount: Int = 0,
        now: Date = .now
    ) -> [AttentionItem] {
        AttentionFeedService.attentionItems(
            businessID: businessID,
            context: context,
            checklist: checklist ?? emptyChecklist(),
            pendingApprovalBookingCount: pendingApprovalBookingCount,
            now: now
        )
    }

    // MARK: - Empty / no business

    func testNoBusinessMeansNoItems() {
        XCTAssertTrue(items(for: nil).isEmpty)
    }

    func testNothingOutstandingMeansNoItems() throws {
        let business = try makeBusiness()
        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    // MARK: - Overdue invoices

    func testOverdueUnpaidInvoiceWithLineItemsIsCritical() throws {
        let business = try makeBusiness()
        let invoice = Invoice(
            businessID: business.id,
            invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            isPaid: false,
            items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        let result = items(for: business.id)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].severity, .critical)
        XCTAssertEqual(result[0].kind, .overdueInvoice(invoiceID: invoice.id))
    }

    func testPaidInvoiceIsNotOverdue() throws {
        let business = try makeBusiness()
        let invoice = Invoice(
            businessID: business.id,
            invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            isPaid: true,
            items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testDraftInvoiceWithNoItemsIsNotOverdue() throws {
        // Mirrors canBeSent: a document nobody could have sent isn't a missed
        // payment, whatever its due date says.
        let business = try makeBusiness()
        let invoice = Invoice(
            businessID: business.id,
            invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            isPaid: false,
            items: []
        )
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testOverdueEstimateIsNotAnOverdueInvoice() throws {
        let business = try makeBusiness()
        let estimate = Invoice(
            businessID: business.id,
            invoiceNumber: "EST-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            isPaid: false,
            documentType: "estimate",
            items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(estimate)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testInvoiceNotYetDueIsNotOverdue() throws {
        let business = try makeBusiness()
        let invoice = Invoice(
            businessID: business.id,
            invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: 3, to: .now)!,
            isPaid: false,
            items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testAnotherBusinessesOverdueInvoiceDoesNotCount() throws {
        let mine = try makeBusiness(name: "Mine")
        let theirs = try makeBusiness(name: "Theirs")
        let invoice = Invoice(
            businessID: theirs.id,
            invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -3, to: .now)!,
            isPaid: false,
            items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(items(for: mine.id).isEmpty)
    }

    func testMostOverdueInvoiceSortsFirstAmongInvoices() throws {
        let business = try makeBusiness()
        // Each invoice needs its own LineItem instance — LineItem is a SwiftData
        // reference type, so sharing one array between two invoices silently
        // moves it to whichever is saved last, leaving the other's items empty
        // and filtered out as an unsendable draft.
        let dueYesterday = Invoice(
            businessID: business.id, invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
            isPaid: false, items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        let dueLastWeek = Invoice(
            businessID: business.id, invoiceNumber: "INV-2",
            dueDate: Calendar.current.date(byAdding: .day, value: -7, to: .now)!,
            isPaid: false, items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(dueYesterday)
        context.insert(dueLastWeek)
        try context.save()

        let result = items(for: business.id)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].kind, .overdueInvoice(invoiceID: dueLastWeek.id), "the older miss should lead")
        XCTAssertEqual(result[1].kind, .overdueInvoice(invoiceID: dueYesterday.id))
    }

    // MARK: - Contracts awaiting signature

    func testSentContractIsAwaitingSignature() throws {
        let business = try makeBusiness()
        let contract = Contract(businessID: business.id, title: "Agreement")
        contract.statusRaw = ContractStatus.sent.rawValue
        context.insert(contract)
        try context.save()

        let result = items(for: business.id)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].severity, .warning)
        XCTAssertEqual(result[0].kind, .unsignedContract(contractID: contract.id))
    }

    func testDraftContractIsNotAwaitingSignature() throws {
        let business = try makeBusiness()
        let contract = Contract(businessID: business.id, title: "Agreement")
        contract.statusRaw = ContractStatus.draft.rawValue
        context.insert(contract)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testSignedContractIsNotAwaitingSignature() throws {
        let business = try makeBusiness()
        let contract = Contract(businessID: business.id, title: "Agreement")
        contract.statusRaw = ContractStatus.signed.rawValue
        context.insert(contract)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    // MARK: - Pending bookings

    func testPendingBookingsProduceOneSummaryItem() throws {
        let business = try makeBusiness()
        let result = items(for: business.id, pendingApprovalBookingCount: 3)

        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .pendingBookings(count: 3))
        XCTAssertEqual(result[0].severity, .warning)
        XCTAssertTrue(result[0].subtitle.contains("3"))
    }

    func testZeroPendingBookingsProducesNoItem() throws {
        let business = try makeBusiness()
        XCTAssertTrue(items(for: business.id, pendingApprovalBookingCount: 0).isEmpty)
    }

    // MARK: - Recurring invoices ready for review

    func testUnreviewedRecurringGeneratedInvoiceProducesOneSummaryItem() throws {
        let business = try makeBusiness()
        let client = Client(businessID: business.id, name: "Ada Lovelace")
        context.insert(client)
        let invoice = Invoice(
            businessID: business.id, invoiceNumber: "SI-2026-001",
            isPaid: false, isRecurringGenerated: true,
            client: client, items: [LineItem(itemDescription: "Retainer", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        let result = items(for: business.id)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .recurringInvoicesReady(count: 1))
        XCTAssertEqual(result[0].severity, .warning)
    }

    func testAReviewedRecurringInvoiceProducesNoItem() throws {
        let business = try makeBusiness()
        let client = Client(businessID: business.id, name: "Ada Lovelace")
        context.insert(client)
        let invoice = Invoice(
            businessID: business.id, invoiceNumber: "SI-2026-001",
            isPaid: false, isRecurringGenerated: true, recurringReviewedAt: .now,
            client: client, items: [LineItem(itemDescription: "Retainer", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testAnOrdinaryInvoiceIsNotMistakenForARecurringOne() throws {
        // Guards the exact bug the isRecurringGenerated flag exists to avoid:
        // every ordinary invoice also has recurringReviewedAt == nil, since
        // that field is never touched outside the recurring flow.
        let business = try makeBusiness()
        let client = Client(businessID: business.id, name: "Ada Lovelace")
        context.insert(client)
        let invoice = Invoice(
            businessID: business.id, invoiceNumber: "SI-2026-001",
            isPaid: false,
            client: client, items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(invoice)
        try context.save()

        XCTAssertTrue(items(for: business.id).isEmpty)
    }

    func testMultipleUnreviewedRecurringInvoicesAreBundledIntoOneCard() throws {
        let business = try makeBusiness()
        let client = Client(businessID: business.id, name: "Ada Lovelace")
        context.insert(client)
        for i in 0..<3 {
            let invoice = Invoice(
                businessID: business.id, invoiceNumber: "SI-2026-00\(i)",
                isPaid: false, isRecurringGenerated: true,
                client: client, items: [LineItem(itemDescription: "Retainer", quantity: 1, unitPrice: 100)]
            )
            context.insert(invoice)
        }
        try context.save()

        let result = items(for: business.id)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .recurringInvoicesReady(count: 3))
    }

    // MARK: - Setup step

    func testIncompleteChecklistAddsSetupCard() throws {
        let business = try makeBusiness()
        let checklist = QuickStartChecklist(completed: [])

        let result = items(for: business.id, checklist: checklist)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].kind, .setupStep(.addClient))
        XCTAssertEqual(result[0].severity, .info)
    }

    func testCompleteChecklistAddsNoSetupCard() throws {
        let business = try makeBusiness()
        XCTAssertTrue(items(for: business.id, checklist: emptyChecklist()).isEmpty)
    }

    // MARK: - Ranking across kinds

    func testCriticalBeatsWarningBeatsInfo() throws {
        let business = try makeBusiness()

        let overdueInvoice = Invoice(
            businessID: business.id, invoiceNumber: "INV-1",
            dueDate: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
            isPaid: false, items: [LineItem(itemDescription: "Work", quantity: 1, unitPrice: 100)]
        )
        context.insert(overdueInvoice)

        let contract = Contract(businessID: business.id, title: "Agreement")
        contract.statusRaw = ContractStatus.sent.rawValue
        context.insert(contract)
        try context.save()

        let result = items(
            for: business.id,
            checklist: QuickStartChecklist(completed: []),
            pendingApprovalBookingCount: 1
        )

        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(result[0].severity, .critical)
        XCTAssertEqual(result[1].severity, .warning)
        XCTAssertEqual(result[2].severity, .warning)
        XCTAssertEqual(result[3].severity, .info)
    }
}
