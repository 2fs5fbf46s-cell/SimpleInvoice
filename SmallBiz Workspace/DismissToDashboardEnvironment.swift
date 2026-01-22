import SwiftUI

private struct DismissToDashboardKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Call this to dismiss the workspace (full-screen cover) back to the dashboard.
    var dismissToDashboard: (() -> Void)? {
        get { self[DismissToDashboardKey.self] }
        set { self[DismissToDashboardKey.self] = newValue }
    }
}
