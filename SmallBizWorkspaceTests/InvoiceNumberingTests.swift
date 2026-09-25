import XCTest
import SwiftUI
import SwiftData
@testable import SmallBizWorkspace

/// Invoices started from Create got no number: their placeholder was a date
/// format ("INV-DRAFT-…") whose letters the formatter read as fields, so it
/// came out empty, and they went to clients that way. A one-time repair
/// numbers them. Money fields show an empty field, not "0.00", so typing
/// 325 doesn't make $3,250.
@MainActor
final class InvoiceNumberingTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()
    private let repairKey = "sbw.migration.numberBlankInvoices"
    private var year: Int { Calendar.current.component(.year, from: .now) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
        UserDefaults.standard.removeObject(forKey: repairKey)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: repairKey)
        container = nil
        try super.tearDownWithError()
    }

    private func invoice(_ number: String, issued daysAgo: Double, type: String = "invoice") -> Invoice {
        let invoice = Invoice(
            businessID: businessID,
            invoiceNumber: number,
            issueDate: .now.addingTimeInterval(-daysAgo * 86_400),
            documentType: type
        )
        invoice.portalNeedsUpload = false
        context.insert(invoice)
        return invoice
    }

    func testUnnumberedInvoicesAreNumberedOldestFirst() throws {
        let profile = BusinessProfile(businessID: businessID, nextInvoiceNumber: 2)
        context.insert(profile)
        let newer = invoice("", issued: 3)
        let older = invoice("", issued: 20)
        older.sentAt = .now.addingTimeInterval(-19 * 86_400)
        let numbered = invoice("SI-\(year)-001", issued: 30)
        let estimate = invoice("", issued: 25, type: "estimate")
        try context.save()

        try BusinessMigration.numberUnnumberedInvoicesIfNeeded(modelContext: context)

        XCTAssertEqual(older.invoiceNumber, "SI-\(year)-002")
        XCTAssertEqual(newer.invoiceNumber, "SI-\(year)-003")
        XCTAssertEqual(numbered.invoiceNumber, "SI-\(year)-001")
        XCTAssertEqual(estimate.invoiceNumber, "", "estimates are named, not numbered")
        XCTAssertTrue(older.portalNeedsUpload, "a sent one republishes so the portal shows its number")
        XCTAssertFalse(newer.portalNeedsUpload)
        XCTAssertEqual(profile.nextInvoiceNumber, 4)
    }

    func testTheRepairRunsOnce() throws {
        context.insert(BusinessProfile(businessID: businessID))
        try context.save()
        try BusinessMigration.numberUnnumberedInvoicesIfNeeded(modelContext: context)

        let later = invoice("", issued: 1)
        try context.save()
        try BusinessMigration.numberUnnumberedInvoicesIfNeeded(modelContext: context)
        XCTAssertEqual(later.invoiceNumber, "")
    }

    func testAnUntouchedDraftGivesBackOnlyTheLatestNumber() {
        let profile = BusinessProfile(businessID: businessID, nextInvoiceNumber: 5)
        context.insert(profile)
        InvoiceNumberGenerator.release("SI-\(year)-003", profile: profile)
        XCTAssertEqual(profile.nextInvoiceNumber, 5, "003 may be on another invoice; never hand it out twice")
        InvoiceNumberGenerator.release("SI-\(year)-004", profile: profile)
        XCTAssertEqual(profile.nextInvoiceNumber, 4)
        XCTAssertEqual(InvoiceNumberGenerator.generateNextNumber(profile: profile), "SI-\(year)-004")
    }

    func testAnUnnamedEstimateIsNamedForItsClient() throws {
        let client = Client(businessID: businessID, name: "Maria Reyes", email: "m@example.com")
        context.insert(client)
        try context.save()
        let first = try EstimateDrafts.make(name: "", client: client, businessID: businessID, context: context)
        let second = try EstimateDrafts.make(name: "  ", client: client, businessID: businessID, context: context)
        let noClient = try EstimateDrafts.make(name: "", client: nil, businessID: businessID, context: context)
        XCTAssertEqual(first.invoiceNumber, "Maria Reyes 1")
        XCTAssertEqual(second.invoiceNumber, "Maria Reyes 2")
        XCTAssertEqual(noClient.invoiceNumber, "Estimate 3")
    }

    func testAnAcceptedEstimatesJobIsNamedForTheWork() {
        let estimate = invoice("Patio Repaint", issued: 1, type: "estimate")
        XCTAssertEqual(EstimateAcceptanceHandler.jobTitle(estimateName: "Patio Repaint", estimate: estimate, client: "Maria"), "Patio Repaint")
        XCTAssertEqual(EstimateAcceptanceHandler.jobTitle(estimateName: "Estimate Deck", estimate: estimate, client: "Maria"), "Deck")
        let item = LineItem(itemDescription: "Fence repair", quantity: 1, unitPrice: 100)
        estimate.items = [item]
        XCTAssertEqual(EstimateAcceptanceHandler.jobTitle(estimateName: "", estimate: estimate, client: "Maria"), "Fence repair")
        estimate.items = []
        XCTAssertEqual(EstimateAcceptanceHandler.jobTitle(estimateName: "", estimate: estimate, client: "Maria"), "Work for Maria")
    }

    func testAContractWithNoInvoiceMarksWhatToFillIn() {
        let text = ContractTemplateEngine.render(
            template: "Scope: {{Invoice.Items}}\nTotal: {{Invoice.Total}}\nDue: {{Invoice.DueDate}}\nTotal again: {{Invoice.Total}}",
            context: ContractContext(business: nil, client: nil, invoice: nil, extras: [:])
        )
        XCTAssertTrue(text.contains("Total: [add total]"), text)
        XCTAssertEqual(ContractTemplateEngine.blanks(in: text), ["what the work includes", "total", "due date"])
        XCTAssertEqual(ContractTemplateEngine.blanks(in: "Total: $1,200.00"), [])
    }

    func testZeroShowsAsAnEmptyField() {
        var price = 0.0
        let field = Binding(get: { price }, set: { price = $0 }).zeroAsEmpty
        XCTAssertNil(field.wrappedValue)
        field.wrappedValue = 325
        XCTAssertEqual(price, 325)
        XCTAssertEqual(field.wrappedValue, 325)
        field.wrappedValue = nil
        XCTAssertEqual(price, 0)
    }
}
