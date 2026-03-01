import Foundation

struct WalkthroughStep: Identifiable, Equatable {
    let id: String
    let targetCoachMarkId: String
    let title: String
    let message: String
    let routeTab: AppTab?
}

enum WalkthroughSteps {
    static let core: [WalkthroughStep] = [
        WalkthroughStep(
            id: "dashboard-overview",
            targetCoachMarkId: "walkthrough.dashboard.metrics",
            title: "Your Command Center",
            message: "Track cash flow and upcoming work from the dashboard.",
            routeTab: .dashboard
        ),
        WalkthroughStep(
            id: "invoices-tab",
            targetCoachMarkId: "walkthrough.tab.invoices",
            title: "Invoices",
            message: "Send invoices and collect payments quickly.",
            routeTab: .invoices
        ),
        WalkthroughStep(
            id: "create-tab",
            targetCoachMarkId: "walkthrough.tab.create",
            title: "Create Fast",
            message: "Use Create to add invoices, clients, bookings, and more.",
            routeTab: .dashboard
        ),
        WalkthroughStep(
            id: "clients-tab",
            targetCoachMarkId: "walkthrough.tab.clients",
            title: "Clients",
            message: "Your customer records and activity live here.",
            routeTab: .clients
        ),
        WalkthroughStep(
            id: "more-tab",
            targetCoachMarkId: "walkthrough.tab.more",
            title: "More Tools",
            message: "Open settings, portals, and advanced workspace tools.",
            routeTab: .more
        ),
        WalkthroughStep(
            id: "payments-tile",
            targetCoachMarkId: "walkthrough.more.setup-payments",
            title: "Setup Payments",
            message: "Connect Stripe/PayPal or add manual payment methods.",
            routeTab: .more
        )
    ]
}
