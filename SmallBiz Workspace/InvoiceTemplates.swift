import Foundation

enum InvoiceTemplateKey: String, CaseIterable, Identifiable {
    case classic_business
    case modern_clean
    case bold_header
    case minimal_compact
    case creative_studio
    case contractor_trades

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic_business:
            return "Classic Business"
        case .modern_clean:
            return "Modern Clean"
        case .bold_header:
            return "Bold Header"
        case .minimal_compact:
            return "Minimal Compact"
        case .creative_studio:
            return "Creative Studio"
        case .contractor_trades:
            return "Contractor Trades"
        }
    }

    var shortDescription: String {
        switch self {
        case .classic_business:
            return "Traditional, familiar invoice styling."
        case .modern_clean:
            return "Balanced spacing and clean visual hierarchy."
        case .bold_header:
            return "High-contrast header treatment for emphasis."
        case .minimal_compact:
            return "Tight layout optimized for concise invoices."
        case .creative_studio:
            return "Expressive layout for design-forward businesses."
        case .contractor_trades:
            return "Structured sections tailored for field work."
        }
    }

    static func from(_ raw: String?) -> InvoiceTemplateKey? {
        guard let raw,
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return InvoiceTemplateKey(rawValue: raw)
    }
}
