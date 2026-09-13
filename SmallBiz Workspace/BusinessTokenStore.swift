import Foundation
import Security

/// Per-business device tokens.
///
/// Replaces the shared `PORTAL_ADMIN_KEY` as the app's proof of which business it
/// is acting for. The old model shipped one key in every copy of the app and let
/// the caller name any `businessId`, so anyone who pulled the key out of the
/// bundle could operate any business on the platform.
///
/// Each business is registered once, and the token it gets back is stored in the
/// Keychain — not UserDefaults, which is readable from a file-system backup.
/// The server derives the businessId from the token and ignores whatever the
/// request says.
@MainActor
final class BusinessTokenStore {
    static let shared = BusinessTokenStore()

    private let service = "com.javonfreeman.smallbizworkspace.businessToken"
    private var cache: [UUID: String] = [:]

    private init() {}

    // MARK: - Keychain

    private func account(for businessID: UUID) -> String {
        businessID.uuidString.lowercased()
    }

    func token(for businessID: UUID) -> String? {
        if let cached = cache[businessID] { return cached }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: businessID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else {
            return nil
        }

        cache[businessID] = token
        return token
    }

    func save(_ token: String, for businessID: UUID) {
        let account = account(for: businessID)
        let data = Data(token.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // The token is only ever needed while the app is running in the
            // foreground or background on this device, and should not migrate to
            // a restored device.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            SecItemAdd(insert as CFDictionary, nil)
        }

        cache[businessID] = token
    }

    func delete(for businessID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: businessID),
        ]
        SecItemDelete(query as CFDictionary)
        cache.removeValue(forKey: businessID)
    }

    func hasToken(for businessID: UUID) -> Bool {
        token(for: businessID) != nil
    }
}
