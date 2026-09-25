import SwiftUI
import SwiftData
import UserNotifications

/// Everything configured once about the business, behind the avatar.
///
/// One row per setting, each with its current state underneath ("Next:
/// SI-2026-042", "Card, Venmo", "Taking bookings"), and a Next step card on
/// top — the same pattern as a record's screen. It used to be a menu of
/// plain rows, several of which led to the same settings as another row
/// (payments and the business switcher were each reachable twice), and whose
/// destinations were rebuilt with fresh ids on every render.
struct BusinessSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    /// Passed in directly rather than resolved via `@EnvironmentObject`: this
    /// sheet's `.onAppear` is the only place that reads it, and an
    /// environment object read solely inside a closure — never in `body`
    /// itself — crashed `BusinessAvatarButton` with the same "No
    /// ObservableObject" error for the same reason (see that type's doc
    /// comment). A sheet's root view is especially exposed to this, since its
    /// `.onAppear` can fire before the presentation's environment is fully
    /// attached.
    let presenter: BusinessSettingsPresenter

    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]
    @Query private var catalogItems: [CatalogItem]
    @Query private var sites: [PublishedBusinessSite]
    @Query private var clients: [Client]

    @State private var route: Route?
    @State private var notificationsAllowed: Bool? = nil

    enum Route: Hashable {
        case switcher, profile, invoiceNumbers, savedItems
        case payments, reminders
        case booking, website, clientPortal
        case notifications, help
        #if DEBUG
        case portalPreview, developer
        #endif
    }

    private var businessID: UUID? { activeBiz.activeBusinessID }
    private var profile: BusinessProfile? { profiles.first { $0.businessID == businessID } }
    private var business: Business? { businesses.first { $0.id == businessID } }
    private var setup: BusinessSetup { BusinessSetup(profile: profile, business: business) }

    private var displayName: String {
        let name = (profile?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Your Business" : name
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    if let step = setup.nextStep { nextStepCard(step) }

                    section("Your Business") {
                        row(.profile, "Profile and Logo", profileSubtitle, "building.2")
                        row(.invoiceNumbers, "Invoice Numbers", invoiceNumberSubtitle, "number")
                        row(.savedItems, "Saved Items", savedItemsSubtitle, "tray.full")
                    }
                    section("Getting Paid") {
                        row(.payments, "Payment Methods", paymentsSubtitle, "creditcard",
                            badge: paymentsBadge)
                            .coachMark(id: "walkthrough.more.setup-payments")
                        row(.reminders, "Overdue Reminders", remindersSubtitle, "bell.badge")
                    }
                    section("What Clients See") {
                        row(.booking, "Booking Page", bookingSubtitle, "calendar.badge.clock", badge: bookingBadge)
                        row(.website, "Website", websiteSubtitle, "globe", badge: websiteBadge)
                        row(.clientPortal, "Client Portal", clientPortalSubtitle, "person.2")
                    }
                    section("Alerts and Help") {
                        row(.notifications, "Notifications", notificationsSubtitle, "bell")
                        row(.help, "Help and About", "Guides, questions and support", "questionmark.circle")
                    }
                    #if DEBUG
                    section("Developer") {
                        row(.portalPreview, "Portal Preview", "See the client portal", "person.crop.rectangle")
                        row(.developer, "Developer Tools", "IDs, onboarding reset", "wrench.and.screwdriver")
                    }
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("Business")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(item: $route) { destination($0) }
            .onAppear {
                if presenter.pendingDestination == .setupPayments {
                    presenter.pendingDestination = nil
                    route = .payments
                }
            }
            .task { await refreshNotificationStatus() }
        }
    }

    // MARK: - Header and next step

    private var header: some View {
        HStack(spacing: 12) {
            Group {
                if let data = profile?.logoData, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text(BusinessIdentity.initials(for: profile?.name ?? ""))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(SBWTheme.brandGradient)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(contactLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if businesses.count > 1 {
                Button("Switch") { route = .switcher }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Menu {
                    Button { route = .switcher } label: { Label("Add a Business", systemImage: "plus") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("More")
            }
        }
        .settingsCard()
    }

    private var contactLine: String {
        let parts = [profile?.email, profile?.phone]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "No contact details yet" : parts.joined(separator: " · ")
    }

    private func nextStepCard(_ step: BusinessSetup.Step) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Next step · \(setup.doneCount) of \(setup.totalCount) set up")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(step.title)
                .font(.headline)
            Text(step.detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button(step.action) { act(on: step) }
                .sbwProminentButton()
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()
    }

    private func act(on step: BusinessSetup.Step) {
        switch step {
        case .contact, .logo: route = .profile
        case .payments: route = .payments
        case .reminders: route = .reminders
        }
    }

    // MARK: - Rows

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                _VariadicView.Tree(DividedRows()) { content() }
            }
            .settingsCard(padding: 0)
        }
    }

    private func row(
        _ target: Route,
        _ title: String,
        _ subtitle: String,
        _ icon: String,
        badge: SettingsBadge? = nil
    ) -> some View {
        Button { route = target } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let badge {
                    Text(badge.text)
                        .font(.caption2.weight(.semibold))
                        .padding(.vertical, 3)
                        .padding(.horizontal, 8)
                        .background(Capsule().fill(badge.color.opacity(0.15)))
                        .foregroundStyle(badge.color)
                        .fixedSize()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .switcher: BusinessSwitcherView()
        case .profile: BusinessProfileView()
        case .invoiceNumbers: InvoiceNumbersView()
        case .savedItems: SavedItemsView(businessID: businessID)
        case .payments: SetupPaymentsView()
        case .reminders: OverdueReminderSettingsView()
        case .booking: BookingPageView()
        case .website: WebsiteCustomizationView()
        case .clientPortal: PortalDirectoryLauncherView()
        case .notifications: NotificationSettingsView()
        case .help: HelpCenterView()
        #if DEBUG
        case .portalPreview: PortalPreviewView()
        case .developer: DeveloperToolsView()
        #endif
        }
    }

    // MARK: - Row states

    private var profileSubtitle: String {
        guard let profile else { return "Name, contact details and logo" }
        if !setup.done.contains(.contact) { return "Add your email so clients can reach you" }
        return profile.logoData == nil ? "No logo yet" : "Name, contact details and logo"
    }

    private var invoiceNumberSubtitle: String {
        guard let profile else { return "How invoices are numbered" }
        return "Next: \(InvoiceNumberGenerator.peekNextNumber(profile: profile))"
    }

    private var savedItemsSubtitle: String {
        let count = catalogItems.filter { $0.businessID == businessID }.count
        switch count {
        case 0: return "Services and materials you sell"
        case 1: return "1 item"
        default: return "\(count) items"
        }
    }

    private var paymentsSubtitle: String {
        guard let business else { return "How clients pay you" }
        return PaymentMethodSummary(business: business).text
    }

    private var paymentsBadge: SettingsBadge? {
        guard let business else { return nil }
        return PaymentMethodSummary(business: business).offered.isEmpty
            ? SettingsBadge(text: "Not set up", color: .orange) : nil
    }

    private var remindersSubtitle: String {
        guard let profile, profile.overdueReminderEnabled else { return "Off" }
        let days = profile.overdueReminderCadenceDays
        return "On · \(days) day\(days == 1 ? "" : "s") after the due date"
    }

    private var bookingSubtitle: String {
        let slug = (profile?.bookingSlug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return slug.isEmpty ? "Let clients request a time" : "Link ends in /\(slug)"
    }

    private var bookingBadge: SettingsBadge? {
        let slug = (profile?.bookingSlug ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !slug.isEmpty else { return nil }
        return profile?.bookingEnabled == false
            ? SettingsBadge(text: "Paused", color: .secondary)
            : SettingsBadge(text: "Taking bookings", color: .green)
    }

    private var site: PublishedBusinessSite? { sites.first { $0.businessID == businessID } }

    private var websiteSubtitle: String {
        guard let site else { return "A simple site for your business" }
        switch site.status {
        case .published:
            if let date = site.lastPublishedAt {
                return "Published \(date.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Published"
        case .queued, .publishing: return "Publishing…"
        case .error: return "Couldn't publish. Open it to try again."
        case .draft: return "Not published yet"
        }
    }

    private var websiteBadge: SettingsBadge? {
        switch site?.status {
        case .published: return SettingsBadge(text: "Live", color: .green)
        case .error: return SettingsBadge(text: "Needs attention", color: .orange)
        default: return nil
        }
    }

    private var clientPortalSubtitle: String {
        let count = clients.filter { $0.businessID == businessID && $0.portalEnabled }.count
        switch count {
        case 0: return "Where clients see and pay their invoices"
        case 1: return "1 client can use it"
        default: return "\(count) clients can use it"
        }
    }

    private var notificationsSubtitle: String {
        switch notificationsAllowed {
        case .some(true): return "On · choose what you're told about"
        case .some(false): return "Off in iPhone Settings"
        case .none: return "Choose what you're told about"
        }
    }

    private func refreshNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: notificationsAllowed = true
        case .denied: notificationsAllowed = false
        default: notificationsAllowed = nil
        }
    }
}

struct SettingsBadge {
    let text: String
    let color: Color
}

/// Rows in a card with hairlines between them.
private struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        let last = children.last?.id
        ForEach(children) { child in
            child
            if child.id != last {
                Divider().padding(.leading, 54)
            }
        }
    }
}

private extension View {
    func settingsCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
    }
}

#if DEBUG
/// IDs and onboarding resets for local testing. The IDs used to be a
/// "Debug / Metadata" card on Business Profile, visible to every user.
private struct DeveloperToolsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Query private var businesses: [Business]
    @Query private var sites: [PublishedBusinessSite]

    var body: some View {
        let business = businesses.first { $0.id == activeBiz.activeBusinessID }
        let site = sites.first { $0.businessID == activeBiz.activeBusinessID }
        Form {
            Section("This Business") {
                LabeledContent("Business ID", value: activeBiz.activeBusinessID?.uuidString ?? "—")
                    .textSelection(.enabled)
                LabeledContent("Stripe account", value: business?.stripeAccountId ?? "—")
                LabeledContent("Stripe status", value: business?.stripeOnboardingStatus ?? "—")
                LabeledContent("PayPal merchant", value: business?.paypalMerchantId ?? "—")
                LabeledContent("Website handle", value: site?.handle ?? "—")
            }
            .font(.footnote)
            Section("Onboarding") {
                Button("Run Walkthrough") { WalkthroughState.requestRun() }
                Button("Reset Onboarding and Walkthrough", role: .destructive) {
                    OnboardingState.reset()
                    WalkthroughState.reset()
                    activeBiz.clearActiveBusiness()
                }
            }
        }
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
