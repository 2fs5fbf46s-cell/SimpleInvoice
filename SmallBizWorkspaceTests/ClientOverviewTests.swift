import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// What the client screen and list say about a client: what they owe, the
/// next step, and their work.
@MainActor
final class ClientOverviewTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()
    private var client: Client!

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
        client = Client(businessID: businessID, name: "Maria Reyes", email: "maria@example.com", phone: "555-0100")
        context.insert(client)
    }

    override func tearDownWithError() throws {
        client = nil
        container = nil
        try super.tearDownWithError()
    }

    private func invoice(
        _ total: Double,
        sent: Bool = true,
        due: Date = .now.addingTimeInterval(7 * 86_400),
        estimate: Bool = false
    ) -> Invoice {
        let document = Invoice(
            businessID: businessID,
            invoiceNumber: estimate ? "EST-1" : "INV-\(Int.random(in: 100...999))",
            dueDate: due,
            documentType: estimate ? "estimate" : "invoice",
            client: client
        )
        context.insert(document)
        let item = LineItem(itemDescription: "Work", quantity: 1, unitPrice: total)
        item.invoice = document
        document.items = [item]
        context.insert(item)
        if sent {
            if estimate { document.estimateStatus = "sent" } else { document.sentAt = .now.addingTimeInterval(-30 * 86_400) }
        }
        return document
    }

    private func job(_ title: String, stage: (Job) -> Void = { _ in }) -> Job {
        let job = Job(businessID: businessID, clientID: client.id, title: title, startDate: .now.addingTimeInterval(86_400), endDate: .now.addingTimeInterval(90_000))
        context.insert(job)
        stage(job)
        return job
    }

    private func overview(_ invoices: [Invoice] = [], jobs: [Job] = [], contracts: [Contract] = []) -> ClientOverview {
        ClientOverview(client: client, invoices: invoices, jobs: jobs, contracts: contracts)
    }

    // MARK: - Money

    func testDraftsAreNotOwed() {
        let draft = invoice(300, sent: false)
        let sent = invoice(200)

        let result = overview([draft, sent])

        XCTAssertEqual(result.owedCents, 20_000)
        XCTAssertEqual(result.openInvoices.map(\.id), [sent.id])
    }

    func testOwedCountsWhatsLeftAfterAPartPayment() throws {
        let sent = invoice(450)
        try InvoicePaymentService.record(on: sent, amountCents: 20_000, paidAt: .now, method: "check", context: context)

        XCTAssertEqual(overview([sent]).owedCents, 25_000)
    }

    func testOverdueIsSeparatedFromOwed() {
        let late = invoice(100, due: .now.addingTimeInterval(-5 * 86_400))
        let current = invoice(200)

        let result = overview([late, current])

        XCTAssertEqual(result.owedCents, 30_000)
        XCTAssertEqual(result.overdueCents, 10_000)
    }

    func testPaidThisYearCountsPaymentsByTheDayTheyWerePaid() throws {
        let sent = invoice(450)
        let lastYear = Calendar.current.date(byAdding: .year, value: -1, to: .now)!
        try InvoicePaymentService.record(on: sent, amountCents: 10_000, paidAt: lastYear, method: "cash", context: context)
        try InvoicePaymentService.record(on: sent, amountCents: 15_000, paidAt: .now, method: "cash", context: context)

        XCTAssertEqual(overview([sent]).paidThisYearCents, 15_000)
    }

    func testEstimatesAreNeverOwed() {
        let estimate = invoice(900, estimate: true)

        XCTAssertEqual(overview([estimate]).owedCents, 0)
        XCTAssertFalse(overview([estimate]).hasBillingHistory)
    }

    func testOtherClientsRecordsAreIgnored() {
        let other = Client(businessID: businessID, name: "Someone Else")
        context.insert(other)
        let theirs = Invoice(businessID: businessID, invoiceNumber: "INV-9", client: other)
        theirs.sentAt = .now
        context.insert(theirs)

        XCTAssertTrue(overview([theirs]).invoices.isEmpty)
    }

    // MARK: - Next step

    func testOverdueComesFirst() {
        let late = invoice(100, due: .now.addingTimeInterval(-5 * 86_400))
        let draft = invoice(50, sent: false)

        guard case .overdue(let found) = overview([late, draft]).nextStep else {
            return XCTFail("Expected the overdue invoice")
        }
        XCTAssertEqual(found.id, late.id)
    }

    func testFinishedJobWithoutAnInvoiceComesBeforeDrafts() {
        let done = job("Fence repair") { $0.stageRaw = JobStage.completed.rawValue }
        let draft = invoice(50, sent: false)

        guard case .invoiceFinishedJob(let found) = overview([draft], jobs: [done]).nextStep else {
            return XCTFail("Expected the finished job")
        }
        XCTAssertEqual(found.id, done.id)
    }

    func testFinishedJobWithItsInvoiceIsNotFlagged() {
        let done = job("Fence repair") { $0.stageRaw = JobStage.completed.rawValue }
        let billed = invoice(400)
        billed.job = done

        guard case .awaitingPayment = overview([billed], jobs: [done]).nextStep else {
            return XCTFail("Expected waiting on payment, not billing the job again")
        }
    }

    func testAcceptedEstimatesJobNeedsScheduling() {
        let unscheduled = job("Deck") { $0.needsScheduling = true }

        guard case .scheduleJob(let found) = overview(jobs: [unscheduled]).nextStep else {
            return XCTFail("Expected schedule job")
        }
        XCTAssertEqual(found.id, unscheduled.id)
    }

    func testDraftBeforeWaitingOnAnEstimate() {
        let sentEstimate = invoice(800, estimate: true)
        let draftEstimate = invoice(300, sent: false, estimate: true)

        guard case .finishDraft(let found) = overview([sentEstimate, draftEstimate]).nextStep else {
            return XCTFail("Expected the draft")
        }
        XCTAssertEqual(found.id, draftEstimate.id)
    }

    func testSentEstimateIsWaitedOn() {
        let sentEstimate = invoice(800, estimate: true)

        guard case .awaitingEstimate = overview([sentEstimate]).nextStep else {
            return XCTFail("Expected waiting on the estimate")
        }
    }

    func testScheduledJobWhenNothingElseIsOpen() {
        let upcoming = job("Gutters")

        guard case .upcomingJob(let found) = overview(jobs: [upcoming]).nextStep else {
            return XCTFail("Expected the upcoming job")
        }
        XCTAssertEqual(found.id, upcoming.id)
    }

    func testCanceledJobsAreIgnored() {
        let canceled = job("Gutters") { $0.stageRaw = JobStage.canceled.rawValue }

        guard case .startWork = overview(jobs: [canceled]).nextStep else {
            return XCTFail("Expected nothing open")
        }
    }

    func testNoContactInfoAsksForIt() {
        client.email = ""
        client.phone = " "

        guard case .addContact = overview().nextStep else {
            return XCTFail("Expected add contact")
        }
    }

    // MARK: - Work and naming

    func testOpenWorkListsFirst() {
        let paid = invoice(100)
        paid.isPaid = true
        paid.issueDate = .now
        let draft = invoice(50, sent: false)
        draft.issueDate = .now.addingTimeInterval(-10 * 86_400)

        let items = overview([paid, draft]).workItems

        XCTAssertEqual(items.map(\.status), ["Draft", "Paid"])
        XCTAssertTrue(items[0].isOpen)
    }

    func testContractsLinkedThroughAJobAreTheClients() {
        let work = job("Kitchen")
        let contract = Contract(businessID: businessID, title: "Kitchen agreement", statusRaw: ContractStatus.sent.rawValue)
        contract.job = work
        context.insert(contract)

        XCTAssertEqual(overview(jobs: [work], contracts: [contract]).contracts.map(\.id), [contract.id])
    }

    func testInitials() {
        XCTAssertEqual(Client(name: "Maria del Reyes").initials, "MR")
        XCTAssertEqual(Client(name: "cher").initials, "C")
        XCTAssertEqual(Client(name: "  ").initials, "?")
    }

    func testNewClientsRecordWhenTheyWereAdded() {
        XCTAssertNotNil(Client(name: "New").createdAt)
        XCTAssertFalse(Client(name: "New").isArchived)
    }
}
