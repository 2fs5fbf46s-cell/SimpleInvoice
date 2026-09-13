import XCTest
@testable import SmallBizWorkspace

/// Poll pacing.
///
/// Getting this wrong produces a battery complaint nobody can reproduce, so the
/// rules are pinned rather than left to inspection.
final class EstimatePollScheduleTests: XCTestCase {

    // MARK: - Nothing to watch

    func testIdlesWhenNothingIsAwaitingADecision() {
        let interval = EstimatePollSchedule.nextInterval(candidates: 0, consecutiveFailures: 0)

        XCTAssertEqual(interval, EstimatePollSchedule.idleInterval)
        XCTAssertGreaterThan(
            interval,
            EstimatePollSchedule.activeInterval,
            "a device with no outstanding estimates must poll less than one that has them"
        )
    }

    func testFailuresDoNotSpeedUpAnIdleDevice() {
        // Backoff only applies when there is something to back off from.
        for failures in 0...5 {
            XCTAssertEqual(
                EstimatePollSchedule.nextInterval(candidates: 0, consecutiveFailures: failures),
                EstimatePollSchedule.idleInterval
            )
        }
    }

    // MARK: - Healthy polling

    func testPollsAtTheActiveRateWhileHealthy() {
        XCTAssertEqual(
            EstimatePollSchedule.nextInterval(candidates: 1, consecutiveFailures: 0),
            EstimatePollSchedule.activeInterval
        )
        XCTAssertEqual(
            EstimatePollSchedule.nextInterval(candidates: 25, consecutiveFailures: 0),
            EstimatePollSchedule.activeInterval,
            "the rate should not depend on how many estimates are outstanding"
        )
    }

    // MARK: - Backoff

    func testEachFailureDoublesTheWait() {
        let base = EstimatePollSchedule.activeInterval

        XCTAssertEqual(EstimatePollSchedule.nextInterval(candidates: 1, consecutiveFailures: 1), base * 2)
        XCTAssertEqual(EstimatePollSchedule.nextInterval(candidates: 1, consecutiveFailures: 2), base * 4)
        XCTAssertEqual(EstimatePollSchedule.nextInterval(candidates: 1, consecutiveFailures: 3), base * 8)
    }

    func testBackoffIsCapped() {
        // A long outage should settle at the ceiling, not escalate forever.
        for failures in 4...200 {
            XCTAssertEqual(
                EstimatePollSchedule.nextInterval(candidates: 1, consecutiveFailures: failures),
                EstimatePollSchedule.maxInterval,
                "failure count \(failures) should be capped"
            )
        }
    }

    func testBackoffIsAlwaysFiniteAndPositive() {
        // Guards the exponent clamp: an unclamped shift overflows on a long outage.
        for failures in 0...1000 {
            let interval = EstimatePollSchedule.nextInterval(candidates: 3, consecutiveFailures: failures)
            XCTAssertTrue(interval.isFinite)
            XCTAssertGreaterThan(interval, 0)
            XCTAssertLessThanOrEqual(interval, EstimatePollSchedule.maxInterval)
        }
    }

    func testRecoveryReturnsToTheActiveRateImmediately() {
        // The caller resets the counter on a good pass; one success is enough.
        XCTAssertEqual(
            EstimatePollSchedule.nextInterval(candidates: 1, consecutiveFailures: 0),
            EstimatePollSchedule.activeInterval
        )
    }

    // MARK: - Outcome

    func testLooksOfflineOnlyWhenEverythingFailed() {
        XCTAssertTrue(
            EstimateSyncOutcome(candidates: 3, updated: 0, failed: 3).looksOffline
        )
        XCTAssertFalse(
            EstimateSyncOutcome(candidates: 3, updated: 1, failed: 2).looksOffline,
            "a partial failure is one bad estimate, not a dead network"
        )
        XCTAssertFalse(
            EstimateSyncOutcome(candidates: 0, updated: 0, failed: 0).looksOffline,
            "nothing attempted is not an outage"
        )
    }

    func testAnEmptyOutcomeIsIdle() {
        let outcome = EstimateSyncOutcome.none

        XCTAssertEqual(outcome.candidates, 0)
        XCTAssertFalse(outcome.looksOffline)
        XCTAssertEqual(
            EstimatePollSchedule.nextInterval(
                candidates: outcome.candidates,
                consecutiveFailures: 0
            ),
            EstimatePollSchedule.idleInterval
        )
    }
}
