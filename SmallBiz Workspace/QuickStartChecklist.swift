import Foundation
import SwiftData
import UserNotifications

/// Getting-started checklist state, derived from what the user has actually done.
///
/// The checklist used to be a hardcoded array of title and action with no notion
/// of completion, so every row showed an empty circle forever — someone who had
/// added a client and sent an invoice saw exactly the same screen as someone who
/// had done nothing. A checklist that cannot complete is furniture.
struct QuickStartChecklist: Equatable {

    enum Step: String, CaseIterable, Identifiable {
        case addClient
        case sendInvoice
        case enableNotifications
        case setUpPayments

        var id: String { rawValue }

        var title: String {
            switch self {
            case .addClient: return "Add your first client"
            case .sendInvoice: return "Create and send an invoice"
            case .enableNotifications: return "Turn on notifications"
            case .setUpPayments: return "Set up how you get paid"
            }
        }

        var detail: String {
            switch self {
            case .addClient: return "Their details fill in automatically on every invoice."
            case .sendInvoice: return "Send a link your client can pay from."
            case .enableNotifications: return "Know the moment an invoice is paid."
            case .setUpPayments: return "Card, PayPal, or your own bank details."
            }
        }

        var route: AppRoute {
            switch self {
            case .addClient: return .clientsRoot
            case .sendInvoice: return .invoicesRoot
            case .enableNotifications: return .openAppSettings
            case .setUpPayments: return .paymentsSetup
            }
        }
    }

    private(set) var completed: Set<Step>

    init(completed: Set<Step> = []) {
        self.completed = completed
    }

    func isComplete(_ step: Step) -> Bool { completed.contains(step) }

    var completedCount: Int { completed.count }
    var totalCount: Int { Step.allCases.count }
    var isFullyComplete: Bool { completedCount == totalCount }

    /// The next thing worth doing, or nil when everything is done.
    var nextStep: Step? { Step.allCases.first { !completed.contains($0) } }

    // MARK: - Derivation

    /// What each step means, given the facts. Pure, so it can be tested exhaustively
    /// without a `ModelContainer` — the queries below are a thin adapter over it.
    static func from(
        hasClient: Bool,
        hasSentInvoice: Bool,
        notificationsEnabled: Bool,
        hasPaymentMethod: Bool
    ) -> QuickStartChecklist {
        var completed: Set<Step> = []
        if hasClient { completed.insert(.addClient) }
        if hasSentInvoice { completed.insert(.sendInvoice) }
        if notificationsEnabled { completed.insert(.enableNotifications) }
        if hasPaymentMethod { completed.insert(.setUpPayments) }
        return QuickStartChecklist(completed: completed)
    }

    /// Everything except the notification permission, which needs an async call.
    @MainActor
    static func fromStoredData(
        businessID: UUID?,
        context: ModelContext,
        notificationsEnabled: Bool
    ) -> QuickStartChecklist {
        guard let businessID else { return QuickStartChecklist() }

        return from(
            hasClient: hasClient(businessID: businessID, context: context),
            // "Sent" rather than "created": a draft nobody has seen isn't the milestone.
            hasSentInvoice: hasSentInvoice(businessID: businessID, context: context),
            notificationsEnabled: notificationsEnabled,
            hasPaymentMethod: hasPaymentMethod(businessID: businessID, context: context)
        )
    }

    @MainActor
    private static func hasClient(businessID: UUID, context: ModelContext) -> Bool {
        // fetchLimit 1: asking "any?" should never materialize the table.
        var descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { $0.businessID == businessID }
        )
        descriptor.fetchLimit = 1
        return ((try? context.fetch(descriptor)) ?? []).isEmpty == false
    }

    @MainActor
    private static func hasSentInvoice(businessID: UUID, context: ModelContext) -> Bool {
        // Two narrow fetches rather than one compound predicate: SwiftData cannot
        // compile `optional != nil` into a predicate, and the whole expression
        // traps at runtime if you try. `isPaid` is a plain Bool and is fine; the
        // upload timestamp is checked by comparing against a floor instead.
        var paid = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
                    && invoice.documentType == "invoice"
                    && invoice.isPaid
            }
        )
        paid.fetchLimit = 1
        if ((try? context.fetch(paid)) ?? []).isEmpty == false { return true }

        var uploaded = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
                    && invoice.documentType == "invoice"
                    && (invoice.portalLastUploadedAtMs ?? 0) > 0
            }
        )
        uploaded.fetchLimit = 1
        return ((try? context.fetch(uploaded)) ?? []).isEmpty == false
    }

    @MainActor
    private static func hasPaymentMethod(businessID: UUID, context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Business>(
            predicate: #Predicate<Business> { $0.id == businessID }
        )
        descriptor.fetchLimit = 1
        guard let business = (try? context.fetch(descriptor))?.first else { return false }

        let hasConnectedStripe = !(business.stripeAccountId ?? "").isEmpty
        return hasConnectedStripe
            || business.paypalEnabled
            || business.squareEnabled
            || business.cashAppEnabled
            || business.venmoEnabled
            || business.achEnabled
    }

    static func notificationsAreEnabled(
        status: UNAuthorizationStatus
    ) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral: return true
        case .denied, .notDetermined: return false
        @unknown default: return false
        }
    }
}
