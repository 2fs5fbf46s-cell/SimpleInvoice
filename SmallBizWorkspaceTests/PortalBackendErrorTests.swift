import XCTest
@testable import SmallBizWorkspace

/// What the business owner reads when a request fails.
///
/// Most failures are transient and the status-code copy is right. A few are not:
/// a deposit above the booking total, or an edit to a contract somebody already
/// signed, will fail identically forever. Those used to land on "try again
/// shortly" and "someone else changed this first" — copy that sends the user off
/// to wait for something that is never going to happen.
final class PortalBackendErrorTests: XCTestCase {

    private func message(status: Int, body: String) -> String? {
        PortalBackendError.http(status, body: body, path: "/api/test").errorDescription
    }

    private func serverBody(error: String, message: String) -> String {
        #"{"ok":false,"error":"\#(error)","message":"\#(message)"}"#
    }

    // MARK: - The cases the server explains better

    func testADepositAboveTheTotalShowsTheServersExplanation() {
        let explanation = "A deposit of $5000.00 is more than the booking total of $200.00. Lower the deposit, or raise the booking total first."

        let shown = message(
            status: 400,
            body: serverBody(error: "DEPOSIT_EXCEEDS_TOTAL", message: explanation)
        )

        XCTAssertEqual(shown, explanation)
    }

    func testASignedContractEditShowsWhyItWasRefused() {
        let explanation = "This contract has been signed. Its text can no longer be changed."

        let shown = message(
            status: 409,
            body: serverBody(error: "CONTRACT_SIGNED_BODY_LOCKED", message: explanation)
        )

        XCTAssertEqual(
            shown, explanation,
            "409 otherwise reads 'someone else changed this first', which is not what happened"
        )
    }

    func testEveryActionableCodeIsSurfaced() {
        for code in PortalBackendError.actionableServerErrors {
            let shown = message(
                status: 400,
                body: serverBody(error: code, message: "Specific explanation for \(code).")
            )
            XCTAssertEqual(shown, "Specific explanation for \(code).", "\(code) was not surfaced")
        }
    }

    /// The point of the change: none of these tell the user to wait.
    func testAnActionableFailureNeverSaysToTryAgain() {
        let shown = message(
            status: 400,
            body: serverBody(error: "DEPOSIT_EXCEEDS_TOTAL", message: "Lower the deposit first.")
        ) ?? ""

        XCTAssertFalse(shown.lowercased().contains("try again"))
        XCTAssertFalse(shown.lowercased().contains("shortly"))
    }

    // MARK: - Everything else keeps the generic copy

    func testAnUnrecognizedErrorCodeFallsBackToTheStatusCopy() {
        let shown = message(
            status: 400,
            body: serverBody(error: "SOMETHING_ELSE", message: "Internal detail nobody should read.")
        )

        XCTAssertNotEqual(shown, "Internal detail nobody should read.")
        XCTAssertEqual(shown, "Couldn't complete that just now. Your work is saved on this device — try again shortly.")
    }

    /// An allowlist, not "show whatever arrives". A message from a route that made
    /// no promise about its wording should not reach the UI.
    func testAnArbitraryServerMessageIsNotShown() {
        let shown = message(status: 500, body: #"{"message":"TypeError: undefined is not a function"}"#)

        XCTAssertFalse(shown?.contains("TypeError") ?? false)
    }

    func testAnActionableCodeWithNoMessageFallsBack() {
        let shown = message(status: 400, body: #"{"error":"DEPOSIT_EXCEEDS_TOTAL"}"#)

        XCTAssertEqual(shown, "Couldn't complete that just now. Your work is saved on this device — try again shortly.")
    }

    func testAnEmptyMessageFallsBack() {
        let shown = message(
            status: 400,
            body: serverBody(error: "DEPOSIT_EXCEEDS_TOTAL", message: "   ")
        )

        XCTAssertEqual(shown, "Couldn't complete that just now. Your work is saved on this device — try again shortly.")
    }

    func testANonJSONBodyIsIgnoredRatherThanShown() {
        for body in ["", "<html>502 Bad Gateway</html>", "not json at all"] {
            let shown = message(status: 502, body: body)
            XCTAssertEqual(
                shown,
                "The sync service is having trouble. Your work is saved on this device — try again shortly.",
                "body \(body.isEmpty ? "<empty>" : body) should not change the copy"
            )
        }
    }

    func testTheOrdinaryStatusCodesKeepTheirCopy() {
        XCTAssertEqual(
            message(status: 401, body: "{}"),
            "This device is no longer signed in for this business. Reopen the app to sign in again."
        )
        XCTAssertEqual(
            message(status: 429, body: "{}"),
            "Too many requests just now. Wait a moment and try again."
        )
        XCTAssertEqual(
            message(status: 409, body: "{}"),
            "Someone else changed this first. Reopen it to see the latest version."
        )
    }

    // MARK: - Diagnostics

    /// The raw body still has to reach the log, just never the screen.
    func testTheRawBodyStaysInTheDiagnosticDescription() {
        let error = PortalBackendError.http(400, body: #"{"error":"X","detail":"internals"}"#, path: "/api/test")

        XCTAssertTrue(error.diagnosticDescription.contains("internals"))
        XCTAssertTrue(error.diagnosticDescription.contains("/api/test"))
        XCTAssertFalse(error.errorDescription?.contains("internals") ?? false)
    }
}
