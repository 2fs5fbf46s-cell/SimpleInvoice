import OSLog
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        SBWLog.launch.note("✅ APNs token received: \(token)")

        Task {
            await PushRegistrationService.shared.registerDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        SBWLog.launch.problem("⚠️ APNs registration failed: \(error)")
    }

    /// Every push the backend sends carries content-available, so this runs
    /// for each one — in the background, and in the foreground alongside
    /// willPresent — letting the app pull what changed without being opened.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        if NotificationInboxService.payloadSuggestsInboxRefresh(userInfo) {
            NotificationInboxService.shared.markNeedsRefresh()
        }
        return await PushSyncCoordinator.shared.syncForRemoteNotification()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        if NotificationInboxService.payloadSuggestsInboxRefresh(userInfo) {
            NotificationInboxService.shared.markNeedsRefresh()
        }
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if NotificationInboxService.payloadSuggestsInboxRefresh(userInfo) {
            NotificationInboxService.shared.markNeedsRefresh()
        }
        NotificationRouter.shared.handleNotificationTap(userInfo: userInfo)
        completionHandler()
    }
}

// Testing steps:
// 1) Run on a physical iPhone (APNs token registration is device-only in real scenarios).
// 2) Open Business Profile -> Notifications -> tap "Enable Push Notifications".
// 3) Confirm logs show APNs token received + backend registration success.
// 4) Trigger a backend test push later and confirm foreground banner appears while app is open.
