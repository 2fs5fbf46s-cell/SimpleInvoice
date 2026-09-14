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
    // Setup Payments step used to target a coach mark buried inside the old
    // More tab — since that row now lives behind the Business settings sheet
    // (which isn't open during a normal walkthrough), it points at the
    // always-visible avatar button instead, which is genuinely where that
    // action lives now rather than a stale reference the coordinator has to
    // silently skip.
    static let core: [WalkthroughStep] = [
        WalkthroughStep(
            id: "today-overview",
            targetCoachMarkId: "walkthrough.today.needsyou",
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
            id: "business-avatar",
            targetCoachMarkId: "walkthrough.avatar",
            title: "Your Business",
            message: "Business Profile, Setup Payments, your website and more live here.",
            routeTab: .today
        )
    ]
}
