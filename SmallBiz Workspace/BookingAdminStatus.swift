import Foundation

enum BookingAdminStatus: String, CaseIterable, Identifiable {
    /// `all` leads the list because it is the default, and because every other
    /// list screen in the app starts on All. It used to sit last, which put it
    /// off the right edge of a horizontally clipped chip row — so the filter
    /// looked as though it had no way to show everything.
    case all
    case pending
    case depositRequested = "deposit_requested"
    case approved
    case declined

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
