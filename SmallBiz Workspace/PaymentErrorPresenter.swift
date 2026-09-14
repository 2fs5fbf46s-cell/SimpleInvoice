import Foundation

/// Turns a payment service failure into something a business owner can act on.
///
/// `PortalPaymentsAPI` builds its errors by passing the server's `error` field
/// straight through, so opening Business Profile or Setup Payments handed the
/// user a modal reading `INVALID_TOKEN` — four of them across two screens, none
/// of which they had asked for.
///
/// `PortalBackendError` already does this mapping for the main API client. This
/// is the same discipline for the payments client, kept pure so the mapping is
/// testable without a network.
enum PaymentErrorPresenter {

    /// Which provider the message is about, so the copy can name it.
    enum Provider: String {
        case stripe = "Stripe"
        case payPal = "PayPal"

        var name: String { rawValue }
    }

    /// Machine codes the backend sends that have a real explanation.
    ///
    /// Anything not listed falls back to generic copy rather than being shown
    /// raw — an unrecognized code is by definition one nobody wrote copy for.
    static func humanize(_ raw: String, provider: Provider) -> String {
        let code = normalizedCode(raw)

        switch code {
        case "INVALID_TOKEN", "MISSING_TOKEN", "REVOKED_TOKEN", "UNAUTHORIZED":
            return "This device isn't signed in for this business yet, so \(provider.name) status can't be checked. Reopen the app, and contact support if it keeps happening."
        case "NOT_CONFIGURED", "MISSING_ENV", "NOT_CONNECTED":
            return "\(provider.name) isn't connected yet. Turn it on here to start setup."
        case "RATE_LIMITED", "TOO_MANY_REQUESTS":
            return "Too many requests to \(provider.name) just now. Wait a moment and try again."
        case "":
            return generic(provider)
        default:
            // A code we have no copy for. Say what happened without quoting it.
            return generic(provider)
        }
    }

    static func generic(_ provider: Provider) -> String {
        "Couldn't check your \(provider.name) status just now. Your settings are unchanged — try again shortly."
    }

    /// True when the text looks like a machine code rather than a sentence.
    ///
    /// Used to decide whether a server message is safe to show as-is: the
    /// backend does send real sentences for some failures, and those are better
    /// than our generic copy.
    static func looksLikeMachineCode(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }

        // Sentences have spaces and lowercase letters; codes are SHOUTY_SNAKE.
        if trimmed.contains(" ") && trimmed.rangeOfCharacter(from: .lowercaseLetters) != nil {
            return false
        }
        return true
    }

    /// The message to display for a raw server string.
    ///
    /// Prefers a real sentence from the server, falls back to mapped copy for a
    /// machine code, and never shows the code itself.
    static func message(forServerText raw: String, provider: Provider) -> String {
        looksLikeMachineCode(raw) ? humanize(raw, provider: provider) : raw
    }

    /// Strip the `[CODE]` suffix `stripeServiceErrorMessage` appends, and
    /// normalize case and whitespace.
    private static func normalizedCode(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if let bracket = text.firstIndex(of: "[") {
            let outside = String(text[text.startIndex..<bracket])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !outside.isEmpty { text = outside }
        }

        return text.uppercased()
    }
}
