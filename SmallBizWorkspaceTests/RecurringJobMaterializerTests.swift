import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `RecurringJobMaterializer`'s chain-handoff model: the recurrence
/// rule lives on whichever Job is currently due, and materializing hands it
/// to the newly created Job rather than keeping a separate schedule object.
@MainActor
final class RecurringJobMaterializerTests: XCTestCase {

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

    private func makeJob(businessID: UUID, title: String = "Lawn mowing", start: Date, end: Date? = nil) -> Job {
        Job(businessID: businessID, title: title, startDate: start, endDate: end ?? start.addingTimeInterval(3600))
    }

    func testDueOccurrenceCreatesTheNextJobAndHandsOffTheChain() throws {
        let businessID = UUID()
        let pastStart = Date().addingTimeInterval(-14 * 86400)
        let job = makeJob(businessID: businessID, start: pastStart)
        job.recurringCadence = .biweekly
        // Due yesterday.
        job.recurringNextOccurrenceAt = Date().addingTimeInterval(-86400)
        context.insert(job)
        try context.save()

        RecurringJobMaterializer.materializeDueOccurrences(context: context, businessID: businessID)

        let all = try context.fetch(FetchDescriptor<Job>(predicate: #Predicate<Job> { $0.businessID == businessID }))
        XCTAssertEqual(all.count, 2, "the original plus one generated occurrence")

        // The original is now history: chain handed off.
        XCTAssertNil(job.recurringCadence)
        XCTAssertNil(job.recurringNextOccurrenceAt)

        let generated = try XCTUnwrap(all.first { $0.id != job.id })
        XCTAssertEqual(generated.recurringParentJobID, job.id)
        XCTAssertEqual(generated.recurringCadence, .biweekly)
        XCTAssertEqual(generated.title, "Lawn mowing")
        XCTAssertNotNil(generated.recurringNextOccurrenceAt)
        // The chain keeps moving: the new job's own next date is another
        // biweekly step past the occurrence that was just generated.
        if let generatedNext = generated.recurringNextOccurrenceAt, let generatedStart = generated.startDate as Date? {
            XCTAssertGreaterThan(generatedNext, generatedStart)
        }
    }

    func testGeneratedJobDoesNotCarryForwardLocationOrMeasurements() throws {
        let businessID = UUID()
        let job = makeJob(businessID: businessID, start: Date().addingTimeInterval(-14 * 86400))
        job.latitude = 37.33
        job.longitude = -122.03
        job.measurements = [JobMeasurement(label: "Fence length", value: 200, unit: "ft")]
        job.recurringCadence = .weekly
        job.recurringNextOccurrenceAt = Date().addingTimeInterval(-3600)
        context.insert(job)
        try context.save()

        RecurringJobMaterializer.materializeDueOccurrences(context: context, businessID: businessID)

        let all = try context.fetch(FetchDescriptor<Job>(predicate: #Predicate<Job> { $0.businessID == businessID }))
        let generated = try XCTUnwrap(all.first { $0.id != job.id })

        XCTAssertNil(generated.latitude)
        XCTAssertNil(generated.longitude)
        XCTAssertTrue(generated.measurements.isEmpty)
    }

    func testNotDueYetDoesNothing() throws {
        let businessID = UUID()
        let job = makeJob(businessID: businessID, start: Date())
        job.recurringCadence = .monthly
        job.recurringNextOccurrenceAt = Date().addingTimeInterval(30 * 86400) // future
        context.insert(job)
        try context.save()

        RecurringJobMaterializer.materializeDueOccurrences(context: context, businessID: businessID)

        let all = try context.fetch(FetchDescriptor<Job>(predicate: #Predicate<Job> { $0.businessID == businessID }))
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(job.recurringCadence, .monthly, "still repeating, not yet due")
    }

    func testNonRecurringJobsAreIgnored() throws {
        let businessID = UUID()
        let job = makeJob(businessID: businessID, start: Date().addingTimeInterval(-86400))
        context.insert(job)
        try context.save()

        RecurringJobMaterializer.materializeDueOccurrences(context: context, businessID: businessID)

        let all = try context.fetch(FetchDescriptor<Job>(predicate: #Predicate<Job> { $0.businessID == businessID }))
        XCTAssertEqual(all.count, 1)
    }

    func testRunningTwiceDoesNotDuplicateAnAlreadyGeneratedOccurrence() throws {
        let businessID = UUID()
        let job = makeJob(businessID: businessID, start: Date().addingTimeInterval(-14 * 86400))
        job.recurringCadence = .biweekly
        job.recurringNextOccurrenceAt = Date().addingTimeInterval(-86400)
        context.insert(job)
        try context.save()

        RecurringJobMaterializer.materializeDueOccurrences(context: context, businessID: businessID)
        RecurringJobMaterializer.materializeDueOccurrences(context: context, businessID: businessID)

        let all = try context.fetch(FetchDescriptor<Job>(predicate: #Predicate<Job> { $0.businessID == businessID }))
        XCTAssertEqual(all.count, 2, "second run must not create a duplicate")
    }

    func testStoppingRecurrenceClearsTheCadence() {
        let job = makeJob(businessID: UUID(), start: Date())
        job.recurringCadence = .weekly
        job.recurringNextOccurrenceAt = Date().addingTimeInterval(7 * 86400)

        job.recurringCadence = nil
        XCTAssertNil(job.recurringCadenceRaw)
        XCTAssertNil(job.recurringCadence)
    }
}
