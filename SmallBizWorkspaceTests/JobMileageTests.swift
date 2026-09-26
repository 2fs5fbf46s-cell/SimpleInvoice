import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// Covers `JobMileage`'s distance/previous-job math and the
/// `Expense.mileage*` fields it feeds into.
@MainActor
final class JobMileageTests: XCTestCase {

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

    private func makeJob(
        title: String = "Job",
        daysFromNow: Double,
        lat: Double? = nil,
        lon: Double? = nil,
        needsScheduling: Bool = false,
        businessID: UUID
    ) -> Job {
        let start = Date().addingTimeInterval(daysFromNow * 86400)
        let job = Job(businessID: businessID, title: title, startDate: start, endDate: start.addingTimeInterval(3600))
        job.latitude = lat
        job.longitude = lon
        job.needsScheduling = needsScheduling
        return job
    }

    // MARK: - miles(from:to:)

    func testMilesReturnsNilWhenEitherJobHasNoLocation() {
        let biz = UUID()
        let a = makeJob(daysFromNow: -1, businessID: biz)
        let b = makeJob(daysFromNow: 0, lat: 37.33, lon: -122.03, businessID: biz)
        XCTAssertNil(JobMileage.miles(from: a, to: b))
        XCTAssertNil(JobMileage.miles(from: b, to: a))
    }

    func testMilesComputesRealDistanceBetweenTwoKnownPoints() {
        let biz = UUID()
        // Apple Park to Cupertino City Hall — roughly 1.4 mi apart.
        let a = makeJob(daysFromNow: -1, lat: 37.3349, lon: -122.0090, businessID: biz)
        let b = makeJob(daysFromNow: 0, lat: 37.3229, lon: -122.0322, businessID: biz)

        let miles = try! XCTUnwrap(JobMileage.miles(from: a, to: b))
        XCTAssertGreaterThan(miles, 1.0)
        XCTAssertLessThan(miles, 3.0)
    }

    // MARK: - previousJob(before:in:)

    func testPreviousJobFindsTheClosestEarlierJobWithALocation() {
        let biz = UUID()
        let target = makeJob(title: "Target", daysFromNow: 0, lat: 37.0, lon: -122.0, businessID: biz)
        let tooOld = makeJob(title: "Too old", daysFromNow: -5, lat: 1, lon: 1, businessID: biz)
        let closest = makeJob(title: "Closest", daysFromNow: -1, lat: 2, lon: 2, businessID: biz)
        let noLocation = makeJob(title: "No location", daysFromNow: -0.5, businessID: biz)

        let jobs = [target, tooOld, closest, noLocation]
        let previous = JobMileage.previousJob(before: target, in: jobs)

        XCTAssertEqual(previous?.title, "Closest")
    }

    func testPreviousJobExcludesJobsThatStillNeedScheduling() {
        let biz = UUID()
        let target = makeJob(daysFromNow: 0, lat: 0, lon: 0, businessID: biz)
        let placeholder = makeJob(daysFromNow: -1, lat: 5, lon: 5, needsScheduling: true, businessID: biz)

        XCTAssertNil(JobMileage.previousJob(before: target, in: [target, placeholder]))
    }

    func testPreviousJobExcludesLaterJobsAndItself() {
        let biz = UUID()
        let target = makeJob(daysFromNow: 0, lat: 0, lon: 0, businessID: biz)
        let later = makeJob(daysFromNow: 1, lat: 5, lon: 5, businessID: biz)

        XCTAssertNil(JobMileage.previousJob(before: target, in: [target, later]))
    }

    // MARK: - estimatedDeductionCents

    func testEstimatedDeductionUsesTheGivenRate() {
        XCTAssertEqual(JobMileage.estimatedDeductionCents(miles: 10, ratePerMileCents: 70), 700)
        XCTAssertEqual(JobMileage.estimatedDeductionCents(miles: 12.4, ratePerMileCents: 70), 868)
    }

    func testEstimatedDeductionDefaultsToTheCurrentIRSRate() {
        XCTAssertEqual(
            JobMileage.estimatedDeductionCents(miles: 1),
            IRSMileageRate.currentCentsPerMile
        )
    }

    // MARK: - Expense fields this feeds

    func testMileageExpenseFieldsPersistAcrossASaveAndRefetch() throws {
        let businessID = UUID()
        let fromJobID = UUID()
        let expense = Expense(businessID: businessID, amountCents: 868, category: .mileage, jobID: UUID())
        expense.mileageMiles = 12.4
        expense.mileageRateCentsPerMile = 70
        expense.mileageFromJobID = fromJobID
        context.insert(expense)
        try context.save()

        let expenseID = expense.id
        let refetched = try XCTUnwrap((try context.fetch(
            FetchDescriptor<Expense>(predicate: #Predicate { $0.id == expenseID })
        )).first)

        XCTAssertEqual(refetched.category, .mileage)
        XCTAssertEqual(refetched.mileageMiles ?? 0, 12.4, accuracy: 0.001)
        XCTAssertEqual(refetched.mileageRateCentsPerMile, 70)
        XCTAssertEqual(refetched.mileageFromJobID, fromJobID)
    }

    func testMileageIsAValidExpenseCategoryWithDisplayNameAndIcon() {
        XCTAssertEqual(ExpenseCategory.mileage.displayName, "Mileage")
        XCTAssertFalse(ExpenseCategory.mileage.systemImage.isEmpty)
        XCTAssertTrue(ExpenseCategory.allCases.contains(.mileage))
    }
}
