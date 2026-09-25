import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Every money number worked out one way (MoneyMath), and the Money tab's
/// estimate stages and expense export.
@MainActor
final class MoneyMathTests: XCTestCase {

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

    private func invoice(_ total: Double, client: String? = "Maria Reyes", sent: Bool = true, due: Date = .now.addingTimeInterval(14 * 86_400)) throws -> Invoice {
        var owner: Client? = nil
        if let client {
            let c = Client(businessID: businessID, name: client, email: "m@example.com")
            context.insert(c)
            owner = c
        }
        let invoice = Invoice(businessID: businessID, invoiceNumber: "SI-\(Int.random(in: 100...999))", client: owner)
        context.insert(invoice)
        let item = LineItem(itemDescription: "Work", quantity: 1, unitPrice: total)
        item.invoice = invoice
        invoice.items = [item]
        context.insert(item)
        if sent { invoice.sentAt = .now.addingTimeInterval(-3 * day) }
        invoice.dueDate = due
        try context.save()
        return invoice
    }

    // MARK: Owed

    func testDraftsAreNotOwed() throws {
        let draft = try invoice(300, sent: false)
        let sent = try invoice(200)
        XCTAssertEqual(MoneyMath.owed([draft, sent]).cents, 20_000)
    }

    func testPartPaymentsReduceWhatsOwed() throws {
        let inv = try invoice(450)
        _ = try InvoicePaymentService.record(on: inv, amountCents: 20_000, paidAt: .now, method: "check", context: context)
        XCTAssertEqual(MoneyMath.owed([inv]).cents, 25_000)
    }

    func testOverdueStartsTheDayAfterTheDueDate() throws {
        let dueToday = try invoice(100, due: Calendar.current.startOfDay(for: .now))
        let late = try invoice(100, due: .now.addingTimeInterval(-2 * day))
        XCTAssertEqual(MoneyMath.overdue([dueToday, late]).count, 1)
    }

    // MARK: Money in

    func testMoneyInIsDatedByThePaymentNotTheInvoice() throws {
        let inv = try invoice(450)
        inv.issueDate = .now.addingTimeInterval(-90 * day)
        _ = try InvoicePaymentService.record(on: inv, amountCents: 45_000, paidAt: .now, method: "card", context: context)
        let received = MoneyMath.received(invoices: [inv], jobs: [])
        XCTAssertEqual(MoneyMath.tally(received, in: MoneyMath.lastDays(7)).cents, 45_000)
    }

    func testPartPaymentsCountAsMoneyIn() throws {
        let inv = try invoice(450)
        _ = try InvoicePaymentService.record(on: inv, amountCents: 10_000, paidAt: .now, method: "cash", context: context)
        XCTAssertEqual(MoneyMath.tally(MoneyMath.received(invoices: [inv], jobs: []), in: MoneyMath.thisMonth()).cents, 10_000)
    }

    func testAPortalPaymentRecordsAPaymentDatedToday() throws {
        let inv = try invoice(300)
        inv.issueDate = .now.addingTimeInterval(-60 * day)
        InvoicePaymentService.markPaidOnline(inv, context: context)
        XCTAssertTrue(inv.isPaid)
        XCTAssertEqual(inv.payments?.count, 1)
        XCTAssertEqual(MoneyMath.tally(MoneyMath.received(invoices: [inv], jobs: []), in: MoneyMath.lastDays(1)).cents, 30_000)
    }

    func testEstimatesAreNeverMoneyIn() throws {
        let est = try invoice(900)
        est.documentType = "estimate"
        est.isPaid = true
        XCTAssertEqual(MoneyMath.received(invoices: [est], jobs: []), [])
        XCTAssertEqual(MoneyMath.owed([est]).cents, 0)
    }

    func testABookingDepositCountsUntilMarkedRefunded() throws {
        let job = Job(businessID: businessID, title: "Mowing — Maria", startDate: .now, endDate: .now)
        job.sourceBookingRequestId = "req-1"
        job.depositAmountCents = 3_000
        job.depositPaidAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        context.insert(job)
        XCTAssertEqual(MoneyMath.tally(MoneyMath.received(invoices: [], jobs: [job]), in: MoneyMath.thisMonth()).cents, 3_000)
        job.depositRefundedAt = .now
        XCTAssertEqual(MoneyMath.received(invoices: [], jobs: [job]), [])
    }

    func testAnEstimateDepositIsntCountedTwice() throws {
        // Estimate deposits have their own invoice; the job's copy isn't money in.
        let job = Job(businessID: businessID, title: "Deck", startDate: .now, endDate: .now)
        job.depositAmountCents = 5_000
        job.depositPaidAtMs = Int64(Date().timeIntervalSince1970 * 1000)
        XCTAssertEqual(MoneyMath.received(invoices: [], jobs: [job]), [])
    }

    func testWeeksEndWithThisWeek() throws {
        let inv = try invoice(100)
        _ = try InvoicePaymentService.record(on: inv, amountCents: 10_000, paidAt: .now, method: "cash", context: context)
        let weeks = MoneyMath.weekly(MoneyMath.received(invoices: [inv], jobs: []), weeks: 8)
        XCTAssertEqual(weeks.count, 8)
        XCTAssertEqual(weeks.last?.cents, 10_000)
        XCTAssertEqual(weeks.dropLast().reduce(0) { $0 + $1.cents }, 0)
    }

    // MARK: Who owes you

    func testInvoicesWithNoClientAreGroupedTogether() throws {
        let a = try invoice(100, client: nil)
        let b = try invoice(50, client: nil)
        let c = try invoice(200, client: "Dunn")
        let groups = MoneyMath.byClient([a, b, c])
        XCTAssertEqual(groups.map(\.name), ["Dunn", "No client"])
        XCTAssertEqual(groups.last?.owedCents, 15_000)
        XCTAssertNil(groups.last?.clientID)
    }

    // MARK: Estimates

    func testEstimateStages() throws {
        let est = try invoice(500, sent: false)
        est.documentType = "estimate"
        XCTAssertEqual(EstimateStage(est), .draft)
        est.sentAt = .now
        XCTAssertEqual(EstimateStage(est), .waiting)
        est.estimateStatus = "accepted"
        XCTAssertEqual(EstimateStage(est), .accepted)
        est.estimateStatus = " Declined "
        XCTAssertEqual(EstimateStage(est), .declined)
    }

    // MARK: Expenses

    func testExpenseTotalsAndDeductible() {
        let month = MoneyMath.thisMonth()
        let a = Expense(businessID: businessID, date: .now); a.amountCents = 21_400; a.isTaxDeductible = true
        let b = Expense(businessID: businessID, date: .now); b.amountCents = 5_800; b.isTaxDeductible = false
        let old = Expense(businessID: businessID, date: .now.addingTimeInterval(-70 * 86_400)); old.amountCents = 999
        XCTAssertEqual(MoneyMath.spent([a, b, old], in: month).cents, 27_200)
        XCTAssertEqual(MoneyMath.deductible([a, b, old], in: month), 21_400)
    }

    func testTheSpreadsheetEscapesAndIncludesEveryField() {
        let e = Expense(businessID: businessID, date: Date(timeIntervalSince1970: 1_790_000_000))
        e.amountCents = 21_450
        e.vendor = "Smith, Jones & Co"
        e.notes = "Said \"rush\""
        let csv = ExpenseExport.csv([e])
        let lines = csv.split(separator: "\n")
        XCTAssertEqual(lines.first, "Date,Vendor,Category,Amount,Tax deductible,Notes")
        XCTAssertTrue(lines[1].contains("\"Smith, Jones & Co\""))
        XCTAssertTrue(lines[1].contains("214.50"))
        XCTAssertTrue(lines[1].contains("\"Said \"\"rush\"\"\""))
    }
}
