import Foundation

enum BookingAdminStatus: String, CaseIterable, Identifiable {
    case pending
    case depositRequested = "deposit_requested"
    case approved
    case declined
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .depositRequested: return "Deposit Requested"
        case .approved: return "Approved"
        case .declined: return "Declined"
        case .all: return "All"
        }
    }
}
