import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Bookings on the device: one set of status names, and the client and job
/// a confirmed booking gets — once, never from merely opening a list.
@MainActor
final class BookingLifecycleTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()
    private var requestIDs: [String] = []

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        for id in requestIDs { UserDefaults.standard.removeObject(forKey: "sbw.booking.jobMade.\(id)") }
        container = nil
        try super.tearDownWithError()
    }

    private func booking(
        status: String = "approved",
        email: String = "maria@example.com",
        phone: String = "(555) 010-0199",
        name: String = "Maria Reyes",
        start: String = "2099-10-04T18:00:00.000Z",
        end: String = "2099-10-04T19:00:00Z",
        total: Int? = 30000,
        deposit: Int? = nil,
        depositPaidAtMs: Int? = nil
    ) -> BookingRequestItem {
        let id = UUID().uuidString
        requestIDs.append(id)
        return BookingRequestItem(
            requestId: id, businessId: businessID.uuidString, slug: "dunn", clientName: name,
            clientEmail: email, clientPhone: phone, requestedStart: start, requestedEnd: end,
            serviceType: "Portrait session", notes: "Outdoors if nice", status: status,
            createdAtMs: 1_790_000_000_000, bookingTotalAmountCents: total,
            depositAmountCents: deposit, depositInvoiceId: nil, depositPaidAtMs: depositPaidAtMs, finalInvoiceId: nil
        )
    }

    private func jobs() throws -> [Job] { try context.fetch(FetchDescriptor<Job>()) }
    private func clients() throws -> [Client] { try context.fetch(FetchDescriptor<Client>()) }

    // MARK: - Names and times

    func testStatusNamesAreTheSameEverywhere() {
        XCTAssertEqual(booking(status: "pending").stage.label, "New")
        XCTAssertEqual(booking(status: "deposit_requested").stage.label, "Deposit")
        XCTAssertEqual(booking(status: "approved").stage.label, "Confirmed")
        XCTAssertEqual(booking(status: "deposit_paid").stage, .confirmed, "the legacy value reads as confirmed")
        XCTAssertEqual(booking(status: "declined").stage.label, "Declined")
        XCTAssertEqual(booking(status: "cancelled").stage.label, "Canceled")
    }

    func testTimesParseWithOrWithoutFractionalSeconds() {
        let item = booking()
        XCTAssertNotNil(item.start)
        XCTAssertNotNil(item.end)
        XCTAssertEqual(item.end!.timeIntervalSince(item.start!), 3600)
        XCTAssertFalse(item.isPast())
        XCTAssertTrue(booking(start: "2020-01-01T10:00:00Z", end: "2020-01-01T11:00:00Z").isPast())
    }

    func testTheServerRecordCarriesEveryField() throws {
        let json = """
        {"requestId":"r1","businessId":"\(businessID.uuidString)","status":"deposit_requested",
         "clientName":"Dan","depositAmountCents":5000,"depositRequestedAtMs":1790000000000,
         "depositWaivedAtMs":0,"cancelledAtMs":1790000001000,"approvedAtMs":1790000002000}
        """
        let dto = try JSONDecoder().decode(BookingRequestDTO.self, from: Data(json.utf8))
        let item = BookingRequestItem(dto: dto)
        XCTAssertEqual(item.stage, .awaitingDeposit)
        XCTAssertEqual(item.depositRequestedAtMs, 1_790_000_000_000)
        XCTAssertEqual(item.cancelledAtMs, 1_790_000_001_000)
        XCTAssertEqual(item.approvedAtMs, 1_790_000_002_000)
    }

    // MARK: - Client and job, once

    func testConfirmingMakesOneClientAndOneJob() async throws {
        let item = booking()

        let first = await BookingWorkSetup.ensureJob(for: item, businessID: businessID, context: context, addToCalendar: false)
        let second = await BookingWorkSetup.ensureJob(for: item, businessID: businessID, context: context, addToCalendar: false)

        XCTAssertNotNil(first)
        XCTAssertEqual(first?.id, second?.id)
        XCTAssertEqual(try jobs().count, 1)
        XCTAssertEqual(try clients().count, 1)
        let job = try XCTUnwrap(first)
        XCTAssertEqual(job.sourceBookingRequestId, item.requestId)
        XCTAssertEqual(job.startDate, item.start)
        XCTAssertEqual(job.quotedTotalCents, 30000)
        XCTAssertEqual(job.stage, .booked)
    }

    func testANewRequestGetsNothing() async throws {
        let made = await BookingWorkSetup.ensureJob(for: booking(status: "pending"), businessID: businessID, context: context, addToCalendar: false)
        XCTAssertNil(made)
        XCTAssertTrue(try jobs().isEmpty)
        XCTAssertTrue(try clients().isEmpty)
    }

    func testADeletedJobIsNotRecreated() async throws {
        let item = booking()
        let made = await BookingWorkSetup.ensureJob(for: item, businessID: businessID, context: context, addToCalendar: false)
        let job = try XCTUnwrap(made)
        context.delete(job)
        try context.save()

        let again = await BookingWorkSetup.ensureJob(for: item, businessID: businessID, context: context, addToCalendar: false)

        XCTAssertNil(again, "the old list brought deleted jobs back on every load")
        XCTAssertTrue(try jobs().isEmpty)
    }

    func testAnExistingClientIsMatchedByEmailOrPhone() async throws {
        let existing = Client(businessID: businessID, name: "M. Reyes", email: "MARIA@example.com")
        context.insert(existing)
        let byPhone = Client(businessID: businessID, name: "Someone", phone: "555-010-0200")
        context.insert(byPhone)
        try context.save()

        let job = await BookingWorkSetup.ensureJob(for: booking(), businessID: businessID, context: context, addToCalendar: false)
        XCTAssertEqual(job?.clientID, existing.id)

        let phoneJob = await BookingWorkSetup.ensureJob(
            for: booking(email: "", phone: "+1 555 010 0200", name: "Other"),
            businessID: businessID, context: context, addToCalendar: false
        )
        XCTAssertEqual(phoneJob?.clientID, byPhone.id)
        XCTAssertEqual(try clients().count, 2)
    }

    func testTheSameNameAloneIsNotTheSameClient() async throws {
        let namesake = Client(businessID: businessID, name: "Maria Reyes", email: "other@example.com")
        context.insert(namesake)
        try context.save()

        let job = await BookingWorkSetup.ensureJob(for: booking(), businessID: businessID, context: context, addToCalendar: false)

        XCTAssertNotEqual(job?.clientID, namesake.id)
        XCTAssertEqual(try clients().count, 2)
    }

    // MARK: - Billing

    func testTheJobInvoiceIsThePriceLessThePaidDeposit() async throws {
        let item = booking(deposit: 5000, depositPaidAtMs: 1_790_000_000_000)
        let made = await BookingWorkSetup.ensureJob(for: item, businessID: businessID, context: context, addToCalendar: false)
        let job = try XCTUnwrap(made)

        let invoice = try JobInvoiceBuilder.makeInvoice(for: job, client: nil, profile: nil, context: context)

        XCTAssertEqual(invoice.totalCents, 25000, "$300 price less the $50 deposit; the old flow made a $0 invoice")
        XCTAssertEqual(invoice.items?.count, 2)
    }

    func testAnUnpaidBookingDepositIsNotCountedAsPaid() {
        let invoice = Invoice(businessID: businessID, invoiceNumber: "INV-1")
        let item = LineItem(itemDescription: "Work", quantity: 1, unitPrice: 300)
        item.invoice = invoice
        invoice.items = [item]
        invoice.sourceBookingDepositAmountCents = 5000

        XCTAssertEqual(invoice.paidCents, 0)
        invoice.sourceBookingDepositPaidAtMs = 1_790_000_000_000
        XCTAssertEqual(invoice.paidCents, 5000)
    }

    // Calendar access can be refused; the notice mustn't claim an event.
    func testTheNoticeOnlyMentionsTheCalendarWhenTheJobIsOnIt() {
        let job = Job(businessID: businessID, title: "Mow", startDate: .now, endDate: .now)
        XCTAssertEqual(BookingDetailView.jobNote(nil, calendar: "is on your calendar"), "")
        XCTAssertEqual(BookingDetailView.jobNote(job, calendar: "is on your calendar"), ", and the job is set up")
        job.calendarEventId = "EVT-1"
        XCTAssertEqual(BookingDetailView.jobNote(job, calendar: "is on your calendar"), ", and the job is on your calendar")
    }

    func testTheTimeRangeStaysTogetherWhenItWraps() {
        let item = booking()
        XCTAssertTrue(item.whenText.contains("\u{2060}–\u{2060}"))
    }
}
