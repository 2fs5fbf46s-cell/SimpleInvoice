import SwiftUI

/// The single checkpoint every "create a new X" action calls before
/// proceeding. A lapsed trial/subscription blocks *new* creation only —
/// existing data, the client portal, and the public booking page all keep
/// working regardless of subscription state, since a lapsed subscription
/// must never take down something a business's own client relies on.
enum SubscriptionGate {
    @discardableResult
    @MainActor
    static func allow(_ store: SubscriptionStore, present paywall: Binding<Bool>) -> Bool {
        if store.isEntitled { return true }
        paywall.wrappedValue = true
        return false
    }
}
