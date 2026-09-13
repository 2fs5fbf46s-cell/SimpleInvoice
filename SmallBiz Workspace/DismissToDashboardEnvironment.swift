import SwiftUI

private struct DismissToDashboardKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// Call this to dismiss the workspace (full-screen cover) back to the dashboard.
    ///
    /// NOTE: nothing sets this any more. Its only producer was WorkspaceTabView,
    /// which had no call sites and was removed, so the three readers
    /// (ClientEditView, InvoiceDetailView, ContractDetailView) always see nil and
    /// their `dismissToDashboard?()` calls are no-ops. Either wire it up or drop
    /// the calls — decide before relying on that dismiss path.
    var dismissToDashboard: (() -> Void)? {
        get { self[DismissToDashboardKey.self] }
        set { self[DismissToDashboardKey.self] = newValue }
    }
}
