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
        [
            MoreItem(
                title: "Notifications",
                systemImage: "bell.badge",
                keyword: "Notifications",
                destination: AnyView(NotificationsView())
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
                            NavigationLink {
                                item.destination
                            } label: {
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
