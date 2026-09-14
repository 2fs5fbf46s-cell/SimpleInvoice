import SwiftUI
import SwiftData

/// What "More" used to be, behind the business avatar instead of a fifth tab.
///
/// Invoices, Estimates and Insights moved to Money; Jobs, Bookings and
/// Contracts moved to Work; Clients already had its own tab. What's left here
/// is genuinely settings-shaped — things configured once, not visited daily.
struct BusinessSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
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
    @Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]) private var profiles: [BusinessProfile]

    @State private var searchText = ""
    @State private var selectedItem: SettingsItem?
    @State private var pushSetupPaymentsNow = false

    private struct SettingsItem: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
        let keyword: String
        let destination: AnyView

        static func == (lhs: SettingsItem, rhs: SettingsItem) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private struct SettingsGroup: Identifiable {
        let id = UUID()
        let title: String
        let items: [SettingsItem]
    }

    private var activeBusinessName: String {
        let name = profiles.first(where: { $0.businessID == activeBiz.activeBusinessID })?.name
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Your Business" : name
    }

    private var groups: [SettingsGroup] {
        var base: [SettingsGroup] = [
            SettingsGroup(title: "Business", items: [
                SettingsItem(
                    title: "Business Profile",
                    subtitle: "Letterhead, branding, and setup",
                    systemImage: "building.2",
                    keyword: "Business Profile",
                    destination: AnyView(BusinessProfileView())
                ),
                SettingsItem(
                    title: "Website",
                    subtitle: "Your public booking page",
                    systemImage: "globe",
                    keyword: "Website",
                    destination: AnyView(WebsiteCustomizationView())
                ),
                SettingsItem(
                    title: "Notifications",
                    subtitle: "Alerts and reminders",
                    systemImage: "bell.badge",
                    keyword: "Notifications",
                    destination: AnyView(NotificationsView())
                )
            ]),
            SettingsGroup(title: "Billing Setup", items: [
                SettingsItem(
                    title: "Saved Items",
                    subtitle: "Services and materials you sell",
                    systemImage: "tray",
                    keyword: "Saved Items",
                    destination: AnyView(SavedItemsView(businessID: activeBiz.activeBusinessID))
                ),
                SettingsItem(
                    title: "Setup Payments",
                    subtitle: "Choose how you get paid",
                    systemImage: "creditcard.fill",
                    keyword: "Payments",
                    destination: AnyView(SetupPaymentsView())
                )
            ]),
            SettingsGroup(title: "Customers", items: [
                SettingsItem(
                    title: "Client Portal",
                    subtitle: "Share files with clients",
                    systemImage: "person.2.badge.gearshape",
                    keyword: "Client Portal",
                    destination: AnyView(PortalDirectoryLauncherView())
                ),
                SettingsItem(
                    title: "Booking Portal",
                    subtitle: "Manage booking requests",
                    systemImage: "calendar.badge.clock",
                    keyword: "Booking Portal",
                    destination: AnyView(BookingPortalView())
                )
            ]),
            SettingsGroup(title: "Support", items: [
                SettingsItem(
                    title: "Help & About",
                    subtitle: "Tutorials and contact support",
                    systemImage: "questionmark.circle",
                    keyword: "Help",
                    destination: AnyView(HelpCenterView())
                )
            ])
        ]

        #if DEBUG
        base.append(SettingsGroup(title: "Developer", items: [
            SettingsItem(
                title: "Portal Preview",
                subtitle: "Preview the client portal",
                systemImage: "person.crop.rectangle",
                keyword: "Client Portal",
                destination: AnyView(PortalPreviewView())
            ),
            SettingsItem(
                title: "Developer Tools",
                subtitle: "Reset onboarding for local testing",
                systemImage: "wrench.and.screwdriver",
                keyword: "Settings",
                destination: AnyView(OnboardingDebugToolsView())
            )
        ]))
        #endif

        return base
    }

    private var filteredGroups: [SettingsGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let items = group.items.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
            return items.isEmpty ? nil : SettingsGroup(title: group.title, items: items)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                SBWTheme.headerWash()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switchBusinessHeader

                        ForEach(filteredGroups) { group in
                            CreateSectionCard(title: group.title) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 {
                                        Divider().opacity(0.6)
                                    }
                                    CreateActionRow(
                                        title: item.title,
                                        subtitle: item.subtitle,
                                        systemImage: item.systemImage,
                                        chipFill: SBWTheme.chipFill(for: item.keyword)
                                    ) {
                                        selectedItem = item
                                    }
                                    .modifier(SetupPaymentsCoachMarkModifier(shouldMark: item.title == "Setup Payments"))
                                }
                            }
                        }

                        if filteredGroups.isEmpty {
                            ContentUnavailableView(
                                "No Results",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different search.")
                            )
                            .padding(.top, 12)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Business")
            .navigationBarTitleDisplayMode(.large)
            .sbwNavigationBarBackdrop()
            .searchable(text: $searchText, prompt: "Search")
            .navigationDestination(item: $selectedItem) { $0.destination }
            .navigationDestination(isPresented: $pushSetupPaymentsNow) { SetupPaymentsView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if presenter.pendingDestination == .setupPayments {
                    presenter.pendingDestination = nil
                    pushSetupPaymentsNow = true
                }
            }
        }
    }

    private var switchBusinessHeader: some View {
        NavigationLink {
            BusinessSwitcherView()
        } label: {
            HStack(spacing: 12) {
                Text(initials)
                    .font(.scaledSystem(size: 16, weight: .bold, relativeTo: .body))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(SBWTheme.brandGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeBusinessName)
                        .font(.scaledSystem(size: 15, weight: .semibold, relativeTo: .body))
                        .foregroundStyle(.primary)
                    Text("Switch business")
                        .font(.scaledSystem(size: 12, relativeTo: .caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.scaledSystem(size: 13, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var initials: String {
        let name = activeBusinessName
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

private struct SetupPaymentsCoachMarkModifier: ViewModifier {
    let shouldMark: Bool

    func body(content: Content) -> some View {
        if shouldMark {
            content.coachMark(id: "walkthrough.more.setup-payments")
        } else {
            content
        }
    }
}

#if DEBUG
private struct OnboardingDebugToolsView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
            ScrollView {
                VStack(spacing: 12) {
                    SBWCardContainer {
                        Text("Developer")
                            .font(.headline)
                        Text("Reset onboarding and walkthrough state for local testing.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Button {
                            WalkthroughState.requestRun()
                        } label: {
                            Label("Run Walkthrough", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button(role: .destructive) {
                            OnboardingState.reset()
                            WalkthroughState.reset()
                            activeBiz.clearActiveBusiness()
                        } label: {
                            Label("Reset Onboarding + Walkthrough", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .navigationTitle("Developer Tools")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
    }
}
#endif
