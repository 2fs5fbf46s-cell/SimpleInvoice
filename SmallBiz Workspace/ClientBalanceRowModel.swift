import Foundation

enum InsightsCurrency {
    static func normalizedCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 3 else { return nil }
        return trimmed.uppercased()
    }

    static func string(cents: Int, code: String) -> String {
        let amount = Double(max(0, cents)) / 100.0
        return amount.formatted(.currency(code: code))
    }
}
