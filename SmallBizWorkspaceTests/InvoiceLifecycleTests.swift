import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// The invoice lifecycle: part payments and the balance, drafts kept out of
/// the portal, online payments coming in once, and older invoices already in
/// the portal counting as sent.
@MainActor
final class InvoiceLifecycleTests: XCTestCase {

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

    /// A $450 draft invoice (unsent, so recording payments doesn't republish).
    private func makeInvoice(total: Double = 450) throws -> Invoice {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Testing Freeman", email: "client@example.com")
        context.insert(client)
        let invoice = Invoice(businessID: businessID, invoiceNumber: "SI-2026-014", client: client)
        context.insert(invoice)
        let item = LineItem(itemDescription: "Fence repair", quantity: 1, unitPrice: total)
        item.invoice = invoice
        invoice.items = [item]
        context.insert(item)
        try context.save()
        return invoice
    }

    // MARK: - Payments and balance

    func testAPartPaymentLeavesTheRestOwed() throws {
        let invoice = try makeInvoice()

        try InvoicePaymentService.record(on: invoice, amountCents: 20_000, paidAt: .now, method: "check", context: context)

        XCTAssertEqual(invoice.paidCents, 20_000)
        XCTAssertEqual(invoice.balanceDueCents, 25_000)
        XCTAssertFalse(invoice.isPaid)
    }

    func testPayingTheBalanceMarksItPaid() throws {
        let invoice = try makeInvoice()

        try InvoicePaymentService.record(on: invoice, amountCents: 20_000, paidAt: .now, method: "check", context: context)
        try InvoicePaymentService.record(on: invoice, amountCents: 25_000, paidAt: .now, method: "cash", context: context)

        XCTAssertTrue(invoice.isPaid)
        XCTAssertEqual(invoice.balanceDueCents, 0)
    }

    func testRecordingMoreThanIsOwedIsRefused() throws {
        let invoice = try makeInvoice()

        XCTAssertThrowsError(
            try InvoicePaymentService.record(on: invoice, amountCents: 50_000, paidAt: .now, method: "cash", context: context)
        )
        XCTAssertTrue((invoice.payments ?? []).isEmpty)
    }

    func testRemovingAPaymentMakesItOwedAgain() throws {
        let invoice = try makeInvoice()
        let payment = try InvoicePaymentService.record(on: invoice, amountCents: 45_000, paidAt: .now, method: "cash", context: context)
        XCTAssertTrue(invoice.isPaid)

        InvoicePaymentService.remove(payment, from: invoice, context: context)

        XCTAssertFalse(invoice.isPaid)
        XCTAssertEqual(invoice.balanceDueCents, 45_000)
    }

    /// Invoices marked paid before payments existed have no payment rows.
    func testAnInvoiceMarkedPaidTheOldWayOwesNothing() throws {
        let invoice = try makeInvoice()
        invoice.isPaid = true

        XCTAssertEqual(invoice.balanceDueCents, 0)
        XCTAssertEqual(invoice.paidCents, 45_000)
    }

    // MARK: - Sent vs draft

    func testADraftInvoiceStaysOutOfThePortal() throws {
        let invoice = try makeInvoice()

        XCTAssertTrue(invoice.isUnsentDocument)
        XCTAssertFalse(PortalAutoSyncService.isEligible(invoice: invoice))

        invoice.sentAt = .now
        XCTAssertFalse(invoice.isUnsentDocument)
        XCTAssertTrue(PortalAutoSyncService.isEligible(invoice: invoice))
    }

    /// Older builds published invoices on Done; those are already in front
    /// of the client and must not be treated as drafts.
    func testAnInvoiceAnOlderBuildPublishedCountsAsSent() throws {
        let invoice = try makeInvoice()
        invoice.portalLastUploadedAtMs = 1

        XCTAssertTrue(invoice.wasSent)
    }

    func testOverdueOnlyOnceSentAndUnpaid() throws {
        let invoice = try makeInvoice()
        invoice.dueDate = .now.addingTimeInterval(-3 * 86_400)
        XCTAssertFalse(invoice.isOverdue, "a draft isn't overdue")

        invoice.sentAt = .now.addingTimeInterval(-20 * 86_400)
        XCTAssertTrue(invoice.isOverdue)

        invoice.isPaid = true
        XCTAssertFalse(invoice.isOverdue)
    }

    // MARK: - Portal activity

    private func activity(
        for invoice: Invoice,
        paid: Bool = false,
        paidOnlineCents: Int? = nil,
        viewedAtMs: Double? = nil
    ) -> PortalBackend.InvoiceActivityDTO {
        PortalBackend.InvoiceActivityDTO(
            invoiceId: invoice.id.uuidString,
            paid: paid,
            paidAtMs: paid ? 1_790_000_000_000 : nil,
            paidOnlineCents: paidOnlineCents,
            provider: paid ? "stripe" : nil,
            viewedAtMs: viewedAtMs,
            sentAtMs: nil,
            lastReminderAtMs: nil,
            updatedAtMs: 1_790_000_000_000
        )
    }

    func testAnOnlinePaymentIsRecordedOnce() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        let item = activity(for: invoice, paid: true, paidOnlineCents: 45_000)

        InvoiceActivityPullService.apply(item, businessID: invoice.businessID, context: context)
        InvoiceActivityPullService.apply(item, businessID: invoice.businessID, context: context)

        XCTAssertTrue(invoice.isPaid)
        XCTAssertEqual(invoice.payments?.count, 1)
        XCTAssertEqual(invoice.payments?.first?.source, "portal")
        XCTAssertEqual(invoice.payments?.first?.amountCents, 45_000)
    }

    func testAnOnlinePaymentAfterACheckPaysTheRest() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        try InvoicePaymentService.record(on: invoice, amountCents: 20_000, paidAt: .now, method: "check", context: context)

        InvoiceActivityPullService.apply(
            activity(for: invoice, paid: true, paidOnlineCents: 25_000),
            businessID: invoice.businessID,
            context: context
        )

        XCTAssertTrue(invoice.isPaid)
        XCTAssertEqual(invoice.paidCents, 45_000)
    }

    func testAViewIsRecorded() throws {
        let invoice = try makeInvoice()

        InvoiceActivityPullService.apply(
            activity(for: invoice, viewedAtMs: 1_790_000_000_000),
            businessID: invoice.businessID,
            context: context
        )

        XCTAssertNotNil(invoice.viewedAt)
        XCTAssertFalse(invoice.isPaid)
    }

    func testAnotherBusinesssActivityIsIgnored() throws {
        let invoice = try makeInvoice()

        InvoiceActivityPullService.apply(
            activity(for: invoice, paid: true, paidOnlineCents: 45_000),
            businessID: UUID(),
            context: context
        )

        XCTAssertFalse(invoice.isPaid)
    }
}
