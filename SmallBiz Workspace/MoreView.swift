import SwiftUI

struct MoreView: View {
    @Binding var path: NavigationPath
    @State private var searchText = ""

    private enum MoreRoute: String, Hashable {
        case notifications
        case bookingPortal
        case businessProfile
        case setupPayments
        case website
        case clientPortal
        case clients
        case contracts
        case estimates
        case files
        case inventory
        case invoices
        case jobs
        case portalPreview
    }

    private struct MoreItem: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let keyword: String   // drives chipFill consistency
        let route: MoreRoute
    }

    private var items: [MoreItem] {
        [
            MoreItem(
                title: "Notifications",
                systemImage: "bell.badge",
                keyword: "Notifications",
                route: .notifications
            ),
            MoreItem(
                title: "Booking Portal",
                systemImage: "calendar.badge.clock",
                keyword: "Booking Portal",
                route: .bookingPortal
            ),
            MoreItem(
                title: "Business Profile",
                systemImage: "building.2",
                keyword: "Business Profile",
                route: .businessProfile
            ),
            MoreItem(
                title: "Setup Payments",
                systemImage: "creditcard.fill",
                keyword: "Payments",
                route: .setupPayments
            ),
            MoreItem(
                title: "Website",
                systemImage: "globe",
                keyword: "Website",
                route: .website
            ),
            MoreItem(
                title: "Client Portal",
                systemImage: "person.2.badge.gearshape",
                keyword: "Client Portal",
                route: .clientPortal
            ),
            MoreItem(
                title: "Clients",
                systemImage: "person.2",
                keyword: "Customers",
                route: .clients
            ),
            MoreItem(
                title: "Contracts",
                systemImage: "doc.text",
                keyword: "Contracts",
                route: .contracts
            ),
            MoreItem(
                title: "Estimates",
                systemImage: "doc.text.fill",
                keyword: "Estimates",
                route: .estimates
            ),
            MoreItem(
                title: "Files",
                systemImage: "folder",
                keyword: "Files",
                route: .files
            ),
            MoreItem(
                title: "Inventory",
                systemImage: "tray",
                keyword: "Saved Items",
                route: .inventory
            ),
            MoreItem(
                title: "Invoices",
                systemImage: "doc.text.fill",
                keyword: "Invoices",
                route: .invoices
            ),
            MoreItem(
                title: "Jobs",
                systemImage: "tray.full",
                keyword: "Jobs",
                route: .jobs
            ),
            MoreItem(
                title: "Portal Preview",
                systemImage: "person.crop.rectangle",
                keyword: "Client Portal",
                route: .portalPreview
            )
        ]
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

            if filtered.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filtered) { item in
                            NavigationLink(value: item.route) {
                                tile(item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .navigationDestination(for: MoreRoute.self) { route in
            switch route {
            case .notifications:
                NotificationsView()
            case .bookingPortal:
                BookingPortalView()
            case .businessProfile:
                BusinessProfileView()
            case .setupPayments:
                SetupPaymentsView()
            case .website:
                WebsiteCustomizationView()
            case .clientPortal:
                PortalDirectoryLauncherView()
            case .clients:
                ClientListView()
            case .contracts:
                ContractsHomeView()
            case .estimates:
                EstimateListView()
            case .files:
                FilesHomeView()
            case .inventory:
                SavedItemsView()
            case .invoices:
                InvoiceListView()
            case .jobs:
                JobsListView()
            case .portalPreview:
                PortalPreviewView()
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
    }
}
