import XCTest
@testable import SmallBizWorkspace

/// What a business owner reads when a payment status check fails.
///
/// `PortalPaymentsAPI` built its errors by passing the server's `error` field
/// straight through, so opening Business Profile or Setup Payments produced a
/// modal reading `INVALID_TOKEN` — four of them across two screens, none of them
/// prompted by anything the user did.
final class PaymentErrorPresenterTests: XCTestCase {

    // MARK: - Machine codes never reach the user

    func testTheCodeItselfIsNeverShown() {
        for code in ["INVALID_TOKEN", "MISSING_TOKEN", "REVOKED_TOKEN", "UNAUTHORIZED",
                     "NOT_CONFIGURED", "RATE_LIMITED", "SOMETHING_WE_HAVE_NO_COPY_FOR"] {
            let shown = PaymentErrorPresenter.message(forServerText: code, provider: .stripe)

            XCTAssertFalse(
                shown.contains(code),
                "\(code) reached the user verbatim"
            )
            XCTAssertFalse(shown.contains("_"), "\(code) leaked machine formatting")
        }
    }

    func testAnUnknownCodeFallsBackToGenericCopy() {
        let shown = PaymentErrorPresenter.message(forServerText: "WEIRD_NEW_CODE", provider: .payPal)

        XCTAssertEqual(shown, PaymentErrorPresenter.generic(.payPal))
    }

    func testTheBracketedCodeSuffixIsStripped() {
        // `stripeServiceErrorMessage` formats as "ERROR [CODE]".
        let shown = PaymentErrorPresenter.humanize("INVALID_TOKEN [401]", provider: .stripe)

        XCTAssertTrue(shown.contains("isn't signed in"))
        XCTAssertFalse(shown.contains("401"))
    }

    func testCaseAndWhitespaceDoNotDefeatTheMapping() {
        let expected = PaymentErrorPresenter.humanize("INVALID_TOKEN", provider: .stripe)

        XCTAssertEqual(PaymentErrorPresenter.humanize("  invalid_token  ", provider: .stripe), expected)
        XCTAssertEqual(PaymentErrorPresenter.humanize("Invalid_Token", provider: .stripe), expected)
    }

    // MARK: - The copy names the provider

    func testTheMessageNamesTheProvider() {
        XCTAssertTrue(
            PaymentErrorPresenter.humanize("INVALID_TOKEN", provider: .stripe).contains("Stripe")
        )
        XCTAssertTrue(
            PaymentErrorPresenter.humanize("INVALID_TOKEN", provider: .payPal).contains("PayPal")
        )
    }

    func testGenericCopySaysNothingWasChanged() {
        let shown = PaymentErrorPresenter.generic(.stripe)

        XCTAssertTrue(
            shown.contains("unchanged"),
            "a failed read must reassure the user it changed nothing"
        )
    }

    // MARK: - Real sentences from the server are preferred

    /// The backend does send human copy for some failures, and it is more
    /// specific than our fallback. The presenter should not flatten it.
    func testARealSentenceFromTheServerIsShownAsIs() {
        let sentence = "Your Stripe account needs more information before payouts can start."

        XCTAssertEqual(
            PaymentErrorPresenter.message(forServerText: sentence, provider: .stripe),
            sentence
        )
    }

    func testMachineCodeDetection() {
        XCTAssertTrue(PaymentErrorPresenter.looksLikeMachineCode("INVALID_TOKEN"))
        XCTAssertTrue(PaymentErrorPresenter.looksLikeMachineCode("NOT_FOUND"))
        XCTAssertTrue(PaymentErrorPresenter.looksLikeMachineCode(""))
        XCTAssertTrue(PaymentErrorPresenter.looksLikeMachineCode("   "))
        XCTAssertFalse(PaymentErrorPresenter.looksLikeMachineCode("Something went wrong here."))
        XCTAssertFalse(PaymentErrorPresenter.looksLikeMachineCode("Your account needs review"))
    }

    func testAnEmptyServerStringStillProducesUsableCopy() {
        let shown = PaymentErrorPresenter.message(forServerText: "", provider: .payPal)

        XCTAssertFalse(shown.isEmpty)
        XCTAssertEqual(shown, PaymentErrorPresenter.generic(.payPal))
    }

    // MARK: - The error type itself

    func testTheServiceErrorMapsItsMessage() {
        let error = PaymentServiceResponseError(
            message: "INVALID_TOKEN",
            details: #"{"error":"INVALID_TOKEN"}"#,
            provider: .payPal
        )

        let shown = error.errorDescription ?? ""
        XCTAssertFalse(shown.contains("INVALID_TOKEN"))
        XCTAssertTrue(shown.contains("PayPal"))
    }

    /// The raw text still has to reach a log, just never the screen.
    func testTheRawTextSurvivesInDiagnostics() {
        let error = PaymentServiceResponseError(
            message: "INVALID_TOKEN",
            details: #"{"error":"INVALID_TOKEN","hint":"internals"}"#,
            provider: .stripe
        )

        XCTAssertTrue(error.diagnosticDescription.contains("INVALID_TOKEN"))
        XCTAssertTrue(error.diagnosticDescription.contains("internals"))
        XCTAssertFalse(error.errorDescription?.contains("internals") ?? false)
    }
}
