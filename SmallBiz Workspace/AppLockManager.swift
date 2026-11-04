import Foundation
import Combine
import LocalAuthentication
import SwiftUI

/// "Require Face ID": an owner's choice, off by default, in Business
/// settings. When on, the app asks for Face ID (or Touch ID, or the iPhone's
/// passcode) on open and after more than a minute away, and its records stay
/// out of iPhone Spotlight (see SpotlightIndexer).
///
/// This existed for a long time with its gate never shown and its setting
/// defaulting to on, so wiring the gate in as it was would have locked every
/// owner behind Face ID on update.
@MainActor
final class AppLockManager: ObservableObject {
    enum AuthResult { case success, failed, unavailable }

    nonisolated static let enabledKey = "sbw.requireFaceID"
    /// Away for longer than this, and it asks again. Under it, switching to
    /// Messages for a code and back doesn't.
    static let gracePeriod: TimeInterval = 60

    /// Read where there's no manager to hand (SpotlightIndexer).
    nonisolated static var isEnabledInDefaults: Bool {
        UserDefaults.standard.bool(forKey: enabledKey)
    }

    @Published private(set) var isEnabled: Bool
    @Published private(set) var isUnlocked: Bool
    /// In the background: the app switcher's picture of the app is covered.
    @Published private(set) var isObscured = false

    private let defaults: UserDefaults
    private let authenticate: (String) async -> AuthResult
    private var backgroundedAt: Date?

    init(
        defaults: UserDefaults = .standard,
        authenticate: @escaping (String) async -> AuthResult = AppLockManager.deviceOwnerAuthentication
    ) {
        self.defaults = defaults
        self.authenticate = authenticate
        let enabled = defaults.bool(forKey: Self.enabledKey)
        isEnabled = enabled
        isUnlocked = !enabled
    }

    /// Turning it on asks first, so it's never switched on where it can't
    /// be answered. False when it couldn't be turned on.
    func setEnabled(_ enabled: Bool) async -> Bool {
        if enabled {
            guard await authenticate("Turn on the lock for SmallBiz Workspace") == .success else { return false }
        }
        defaults.set(enabled, forKey: Self.enabledKey)
        isEnabled = enabled
        isUnlocked = true
        return true
    }

    func unlock() async {
        guard isEnabled, !isUnlocked else { return }
        switch await authenticate("Unlock SmallBiz Workspace") {
        case .success:
            isUnlocked = true
        case .unavailable:
            // The passcode was removed from this iPhone after the lock was
            // turned on. Nothing here can be answered any more, and the
            // records are the owner's, so open rather than lock them out.
            isUnlocked = true
        case .failed:
            break
        }
    }

    func didEnterBackground(at date: Date = .now) {
        backgroundedAt = date
        isObscured = isEnabled
    }

    func didBecomeActive(at date: Date = .now) {
        isObscured = false
        guard isEnabled, let away = backgroundedAt else { return }
        backgroundedAt = nil
        if date.timeIntervalSince(away) > Self.gracePeriod {
            isUnlocked = false
        }
    }

    /// "Face ID", "Touch ID" or "Passcode", for the setting's name.
    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Passcode"
        }
    }

    /// False on an iPhone with no passcode, where there's nothing to ask.
    nonisolated static var deviceCanAuthenticate: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    nonisolated static func deviceOwnerAuthentication(reason: String) async -> AuthResult {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return .unavailable }
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) ? .success : .failed
        } catch {
            return .failed
        }
    }
}
