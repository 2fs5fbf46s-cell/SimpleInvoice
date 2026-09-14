import Foundation

/// Reading a typed money amount.
///
/// Kept separate and pure because the failure modes are the interesting part:
/// a currency symbol pasted in, a thousands separator, a comma decimal from a
/// non-US keyboard, or nothing at all. None of those should produce a silently
/// wrong invoice.
enum InvoiceAmountParser {

    /// Dollars from whatever the user typed. Never negative, never NaN.
    static func dollars(from text: String) -> Double {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { $0.isNumber || $0 == "." || $0 == "," || $0 == "-" }

        guard !cleaned.isEmpty else { return 0 }

        // A comma is a decimal separator in much of the world, and a thousands
        // separator here. If there is also a dot, the comma is grouping.
        let normalized: String
        if cleaned.contains("."), cleaned.contains(",") {
            normalized = cleaned.replacingOccurrences(of: ",", with: "")
        } else {
            normalized = cleaned.replacingOccurrences(of: ",", with: ".")
        }

        guard let value = Double(normalized), value.isFinite else { return 0 }
        return max(0, value)
    }

    /// Whole cents, which is what the invoice actually charges.
    static func cents(from text: String) -> Int {
        Int((dollars(from: text) * 100).rounded())
    }
}
