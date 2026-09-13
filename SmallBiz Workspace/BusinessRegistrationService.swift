import Foundation

/// Claims a business on the backend and keeps its device token current.
///
/// Called when a business becomes active. The first device to register a business
/// owns it; a later caller holding only the shared bootstrap key is refused, which
/// is what stops that key from being a master key over existing businesses.
@MainActor
enum BusinessRegistrationService {

    enum RegistrationError: LocalizedError {
        case alreadyRegisteredElsewhere
        case backend(String)

        var errorDescription: String? {
            switch self {
            case .alreadyRegisteredElsewhere:
                return "This business is already set up on another device."
            case .backend(let message):
                return message
            }
        }
    }

    private struct RegisterResponse: Decodable {
        let ok: Bool
        let businessId: String?
        let token: String?
        let rotated: Bool?
    }

    /// Registers the business if this device has no token for it yet, and makes
    /// that token the active one. Safe to call repeatedly.
    @discardableResult
    static func ensureRegistered(businessID: UUID) async -> Bool {
        if let existing = BusinessTokenStore.shared.token(for: businessID) {
            PortalBackend.activeBusinessToken = existing
            return true
        }

        do {
            let token = try await register(businessID: businessID)
            BusinessTokenStore.shared.save(token, for: businessID)
            PortalBackend.activeBusinessToken = token
            return true
        } catch {
            // Leave the token unset: business-scoped calls will fail with a clear
            // 401 rather than silently acting as some other business.
            PortalBackend.activeBusinessToken = nil
            print("[BusinessAuth] Registration failed for \(businessID): \(error.localizedDescription)")
            return false
        }
    }

    /// Point the backend client at a business this device has already claimed.
    static func activate(businessID: UUID?) {
        guard let businessID else {
            PortalBackend.activeBusinessToken = nil
            return
        }
        PortalBackend.activeBusinessToken = BusinessTokenStore.shared.token(for: businessID)
    }

    private static func register(businessID: UUID) async throws -> String {
        guard let adminKey = PortalSecrets.portalAdminKey(), !adminKey.isEmpty else {
            throw PortalBackendError.missingAdminKey
        }

        var req = URLRequest(
            url: PortalConfig.shared.baseURL.appendingPathComponent("/api/business/register")
        )
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        // Presenting the current token (when we have one) asks the server to rotate
        // rather than refuse.
        if let existing = BusinessTokenStore.shared.token(for: businessID) {
            req.setValue(existing, forHTTPHeaderField: "x-sbw-business-token")
        }

        req.httpBody = try JSONSerialization.data(
            withJSONObject: ["businessId": businessID.uuidString.lowercased()]
        )

        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        if status == 409 {
            throw RegistrationError.alreadyRegisteredElsewhere
        }

        guard (200..<300).contains(status) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RegistrationError.backend("Registration failed (HTTP \(status)). \(body)")
        }

        let decoded = try JSONDecoder().decode(RegisterResponse.self, from: data)
        guard decoded.ok, let token = decoded.token, !token.isEmpty else {
            throw RegistrationError.backend("Registration response had no token.")
        }

        return token
    }
}
