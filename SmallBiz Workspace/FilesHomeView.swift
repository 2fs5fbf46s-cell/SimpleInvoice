import SwiftUI
import SwiftData

struct FilesHomeView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var activeBusiness: Business? = nil
    @State private var rootFolder: Folder? = nil
    @State private var loadError: String? = nil
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                SBWTheme.headerWash()

                Group {
                    if let business = activeBusiness, let root = rootFolder {
                        FolderBrowserView(business: business, folder: root)
                    } else if let loadError {
                        ContentUnavailableView(
                            "Files Unavailable",
                            systemImage: "folder.badge.questionmark",
                            description: Text(loadError)
                        )
                    } else {
                        ProgressView("Loading Files…")
                    }
                }
            }
            .navigationTitle("Files")
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            loadRoot()
        }
        .refreshable {
            loadRoot(force: true)
        }
    }

    private func loadRoot(force: Bool = false) {
        do {
            let biz = try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)

            // ✅ Ensure root exists (no manual Folder(...) creation)
            try FolderService.bootstrapRootIfNeeded(businessID: biz.id, context: modelContext)

            guard let root = try FolderService.fetchRootFolder(businessID: biz.id, context: modelContext) else {
                loadError = "Root folder 'Files' could not be loaded."
                activeBusiness = biz
                rootFolder = nil
                return
            }

            activeBusiness = biz
            rootFolder = root
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
