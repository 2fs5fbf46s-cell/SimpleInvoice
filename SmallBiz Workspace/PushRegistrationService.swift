import Foundation

@MainActor
final class PushRegistrationService {
    static let shared = PushRegistrationService()

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func registerDeviceToken(_ token: String, businessId: UUID) async {
        await registerDeviceToken(token, businessId: businessId.uuidString)
    }

    func registerDeviceToken(_ token: String, businessId: String? = nil) async {
        let rawBusinessID = (businessId ?? defaults.string(forKey: "activeBusinessID"))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBusinessID = rawBusinessID.flatMap(UUID.init(uuidString:))?.uuidString

        guard let resolvedBusinessID, !resolvedBusinessID.isEmpty else {
            print("⚠️ Skipping push token registration: no valid active business UUID.")
            return
        }

        let env = Self.currentAPNsEnvironment()

        do {
            try await PortalBackend.shared.registerPushToken(
                businessId: resolvedBusinessID,
                deviceToken: token,
                environment: env
            )
            print("✅ Registered push token for business \(resolvedBusinessID) [\(env)].")
        } catch {
            print("⚠️ Push token registration failed: \(error)")
        }
    }

    static func currentAPNsEnvironment() -> String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}
