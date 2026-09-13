import XCTest
@testable import SmallBizWorkspace

/// Counting unsynced work.
///
/// The distinction that matters is "waiting" versus "failed": a document queued
/// to upload is normal, one that tried and errored needs the user to know.
final class PortalSyncHealthTests: XCTestCase {

    func testNothingUnsyncedIsHealthy() {
        let health = PortalSyncHealth.tally(messages: [])

        XCTAssertFalse(health.hasFailures)
        XCTAssertEqual(health.failedCount, 0)
        XCTAssertEqual(health.pendingCount, 0)
        XCTAssertNil(health.latestMessage)
    }

    func testQueuedDocumentsAreNotFailures() {
        // No message means it hasn't tried yet, which is not something to alarm
        // the user about.
        let health = PortalSyncHealth.tally(messages: [nil, nil, nil])

        XCTAssertFalse(health.hasFailures)
        XCTAssertEqual(health.pendingCount, 3)
    }

    func testBlankMessagesCountAsPendingNotFailed() {
        // The error field is cleared to "" in places rather than nil.
        let health = PortalSyncHealth.tally(messages: ["", "   ", "\n"])

        XCTAssertFalse(health.hasFailures)
        XCTAssertEqual(health.pendingCount, 3)
        XCTAssertEqual(health.failedCount, 0)
    }

    func testFailuresAreCountedAndSurfaced() {
        let health = PortalSyncHealth.tally(messages: ["Couldn't reach the sync service.", nil])

        XCTAssertTrue(health.hasFailures)
        XCTAssertEqual(health.failedCount, 1)
        XCTAssertEqual(health.pendingCount, 1)
        XCTAssertEqual(health.latestMessage, "Couldn't reach the sync service.")
    }

    func testTheFirstFailureMessageIsShown() {
        let health = PortalSyncHealth.tally(messages: ["first", "second", "third"])

        XCTAssertEqual(health.failedCount, 3)
        XCTAssertEqual(health.latestMessage, "first")
    }

    // MARK: - Copy

    func testSummaryReadsCorrectlyForOne() {
        // "1 documents" is the classic tell that nobody looked at this screen.
        XCTAssertEqual(
            PortalSyncHealth.tally(messages: ["boom"]).summary,
            "1 document didn't sync"
        )
        XCTAssertEqual(
            PortalSyncHealth.tally(messages: [nil]).summary,
            "1 document waiting to sync"
        )
    }

    func testSummaryReadsCorrectlyForMany() {
        XCTAssertEqual(
            PortalSyncHealth.tally(messages: ["a", "b"]).summary,
            "2 documents didn't sync"
        )
        XCTAssertEqual(
            PortalSyncHealth.tally(messages: [nil, nil]).summary,
            "2 documents waiting to sync"
        )
    }

    func testFailuresTakePrecedenceOverPendingInTheSummary() {
        // Nine queued and one failed should report the failure, not the queue.
        let messages: [String?] = Array(repeating: nil, count: 9) + ["boom"]
        let health = PortalSyncHealth.tally(messages: messages)

        XCTAssertEqual(health.summary, "1 document didn't sync")
        XCTAssertEqual(health.pendingCount, 9)
    }

    func testHealthyConstantIsActuallyHealthy() {
        XCTAssertFalse(PortalSyncHealth.healthy.hasFailures)
        XCTAssertEqual(PortalSyncHealth.healthy.failedCount, 0)
    }
}
