import XCTest
import UserNotifications
@testable import SmallBizWorkspace

/// The checklist has to reflect reality, or it's the same decoration it replaced.
///
/// These cover `QuickStartChecklist.from`, which is the whole decision — the
/// `fromStoredData` wrapper only turns four SwiftData queries into the four
/// booleans passed here.
final class QuickStartChecklistTests: XCTestCase {

    private func checklist(
        client: Bool = false,
        invoice: Bool = false,
        notifications: Bool = false,
        payments: Bool = false
    ) -> QuickStartChecklist {
        QuickStartChecklist.from(
            hasClient: client,
            hasSentInvoice: invoice,
            notificationsEnabled: notifications,
            hasPaymentMethod: payments
        )
    }

    // MARK: - Empty state

    func testNothingIsCompleteForABrandNewBusiness() {
        let result = checklist()

        XCTAssertEqual(result.completedCount, 0)
        XCTAssertFalse(result.isFullyComplete)
        XCTAssertEqual(result.nextStep, .addClient, "a new user should be pointed at their first client")
    }

    // MARK: - Individual steps

    func testEachFactCompletesOnlyItsOwnStep() {
        XCTAssertEqual(checklist(client: true).completed, [.addClient])
        XCTAssertEqual(checklist(invoice: true).completed, [.sendInvoice])
        XCTAssertEqual(checklist(notifications: true).completed, [.enableNotifications])
        XCTAssertEqual(checklist(payments: true).completed, [.setUpPayments])
    }

    func testCompletedStepsAreReportedAsComplete() {
        let result = checklist(client: true, payments: true)

        XCTAssertTrue(result.isComplete(.addClient))
        XCTAssertTrue(result.isComplete(.setUpPayments))
        XCTAssertFalse(result.isComplete(.sendInvoice))
        XCTAssertFalse(result.isComplete(.enableNotifications))
        XCTAssertEqual(result.completedCount, 2)
    }

    // MARK: - What to do next

    func testNextStepSkipsWhatIsAlreadyDone() {
        XCTAssertEqual(checklist(client: true).nextStep, .sendInvoice)
        XCTAssertEqual(checklist(client: true, invoice: true).nextStep, .enableNotifications)
        XCTAssertEqual(
            checklist(client: true, invoice: true, notifications: true).nextStep,
            .setUpPayments
        )
    }

    func testNextStepFollowsDeclarationOrderNotCompletionOrder() {
        // Someone who set up payments first should still be pointed at the client
        // step, because that is the one that unblocks everything else.
        XCTAssertEqual(checklist(payments: true).nextStep, .addClient)
        XCTAssertEqual(checklist(notifications: true, payments: true).nextStep, .addClient)
    }

    // MARK: - Completion

    func testDoingEverythingCompletesTheChecklist() {
        let result = checklist(client: true, invoice: true, notifications: true, payments: true)

        XCTAssertTrue(result.isFullyComplete)
        XCTAssertEqual(result.completedCount, result.totalCount)
        XCTAssertNil(result.nextStep, "a finished checklist has nothing left to suggest")
    }

    func testPartialProgressIsNotComplete() {
        // The bug this replaced: every row showed an empty circle forever. Progress
        // has to actually move.
        for count in 1..<QuickStartChecklist.Step.allCases.count {
            let steps = Set(QuickStartChecklist.Step.allCases.prefix(count))
            let result = QuickStartChecklist(completed: steps)

            XCTAssertEqual(result.completedCount, count)
            XCTAssertFalse(result.isFullyComplete)
            XCTAssertNotNil(result.nextStep)
        }
    }

    // MARK: - Notification authorization

    func testProvisionalAndEphemeralCountAsEnabled() {
        XCTAssertTrue(QuickStartChecklist.notificationsAreEnabled(status: .authorized))
        XCTAssertTrue(QuickStartChecklist.notificationsAreEnabled(status: .provisional))
        XCTAssertTrue(QuickStartChecklist.notificationsAreEnabled(status: .ephemeral))
    }

    func testDeniedAndUndeterminedDoNotCountAsEnabled() {
        XCTAssertFalse(QuickStartChecklist.notificationsAreEnabled(status: .denied))
        XCTAssertFalse(
            QuickStartChecklist.notificationsAreEnabled(status: .notDetermined),
            "never asking is not the same as being turned on"
        )
    }

    // MARK: - Copy and routing

    func testEveryStepHasCopyAndADestination() {
        for step in QuickStartChecklist.Step.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step.rawValue) needs a title")
            XCTAssertFalse(step.detail.isEmpty, "\(step.rawValue) needs a detail line")
            _ = step.route
        }
    }

    func testStepsAreDistinct() {
        let titles = Set(QuickStartChecklist.Step.allCases.map(\.title))
        XCTAssertEqual(titles.count, QuickStartChecklist.Step.allCases.count)
    }
}
