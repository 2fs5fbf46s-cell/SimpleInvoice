import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `Job.measurements`, the JSON bridge over `measurementsData` —
/// same idiom as `RecurringInvoiceSchedule.lineItems`/`Expense.categoryRaw`.
///
/// Container is held in a property for the test's lifetime — see
/// `QuickStartQueryTests` for why a container built and discarded in the
/// same expression traps on save.
@MainActor
final class JobMeasurementTests: XCTestCase {

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
        Job(businessID: UUID(), startDate: .now, endDate: .now.addingTimeInterval(3600))
    }

    func testEmptyMeasurementsDataDecodesToEmptyArray() {
        let job = makeJob()
        XCTAssertEqual(job.measurements, [])
    }

    func testMeasurementsRoundTripThroughJSON() {
        let job = makeJob()
        let entries = [
            JobMeasurement(label: "Fence length", value: 200, unit: "ft"),
            JobMeasurement(label: "Gate width", value: 4, unit: "ft")
        ]
        job.measurements = entries

        XCTAssertEqual(job.measurements.count, 2)
        XCTAssertEqual(job.measurements[0].label, "Fence length")
        XCTAssertEqual(job.measurements[0].value, 200)
        XCTAssertEqual(job.measurements[0].unit, "ft")
        XCTAssertEqual(job.measurements[1].label, "Gate width")
        XCTAssertEqual(job.measurements[1].value, 4)
    }

    func testMeasurementsPersistAcrossASaveAndRefetch() throws {
        let job = makeJob()
        job.measurements = [JobMeasurement(label: "Room width", value: 12, unit: "ft")]
        context.insert(job)
        try context.save()

        let jobID = job.id
        let refetched = try XCTUnwrap((try context.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        )).first)

        XCTAssertEqual(refetched.measurements.count, 1)
        XCTAssertEqual(refetched.measurements[0].label, "Room width")
        XCTAssertEqual(refetched.measurements[0].value, 12, accuracy: 0.001)
    }

    func testAppendingThenModifyingAnEntryPersistsCorrectly() throws {
        let job = makeJob()
        context.insert(job)

        job.measurements.append(JobMeasurement(label: "Deck length", value: 10, unit: "ft"))
        try context.save()

        guard var first = job.measurements.first else {
            XCTFail("expected the appended entry")
            return
        }
        first.value = 15
        job.measurements[0] = first
        try context.save()

        let jobID = job.id
        let refetched = try XCTUnwrap((try context.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.id == jobID })
        )).first)

        XCTAssertEqual(refetched.measurements.count, 1)
        XCTAssertEqual(refetched.measurements[0].value, 15, accuracy: 0.001)
        XCTAssertEqual(refetched.measurements[0].label, "Deck length")
    }
}
