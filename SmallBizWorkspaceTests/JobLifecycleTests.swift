import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// The job screen's lifecycle: jobs made from an accepted estimate wait for a
/// real date, Start/Complete record when they happened, one set of status
/// names, and the invoice a finished job gets.
@MainActor
final class JobLifecycleTests: XCTestCase {

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

    private func makeJob() -> Job {
        let job = Job(businessID: UUID(), startDate: .now, endDate: .now.addingTimeInterval(3600))
        context.insert(job)
        return job
    }

    private func makeAcceptedEstimate(items: [(String, Double, Double)]) throws -> Invoice {
        let businessID = UUID()
        let client = Client(businessID: businessID, name: "Testing Freeman", address: "12 Oak St")
        context.insert(client)
        let estimate = Invoice(
            businessID: businessID,
            invoiceNumber: "TF Estimate",
            issueDate: .now.addingTimeInterval(-30 * 86_400),
            dueDate: .now.addingTimeInterval(-16 * 86_400),
            documentType: "estimate",
            client: client
        )
        estimate.estimateStatus = "accepted"
        context.insert(estimate)
        for (description, qty, price) in items {
            let item = LineItem(itemDescription: description, quantity: qty, unitPrice: price)
            item.invoice = estimate
            estimate.items = (estimate.items ?? []) + [item]
            context.insert(item)
        }
        try context.save()
        return estimate
    }

    // MARK: - Jobs from accepted estimates

    /// They used to borrow the estimate's issue/due dates — weeks in the past
    /// — and show as "Scheduled".
    func testAJobFromAnAcceptedEstimateNeedsScheduling() throws {
        let estimate = try makeAcceptedEstimate(items: [("Fence repair", 1, 250)])

        try EstimateAcceptanceHandler.handleAccepted(estimate: estimate, context: context)

        let job = try XCTUnwrap(estimate.job)
        XCTAssertTrue(job.needsScheduling)
        XCTAssertEqual(JobDisplayStatus(job), .needsScheduling)
        XCTAssertEqual(job.locationName, "12 Oak St", "starts at the client's address")
    }

    // MARK: - Start, complete, cancel, reopen

    func testStartAndCompleteRecordTheirTimes() {
        let job = makeJob()

        JobLifecycle.start(job)
        XCTAssertEqual(job.stage, .inProgress)
        XCTAssertNotNil(job.startedAt)

        JobLifecycle.complete(job)
        XCTAssertEqual(job.stage, .completed)
        XCTAssertNotNil(job.completedAt)
        XCTAssertEqual(JobDisplayStatus(job).label, "Completed")
    }

    func testStartingAJobThatNeededSchedulingClearsTheFlag() {
        let job = makeJob()
        job.needsScheduling = true

        JobLifecycle.start(job)

        XCTAssertFalse(job.needsScheduling)
    }

    func testCancelThenReopen() async {
        let job = makeJob()

        await JobLifecycle.cancel(job)
        XCTAssertEqual(JobDisplayStatus(job), .canceled)
        XCTAssertNotNil(job.canceledAt)
        XCTAssertNil(job.calendarEventId)

        JobLifecycle.reopen(job)
        XCTAssertEqual(JobDisplayStatus(job), .scheduled)
        XCTAssertNil(job.canceledAt)
    }

    func testEveryStageHasOneName() {
        let job = makeJob()
        let labels: [JobStage: String] = [
            .booked: "Scheduled", .inProgress: "In progress", .completed: "Completed", .canceled: "Canceled"
        ]
        for (stage, label) in labels {
            job.stage = stage
            XCTAssertEqual(JobDisplayStatus(job).label, label)
        }
    }

    // MARK: - The invoice for a finished job

    func testTheInvoiceCopiesTheEstimateAndTakesOffAPaidDeposit() throws {
        let estimate = try makeAcceptedEstimate(items: [("Posts", 4, 50), ("Labor", 1, 300)])
        try EstimateAcceptanceHandler.handleAccepted(estimate: estimate, context: context)
        let job = try XCTUnwrap(estimate.job)
        job.depositAmountCents = 5_000
        job.depositPaidAtMs = 1

        let invoice = try JobInvoiceBuilder.makeInvoice(for: job, client: estimate.client, profile: nil, context: context)

        XCTAssertEqual(invoice.documentType, "invoice")
        XCTAssertTrue(invoice.job === job)
        XCTAssertEqual(invoice.items?.count, 3)
        XCTAssertEqual(invoice.totalCents, 45_000, "$200 + $300 − $50 deposit")
        XCTAssertEqual(invoice.sourceEstimateId, estimate.id.uuidString)
    }

    func testAnUnpaidDepositIsNotTakenOff() throws {
        let estimate = try makeAcceptedEstimate(items: [("Labor", 1, 300)])
        try EstimateAcceptanceHandler.handleAccepted(estimate: estimate, context: context)
        let job = try XCTUnwrap(estimate.job)
        job.depositAmountCents = 5_000

        let invoice = try JobInvoiceBuilder.makeInvoice(for: job, client: estimate.client, profile: nil, context: context)

        XCTAssertEqual(invoice.totalCents, 30_000)
    }

    func testAJobWithNoEstimateGetsABlankInvoice() throws {
        let job = makeJob()

        let invoice = try JobInvoiceBuilder.makeInvoice(for: job, client: nil, profile: nil, context: context)

        XCTAssertEqual(invoice.items?.count ?? 0, 0)
        XCTAssertTrue(invoice.job === job)
    }
}
