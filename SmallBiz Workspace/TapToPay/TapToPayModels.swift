//
//  TapToPayModels.swift
//  SmallBiz Workspace
//

import Foundation

/// The business address in the parts Stripe needs for a Terminal location,
/// which sets the reader up for its region.
struct TapToPayAddress: Equatable, Codable {
    var line1 = ""
    var line2 = ""
    var city = ""
    var state = ""
    var postalCode = ""
    var country = "US"

    var isComplete: Bool {
        [line1, city, state, postalCode].allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Reads the profile's one-line address — "1 Main St, Columbia, SC 29201",
    /// as onboarding writes it — or the same split across lines. Nil when it
    /// isn't a full US street address; setup then asks for it.
    static func parse(_ text: String) -> TapToPayAddress? {
        var parts = text
            .components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let last = parts.last, ["us", "usa", "u.s.", "u.s.a.", "united states", "united states of america"].contains(last.lowercased()) {
            parts.removeLast()
        }
        guard let tail = parts.popLast() else { return nil }

        var state = ""
        var postalCode = ""
        if let match = tail.wholeMatch(of: /([A-Za-z][A-Za-z .]*?)\s+(\d{5}(?:-\d{4})?)/) {
            state = String(match.1)
            postalCode = String(match.2)
        } else if tail.wholeMatch(of: /\d{5}(?:-\d{4})?/) != nil, let named = parts.popLast() {
            state = named
            postalCode = tail
        } else {
            return nil
        }
        guard let code = stateCode(state), parts.count >= 2 else { return nil }

        let city = parts.removeLast()
        let line1 = parts.removeFirst()
        return TapToPayAddress(line1: line1, line2: parts.joined(separator: ", "), city: city, state: code, postalCode: postalCode)
    }

    /// "SC", "sc" or "South Carolina" → "SC".
    static func stateCode(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.count == 2, statesByCode[trimmed.uppercased()] != nil { return trimmed.uppercased() }
        return statesByCode.first { $0.value.caseInsensitiveCompare(trimmed) == .orderedSame }?.key
    }

    static let statesByCode: [String: String] = [
        "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California",
        "CO": "Colorado", "CT": "Connecticut", "DE": "Delaware", "DC": "District of Columbia",
        "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
        "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana",
        "ME": "Maine", "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
        "MS": "Mississippi", "MO": "Missouri", "MT": "Montana", "NE": "Nebraska", "NV": "Nevada",
        "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
        "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
        "PA": "Pennsylvania", "PR": "Puerto Rico", "RI": "Rhode Island", "SC": "South Carolina",
        "SD": "South Dakota", "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
        "VA": "Virginia", "WA": "Washington", "WV": "West Virginia", "WI": "Wisconsin", "WY": "Wyoming",
    ]
}

/// What's charged at the counter. Same tip rules as paying online: only on
/// the payment that settles the invoice, and only when tips are on.
enum TapToPayCharge {
    static let tipPercents = [10, 15, 20]

    static func allowsTip(amountCents: Int, balanceDueCents: Int, tipsEnabled: Bool) -> Bool {
        tipsEnabled && amountCents > 0 && amountCents == balanceDueCents
    }

    /// A percentage of what's being paid, rounded to the nearest cent.
    static func tipCents(percent: Int, of amountCents: Int) -> Int {
        (amountCents * percent + 50) / 100
    }
}

/// A receipt for one tap, approved or declined. Card shown by brand and last
/// four digits only.
struct TapToPayReceipt: Equatable {
    var businessName: String
    var invoiceNumber: String
    var amountCents: Int
    var tipCents: Int
    var currencyCode: String
    var card: String?
    var date: Date
    var approved: Bool
    var receiptURL: URL?

    var totalCents: Int { amountCents + tipCents }

    /// "Visa •••• 4242", from Stripe's "visa" / "visa (apple pay)".
    static func cardDescription(brand: String?, last4: String?) -> String? {
        guard let last4, !last4.isEmpty else { return nil }
        let name = (brand ?? "Card")
            .split(separator: " ")
            .map { word -> String in
                let lower = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                switch lower {
                case "amex", "american_express": return "American Express"
                case "mastercard": return "Mastercard"
                default: return word.capitalized
                }
            }
            .joined(separator: " ")
        return "\(name) •••• \(last4)"
    }

    var text: String {
        func money(_ cents: Int) -> String {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.currencyCode = currencyCode
            return formatter.string(from: NSNumber(value: Double(cents) / 100)) ?? "\(cents)"
        }
        var lines = [
            businessName,
            date.formatted(date: .abbreviated, time: .shortened),
            "",
            approved ? "Payment approved" : "Payment declined — you were not charged",
            invoiceNumber.isEmpty ? nil : "Invoice \(invoiceNumber)",
        ].compactMap { $0 }
        if tipCents > 0 {
            lines += ["Amount: \(money(amountCents))", "Tip: \(money(tipCents))"]
        }
        lines.append("Total: \(money(totalCents))")
        if let card { lines.append(card) }
        if approved, let receiptURL { lines += ["", "Receipt: \(receiptURL.absoluteString)"] }
        return lines.joined(separator: "\n")
    }
}

/// How one tap ended.
enum TapToPayOutcome: Equatable {
    case approved(TapToPayReceipt)
    case declined(TapToPayReceipt, reason: String)
    case timedOut
    case canceled
    case failed(String)
}
