import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Today's Needs You: only what's real, most urgent first. Overdue means
/// sent and unpaid past the due date; contracts show once they've been out
/// 4 days; recurring invoices that went out are named as such; setup steps
/// aren't here at all (the Business sheet has them).
@MainActor
final class AttentionFeedServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()
    private let day: TimeInterval = 86_400

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func items(_ remote: TodayRemoteState = TodayRemoteState()) -> [AttentionItem] {
        AttentionFeedService.attentionItems(businessID: businessID, context: context, remote: remote)
    }

    @discardableResult
    private func invoice(_ total: Double, sent: Bool = true, dueInDays: Double) throws -> Invoice {
        let client = Client(businessID: businessID, name: "Maria Reyes", email: "m@example.com")
        context.insert(client)
        let invoice = Invoice(businessID: businessID, invoiceNumber: "SI-2026-014", client: client)
        context.insert(invoice)
        let item = LineItem(itemDescription: "Work", quantity: 1, unitPrice: total)
        item.invoice = invoice
        invoice.items = [item]
        context.insert(item)
        if sent { invoice.sentAt = .now.addingTimeInterval(-20 * day) }
        invoice.dueDate = .now.addingTimeInterval(dueInDays * day)
        try context.save()
        return invoice
    }

    private func booking(_ name: String, start: String) -> BookingRequestItem {
        BookingRequestItem(
            requestId: UUID().uuidString, businessId: businessID.uuidString, slug: "dunn", clientName: name,
            clientEmail: "b@example.com", clientPhone: nil, requestedStart: start, requestedEnd: nil,
            serviceType: "Mowing", notes: nil, status: "pending",
            createdAtMs: 1_790_000_000_000, bookingTotalAmountCents: nil,
            depositAmountCents: nil, depositInvoiceId: nil, depositPaidAtMs: nil, finalInvoiceId: nil
        )
    }

    func testNoBusinessMeansNothing() {
        XCTAssertTrue(AttentionFeedService.attentionItems(businessID: nil, context: context, remote: .init()).isEmpty)
    }

    // MARK: Overdue

    func testAnUnsentDraftIsNeverOverdue() throws {
        try invoice(300, sent: false, dueInDays: -10)
        XCTAssertTrue(items().isEmpty)
    }

    func testOverdueShowsWhatsStillDueWithARemindButton() throws {
        let inv = try invoice(450, dueInDays: -12)
        _ = try InvoicePaymentService.record(on: inv, amountCents: 20_000, paidAt: .now, method: "check", context: context)
        let item = try XCTUnwrap(items().first)
        XCTAssertEqual(item.severity, .critical)
        XCTAssertEqual(item.action, .remind)
        XCTAssertEqual(item.title, "Maria Reyes is 12 days late")
        XCTAssertTrue(item.subtitle.contains("$250.00"), item.subtitle)
    }

    func testDueTodayIsNotLateYet() throws {
        try invoice(100, dueInDays: 0)
        XCTAssertTrue(items().isEmpty)
    }

    // MARK: Bookings and payments

    func testOneBookingRequestNamesTheClient() {
        let feed = items(TodayRemoteState(pendingBookings: [booking("Test Four", start: "2099-10-01T14:00:00Z")]))
        XCTAssertEqual(feed.first?.title, "Test Four wants to book")
        XCTAssertEqual(feed.first?.action, .answer)
    }

    func testSeveralBookingRequestsAreOneRowStartingWithTheSoonest() {
        let feed = items(TodayRemoteState(pendingBookings: [
            booking("Later", start: "2099-10-09T14:00:00Z"),
            booking("Sooner", start: "2099-10-01T14:00:00Z"),
        ]))
        XCTAssertEqual(feed.count, 1)
        XCTAssertEqual(feed.first?.title, "2 booking requests")
        if case .bookingRequests(let count, let first) = feed.first?.kind {
            XCTAssertEqual(count, 2)
            XCTAssertNil(first, "several open the Bookings list")
        } else { XCTFail() }
    }

    func testAReportedPaymentAsksToConfirm() throws {
        let inv = try invoice(1_200, dueInDays: 5)
        let report = ManualPaymentReportDTO(
            id: "r1", businessId: businessID.uuidString, invoiceId: inv.id.uuidString, method: "venmo",
            amountCents: 120_000, payerName: "Dunn", payerEmail: nil, reference: nil, status: "pending",
            createdAtMs: 1, resolvedAtMs: nil
        )
        let feed = items(TodayRemoteState(manualReports: [report]))
        XCTAssertEqual(feed.first?.title, "Dunn says they paid by Venmo")
        XCTAssertEqual(feed.first?.action, .confirm)
    }

    // MARK: Jobs

    func testAFinishedJobWithNoInvoiceAsksToBill() throws {
        let job = Job(businessID: businessID, title: "Fence repair", startDate: .now.addingTimeInterval(-day), endDate: .now)
        context.insert(job)
        JobLifecycle.complete(job)
        try context.save()
        XCTAssertEqual(items().first?.action, .bill)
        XCTAssertEqual(items().first?.title, "Fence repair is done")
    }

    func testAJobWaitingForADateAsksToSchedule() throws {
        let job = Job(businessID: businessID, title: "Deck", startDate: .now, endDate: .now)
        job.needsScheduling = true
        context.insert(job)
        try context.save()
        XCTAssertEqual(items().first?.action, .schedule)
    }

    // MARK: Contracts

    func testAContractShowsOnlyAfterFourDays() throws {
        let contract = Contract(businessID: businessID, title: "Deck agreement", statusRaw: ContractStatus.sent.rawValue)
        contract.sentAt = .now.addingTimeInterval(-2 * day)
        context.insert(contract)
        try context.save()
        XCTAssertTrue(items().isEmpty, "sent 2 days ago isn't something to do yet")

        contract.sentAt = .now.addingTimeInterval(-5 * day)
        XCTAssertEqual(items().first?.action, .remindContract)

        contract.lastReminderAt = .now.addingTimeInterval(-1 * day)
        XCTAssertTrue(items().isEmpty, "a reminder restarts the clock")
    }

    // MARK: Recurring

    func testRecurringInvoicesThatWentOutSayWhatHappened() throws {
        let inv = try invoice(80, dueInDays: 10)
        inv.isRecurringGenerated = true
        try context.save()
        let item = try XCTUnwrap(items().first)
        XCTAssertEqual(item.title, "A recurring invoice went out")
        XCTAssertEqual(item.action, .gotIt)
        inv.recurringReviewedAt = .now
        XCTAssertTrue(items().isEmpty)
    }

    // MARK: Ranking

    func testOverdueComesFirst() throws {
        let job = Job(businessID: businessID, title: "Deck", startDate: .now, endDate: .now)
        job.needsScheduling = true
        context.insert(job)
        try invoice(100, dueInDays: -3)
        let feed = items(TodayRemoteState(pendingBookings: [booking("A", start: "2099-10-01T14:00:00Z")]))
        XCTAssertEqual(feed.map(\.action), [.remind, .answer, .schedule])
    }
}
