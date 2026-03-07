import SwiftUI

struct MoreView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @State private var searchText = ""

    private struct MoreItem: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let keyword: String   // drives chipFill consistency
        let destination: AnyView
    }

    private var items: [MoreItem] {
        var base: [MoreItem] = [
            MoreItem(
                title: "Notifications",
                systemImage: "bell.badge",
                keyword: "Notifications",
                destination: AnyView(NotificationsView())
            ),
            MoreItem(
                title: "Help Center",
                systemImage: "questionmark.circle",
                keyword: "Help",
                destination: AnyView(HelpCenterView())
            ),
            MoreItem(
                title: "Booking Portal",
                systemImage: "calendar.badge.clock",
                keyword: "Booking Portal",
                destination: AnyView(BookingPortalView())
            ),
            MoreItem(
                title: "Business Profile",
                systemImage: "building.2",
                keyword: "Business Profile",
                destination: AnyView(BusinessProfileView())
            ),
            MoreItem(
                title: "Setup Payments",
                systemImage: "creditcard.fill",
                keyword: "Payments",
                destination: AnyView(SetupPaymentsView())
            ),
            MoreItem(
                title: "Website",
                systemImage: "globe",
                keyword: "Website",
                destination: AnyView(WebsiteCustomizationView())
            ),
            MoreItem(
                title: "Client Portal",
                systemImage: "person.2.badge.gearshape",
                keyword: "Client Portal",
                destination: AnyView(PortalDirectoryLauncherView())
            ),
            MoreItem(
                title: "Clients",
                systemImage: "person.2",
                keyword: "Customers",
                destination: AnyView(ClientListView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Contracts",
                systemImage: "doc.text",
                keyword: "Contracts",
                destination: AnyView(ContractsHomeView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Estimates",
                systemImage: "doc.text.fill",
                keyword: "Estimates",
                destination: AnyView(EstimateListView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Files",
                systemImage: "folder",
                keyword: "Files",
                destination: AnyView(FilesHomeView())
            ),
            MoreItem(
                title: "Inventory",
                systemImage: "tray",
                keyword: "Saved Items",
                destination: AnyView(SavedItemsView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Invoices",
                systemImage: "doc.text.fill",
                keyword: "Invoices",
                destination: AnyView(InvoiceListView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Business Insights",
                systemImage: "chart.line.uptrend.xyaxis",
                keyword: "Revenue",
                destination: AnyView(BusinessInsightsView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Jobs",
                systemImage: "tray.full",
                keyword: "Jobs",
                destination: AnyView(JobsListView(businessID: activeBiz.activeBusinessID))
            ),
            MoreItem(
                title: "Portal Preview",
                systemImage: "person.crop.rectangle",
                keyword: "Client Portal",
                destination: AnyView(PortalPreviewView())
            )
        ]

        #if DEBUG
        base.append(
            MoreItem(
                title: "Developer Tools",
                systemImage: "wrench.and.screwdriver",
                keyword: "Settings",
                destination: AnyView(OnboardingDebugToolsView())
            )
        )
        #endif

        return base
    }

    private var filtered: [MoreItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let sorted = items.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { $0.title.lowercased().contains(q) }
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
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(filtered) { item in
                        NavigationLink {
                            item.destination
                        } label: {
                            tile(item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search.")
                    )
                    .padding(.top, 12)
                }

                helpCard
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    HelpCenterView()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("Help Center")
            }
        }
    }

    private var helpCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Help")
                    .font(.headline)
                Text("Need a refresher? Open Help Center for tutorial and support.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                NavigationLink {
                    HelpCenterView()
                } label: {
                    Label("Open Help Center", systemImage: "questionmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
        }
    }

    private func tile(_ item: MoreItem) -> some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(SBWTheme.chipFill(for: item.keyword))
                    Image(systemName: item.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 38, height: 38)

                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        }
        .modifier(SetupPaymentsCoachMarkModifier(shouldMark: item.title == "Setup Payments"))
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
    }
}
#endif
