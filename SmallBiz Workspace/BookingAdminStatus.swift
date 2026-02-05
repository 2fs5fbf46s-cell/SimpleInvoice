import Foundation

enum BookingAdminStatus: String, CaseIterable, Identifiable {
    case pending
    case approved
    case declined
    case all

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
