import XCTest
import SwiftData
import PDFKit
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

    // MARK: - Contract terms (v3 templates)

    /// The Voorhees agreement's numbers: $8,000 total, $4,000 deposit,
    /// event on a Sunday two days after the Friday balance deadline.
    private func voorheesContext(terms: ContractTerms? = nil, business: BusinessProfile? = nil) -> ContractContext {
        var parts = DateComponents()
        parts.year = 2026; parts.month = 11; parts.day = 8; parts.hour = 18
        let start = Calendar.current.date(from: parts)!
        let job = Job(businessID: UUID(), title: "Full audio production", startDate: start,
                      endDate: start.addingTimeInterval(3600 * 4), locationName: "Massachusetts Hall, Denmark, SC")
        let client = Client(name: "Voorhees University", email: "events@example.edu")
        let invoice = makeInvoice(total: 8000)
        return ContractContext(business: business, client: client, invoice: invoice, job: job,
                               depositAmountCents: 400_000, terms: terms)
    }

    private func render(_ template: String, _ ctx: ContractContext) -> String {
        ContractTemplateEngine.render(template: template, context: ctx)
    }

    func testCancellationTiersSpellOutWhatEachCosts() {
        let ctx = voorheesContext()
        XCTAssertEqual(render("{{Terms.CancelEarlyDays}} / {{Terms.CancelMidRange}} / {{Terms.CancelLateDays}}", ctx),
                       "thirty (30) / Eight (8) to thirty (30) / Seven (7)")
        XCTAssertTrue(render("{{Terms.CancelEarlyFee}}", ctx).contains("the $4,000.00 deposit, which Provider shall retain"))
        XCTAssertTrue(render("{{Terms.CancelMidFee}}", ctx).contains("$6,000.00 (75% of the Total Fee)"))
        let late = render("{{Terms.CancelLateFee}}", ctx)
        XCTAssertTrue(late.contains("$8,000.00 (100% of the Total Fee)"))
        XCTAssertTrue(late.contains("No refund shall be issued"))
        XCTAssertEqual(render("{{Terms.CancellationSummary}}", ctx),
                       "Deposit kept if more than 30 days out · 75% at 8–30 days · 100% at 7 days or fewer")
    }

    func testFeeDepositAndBalanceRead() {
        let ctx = voorheesContext()
        XCTAssertEqual(render("{{Invoice.TotalWords}}", ctx), "Eight Thousand Dollars ($8,000.00)")
        XCTAssertEqual(render("{{Terms.DepositLine}}", ctx), "$4,000.00 (50%) — due upon signing")
        XCTAssertEqual(render("{{Terms.BalanceLine}}", ctx), "$4,000.00 — due 48 hours before start")
        let balance = render("{{Terms.BalanceClause}}", ctx)
        XCTAssertTrue(balance.contains("no later than forty-eight (48) hours before"), balance)
        XCTAssertTrue(balance.contains("Sunday, November 8, 2026"), balance)
        XCTAssertTrue(balance.contains("Friday, November 6, 2026"), balance)
        XCTAssertTrue(render("{{Terms.BalanceDeadline}}", ctx).hasPrefix("Friday, November 6, 2026, at ________"))
        XCTAssertEqual(render("{{Contract.Subtitle}}", ctx),
                       "Voorhees University · Sunday, November 8, 2026 · Massachusetts Hall, Denmark, SC")
    }

    func testTermsComeFromTheBusinessUnlessTheContractHasItsOwn() {
        let profile = BusinessProfile(businessID: UUID())
        profile.contractCancelMidPercent = 50
        profile.contractGoverningState = "South Carolina"
        let fromProfile = voorheesContext(business: profile)
        XCTAssertTrue(render("{{Terms.CancelMidFee}}", fromProfile).contains("$4,000.00 (50% of the Total Fee)"))
        XCTAssertEqual(render("{{Terms.GoverningLaw}}", fromProfile), "the laws of the State of South Carolina")

        var own = ContractTerms(profile: profile)
        own.cancelMidPercent = 90
        own.balanceDueHours = 72
        let overridden = voorheesContext(terms: own, business: profile)
        XCTAssertTrue(render("{{Terms.CancelMidFee}}", overridden).contains("$7,200.00 (90% of the Total Fee)"))
        XCTAssertTrue(render("{{Terms.BalanceClause}}", overridden).contains("Thursday, November 5, 2026"))
    }

    func testTermsNormalizeIntoNonOverlappingTiers() {
        var t = ContractTerms()
        t.cancelEarlyDays = 5
        t.cancelLateDays = 9
        t.cancelMidPercent = 80
        t.cancelLatePercent = 60
        let n = t.normalized
        XCTAssertLessThan(n.cancelLateDays, n.cancelEarlyDays)
        XCTAssertGreaterThanOrEqual(n.cancelLatePercent, n.cancelMidPercent)
    }

    func testNoDepositAndNoGoverningStateStillReadCleanly() {
        let ctx = ContractContext(business: nil, client: nil, invoice: makeInvoice(total: 1000), job: nil, depositAmountCents: nil)
        XCTAssertEqual(render("{{Terms.DepositLine}}", ctx), "None required")
        XCTAssertTrue(render("{{Terms.CancelEarlyFee}}", ctx).hasPrefix("no cancellation fee applies"))
        XCTAssertTrue(render("{{Terms.BalanceClause}}", ctx).hasPrefix("The full Total Fee of $1,000.00"))
        XCTAssertEqual(render("{{Terms.BalanceDeadline}}", ctx), "48 hours before start")
        XCTAssertEqual(render("{{Terms.GoverningLaw}}", ctx), "the laws of the state in which Provider principally operates")
        XCTAssertEqual(render("{{Contract.Subtitle}}", ctx), "")
    }

    func testBuiltInAgreementsRenderCompletelyWithEverythingKnown() {
        let profile = BusinessProfile(businessID: UUID())
        profile.name = "Javon F. Studios"
        profile.email = "studio@example.com"
        let ctx = voorheesContext(business: profile)
        for body in [ContractTemplateSeeder.generalAgreement(), ContractTemplateSeeder.photographyAgreement(), ContractTemplateSeeder.djAgreement()] {
            let out = render(body, ctx)
            XCTAssertFalse(out.contains("{{"), "no token survives")
            XCTAssertEqual(ContractTemplateEngine.blanks(in: out), [], "nothing left to fill in, so it can be sent")
            XCTAssertTrue(out.contains("$6,000.00 (75% of the Total Fee)"))
        }
    }

    // MARK: - Layout

    func testDocumentMarkupParsesIntoBlocks() {
        let blocks = ContractDocument.parse("""
        # SERVICE AGREEMENT
        _Ada · Monday_
        ## ARTICLE 3 — FEES AND PAYMENT
        3.2 Deposit. A booking deposit of $4,000.00 is due.
        (a) More than thirty (30) days: kept.
        • Deck staining — 1 × $3,250.00 = $3,250.00
        | Item | Details |
        |---|---|
        | Event Name |  |
        | Client | Ada |
        Plain closing line.
        """)
        XCTAssertEqual(blocks, [
            .title("SERVICE AGREEMENT"),
            .subtitle("Ada · Monday"),
            .heading("ARTICLE 3 — FEES AND PAYMENT"),
            .clause(number: "3.2", lead: "Deposit.", text: "A booking deposit of $4,000.00 is due."),
            .item(marker: "(a)", text: "More than thirty (30) days: kept."),
            .item(marker: "•", text: "Deck staining — 1 × $3,250.00 = $3,250.00"),
            .table(header: ["Item", "Details"], rows: [["Event Name", ""], ["Client", "Ada"]]),
            .paragraph("Plain closing line.")
        ])
    }

    func testAnOlderBodyIsAllParagraphs() {
        let blocks = ContractDocument.parse("1. SCOPE OF SERVICES\nProvider: Studio\nSong | Writer | 50%")
        XCTAssertEqual(blocks, [.paragraph("1. SCOPE OF SERVICES"), .paragraph("Provider: Studio"), .paragraph("Song | Writer | 50%")])
        XCTAssertFalse(ContractDocument.isStructured("1. SCOPE OF SERVICES"))
    }

    func testAgreementPDFHasPageNumbersInitialsAndExhibit() throws {
        let profile = BusinessProfile(businessID: UUID())
        profile.name = "Javon F. Studios"
        let body = render(ContractTemplateSeeder.djAgreement(), voorheesContext(business: profile))
        let data = ContractPDFGenerator.makePDFData(ContractPDFGenerator.Input(
            title: "DJ Services Agreement", body: body, preparedDate: .now, business: profile,
            client: ClientSnapshot(name: "Voorhees University"), clientSignature: nil
        ))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertGreaterThanOrEqual(pdf.pageCount, 5)
        let first = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(first.contains("Page 1 of \(pdf.pageCount)"), first)
        XCTAssertTrue(first.contains("Client Initials"))
        XCTAssertTrue(first.contains("KEY TERMS AT A GLANCE"))
        let last = try XCTUnwrap(pdf.page(at: pdf.pageCount - 1)?.string)
        XCTAssertTrue(last.contains("EXHIBIT A"), last)
        let all = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
        XCTAssertTrue(all.contains("SERVICE PROVIDER"))
        XCTAssertTrue(all.contains("PROVIDER USE ONLY"))
    }

    func testAnOlderBodyPrintsWithoutInitials() throws {
        let data = ContractPDFGenerator.makePDFData(ContractPDFGenerator.Input(
            title: "Old Contract", body: "SERVICE AGREEMENT\n\n1. SCOPE\nWork.", preparedDate: .now,
            business: nil, client: nil, clientSignature: nil
        ))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertFalse(text.contains("Client Initials"))
        XCTAssertTrue(text.contains("Page 1 of 1"))
        XCTAssertTrue(text.contains("Old Contract"))
    }
}
