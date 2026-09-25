import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Two rules about money leaving the app.
///
/// A new invoice is created with one placeholder line at $0, and Send was live
/// the moment it existed — so the app would email a customer a bill for $0.00
/// with a line reading "Service". And the amount the user types has to survive
/// currency symbols, separators and non-US keyboards without silently becoming
/// a different number.
@MainActor
final class InvoiceSendGuardTests: XCTestCase {

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

    private func makeInvoice(
        items: [(String, Double, Double)] = [],
        documentType: String = "invoice"
    ) throws -> Invoice {
        let invoice = Invoice(
            businessID: UUID(),
            invoiceNumber: "INV-1",
            documentType: documentType
        )
        context.insert(invoice)
        for (description, qty, price) in items {
            let item = LineItem(itemDescription: description, quantity: qty, unitPrice: price)
            item.invoice = invoice
            invoice.items = (invoice.items ?? []) + [item]
            context.insert(item)
        }
        try context.save()
        return invoice
    }

    // MARK: - The defect

    func testAnInvoiceWithNoItemsCannotBeSent() throws {
        let invoice = try makeInvoice()

        XCTAssertFalse(invoice.canBeSent)
        XCTAssertEqual(
            invoice.cannotBeSentReason,
            "Add what you're charging for before sending this invoice."
        )
    }

    /// The exact state the creation flow produced: one placeholder line at zero.
    func testTheDefaultPlaceholderLineIsNotSendable() throws {
        let invoice = try makeInvoice(items: [("Service", 1, 0)])

        XCTAssertFalse(invoice.canBeSent)
        XCTAssertEqual(invoice.totalCents, 0)
        XCTAssertTrue(invoice.cannotBeSentReason?.contains("$0.00") ?? false)
    }

    func testAnInvoiceWithAnAmountCanBeSent() throws {
        let invoice = try makeInvoice(items: [("Mixing session", 1, 250)])

        XCTAssertTrue(invoice.canBeSent)
        XCTAssertNil(invoice.cannotBeSentReason)
    }

    func testTheReasonNamesTheDocumentType() throws {
        let estimate = try makeInvoice(documentType: "estimate")

        XCTAssertTrue(
            estimate.cannotBeSentReason?.contains("estimate") ?? false,
            "an estimate should not be called an invoice"
        )
    }

    /// A fully discounted invoice is still a $0 document going to a customer.
    func testADiscountThatZeroesTheTotalBlocksSending() throws {
        let invoice = try makeInvoice(items: [("Service", 1, 100)])
        invoice.discountAmount = 100
        try context.save()

        XCTAssertEqual(invoice.totalCents, 0)
        XCTAssertFalse(invoice.canBeSent)
    }

    // MARK: - Reading the typed amount

    func testPlainAmountsParse() {
        XCTAssertEqual(InvoiceAmountParser.dollars(from: "250"), 250, accuracy: 0.001)
        XCTAssertEqual(InvoiceAmountParser.dollars(from: "250.50"), 250.50, accuracy: 0.001)
        XCTAssertEqual(InvoiceAmountParser.cents(from: "250.50"), 25_050)
    }

    func testCurrencySymbolsAndSpacesAreIgnored() {
        XCTAssertEqual(InvoiceAmountParser.dollars(from: " $250.50 "), 250.50, accuracy: 0.001)
        XCTAssertEqual(InvoiceAmountParser.dollars(from: "USD 99"), 99, accuracy: 0.001)
    }

    /// The slip that matters most: a thousands separator read as a decimal point
    /// turns $1,500 into $1.50.
    func testAThousandsSeparatorIsNotReadAsADecimalPoint() {
        XCTAssertEqual(InvoiceAmountParser.dollars(from: "1,500.00"), 1500, accuracy: 0.001)
        XCTAssertEqual(InvoiceAmountParser.cents(from: "1,500.00"), 150_000)
    }

    /// On a European keyboard the comma *is* the decimal separator.
    func testACommaDecimalIsUnderstood() {
        XCTAssertEqual(InvoiceAmountParser.dollars(from: "250,50"), 250.50, accuracy: 0.001)
    }

    func testJunkAndEmptyInputBecomeZeroRatherThanCrashing() {
        for text in ["", "   ", "abc", ".", "-", "$"] {
            XCTAssertEqual(
                InvoiceAmountParser.dollars(from: text), 0, accuracy: 0.001,
                "\(text.isEmpty ? "<empty>" : text) should read as zero"
            )
        }
    }

    func testANegativeAmountIsClampedToZero() {
        XCTAssertEqual(InvoiceAmountParser.dollars(from: "-50"), 0, accuracy: 0.001)
    }

    func testCentsRoundRatherThanTruncate() {
        XCTAssertEqual(InvoiceAmountParser.cents(from: "0.005"), 1)
        XCTAssertEqual(InvoiceAmountParser.cents(from: "19.999"), 2000)
    }

    // MARK: - Draft estimates stay on the device

    // The portal buttons, Done and the PDF upload all used to publish draft
    // estimates to the client's portal. Only Send Estimate may now.

    private func makeEstimate(status: String, clientEmail: String = "client@example.com") throws -> Invoice {
        let estimate = try makeInvoice(items: [("Fence repair", 1, 250)], documentType: "estimate")
        estimate.estimateStatus = status
        let client = Client(businessID: estimate.businessID, name: "Testing Freeman", email: clientEmail)
        context.insert(client)
        estimate.client = client
        try context.save()
        return estimate
    }

    func testOnlyAnEstimateThatWasSentIsPublishable() throws {
        XCTAssertTrue(try makeEstimate(status: "draft").isUnsentEstimate)
        XCTAssertTrue(try makeEstimate(status: "").isUnsentEstimate)
        XCTAssertFalse(try makeEstimate(status: "sent").isUnsentEstimate)
        XCTAssertFalse(try makeEstimate(status: " Accepted ").isUnsentEstimate)
        XCTAssertFalse(try makeEstimate(status: "declined").isUnsentEstimate)
        XCTAssertFalse(try makeInvoice(items: [("Work", 1, 10)]).isUnsentEstimate)
    }

    func testPortalSyncSkipsADraftEstimate() throws {
        let estimate = try makeEstimate(status: "draft")
        XCTAssertFalse(PortalAutoSyncService.isEligible(invoice: estimate))

        estimate.estimateStatus = "sent"
        XCTAssertTrue(PortalAutoSyncService.isEligible(invoice: estimate))
    }

    func testADraftEstimateCannotMintAPortalLink() async throws {
        let estimate = try makeEstimate(status: "draft")
        do {
            _ = try await PortalBackend.shared.createInvoicePortalToken(invoice: estimate)
            XCTFail("A draft estimate must not reach the portal")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Send this estimate"))
        }
    }

    func testSendingWithoutAClientEmailLeavesTheEstimateADraft() async throws {
        let estimate = try makeEstimate(status: "draft", clientEmail: "")
        do {
            _ = try await EstimateSendService.send(estimate: estimate, context: context, businessName: nil)
            XCTFail("Expected noClientEmail")
        } catch EstimateSendService.SendError.noClientEmail {
            XCTAssertEqual(estimate.estimateStatus, "draft")
        }
    }

    func testAnEstimateTheClientDecidedCannotBeSentAgain() async throws {
        let estimate = try makeEstimate(status: "accepted")
        do {
            _ = try await EstimateSendService.send(estimate: estimate, context: context, businessName: nil)
            XCTFail("Expected alreadyDecided")
        } catch EstimateSendService.SendError.alreadyDecided {
            XCTAssertEqual(estimate.estimateStatus, "accepted")
        }
    }
}
