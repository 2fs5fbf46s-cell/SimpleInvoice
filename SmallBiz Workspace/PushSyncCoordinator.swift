import UIKit

/// Hands a push wake from AppDelegate to the workspace sync. The sync needs
/// the SwiftData container, which only exists once LaunchCoordinator finishes
/// and the App registers a handler here.
@MainActor
final class PushSyncCoordinator {
    static let shared = PushSyncCoordinator()

    private var sync: (() async -> Void)?

    private init() {}

    func register(_ sync: @escaping () async -> Void) {
        self.sync = sync
    }

    /// iOS allows about 30 seconds for this. On a cold background launch the
    /// push can arrive before the workspace is ready, so wait briefly for it
    /// instead of dropping the wake; if it never becomes ready, the next
    /// foreground's regular pull catches up.
    func syncForRemoteNotification() async -> UIBackgroundFetchResult {
        var waitedSteps = 0
        while sync == nil, waitedSteps < 20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            waitedSteps += 1
        }
        guard let sync else { return .noData }
        await sync()
        return .newData
    }
}
