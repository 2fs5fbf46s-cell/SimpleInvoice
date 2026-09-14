import Foundation

struct WalkthroughStep: Identifiable, Equatable {
    let id: String
    let targetCoachMarkId: String
    let title: String
    let message: String
    let routeTab: AppTab?
}

enum WalkthroughSteps {
    // Target ids updated for the Today/Clients/Create/Money/Work tab bar. The
    // old "More" tab's coach mark (setup-payments) lives inside the Business
    // settings sheet now rather than a tab, so that step's target frame won't
    // register during a normal walkthrough — the coordinator already treats a
    // frame that never appears as "skip this step," so it degrades gracefully
    // rather than getting stuck. A proper fix (walkthrough opens the sheet for
    // that one step) is scoped separately, not part of this navigation pass.
    static let core: [WalkthroughStep] = [
        WalkthroughStep(
            id: "today-overview",
            targetCoachMarkId: "walkthrough.dashboard.metrics",
            title: "Your Command Center",
            message: "Track cash flow and upcoming work from Today.",
            routeTab: .today
        ),
        WalkthroughStep(
            id: "money-tab",
            targetCoachMarkId: "walkthrough.tab.money",
            title: "Money",
            message: "Invoices, estimates and insights, all in one place.",
            routeTab: .money
        ),
        WalkthroughStep(
            id: "create-tab",
            targetCoachMarkId: "walkthrough.tab.create",
            title: "Create Fast",
            message: "Use Create to add invoices, clients, bookings, and more.",
            routeTab: .today
        ),
        WalkthroughStep(
            id: "clients-tab",
            targetCoachMarkId: "walkthrough.tab.clients",
            title: "Clients",
            message: "Your customer records and activity live here.",
            routeTab: .clients
        ),
        WalkthroughStep(
            id: "work-tab",
            targetCoachMarkId: "walkthrough.tab.work",
            title: "Work",
            message: "Jobs, bookings and contracts — everything you've committed to.",
            routeTab: .work
        ),
        WalkthroughStep(
            id: "payments-tile",
            targetCoachMarkId: "walkthrough.more.setup-payments",
            title: "Setup Payments",
            message: "Tap your business avatar, then Setup Payments, to connect Stripe/PayPal or add manual payment methods.",
            routeTab: .today
        )
    ]
}
