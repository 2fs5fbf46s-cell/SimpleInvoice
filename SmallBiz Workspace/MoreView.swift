import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @State private var searchText = ""
    @State private var selectedItem: MoreItem?

    private struct MoreItem: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let subtitle: String
        let systemImage: String
        let keyword: String   // drives chipFill consistency
        let destination: AnyView

        static func == (lhs: MoreItem, rhs: MoreItem) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    private struct MoreGroup: Identifiable {
        let id = UUID()
        let title: String
        let items: [MoreItem]
    }

    private var groups: [MoreGroup] {
        var base: [MoreGroup] = [
            MoreGroup(title: "Billing", items: [
                MoreItem(
                    title: "Invoices",
                    subtitle: "Create and track invoices",
                    systemImage: "doc.text.fill",
                    keyword: "Invoices",
                    destination: AnyView(InvoiceListView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Estimates",
                    subtitle: "Send quotes and proposals",
                    systemImage: "doc.text.fill",
                    keyword: "Estimates",
                    destination: AnyView(EstimateListView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Saved Items",
                    subtitle: "Services and materials you sell",
                    systemImage: "tray",
                    keyword: "Saved Items",
                    destination: AnyView(SavedItemsView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Setup Payments",
                    subtitle: "Choose how you get paid",
                    systemImage: "creditcard.fill",
                    keyword: "Payments",
                    destination: AnyView(SetupPaymentsView())
                )
            ]),
            MoreGroup(title: "Scheduling", items: [
                MoreItem(
                    title: "Jobs",
                    subtitle: "Scheduled work and requests",
                    systemImage: "tray.full",
                    keyword: "Jobs",
                    destination: AnyView(JobsListView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Booking Portal",
                    subtitle: "Manage booking requests",
                    systemImage: "calendar.badge.clock",
                    keyword: "Booking Portal",
                    destination: AnyView(BookingPortalView())
                )
            ]),
            MoreGroup(title: "Customers", items: [
                MoreItem(
                    title: "Clients",
                    subtitle: "Contacts and their history",
                    systemImage: "person.2",
                    keyword: "Customers",
                    destination: AnyView(ClientListView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Contracts",
                    subtitle: "Agreements and signatures",
                    systemImage: "doc.text",
                    keyword: "Contracts",
                    destination: AnyView(ContractsHomeView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Client Portal",
                    subtitle: "Share files with clients",
                    systemImage: "person.2.badge.gearshape",
                    keyword: "Client Portal",
                    destination: AnyView(PortalDirectoryLauncherView())
                )
            ]),
            MoreGroup(title: "Business", items: [
                MoreItem(
                    title: "Business Profile",
                    subtitle: "Letterhead, branding, and setup",
                    systemImage: "building.2",
                    keyword: "Business Profile",
                    destination: AnyView(BusinessProfileView())
                ),
                MoreItem(
                    title: "Website",
                    subtitle: "Your public booking page",
                    systemImage: "globe",
                    keyword: "Website",
                    destination: AnyView(WebsiteCustomizationView())
                ),
                MoreItem(
                    title: "Business Insights",
                    subtitle: "Cash in, outstanding, pipeline",
                    systemImage: "chart.line.uptrend.xyaxis",
                    keyword: "Revenue",
                    destination: AnyView(BusinessInsightsView(businessID: activeBiz.activeBusinessID))
                ),
                MoreItem(
                    title: "Notifications",
                    subtitle: "Alerts and reminders",
                    systemImage: "bell.badge",
                    keyword: "Notifications",
                    destination: AnyView(NotificationsView())
                )
            ]),
            MoreGroup(title: "Support", items: [
                MoreItem(
                    title: "Help & About",
                    subtitle: "Tutorials and contact support",
                    systemImage: "questionmark.circle",
                    keyword: "Help",
                    destination: AnyView(HelpCenterView())
                )
            ])
        ]

        #if DEBUG
        base.append(MoreGroup(title: "Developer", items: [
            MoreItem(
                title: "Portal Preview",
                subtitle: "Preview the client portal",
                systemImage: "person.crop.rectangle",
                keyword: "Client Portal",
                destination: AnyView(PortalPreviewView())
            ),
            MoreItem(
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

    private var filteredGroups: [MoreGroup] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return groups }
        return groups.compactMap { group in
            let items = group.items.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
            return items.isEmpty ? nil : MoreGroup(title: group.title, items: items)
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .searchable(text: $searchText, prompt: "Search")
        .navigationDestination(item: $selectedItem) { $0.destination }
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
