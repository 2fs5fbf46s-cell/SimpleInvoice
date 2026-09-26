import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// `JobAppointmentReminderEligibility` — the pure predicate that decides
/// whether a Job qualifies for the backend's 24h-before reminder email.
@MainActor
final class JobAppointmentReminderTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }
    private let businessID = UUID()

    override func setUpWithError() throws {
        try super.setUpWithError()
        container = try AppModelContainerFactory.makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        try super.tearDownWithError()
    }

    private func makeJob(needsScheduling: Bool = false) -> Job {
        let start = Date().addingTimeInterval(86400)
        let job = Job(businessID: businessID, title: "Fence install", startDate: start, endDate: start.addingTimeInterval(3600))
        job.needsScheduling = needsScheduling
        return job
    }

    private func makeClient(email: String = "client@example.com") -> Client {
        Client(businessID: businessID, name: "Jane Client", email: email)
    }

    func testAJobWithAClientAndAConfirmedDateIsEligible() {
        XCTAssertTrue(JobAppointmentReminderEligibility.isEligible(job: makeJob(), client: makeClient()))
    }

    func testAJobStillWaitingToBeScheduledIsNotEligible() {
        XCTAssertFalse(JobAppointmentReminderEligibility.isEligible(job: makeJob(needsScheduling: true), client: makeClient()))
    }

    func testAJobWithNoClientIsNotEligible() {
        XCTAssertFalse(JobAppointmentReminderEligibility.isEligible(job: makeJob(), client: nil))
    }

    func testAClientWithNoEmailIsNotEligible() {
        XCTAssertFalse(JobAppointmentReminderEligibility.isEligible(job: makeJob(), client: makeClient(email: "")))
        XCTAssertFalse(JobAppointmentReminderEligibility.isEligible(job: makeJob(), client: makeClient(email: "   ")))
    }
}
