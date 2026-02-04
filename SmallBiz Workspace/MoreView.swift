import SwiftUI

struct MoreView: View {
    @Binding var path: NavigationPath
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
                title: "Business Profile",
                systemImage: "building.2",
                keyword: "Business Profile",
                destination: AnyView(BusinessProfileView())
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
                destination: AnyView(ClientListView())
            ),
            MoreItem(
                title: "Contracts",
                systemImage: "doc.text",
                keyword: "Contracts",
                destination: AnyView(ContractsHomeView())
            ),
            MoreItem(
                title: "Estimates",
                systemImage: "doc.text.fill",
                keyword: "Estimates",
                destination: AnyView(EstimateListView())
            ),
            MoreItem(
                title: "Files",
                systemImage: "folder",
                keyword: "Files",
                destination: AnyView(FilesHomeView())
            ),
            MoreItem(
                title: "Invoices",
                systemImage: "doc.text.fill",
                keyword: "Invoices",
                destination: AnyView(InvoiceListView())
            ),
            MoreItem(
                title: "Portal Preview",
                systemImage: "person.crop.rectangle",
                keyword: "Client Portal",
                destination: AnyView(PortalPreviewView())
            ),
            MoreItem(
                title: "Requests",
                systemImage: "tray.full",
                keyword: "Requests",
                destination: AnyView(JobsListView())
            )
        ]
    }

    private var filtered: [MoreItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.title.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                SBWTheme.brandGradient
                    .opacity(SBWTheme.headerWashOpacity)
                    .blur(radius: SBWTheme.headerWashBlur)
                    .frame(height: SBWTheme.headerWashHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()

                List {
                    if filtered.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different search.")
                        )
                    } else {
                        ForEach(filtered) { item in
                            NavigationLink {
                                item.destination
                            } label: {
                                row(item)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search"
            )
        }
    }

    private func row(_ item: MoreItem) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: item.keyword))
                Image(systemName: item.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            Text(item.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(.vertical, 6)
    }
}
