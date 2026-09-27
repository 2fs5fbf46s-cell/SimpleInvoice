import SwiftUI
import StoreKit

/// Business Settings → Subscription. Shows the paywall (via
/// `SubscriptionStoreView`) when there's no active entitlement, or status +
/// Apple's native "Manage Subscription" sheet once there is one.
struct SubscriptionSettingsView: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore

    var body: some View {
        Group {
            switch subscriptionStore.state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .trialing, .active:
                activeContent
            case .notEntitled:
                SubscriptionStoreView(productIDs: [SubscriptionStore.productID])
                    .subscriptionStoreControlStyle(.prominentPicker)
                    .onInAppPurchaseCompletion { _, result in
                        if case .success(.success(let verification)) = result, case .verified = verification {
                            await subscriptionStore.refreshEntitlement()
                        }
                    }
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .task { await subscriptionStore.load() }
    }

    private var activeContent: some View {
        Form {
            Section {
                LabeledContent("Status", value: statusText)
            } footer: {
                Text("Manage your plan, payment method, or cancel anytime through Apple.")
            }
            Section {
                Button("Manage Subscription") {
                    Task { await openManageSubscriptions() }
                }
            }
        }
    }

    private var statusText: String {
        switch subscriptionStore.state {
        case .trialing(let daysLeft):
            return "Trial · \(daysLeft) day\(daysLeft == 1 ? "" : "s") left"
        case .active:
            return "Active"
        case .loading, .notEntitled:
            return "—"
        }
    }

    @MainActor
    private func openManageSubscriptions() async {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }
        try? await AppStore.showManageSubscriptions(in: scene)
    }
}
