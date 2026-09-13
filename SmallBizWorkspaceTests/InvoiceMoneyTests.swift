import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Money tests.
///
/// The bug these exist to prevent: the invoice PDF and the amount the customer is
/// actually charged were computed by different formulas. `total` summed unrounded
/// line totals and rounded once; `totalCents` rounded each line and summed. On
/// fractional unit prices those disagree, so a client could receive a PDF for one
/// amount and a checkout page for another.
///
/// Integer cents are now authoritative and the Double accessors derive from them.
/// `testDisplayedTotalAlwaysMatchesChargedTotal` is the guard on that invariant —
/// if it fails, some display path has gone back to its own arithmetic.
final class InvoiceMoneyTests: XCTestCase {

    // MARK: - Helpers

    private func makeInvoice(
        lines: [(qty: Double, unitPrice: Double)],
        taxRate: Double = 0,
        discount: Double = 0,
        documentType: String = "invoice"
    ) -> Invoice {
        let items = lines.map { line in
            LineItem(itemDescription: "Item", quantity: line.qty, unitPrice: line.unitPrice)
        }
        return Invoice(
            invoiceNumber: "INV-TEST",
            taxRate: taxRate,
            discountAmount: discount,
            documentType: documentType,
            items: items
        )
    }

    /// What a display surface would produce if it did its own dollars->cents
    /// conversion, the way several call sites used to.
    private func naiveCentsFromDisplayedTotal(_ invoice: Invoice) -> Int {
        Int((invoice.total * 100).rounded())
    }

    // MARK: - The core invariant

    func testDisplayedTotalAlwaysMatchesChargedTotal() {
        // Each case previously produced a mismatch between the two paths, or is a
        // plausible real invoice that exercises rounding.
        let cases: [(lines: [(qty: Double, unitPrice: Double)], tax: Double, discount: Double)] = [
            ([(3, 0.335)], 0, 0),
            ([(1, 0.335), (1, 0.335), (1, 0.335)], 0, 0),
            ([(7, 1.005)], 0, 0),
            ([(1, 19.99), (2, 5.005)], 0.0825, 0),
            ([(3, 33.333)], 0.07, 10),
            ([(1, 0.005), (1, 0.005)], 0, 0),
            ([(12, 8.125), (5, 2.675)], 0.06, 7.77),
            ([(1, 1234.565)], 0.0875, 0),
        ]

        for (index, testCase) in cases.enumerated() {
            let invoice = makeInvoice(
                lines: testCase.lines,
                taxRate: testCase.tax,
                discount: testCase.discount
            )

            XCTAssertEqual(
                naiveCentsFromDisplayedTotal(invoice),
                invoice.totalCents,
                """
                Case \(index): the total shown to the customer (\(invoice.total)) does not \
                round-trip to the amount charged (\(invoice.totalCents) cents). A display \
                path is computing money independently of the authoritative cents.
                """
            )
        }
    }

    // MARK: - Per-line rounding

    func testSubtotalRoundsEachLineThenSums() {
        // 3 x $0.335 -> each line rounds to 34c -> 102c.
        // Summing first would give 100.5c, which rounds to 101c. The per-line
        // result is the correct one: it is what an itemized invoice adds up to.
        let invoice = makeInvoice(lines: [(1, 0.335), (1, 0.335), (1, 0.335)])

        XCTAssertEqual(invoice.subtotalCents, 102)
        XCTAssertEqual(invoice.totalCents, 102)
        XCTAssertEqual(invoice.subtotal, 1.02, accuracy: 0.0001)
    }

    func testSubtotalMatchesSumOfDisplayedLineTotals() {
        // Whatever the line rows add up to on screen must equal the subtotal row.
        let invoice = makeInvoice(lines: [(2, 4.125), (3, 1.335), (1, 0.505)])

        let displayedLineCents = (invoice.items ?? []).reduce(0) { partial, item in
            partial + Int((item.lineTotal * 100).rounded())
        }

        XCTAssertEqual(displayedLineCents, invoice.subtotalCents)
    }

    // MARK: - Tax and discount

    func testTaxAppliesAfterDiscount() {
        // $100 subtotal, $20 off, 10% tax -> tax on $80 = $8, total $88.
        let invoice = makeInvoice(lines: [(1, 100)], taxRate: 0.10, discount: 20)

        XCTAssertEqual(invoice.discountedSubtotalCents, 8000)
        XCTAssertEqual(invoice.taxCents, 800)
        XCTAssertEqual(invoice.totalCents, 8800)
    }

    func testDiscountLargerThanSubtotalClampsToZero() {
        let invoice = makeInvoice(lines: [(1, 25)], taxRate: 0.10, discount: 100)

        XCTAssertEqual(invoice.discountedSubtotalCents, 0)
        XCTAssertEqual(invoice.taxCents, 0)
        XCTAssertEqual(invoice.totalCents, 0)
        XCTAssertEqual(invoice.total, 0)
    }

    func testZeroTaxRateProducesNoTax() {
        let invoice = makeInvoice(lines: [(4, 12.50)], taxRate: 0)

        XCTAssertEqual(invoice.taxCents, 0)
        XCTAssertEqual(invoice.totalCents, 5000)
    }

    func testEmptyInvoiceIsZero() {
        let invoice = makeInvoice(lines: [], taxRate: 0.08, discount: 5)

        XCTAssertEqual(invoice.subtotalCents, 0)
        XCTAssertEqual(invoice.totalCents, 0)
        XCTAssertEqual(invoice.total, 0)
    }

    // MARK: - Derived Double accessors

    func testDoubleAccessorsDeriveFromCents() {
        let invoice = makeInvoice(lines: [(3, 19.995)], taxRate: 0.0825, discount: 4.44)

        XCTAssertEqual(invoice.subtotal, Double(invoice.subtotalCents) / 100, accuracy: 0.000001)
        XCTAssertEqual(invoice.discountedSubtotal, Double(invoice.discountedSubtotalCents) / 100, accuracy: 0.000001)
        XCTAssertEqual(invoice.taxAmount, Double(invoice.taxCents) / 100, accuracy: 0.000001)
        XCTAssertEqual(invoice.total, Double(invoice.totalCents) / 100, accuracy: 0.000001)
    }

    func testTotalsComponentsSumToTotal() {
        let invoice = makeInvoice(lines: [(2, 33.335), (1, 9.995)], taxRate: 0.0725, discount: 3.33)

        XCTAssertEqual(
            invoice.discountedSubtotalCents + invoice.taxCents,
            invoice.totalCents,
            "The Subtotal/Tax/Total rows on the PDF must add up."
        )
        XCTAssertEqual(
            invoice.subtotalCents - invoice.discountCents,
            invoice.discountedSubtotalCents
        )
    }

    // MARK: - Estimates use the same arithmetic

    func testEstimateAndInvoiceAgreeOnIdenticalLines() {
        let lines = [(qty: 3.0, unitPrice: 0.335), (qty: 2.0, unitPrice: 17.775)]
        let invoice = makeInvoice(lines: lines, taxRate: 0.0625, discount: 1.11)
        let estimate = makeInvoice(lines: lines, taxRate: 0.0625, discount: 1.11, documentType: "estimate")

        XCTAssertEqual(invoice.totalCents, estimate.totalCents)
        XCTAssertEqual(invoice.total, estimate.total)
    }

    // MARK: - Booking deposits

    func testRemainingDueSubtractsDeposit() {
        let invoice = makeInvoice(lines: [(1, 500)])
        invoice.sourceBookingDepositAmountCents = 15000

        XCTAssertEqual(invoice.totalCents, 50000)
        XCTAssertEqual(invoice.remainingDueCents, 35000)
        XCTAssertEqual(invoice.overpaidCents, 0)
    }

    func testDepositLargerThanTotalReportsOverpayment() {
        let invoice = makeInvoice(lines: [(1, 100)])
        invoice.sourceBookingDepositAmountCents = 15000

        XCTAssertEqual(invoice.remainingDueCents, 0)
        XCTAssertEqual(invoice.overpaidCents, 5000)
    }
}
