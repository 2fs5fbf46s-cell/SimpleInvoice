import SwiftUI
import SwiftData

struct DestinationFolderPicker: View {
    @Environment(\.dismiss) private var dismiss

    let business: Business
    let currentFolder: Folder
    let onPick: (Folder?) -> Void   // nil = Files root

    // ✅ Avoid SwiftData #Predicate macro issues: query all and filter in-memory
    @Query private var allFolders: [Folder]

    @State private var path: [Folder] = []
    @State private var searchText: String = ""

    private var filesRoot: Folder? {
        allFolders.first(where: { $0.businessID == business.id && $0.parentFolderID == nil })
        ?? allFolders.first(where: { $0.businessID == business.id && $0.relativePath == "Files" })
    }

    private var currentParent: Folder? {
        path.last ?? filesRoot
    }

    private var visibleChildren: [Folder] {
        let parentID = currentParent?.id
        var children = allFolders.filter { f in
            f.businessID == business.id && f.parentFolderID == parentID
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            children = children.filter { $0.name.lowercased().contains(q) || $0.relativePath.lowercased().contains(q) }
        }

        children.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return children
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    Button {
                        onPick(nil)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: "tray.full")
                            Text("Files (Root)")
                            Spacer()
                            if path.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }

                Section(pathTitle) {
                    if visibleChildren.isEmpty {
                        Text("No subfolders here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(visibleChildren) { folder in
                            Button {
                                path.append(folder)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "folder")
                                        .foregroundStyle(.secondary)
                                    SBWNavigationRow(
                                        title: folder.name,
                                        subtitle: folder.relativePath
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    onPick(folder)
                                    dismiss()
                                } label: {
                                    Label("Move here", systemImage: "arrow.down.to.line.compact")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Move To…")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search folders")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move Here") {
                        // Move to the folder you're currently “inside”
                        onPick(currentParent)
                        dismiss()
                    }
                    .disabled(currentParent == nil)
                }
            }
            .navigationDestination(for: Folder.self) { folder in
                FolderLevelView(
                    business: business,
                    folder: folder,
                    allFolders: allFolders,
                    searchText: $searchText,
                    onNavigate: { path.append($0) }
                ) { chosen in
                    onPick(chosen)
                    dismiss()
                }
            }
        }
    }

    private var pathTitle: String {
        if let currentParent {
            return "Inside: \(currentParent.name)"
        }
        return "Folders"
    }
}

private struct FolderLevelView: View {
    let business: Business
    let folder: Folder
    let allFolders: [Folder]
    @Binding var searchText: String
    let onNavigate: (Folder) -> Void
    let onChoose: (Folder?) -> Void

    private var children: [Folder] {
        var c = allFolders.filter { f in
            f.businessID == business.id && f.parentFolderID == folder.id
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            c = c.filter { $0.name.lowercased().contains(q) || $0.relativePath.lowercased().contains(q) }
        }

        c.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return c
    }

    var body: some View {
        List {
            Section {
                Button {
                    onChoose(folder)
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.to.line.compact")
                        Text("Move Here")
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                            .opacity(0.001) // keeps row height consistent
                    }
                }
            }

            Section("Subfolders") {
                if children.isEmpty {
                    Text("No subfolders.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(children) { f in
                        Button {
                            onNavigate(f)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                SBWNavigationRow(
                                    title: f.name,
                                    subtitle: f.relativePath
                                )
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onChoose(f)
                            } label: {
                                Label("Move here", systemImage: "arrow.down.to.line.compact")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folder.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Move Here") { onChoose(folder) }
            }
        }
    }
}
