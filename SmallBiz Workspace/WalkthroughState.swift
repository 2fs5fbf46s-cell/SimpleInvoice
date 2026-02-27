import Foundation

enum WalkthroughState {
    private static let defaults = UserDefaults.standard

    static let completeKey = "sbw.walkthrough.complete"
    static let lastVersionKey = "sbw.walkthrough.lastVersion"
    static let runRequestNotification = Notification.Name("sbw.walkthrough.run-request")

    static var isComplete: Bool {
        defaults.bool(forKey: completeKey) && defaults.string(forKey: lastVersionKey) == currentVersion
    }

    static func markComplete() {
        defaults.set(true, forKey: completeKey)
        defaults.set(currentVersion, forKey: lastVersionKey)
    }

    static func requestRun() {
        NotificationCenter.default.post(name: runRequestNotification, object: nil)
    }

    #if DEBUG
    static func reset() {
        defaults.removeObject(forKey: completeKey)
        defaults.removeObject(forKey: lastVersionKey)
    }
    #endif

    private static var currentVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return "\(short ?? "0")(\(build ?? "0"))"
    }
}
