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

    // MARK: - Payment links (deposits)

    private func ledgerActivity(
        for invoice: Invoice,
        paid: Bool = false,
        payments: [(id: String, cents: Int)]
    ) -> PortalBackend.InvoiceActivityDTO {
        PortalBackend.InvoiceActivityDTO(
            invoiceId: invoice.id.uuidString,
            paid: paid,
            paidAtMs: paid ? 1_790_000_000_000 : nil,
            paidOnlineCents: nil,
            provider: paid ? "stripe" : nil,
            viewedAtMs: nil,
            sentAtMs: nil,
            lastReminderAtMs: nil,
            updatedAtMs: 1_790_000_000_000,
            payments: payments.map {
                PortalBackend.InvoiceActivityPaymentDTO(
                    id: $0.id,
                    amountCents: $0.cents,
                    provider: "stripe",
                    paidAtMs: 1_790_000_000_000,
                    paymentRequestId: "req-1"
                )
            }
        )
    }

    func testADepositPaidOnlineLeavesTheRestOwed() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        let item = ledgerActivity(for: invoice, payments: [("pi_dep", 15_000)])

        InvoiceActivityPullService.apply(item, businessID: invoice.businessID, context: context)
        InvoiceActivityPullService.apply(item, businessID: invoice.businessID, context: context)

        XCTAssertFalse(invoice.isPaid)
        XCTAssertEqual(invoice.payments?.count, 1, "the same ledger payment pulled twice is one payment")
        XCTAssertEqual(invoice.payments?.first?.externalId, "pi_dep")
        XCTAssertEqual(invoice.balanceDueCents, 30_000)
    }

    func testATipIsRecordedButDoesntPayDownTheInvoice() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        var item = ledgerActivity(for: invoice, paid: true, payments: [("pi_tip", 45_000)])
        item.payments?[0].tipCents = 9_000

        InvoiceActivityPullService.apply(item, businessID: invoice.businessID, context: context)

        XCTAssertTrue(invoice.isPaid)
        XCTAssertEqual(invoice.paidCents, 45_000)
        XCTAssertEqual(invoice.balanceDueCents, 0)
        XCTAssertEqual(invoice.payments?.first?.tipCents, 9_000)
        XCTAssertEqual(invoice.tipsReceivedCents, 9_000)
        let received = MoneyMath.received(invoices: [invoice], jobs: [])
        XCTAssertEqual(received.reduce(0) { $0 + $1.amountCents }, 54_000, "a tip is money in")
    }

    func testTheLastLedgerPaymentPaysItOff() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        InvoiceActivityPullService.apply(
            ledgerActivity(for: invoice, payments: [("pi_dep", 15_000)]),
            businessID: invoice.businessID,
            context: context
        )

        InvoiceActivityPullService.apply(
            ledgerActivity(for: invoice, paid: true, payments: [("pi_dep", 15_000), ("pi_rest", 30_000)]),
            businessID: invoice.businessID,
            context: context
        )

        XCTAssertTrue(invoice.isPaid)
        XCTAssertEqual(invoice.payments?.count, 2)
        XCTAssertEqual(invoice.paidCents, 45_000)
    }

    /// A device on an older build records an online payment without the
    /// ledger id; the newer device must not count it again.
    func testALedgerPaymentClaimsTheOldStyleRecordOfIt() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        try InvoicePaymentService.record(
            on: invoice, amountCents: 15_000, paidAt: .now, method: "stripe", source: "portal", context: context
        )

        InvoiceActivityPullService.apply(
            ledgerActivity(for: invoice, payments: [("pi_dep", 15_000)]),
            businessID: invoice.businessID,
            context: context
        )

        XCTAssertEqual(invoice.payments?.count, 1)
        XCTAssertEqual(invoice.payments?.first?.externalId, "pi_dep")
    }

    /// What the server adds its own ledger to: a check counts, an online
    /// payment it reported does not (it already has that one).
    func testOfflinePaidLeavesOutLedgerPayments() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        try InvoicePaymentService.record(on: invoice, amountCents: 10_000, paidAt: .now, method: "check", context: context)
        InvoiceActivityPullService.apply(
            ledgerActivity(for: invoice, payments: [("pi_dep", 15_000)]),
            businessID: invoice.businessID,
            context: context
        )

        XCTAssertEqual(invoice.paidCents, 25_000)
        XCTAssertEqual(invoice.offlinePaidCents, 10_000)
        XCTAssertEqual(PortalBackend.invoiceBalanceFields(invoice)["offlinePaidCents"] as? Int, 10_000)
    }

    func testAnInvoiceMarkedPaidTheOldWayIsAllOffline() throws {
        let invoice = try makeInvoice()
        invoice.isPaid = true

        XCTAssertEqual(invoice.offlinePaidCents, 45_000)
    }

    func testAPaymentLinkAsksForNoMoreThanIsOwed() throws {
        let invoice = try makeInvoice()

        XCTAssertNoThrow(try PaymentRequestService.validate(invoice, amountCents: 15_000))
        XCTAssertNoThrow(try PaymentRequestService.validate(invoice, amountCents: 45_000))
        XCTAssertThrowsError(try PaymentRequestService.validate(invoice, amountCents: 45_001))
        XCTAssertThrowsError(try PaymentRequestService.validate(invoice, amountCents: 0))

        invoice.isPaid = true
        XCTAssertThrowsError(try PaymentRequestService.validate(invoice, amountCents: 100))
    }

    func testAPaymentLinkNeedsAClientWithThePortalOn() throws {
        let invoice = try makeInvoice()
        invoice.client?.portalEnabled = false
        XCTAssertThrowsError(try PaymentRequestService.validate(invoice, amountCents: 100))

        invoice.client = nil
        XCTAssertThrowsError(try PaymentRequestService.validate(invoice, amountCents: 100))
    }

    func testThePaymentLinkMessageNamesTheAmountAndInvoice() throws {
        let invoice = try makeInvoice()
        let url = URL(string: "https://portal.example.test/portal/invoice/x?t=abc")!

        let message = PaymentRequestService.shareMessage(
            for: invoice, amountCents: 15_000, label: "Deposit", businessName: "Freeman DJ", url: url
        )

        XCTAssertTrue(message.contains("deposit for invoice SI-2026-014 from Freeman DJ"), message)
        XCTAssertTrue(message.contains(url.absoluteString))
    }

    // MARK: - Tap to Pay on iPhone

    /// What TapToPayReader records after an approved tap.
    @discardableResult
    private func recordTap(on invoice: Invoice, id: String, cents: Int, tip: Int = 0) throws -> InvoicePayment {
        try InvoicePaymentService.record(
            on: invoice, amountCents: cents, paidAt: .now, method: "card", note: "Tap to Pay on iPhone",
            source: "tap_to_pay", externalId: id, tipCents: tip, context: context
        )
    }

    func testATapToPayDepositLeavesTheRestOwed() throws {
        let invoice = try makeInvoice()
        try recordTap(on: invoice, id: "pi_tap1", cents: 15_000)

        XCTAssertEqual(invoice.balanceDueCents, 30_000)
        XCTAssertEqual(invoice.offlinePaidCents, 0, "the server's ledger holds it, so it isn't offline")
    }

    func testATapToPayPaymentPulledBackFromTheLedgerIsRecordedOnce() throws {
        let invoice = try makeInvoice()
        invoice.sentAt = .now
        try recordTap(on: invoice, id: "pi_tap2", cents: 45_000, tip: 6_750)

        InvoiceActivityPullService.apply(
            ledgerActivity(for: invoice, paid: true, payments: [("pi_tap2", 45_000)]),
            businessID: invoice.businessID,
            context: context
        )

        XCTAssertEqual(invoice.payments?.count, 1, "the tap and its ledger entry are one payment")
        XCTAssertTrue(invoice.isPaid)
        XCTAssertEqual(invoice.tipsReceivedCents, 6_750)
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

/// Tap to Pay on iPhone's own rules: the address Stripe needs, tips, receipts.
final class TapToPayModelTests: XCTestCase {
    func testTheProfileAddressSplitsIntoStripesParts() {
        XCTAssertEqual(
            TapToPayAddress.parse("1 Main St, Columbia, SC 29201"),
            TapToPayAddress(line1: "1 Main St", city: "Columbia", state: "SC", postalCode: "29201")
        )
        XCTAssertEqual(
            TapToPayAddress.parse("1 Main St\nSuite 4\nColumbia, South Carolina 29201-1234\nUSA"),
            TapToPayAddress(line1: "1 Main St", line2: "Suite 4", city: "Columbia", state: "SC", postalCode: "29201-1234")
        )
        XCTAssertEqual(TapToPayAddress.parse("1 Main St, Columbia, sc, 29201")?.state, "SC")
    }

    func testAnAddressThatIsntAFullOneIsLeftForTheOwner() {
        XCTAssertNil(TapToPayAddress.parse(""))
        XCTAssertNil(TapToPayAddress.parse("Columbia, SC 29201"), "no street")
        XCTAssertNil(TapToPayAddress.parse("1 Main St, Columbia"), "no state or ZIP")
        XCTAssertNil(TapToPayAddress.parse("1 Main St, Columbia, Nowhere 29201"), "not a state")
        XCTAssertFalse(TapToPayAddress(line1: "1 Main St", city: "Columbia", state: "SC").isComplete)
    }

    func testTipsOnlyOnThePaymentThatSettlesTheInvoice() {
        XCTAssertTrue(TapToPayCharge.allowsTip(amountCents: 40_000, balanceDueCents: 40_000, tipsEnabled: true))
        XCTAssertFalse(TapToPayCharge.allowsTip(amountCents: 10_000, balanceDueCents: 40_000, tipsEnabled: true), "a deposit")
        XCTAssertFalse(TapToPayCharge.allowsTip(amountCents: 40_000, balanceDueCents: 40_000, tipsEnabled: false))
        XCTAssertEqual(TapToPayCharge.tipCents(percent: 15, of: 40_000), 6_000)
        XCTAssertEqual(TapToPayCharge.tipCents(percent: 15, of: 3_333), 500, "rounded to the nearest cent")
        XCTAssertEqual(TapToPayCharge.tipPercents, [10, 15, 20])
    }

    func testTheReceiptShowsTheCardByBrandAndLastFourOnly() {
        XCTAssertEqual(TapToPayReceipt.cardDescription(brand: "visa (apple pay)", last4: "4242"), "Visa (Apple Pay) •••• 4242")
        XCTAssertEqual(TapToPayReceipt.cardDescription(brand: "amex", last4: "0005"), "American Express •••• 0005")
        XCTAssertNil(TapToPayReceipt.cardDescription(brand: "visa", last4: nil))

        let approved = TapToPayReceipt(
            businessName: "Reed Sound", invoiceNumber: "SI-2026-014", amountCents: 40_000, tipCents: 6_000,
            currencyCode: "USD", card: "Visa •••• 4242", date: .now, approved: true, receiptURL: nil
        )
        XCTAssertTrue(approved.text.contains("Payment approved"))
        XCTAssertTrue(approved.text.contains("Tip: $60.00"))
        XCTAssertTrue(approved.text.contains("Total: $460.00"))
        XCTAssertTrue(approved.text.contains("Visa •••• 4242"))

        var declined = approved
        declined.approved = false
        XCTAssertTrue(declined.text.contains("you were not charged"))
    }
}
