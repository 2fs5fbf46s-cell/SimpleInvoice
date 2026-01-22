import Foundation
import Combine
import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockManager: ObservableObject {
    @AppStorage("appLockEnabled") var appLockEnabled: Bool = true
    @Published var isUnlocked: Bool = false
    @Published var lastUnlockDate: Date? = nil

    func lock() {
        isUnlocked = false
    }

    func unlockIfNeeded() async {
        guard appLockEnabled else {
            isUnlocked = true
            return
        }

        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            isUnlocked = true
            return
        }

        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock SmallBiz Workspace")
            if ok {
                isUnlocked = true
                lastUnlockDate = .now
            }
        } catch {
            isUnlocked = false
        }
    }
}
