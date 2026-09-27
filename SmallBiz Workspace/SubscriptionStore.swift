import Combine
import Foundation
import StoreKit

/// The one place in the app that knows whether the subscription is active.
/// StoreKit is the sole source of truth — no backend involvement. Apple
/// already tracks trial-once-per-Apple-ID, receipt validity, renewal,
/// cancellation and refunds, so there's nothing else to sync for v1.
@MainActor
final class SubscriptionStore: ObservableObject {
    static let productID = "com.javonfreeman.smallbizworkspace.subscription.core.monthly"

    enum State: Equatable {
        case loading
        case trialing(daysLeft: Int)
        case active
        case notEntitled
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var product: Product?

    /// The single signal every creation gate checks.
    var isEntitled: Bool {
        switch state {
        case .trialing, .active: return true
        case .loading, .notEntitled: return false
        }
    }

    private var updatesTask: Task<Void, Never>?

    /// Starts the once-per-launch `Transaction.updates` listener (renewals,
    /// cancellations, refunds arriving in real time) and kicks off the
    /// initial product load + entitlement check. Safe to call more than
    /// once — only the first call does anything.
    func startObserving() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }
        Task { await load() }
    }

    deinit {
        updatesTask?.cancel()
    }

    func load() async {
        do {
            product = try await Product.products(for: [Self.productID]).first
        } catch {
            SBWLog.ui.problem("Failed to load subscription product: \(error)")
        }
        await refreshEntitlement()
    }

    private func handle(_ verification: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = verification else { return }
        await transaction.finish()
        await refreshEntitlement()
    }

    func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil
            else { continue }

            guard let expirationDate = transaction.expirationDate, expirationDate > .now else {
                continue
            }

            if transaction.offerType == .introductory {
                let days = Calendar.current.dateComponents([.day], from: .now, to: expirationDate).day ?? 0
                state = .trialing(daysLeft: max(0, days))
            } else {
                state = .active
            }
            return
        }
        state = .notEntitled
    }
}
