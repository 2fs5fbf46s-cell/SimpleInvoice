import SwiftUI
import StoreKit

/// Shown when `SubscriptionGate.allow` blocks a creation action. Leans on
/// Apple's own `SubscriptionStoreView` for the actual product/price/trial
/// UI, purchase button, legal footer and Restore Purchases — no hand-rolled
/// pricing UI to keep in sync with what's actually configured in App Store
/// Connect.
struct SubscriptionPaywallView: View {
    @EnvironmentObject private var subscriptionStore: SubscriptionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(productIDs: [SubscriptionStore.productID]) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .foregroundStyle(SBWTheme.brand)
                    Text("Your trial has ended")
                        .font(.title3.weight(.semibold))
                    Text("Subscribe to keep creating invoices, jobs, clients and more. Everything you already have stays exactly as it is.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .subscriptionStoreControlStyle(.prominentPicker)
            // Apple requires Terms and Privacy links beside any subscription offer.
            .storeButton(.visible, for: .restorePurchases, .policies)
            .subscriptionStorePolicyDestination(url: URL(string: "https://portal.smallbizworkspace.com/terms")!, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: URL(string: "https://portal.smallbizworkspace.com/privacy")!, for: .privacyPolicy)
            .navigationTitle("Subscribe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onInAppPurchaseCompletion { _, result in
                if case .success(.success(let verification)) = result, case .verified = verification {
                    await subscriptionStore.refreshEntitlement()
                    dismiss()
                }
            }
        }
    }
}
