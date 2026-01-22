import SwiftUI
import SwiftData

struct WorkspaceTabView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {

            NavigationStack {
                ClientListView()
                    .toolbar { homeToolbar }
            }
            .tabItem {
                Label("Clients", systemImage: "person.2")
            }

            NavigationStack {
                JobsListView()
                    .toolbar { homeToolbar }
            }
            .tabItem {
                Label("Projects", systemImage: "calendar")
            }

            NavigationStack {
                ContractsHomeView()
                    .toolbar { homeToolbar }
            }
            .tabItem {
                Label("Contracts", systemImage: "doc.text")
            }

            NavigationStack {
                InvoiceListView()
                    .toolbar { homeToolbar }
            }
            .tabItem {
                Label("Invoices", systemImage: "doc.plaintext")
            }

            NavigationStack {
                FilesHomeView()
                    .toolbar { homeToolbar }
            }
            .tabItem {
                Label("Files", systemImage: "folder")
            }

            // ✅ Portal Preview MUST be inside TabView
            NavigationStack {
                PortalPreviewView()
                    .toolbar { homeToolbar }
            }
            .tabItem {
                Label("Portal", systemImage: "person.crop.rectangle")
            }
        }
        .environment(\.dismissToDashboard, { dismiss() })
        .task {
            ContractTemplateSeeder.seedIfNeeded(context: modelContext)
        }
    }

    // MARK: - Home toolbar (top-left)
    @ToolbarContentBuilder
    private var homeToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "house")
            }
            .accessibilityLabel("Home")
        }
    }
}
