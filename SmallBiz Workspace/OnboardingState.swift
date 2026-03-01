import Foundation

enum OnboardingState {
    private static let defaults = UserDefaults.standard

    static let completeKey = "sbw.onboarding.complete"
    static let didRequestNotificationsKey = "sbw.onboarding.didRequestNotifications"
    static let notificationsChoiceKey = "sbw.onboarding.notificationsChoice"

    static var isComplete: Bool {
        defaults.bool(forKey: completeKey)
    }

    static var didRequestNotifications: Bool {
        defaults.bool(forKey: didRequestNotificationsKey)
    }

    static var notificationsChoice: String? {
        defaults.string(forKey: notificationsChoiceKey)
    }

    static func markComplete() {
        defaults.set(true, forKey: completeKey)
    }

    static func setNotificationsChoice(_ choice: String, didRequest: Bool) {
        defaults.set(choice, forKey: notificationsChoiceKey)
        defaults.set(didRequest, forKey: didRequestNotificationsKey)
    }

    #if DEBUG
    static func reset() {
        defaults.removeObject(forKey: completeKey)
        defaults.removeObject(forKey: didRequestNotificationsKey)
        defaults.removeObject(forKey: notificationsChoiceKey)
    }
    #endif
}
