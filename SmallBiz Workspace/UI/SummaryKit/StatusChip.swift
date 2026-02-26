import SwiftUI

extension SummaryKit {
struct StatusChip: View {
    enum Kind {
        case disabled
        case draft
        case pending
        case active
        case paid
        case unpaid
        case signed
        case overdue
        case error
        case custom(String)

        init(text: String) {
            let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            switch key {
            case "disabled": self = .disabled
            case "draft": self = .draft
            case "pending": self = .pending
            case "active": self = .active
            case "paid": self = .paid
            case "unpaid": self = .unpaid
            case "signed": self = .signed
            case "overdue": self = .overdue
            case "error", "failed": self = .error
            default: self = .custom(text)
            }
        }

        var label: String {
            switch self {
            case .disabled: return "DISABLED"
            case .draft: return "DRAFT"
            case .pending: return "PENDING"
            case .active: return "ACTIVE"
            case .paid: return "PAID"
            case .unpaid: return "UNPAID"
            case .signed: return "SIGNED"
            case .overdue: return "OVERDUE"
            case .error: return "ERROR"
            case .custom(let value): return value.uppercased()
            }
        }

        var colors: (fg: Color, bg: Color) {
            switch self {
            case .disabled:
                return (.secondary, Color.primary.opacity(0.08))
            case .pending:
                return (Color.orange, Color.orange.opacity(0.12))
            case .active:
                return (SBWTheme.brandGreen, SBWTheme.brandGreen.opacity(0.12))
            case .overdue, .error:
                return (.red, Color.red.opacity(0.12))
            case .custom(let value):
                return SBWTheme.chip(forStatus: value)
            default:
                return SBWTheme.chip(forStatus: label)
            }
        }
    }

    private let kind: Kind

    init(text: String) {
        self.kind = Kind(text: text)
    }

    var body: some View {
        let colors = kind.colors
        Text(kind.label)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
    }
}
}
