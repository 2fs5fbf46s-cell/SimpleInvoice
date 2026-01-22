import Foundation

// MARK: - Client Portal helper (no relationships; CloudKit-safe)

extension Client {
    var portalClientID: UUID { id }
}
