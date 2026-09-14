import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers the schedule model's computed bridges and totals, the cadence
/// advancement math (which must match the backend's `advanceNextRun`
/// exactly — see recurringSchedules.ts), and the pull service's
/// materialization: idempotent by invoiceId, and correctly populating a
/// real local Invoice from a hand-built DTO (no network mocking needed —
/// see `RecurringInvoicePullService.materialize`'s doc comment for why it's
/// `internal`, not `private`).
///
/// Container is held in a property for the test's lifetime — see
/// `QuickStartQueryTests` for why a container built and discarded in the same
/// expression traps on save.
@MainActor
final class RecurringInvoiceScheduleTests: XCTestCase {

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

    // MARK: - cadence bridge

    func testCadenceDefaultsToMonthlyWhenRawIsUnrecognized() {
        let schedule = RecurringInvoiceSchedule(businessID: UUID(), clientID: UUID())
        schedule.cadenceRaw = "yearly-ish-nonsense"
        XCTAssertEqual(schedule.cadence, .monthly)
    }

    func testSettingCadenceUpdatesTheRawValue() {
        let schedule = RecurringInvoiceSchedule(businessID: UUID(), clientID: UUID())
        schedule.cadence = .weekly
        XCTAssertEqual(schedule.cadenceRaw, "weekly")
    }

    // MARK: - cadence advancement (must match the backend's math)

    func testWeeklyAdvancesBySevenDays() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let next = RecurringCadence.weekly.advancing(from: start, calendar: calendar)
        let days = calendar.dateComponents([.day], from: start, to: next).day
        XCTAssertEqual(days, 7)
    }

    func testBiweeklyAdvancesByFourteenDays() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let next = RecurringCadence.biweekly.advancing(from: start, calendar: calendar)
        let days = calendar.dateComponents([.day], from: start, to: next).day
        XCTAssertEqual(days, 14)
    }

    func testMonthlyAdvancesByOneCalendarMonth() {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let next = RecurringCadence.monthly.advancing(from: start, calendar: calendar)
        let components = calendar.dateComponents([.year, .month], from: next)
        XCTAssertEqual(components.month, 2)
    }

    // MARK: - lineItems JSON bridge

    func testLineItemsRoundTripThroughJSON() {
        let schedule = RecurringInvoiceSchedule(businessID: UUID(), clientID: UUID())
        let items = [
            RecurringScheduleLineItem(itemDescription: "Lawn care", quantity: 1, unitPrice: 75),
            RecurringScheduleLineItem(itemDescription: "Trimming", quantity: 2, unitPrice: 20)
        ]
        schedule.lineItems = items

        XCTAssertEqual(schedule.lineItems.count, 2)
        XCTAssertEqual(schedule.lineItems[0].itemDescription, "Lawn care")
        XCTAssertEqual(schedule.lineItems[1].unitPrice, 20)
    }

    func testEmptyLineItemsDataDecodesToEmptyArray() {
        let schedule = RecurringInvoiceSchedule(businessID: UUID(), clientID: UUID())
        XCTAssertEqual(schedule.lineItems, [])
    }

    // MARK: - totals

    func testTotalsComputeSubtotalDiscountTaxAndTotal() {
        let schedule = RecurringInvoiceSchedule(businessID: UUID(), clientID: UUID())
        schedule.lineItems = [
            RecurringScheduleLineItem(itemDescription: "Item A", quantity: 2, unitPrice: 50), // 100
            RecurringScheduleLineItem(itemDescription: "Item B", quantity: 1, unitPrice: 25)   // 25
        ]
        schedule.discountAmount = 10
        schedule.taxRatePercent = 10 // 10%

        XCTAssertEqual(schedule.subtotal, 125, accuracy: 0.001)
        XCTAssertEqual(schedule.discountedSubtotal, 115, accuracy: 0.001)
        XCTAssertEqual(schedule.taxAmount, 11.5, accuracy: 0.001)
        XCTAssertEqual(schedule.total, 126.5, accuracy: 0.001)
    }

    func testDiscountLargerThanSubtotalClampsToZeroNotNegative() {
        let schedule = RecurringInvoiceSchedule(businessID: UUID(), clientID: UUID())
        schedule.lineItems = [RecurringScheduleLineItem(itemDescription: "Item", quantity: 1, unitPrice: 10)]
        schedule.discountAmount = 500

        XCTAssertEqual(schedule.discountedSubtotal, 0)
        XCTAssertEqual(schedule.total, 0)
    }

    // MARK: - BusinessOwned scoping

    func testScopedToFiltersByBusinessID() throws {
        let mine = UUID()
        let theirs = UUID()
        let mineSchedule = RecurringInvoiceSchedule(businessID: mine, clientID: UUID())
        let theirsSchedule = RecurringInvoiceSchedule(businessID: theirs, clientID: UUID())
        context.insert(mineSchedule)
        context.insert(theirsSchedule)
        try context.save()

        let all = try context.fetch(FetchDescriptor<RecurringInvoiceSchedule>())
        let scoped = all.scoped(to: mine)

        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(scoped.first?.businessID, mine)
    }

    // MARK: - materialization

    private func makeClient(businessID: UUID, name: String = "Ada Lovelace") throws -> Client {
        let client = Client(businessID: businessID, name: name, email: "ada@example.com")
        context.insert(client)
        try context.save()
        return client
    }

    private func makeDTO(
        invoiceId: String = UUID().uuidString,
        clientId: String,
        taxRate: Double = 0.08,
        discountAmountCents: Int = 500
    ) -> GeneratedRecurringInvoiceDTO {
        GeneratedRecurringInvoiceDTO(
            invoiceId: invoiceId,
            invoiceNumber: "REC-20260301-AB12",
            clientId: clientId,
            amountCents: 10800,
            taxCents: 800,
            discountAmountCents: discountAmountCents,
            taxRate: taxRate,
            currency: "usd",
            dueAtMs: (Date().timeIntervalSince1970 + 14 * 86400) * 1000,
            updatedAtMs: Date().timeIntervalSince1970 * 1000,
            lineItems: [
                GeneratedLineItemDTO(description: "Monthly retainer", quantity: 1, unitPrice: 100)
            ]
        )
    }

    func testMaterializeCreatesALocalInvoiceMatchingTheGeneratedId() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let invoiceUUID = UUID()
        let dto = makeDTO(invoiceId: invoiceUUID.uuidString, clientId: client.id.uuidString)

        let created = RecurringInvoicePullService.materialize(dto, businessID: businessID, context: context)
        try context.save()

        XCTAssertTrue(created)
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        XCTAssertEqual(invoices.count, 1)
        let invoice = invoices[0]
        XCTAssertEqual(invoice.id, invoiceUUID)
        XCTAssertEqual(invoice.businessID, businessID)
        XCTAssertEqual(invoice.client?.id, client.id)
        XCTAssertTrue(invoice.isRecurringGenerated)
        XCTAssertNil(invoice.recurringReviewedAt)
        XCTAssertFalse(invoice.isPaid)
        XCTAssertEqual(invoice.items?.count, 1)
        XCTAssertEqual(invoice.items?.first?.itemDescription, "Monthly retainer")
        XCTAssertEqual(invoice.discountAmount, 5, accuracy: 0.001) // 500 cents
        XCTAssertEqual(invoice.taxRate, 0.08, accuracy: 0.001)
    }

    func testMaterializeIsIdempotentForTheSameInvoiceId() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let invoiceUUID = UUID()
        let dto = makeDTO(invoiceId: invoiceUUID.uuidString, clientId: client.id.uuidString)

        let firstResult = RecurringInvoicePullService.materialize(dto, businessID: businessID, context: context)
        try context.save()
        let secondResult = RecurringInvoicePullService.materialize(dto, businessID: businessID, context: context)
        try context.save()

        XCTAssertTrue(firstResult)
        XCTAssertFalse(secondResult, "a repeat materialize of the same invoiceId must be a no-op")
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        XCTAssertEqual(invoices.count, 1, "must never produce a duplicate local Invoice")
    }

    func testMaterializeSkipsAnUnknownClient() throws {
        let businessID = UUID()
        let dto = makeDTO(clientId: UUID().uuidString) // no such client exists

        let created = RecurringInvoicePullService.materialize(dto, businessID: businessID, context: context)

        XCTAssertFalse(created)
        let invoices = try context.fetch(FetchDescriptor<Invoice>())
        XCTAssertTrue(invoices.isEmpty)
    }

    func testMaterializeSkipsAMalformedInvoiceId() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let dto = makeDTO(invoiceId: "not-a-uuid", clientId: client.id.uuidString)

        let created = RecurringInvoicePullService.materialize(dto, businessID: businessID, context: context)

        XCTAssertFalse(created)
    }

    func testMaterializeMintsARealSequentialInvoiceNumberNotThePlaceholder() throws {
        let businessID = UUID()
        let client = try makeClient(businessID: businessID)
        let profile = BusinessProfile(businessID: businessID, invoicePrefix: "SI")
        context.insert(profile)
        try context.save()

        let dto = makeDTO(clientId: client.id.uuidString)
        RecurringInvoicePullService.materialize(dto, businessID: businessID, context: context)
        try context.save()

        let invoice = try context.fetch(FetchDescriptor<Invoice>()).first
        XCTAssertNotEqual(invoice?.invoiceNumber, "REC-20260301-AB12", "the server placeholder must be replaced by a real number")
        XCTAssertTrue(invoice?.invoiceNumber.hasPrefix("SI-") ?? false)
    }
}
