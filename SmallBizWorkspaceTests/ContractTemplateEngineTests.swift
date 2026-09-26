import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers the Job/deposit/balance tokens added to `ContractTemplateEngine`
/// and the contact-line helper that replaced the old per-field
/// "Email: X | Phone: Y" tokens (which left a dangling "| " when a field was
/// empty). See `ContractCreation.defaultDepositCentsTests` for the 50/50
/// split math itself.
@MainActor
final class ContractTemplateEngineTests: XCTestCase {

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

    private func makeInvoice(total: Double = 3250, dueInDays: Int = 14) -> Invoice {
        let due = Calendar.current.date(byAdding: .day, value: dueInDays, to: .now) ?? .now
        let invoice = Invoice(
            invoiceNumber: "SI-2026-004",
            dueDate: due,
            items: [LineItem(itemDescription: "Deck staining", quantity: 1, unitPrice: total)]
        )
        return invoice
    }

    private func makeJob(title: String = "Deck staining", location: String = "1 Infinite Loop, Cupertino, CA") -> Job {
        let start = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
        return Job(
            businessID: UUID(),
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(3600 * 4),
            locationName: location
        )
    }

    // MARK: - Job tokens

    func testJobTokensFillFromARealJob() {
        let job = makeJob()
        let ctx = ContractContext(business: nil, client: nil, invoice: nil, job: job)
        let out = ContractTemplateEngine.render(template: "{{Job.Title}} at {{Job.Location}}, {{Job.Date}}", context: ctx)

        XCTAssertTrue(out.contains("Deck staining at 1 Infinite Loop, Cupertino, CA"))
        XCTAssertFalse(out.contains("[add"))
    }

    func testNoJobLeavesVisibleBlanksForRequiredFields() {
        let ctx = ContractContext(business: nil, client: nil, invoice: nil, job: nil)
        let out = ContractTemplateEngine.render(template: "{{Job.Title}} / {{Job.Location}} / {{Job.Date}}", context: ctx)

        XCTAssertTrue(out.contains("[add job description]"))
        XCTAssertTrue(out.contains("[add job site address]"))
        XCTAssertTrue(out.contains("[add scheduled date]"))
    }

    func testJobNeedsSchedulingIsTreatedAsNoRealDate() {
        let job = makeJob()
        job.needsScheduling = true
        let ctx = ContractContext(business: nil, client: nil, invoice: nil, job: job)
        let out = ContractTemplateEngine.render(template: "{{Job.Date}}", context: ctx)

        XCTAssertTrue(out.contains("[add scheduled date]"))
    }

    func testOptionalJobFieldsAreEmptyRatherThanBlankMarked() {
        let job = makeJob()
        XCTAssertEqual(job.notes, "")
        XCTAssertTrue(job.measurements.isEmpty)

        let ctx = ContractContext(business: nil, client: nil, invoice: nil, job: job)
        let out = ContractTemplateEngine.render(template: "[{{Job.Notes}}][{{Job.Measurements}}]", context: ctx)

        XCTAssertEqual(out, "[][]")
    }

    func testJobMeasurementsRenderAsABulletList() {
        let job = makeJob()
        job.measurements = [JobMeasurement(label: "Deck length", value: 20, unit: "ft")]
        let ctx = ContractContext(business: nil, client: nil, invoice: nil, job: job)
        let out = ContractTemplateEngine.render(template: "{{Job.Measurements}}", context: ctx)

        XCTAssertEqual(out, "• Deck length: 20 ft")
    }

    // MARK: - Deposit / balance

    func testDepositAndBalanceSplitTheInvoiceTotal() {
        let invoice = makeInvoice(total: 3250)
        let deposit = ContractCreation.defaultDepositCents(invoiceTotalCents: invoice.totalCents)
        let ctx = ContractContext(business: nil, client: nil, invoice: invoice, depositAmountCents: deposit)

        let out = ContractTemplateEngine.render(
            template: "{{Invoice.Deposit}} / {{Invoice.Balance}} / {{Invoice.DepositDueDate}} / {{Invoice.BalanceDueDate}}",
            context: ctx
        )

        XCTAssertTrue(out.contains("$1,625.00"), out)
        XCTAssertEqual(out.components(separatedBy: "$1,625.00").count - 1, 2, "50/50 of $3,250 is $1,625 on both sides")
        XCTAssertTrue(out.contains("due at signing"))
    }

    func testNoDepositMeansTheFullTotalIsDueOnCompletion() {
        let invoice = makeInvoice(total: 500)
        let ctx = ContractContext(business: nil, client: nil, invoice: invoice, depositAmountCents: nil)

        let out = ContractTemplateEngine.render(template: "{{Invoice.Deposit}} / {{Invoice.Balance}}", context: ctx)

        XCTAssertTrue(out.contains("No deposit required"))
        XCTAssertTrue(out.contains("$500.00"))
    }

    func testNoInvoiceLeavesDepositAndBalanceBlankMarked() {
        let ctx = ContractContext(business: nil, client: nil, invoice: nil)
        let out = ContractTemplateEngine.render(template: "{{Invoice.Deposit}} / {{Invoice.Balance}}", context: ctx)

        XCTAssertTrue(out.contains("[add deposit]"))
        XCTAssertTrue(out.contains("[add balance]"))
    }

    func testPaymentTermsFallsBackWhenBlank() {
        let invoice = makeInvoice()
        invoice.paymentTerms = ""
        let ctx = ContractContext(business: nil, client: nil, invoice: invoice)
        let out = ContractTemplateEngine.render(template: "{{Invoice.PaymentTerms}}", context: ctx)
        XCTAssertEqual(out, "Due upon completion")

        invoice.paymentTerms = "Net 30"
        let ctx2 = ContractContext(business: nil, client: nil, invoice: invoice)
        XCTAssertEqual(ContractTemplateEngine.render(template: "{{Invoice.PaymentTerms}}", context: ctx2), "Net 30")
    }

    // MARK: - Contact line (the dangling "Phone: | " fix)

    func testContactLineOmitsMissingFieldsWithoutADanglingSeparator() {
        let bothClient = Client(name: "Testing Freeman", email: "t@example.com", phone: "555-1234")
        let emailOnlyClient = Client(name: "Ana Lopez", email: "ana@example.com")
        let neitherClient = Client(name: "No Contact")

        func render(_ client: Client) -> String {
            let ctx = ContractContext(business: nil, client: client, invoice: nil)
            return ContractTemplateEngine.render(template: "{{Client.ContactLine}}", context: ctx)
        }

        XCTAssertEqual(render(bothClient), "t@example.com | 555-1234")
        XCTAssertEqual(render(emailOnlyClient), "ana@example.com")
        XCTAssertEqual(render(neitherClient), "")
    }

    // MARK: - defaultDepositCents

    func testDefaultDepositCentsIsHalfRoundedToTheNearestCent() {
        XCTAssertEqual(ContractCreation.defaultDepositCents(invoiceTotalCents: 325_000), 162_500)
        XCTAssertEqual(ContractCreation.defaultDepositCents(invoiceTotalCents: 100), 50)
        XCTAssertEqual(ContractCreation.defaultDepositCents(invoiceTotalCents: 101), 51) // rounds, doesn't truncate
    }
}
