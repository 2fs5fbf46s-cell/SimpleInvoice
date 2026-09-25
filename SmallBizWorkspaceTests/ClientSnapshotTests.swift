import XCTest
import SwiftData
@testable import SmallBizWorkspace

/// An invoice has to keep saying who it was sent to.
///
/// `Invoice.client` is a plain relationship with no delete rule — exactly one of
/// the schema's 29 relationships has one — so deleting a client left every
/// invoice ever sent to them alive with `client == nil`, rendering with a blank
/// bill-to block. Paid ones included.
///
/// These cover `ClientSnapshotPolicy`, which is the whole decision. The SwiftData
/// half is in `ClientDeletionTests`.
final class ClientSnapshotTests: XCTestCase {

    private let ada = ClientSnapshot(
        name: "Ada Lovelace",
        email: "ada@example.com",
        phone: "555-0100",
        address: "1 Analytical Way"
    )

    private let renamed = ClientSnapshot(
        name: "Ada Byron",
        email: "ada@example.com",
        phone: "555-0100",
        address: "1 Analytical Way"
    )

    // MARK: - Emptiness

    func testASnapshotWithOnlyWhitespaceIsEmpty() {
        XCTAssertTrue(ClientSnapshot().isEmpty)
        XCTAssertTrue(ClientSnapshot(name: "   ", email: "\n").isEmpty)
        XCTAssertFalse(ClientSnapshot(name: "Ada").isEmpty)
        XCTAssertFalse(ClientSnapshot(email: "ada@example.com").isEmpty)
    }

    // MARK: - What to store

    func testADraftTracksTheLiveClient() {
        let next = ClientSnapshotPolicy.snapshotToStore(live: ada, stored: nil, isLocked: false)

        XCTAssertEqual(next, ada)
    }

    func testADraftPicksUpACorrectedName() {
        let next = ClientSnapshotPolicy.snapshotToStore(live: renamed, stored: ada, isLocked: false)

        XCTAssertEqual(next, renamed, "a draft should still reflect edits to the client")
    }

    func testNothingIsWrittenWhenTheStoredCopyAlreadyMatches() {
        XCTAssertNil(
            ClientSnapshotPolicy.snapshotToStore(live: ada, stored: ada, isLocked: false),
            "an unchanged snapshot should not cause a write on every render"
        )
    }

    func testALockedInvoiceNeverOverwritesItsSnapshot() {
        let next = ClientSnapshotPolicy.snapshotToStore(live: renamed, stored: ada, isLocked: true)

        XCTAssertNil(next, "a sent invoice must keep the details it was sent with")
    }

    /// Invoices finalized before this existed have no snapshot at all. A late one
    /// is better than none.
    func testALockedInvoiceWithNoSnapshotIsBackfilled() {
        let next = ClientSnapshotPolicy.snapshotToStore(live: ada, stored: nil, isLocked: true)

        XCTAssertEqual(next, ada)
    }

    func testADeletedClientNeverBlanksAGoodSnapshot() {
        for locked in [true, false] {
            XCTAssertNil(
                ClientSnapshotPolicy.snapshotToStore(live: nil, stored: ada, isLocked: locked),
                "the relationship going nil is exactly when the snapshot matters"
            )
        }
    }

    func testAnEmptiedOutClientNeverBlanksAGoodSnapshot() {
        XCTAssertNil(
            ClientSnapshotPolicy.snapshotToStore(
                live: ClientSnapshot(),
                stored: ada,
                isLocked: false
            )
        )
    }

    // MARK: - What to render

    /// The defect, stated directly.
    func testADeletedClientStillRendersOnASentInvoice() {
        let party = ClientSnapshotPolicy.partyToRender(live: nil, stored: ada, isLocked: true)

        XCTAssertEqual(party?.name, "Ada Lovelace")
        XCTAssertEqual(party?.address, "1 Analytical Way")
    }

    func testADeletedClientStillRendersOnADraft() {
        let party = ClientSnapshotPolicy.partyToRender(live: nil, stored: ada, isLocked: false)

        XCTAssertEqual(party?.name, "Ada Lovelace")
    }

    func testASentInvoicePrefersWhatItRecorded() {
        let party = ClientSnapshotPolicy.partyToRender(live: renamed, stored: ada, isLocked: true)

        XCTAssertEqual(party?.name, "Ada Lovelace", "history does not get rewritten by a rename")
    }

    func testADraftPrefersTheLiveClient() {
        let party = ClientSnapshotPolicy.partyToRender(live: renamed, stored: ada, isLocked: false)

        XCTAssertEqual(party?.name, "Ada Byron")
    }

    func testAnInvoiceThatNeverHadAClientRendersNoParty() {
        XCTAssertNil(ClientSnapshotPolicy.partyToRender(live: nil, stored: nil, isLocked: false))
        XCTAssertNil(ClientSnapshotPolicy.partyToRender(live: nil, stored: nil, isLocked: true))
    }

    // MARK: - Deletion impact

    func testNoHistoryReadsAsNoHistory() {
        let impact = ClientDeletionImpact()

        XCTAssertFalse(impact.hasHistory)
        XCTAssertEqual(impact.summary, "")
        XCTAssertTrue(
            impact.confirmationMessage(clientName: "Ada").contains("no invoices"),
            "the dialog should say plainly that nothing else is affected"
        )
    }

    func testASingleReferenceIsSingular() {
        let impact = ClientDeletionImpact(invoices: 1)

        XCTAssertEqual(impact.summary, "1 invoice")
    }

    func testTwoKindsAreJoinedWithAnd() {
        let impact = ClientDeletionImpact(invoices: 3, jobs: 2)

        XCTAssertEqual(impact.summary, "3 invoices and 2 jobs")
    }

    func testMoreKindsUseCommasAndAreOrderedBySize() {
        let impact = ClientDeletionImpact(invoices: 4, estimates: 9, jobs: 2)

        XCTAssertEqual(impact.summary, "9 estimates, 4 invoices, and 2 jobs")
    }

    func testTheConfirmationNamesWhatIsAtStake() {
        let impact = ClientDeletionImpact(invoices: 12, contracts: 1)
        let message = impact.confirmationMessage(clientName: "  Ada Lovelace  ")

        XCTAssertTrue(message.contains("Ada Lovelace"))
        XCTAssertTrue(message.contains("12 invoices"))
        XCTAssertTrue(message.contains("1 contract"))
        XCTAssertTrue(
            message.contains("keep the name and address they were sent with"),
            "the dialog should say the documents survive intact, because now they do"
        )
    }

    func testANamelessClientStillReadsSensibly() {
        let message = ClientDeletionImpact(invoices: 1).confirmationMessage(clientName: "   ")

        XCTAssertTrue(message.contains("this client"))
        XCTAssertFalse(message.contains("  is referenced"))
    }

    func testTotalCountsEveryKind() {
        let impact = ClientDeletionImpact(
            invoices: 1, estimates: 2, jobs: 3, contracts: 4
        )

        XCTAssertEqual(impact.total, 10)
        XCTAssertTrue(impact.hasHistory)
    }
}
