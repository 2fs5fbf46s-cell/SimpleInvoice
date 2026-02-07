//
//  FolderBrowserView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct FolderBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode

    let business: Business
    @Bindable var folder: Folder

    // MARK: - State
    @State private var errorText: String? = nil

    @State private var showingNewFolder = false
    @State private var newFolderName = ""

    @State private var renamingFolder: Folder? = nil
    @State private var renameText: String = ""

    // Import
    @State private var showFileImporter = false
    @State private var importError: String? = nil
    @State private var showPhotosSheet = false

    // Preview
    @State private var previewItem: IdentifiableURL? = nil

    // ✅ Query all, filter in-memory (avoids #Predicate macro errors)
    @Query private var allFileItems: [FileItem]
    @Query private var allFolders: [Folder]

    // ✅ List-managed selection
    @State private var selection = Set<UUID>()
    @State private var selectedFolder: Folder? = nil

    // Sheets / dialogs
    @State private var showMoveSheet = false
    @State private var confirmBulkDelete = false

    // ZIP share
    @State private var zipURL: URL? = nil
    @State private var zipError: String? = nil

    // Search + sort
    @State private var searchText: String = ""
    @State private var fileSort: FileSort = .dateDesc
    @State private var folderSort: FolderSort = .nameAsc

    // Forces redraw when SwiftUI/SwiftData are “sticky”
    @State private var refreshToken = UUID()

    // Bulk actions helper
    @State private var pendingSelection = Set<UUID>()

    init(business: Business, folder: Folder) {
        self.business = business
        self._folder = Bindable(wrappedValue: folder)
    }

    // MARK: - Derived

    private var isEditing: Bool { editMode?.wrappedValue == .active }

    private var children: [Folder] {
        // ✅ No #Predicate — filter in memory
        allFolders.filter { f in
            f.businessID == business.id && f.parentFolderID == folder.id
        }
        .sorted(by: folderSort.sort)
    }

    private var filesInThisFolder: [FileItem] {
        let key = folder.id.uuidString
        return allFileItems.filter { $0.folderKey == key }
    }

    private var visibleFiles: [FileItem] {
        var items = filesInThisFolder

        let qTrim = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qTrim.isEmpty {
            let q = qTrim.lowercased()
            items = items.filter {
                $0.displayName.lowercased().contains(q) ||
                $0.originalFileName.lowercased().contains(q) ||
                $0.fileExtension.lowercased().contains(q)
            }
        }

        items.sort(by: fileSort.sort)
        return items
    }

    private var visibleFolders: [Folder] {
        var items = children

        let qTrim = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !qTrim.isEmpty {
            let q = qTrim.lowercased()
            items = items.filter {
                $0.name.lowercased().contains(q) ||
                $0.relativePath.lowercased().contains(q)
            }
        }

        items.sort(by: folderSort.sort)
        return items
    }

    private var allSelectableIDs: [UUID] {
        visibleFiles.map(\.id) + visibleFolders.map(\.id)
    }

    private var isAllSelected: Bool {
        let all = Set(allSelectableIDs)
        return !all.isEmpty && selection.isSuperset(of: all)
    }

    private var summaryText: String {
        "\(visibleFolders.count) folders • \(visibleFiles.count) files"
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            List(selection: $selection) {
                errorBanner
                foldersSection
                filesSection
            }
            .id(refreshToken)
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .padding(.top, 58)

            pinnedHeader
        }
        .navigationTitle(folder.name)
        .searchable(text: $searchText, prompt: "Search files & folders")
        .navigationDestination(item: $selectedFolder) { f in
            FolderBrowserView(business: business, folder: f)
        }
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) { bottomBar }

        .onChange(of: editMode?.wrappedValue) { _, mode in
            if mode != .active { selection.removeAll() }
        }

        // Import from Files
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: UTType.importable,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importFromFiles(urls)
            case .failure(let error):
                importError = error.localizedDescription
            }
        }

        // Photos import
        .sheet(isPresented: $showPhotosSheet) { photosSheet }

        // Preview
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }

        // Move picker
        .sheet(isPresented: $showMoveSheet) {
            DestinationFolderPicker(
                business: business,
                currentFolder: folder
            ) { destination in
                moveSelected(to: destination)
                showMoveSheet = false
            }
        }

        // Share ZIP
        .sheet(isPresented: Binding(
            get: { zipURL != nil },
            set: { if !$0 { zipURL = nil } }
        )) {
            ShareSheet(items: zipURL.map { [$0] } ?? [])
        }

        // New folder sheet
        .sheet(isPresented: $showingNewFolder) { newFolderSheet }

        // Rename alert
        .alert("Rename Folder", isPresented: Binding(
            get: { renamingFolder != nil },
            set: { if !$0 { renamingFolder = nil } }
        )) {
            TextField("New name", text: $renameText)
            Button("Cancel", role: .cancel) { renamingFolder = nil }
            Button("Save") {
                if let f = renamingFolder { renameFolderAndDescendants(f, newName: renameText) }
                renamingFolder = nil
            }
        }

        // Bulk delete confirmation
        .confirmationDialog("Delete selected items?", isPresented: $confirmBulkDelete) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Deletes selected file records + local files. Folders are deleted (non-recursive).")
        }

        // Errors
        .alert("Error", isPresented: Binding(
            get: { importError != nil || zipError != nil || errorText != nil },
            set: { _ in importError = nil; zipError = nil; errorText = nil }
        )) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(importError ?? zipError ?? errorText ?? "")
        }
    }

    // MARK: - Split views

    @ViewBuilder private var errorBanner: some View {
        if let errorText {
            Text(errorText)
                .foregroundStyle(.red)
                .sbwFilesCardRow()
        }
    }

    @ViewBuilder private var filesSection: some View {
        if !visibleFiles.isEmpty {
            Section("Files") {
                ForEach(visibleFiles) { item in
                    FileRowView(
                        item: item,
                        icon: iconName(for: item),
                        isEditing: isEditing,
                        onOpen: { openPreview(for: item) },
                        onZip: { exportZipForFiles([item]) },
                        onMove: { selection = [item.id]; showMoveSheet = true },
                        onDelete: { deleteFile(item) }
                    )
                    .tag(item.id)
                    .sbwFilesCardRow()
                }
                .onDelete { offsets in deleteOffsets(offsets, from: visibleFiles) }
            }
        }
    }

    private var foldersSection: some View {
        Section("Folders") {
            if visibleFolders.isEmpty {
                ContentUnavailableView("No folders yet", systemImage: "folder")
            } else {
                ForEach(visibleFolders) { f in
                    FolderRowView(
                        business: business,
                        folder: f,
                        isEditing: isEditing,
                        onOpen: { selectedFolder = f }
                    )
                        .tag(f.id)
                        .sbwFilesCardRow()
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            // ✅ Swipe-to-delete for folders (matches file behavior)
                            // Avoid swipe actions while multi-select edit mode is active.
                            if !isEditing {
                                Button(role: .destructive) {
                                    deleteFolder(f)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            if !isEditing {
                                Button {
                                    renamingFolder = f
                                    renameText = f.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }

                                Button {
                                    selection = [f.id]
                                    showMoveSheet = true
                                } label: {
                                    Label("Move", systemImage: "folder")
                                }
                                .tint(.blue)
                            }
                        }
                        .contextMenu {
                            Button("Rename") { renamingFolder = f; renameText = f.name }
                            Button("Move…") { selection = [f.id]; showMoveSheet = true }
                            Button(role: .destructive) { deleteFolder(f) } label: { Text("Delete") }
                        }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {

            Menu {
                Picker("Sort Files", selection: $fileSort) {
                    ForEach(FileSort.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            } label: { Image(systemName: "arrow.up.arrow.down") }

            Menu {
                Button { showingNewFolder = true } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                Button { showFileImporter = true } label: {
                    Label("Import from Files", systemImage: "tray.and.arrow.down")
                }
                Button { showPhotosSheet = true } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
                if !visibleFiles.isEmpty {
                    Button { exportZipForFiles(visibleFiles) } label: {
                        Label("ZIP Visible Files", systemImage: "doc.zipper")
                    }
                }
            } label: { Image(systemName: "plus") }

            EditButton()
        }
    }

    private var pinnedHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name.isEmpty ? "Files" : folder.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(summaryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(isEditing ? "EDITING" : "BROWSE")
                .font(.caption.weight(.semibold))
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Capsule().fill((isEditing ? SBWTheme.brandBlue : SBWTheme.brandGreen).opacity(0.18)))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if isEditing {
            VStack(spacing: 10) {
                HStack {
                    Text("\(selection.count) selected")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(isAllSelected ? "Clear" : "Select All") {
                        if isAllSelected { selection.removeAll() }
                        else { selection = Set(allSelectableIDs) }
                    }
                    .font(.footnote.weight(.semibold))
                }

                HStack(spacing: 12) {
                    Button {
                        pendingSelection = selection
                        showMoveSheet = true
                    } label: {
                        Label("Move", systemImage: "folder")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selection.isEmpty)

                    Button(role: .destructive) {
                        pendingSelection = selection
                        confirmBulkDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selection.isEmpty)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Sheets

    private var newFolderSheet: some View {
        NavigationStack {
            Form {
                Section("New Folder") {
                    TextField("Folder Name", text: $newFolderName)
                }
            }
            .navigationTitle("Create Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingNewFolder = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createFolder()
                        showingNewFolder = false
                    }
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private var photosSheet: some View {
        NavigationStack {
            List {
                PhotosImportButton { data, suggestedName in
                    importFromPhotos(data: data, suggestedFileName: suggestedName)
                    showPhotosSheet = false
                }
            }
            .navigationTitle("Import Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showPhotosSheet = false }
                }
            }
        }
    }

    // MARK: - Folder helpers (NO SwiftData predicate macros)

    private func makeChildRelativePath(parent: Folder, childName: String) -> String {
        let p = parent.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let c = childName.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if p.isEmpty { return c }
        return "\(p)/\(c)"
    }

    private func createFolder() {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            let rel = makeChildRelativePath(parent: folder, childName: name)
            let new = Folder(
                businessID: business.id,
                name: name,
                relativePath: rel,
                parentFolderID: folder.id
            )
            modelContext.insert(new)
            try modelContext.save()

            newFolderName = ""
            refreshToken = UUID()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func renameFolderAndDescendants(_ target: Folder, newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        do {
            let oldPath = target.relativePath

            // Find the parent folder (in-memory)
            let parent = allFolders.first(where: { $0.id == target.parentFolderID }) ?? folder
            let newPath = makeChildRelativePath(parent: parent, childName: name)

            for f in allFolders where f.businessID == business.id {
                if f.id == target.id {
                    f.name = name
                    f.relativePath = newPath
                    f.updatedAt = .now
                } else if f.relativePath.hasPrefix(oldPath + "/") {
                    f.relativePath = newPath + f.relativePath.dropFirst((oldPath + "/").count)
                    f.updatedAt = .now
                }
            }

            try modelContext.save()
            refreshToken = UUID()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func deleteFolder(_ folder: Folder) {
        modelContext.delete(folder)
        do {
            try modelContext.save()
            refreshToken = UUID()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - File ops

    private func openPreview(for item: FileItem) {
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: item.relativePath)
            previewItem = IdentifiableURL(url: url)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deleteFile(_ item: FileItem) {
        do { try AppFileStore.deleteFile(for: item) } catch { }
        modelContext.delete(item)
        do {
            try modelContext.save()
            refreshToken = UUID()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func deleteOffsets(_ offsets: IndexSet, from list: [FileItem]) {
        for idx in offsets where idx < list.count {
            deleteFile(list[idx])
        }
    }

    private func deleteSelected() {
        let ids = pendingSelection.isEmpty ? selection : pendingSelection
        pendingSelection.removeAll()
        selection.removeAll()

        do {
            for item in allFileItems where ids.contains(item.id) {
                try? AppFileStore.deleteFile(for: item)
                modelContext.delete(item)
            }
            for f in allFolders where ids.contains(f.id) {
                modelContext.delete(f)
            }
            try modelContext.save()
            editMode?.wrappedValue = .inactive
            refreshToken = UUID()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Move

    private func moveSelected(to destination: Folder?) {
        let ids = pendingSelection.isEmpty ? selection : pendingSelection
        pendingSelection.removeAll()
        selection.removeAll()

        do {
            let dest = destination
            let destKey = (dest?.id.uuidString) ?? (folder.parentFolderID?.uuidString ?? folder.id.uuidString)
            let destPath = (dest?.relativePath) ?? ""

            // Move files
            for item in allFileItems where ids.contains(item.id) {
                item.folder = dest
                item.folderKey = destKey
            }

            // Move folders + cascade paths
            for moving in allFolders where ids.contains(moving.id) {
                let oldPath = moving.relativePath
                moving.parentFolderID = dest?.id

                let base = destPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let nm = moving.name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let newPath = base.isEmpty ? nm : "\(base)/\(nm)"
                moving.relativePath = newPath
                moving.updatedAt = .now

                for child in allFolders where child.relativePath.hasPrefix(oldPath + "/") {
                    child.relativePath = newPath + child.relativePath.dropFirst((oldPath + "/").count)
                    child.updatedAt = .now
                }
            }

            try modelContext.save()
            editMode?.wrappedValue = .inactive
            refreshToken = UUID()
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Import

    private func importFromFiles(_ urls: [URL]) {
        for url in urls {
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                let fileId = UUID()
                let ext = url.pathExtension.lowercased()
                let uti = UTType(filenameExtension: ext)?.identifier ?? "public.data"

                let (rel, size) = try AppFileStore.importFile(from: url, fileId: fileId)

                let item = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: uti,
                    byteCount: size,
                    folderKey: folder.id.uuidString,
                    folder: folder
                )
                modelContext.insert(item)
            } catch {
                importError = error.localizedDescription
                return
            }
        }

        do {
            try modelContext.save()
            refreshToken = UUID()
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importFromPhotos(data: Data, suggestedFileName: String) {
        do {
            let fileId = UUID()
            let (rel, size) = try AppFileStore.importData(
                data,
                fileId: fileId,
                preferredFileName: suggestedFileName
            )

            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = UTType(filenameExtension: ext)?.identifier ?? "public.data"

            let file = FileItem(
                displayName: suggestedFileName.replacingOccurrences(of: ".\(ext)", with: ""),
                originalFileName: suggestedFileName,
                relativePath: rel,
                fileExtension: ext,
                uti: uti,
                byteCount: size,
                folderKey: folder.id.uuidString,
                folder: folder
            )
            modelContext.insert(file)

            try modelContext.save()
            refreshToken = UUID()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - ZIP

    private func exportZipForFiles(_ items: [FileItem]) {
        do {
            let urls = try items.map { try AppFileStore.absoluteURL(forRelativePath: $0.relativePath) }
            let name = folder.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Files" : folder.name
            zipURL = try AttachmentZipExporter.zipFiles(urls, zipName: "\(name)-Files")
            zipError = nil
        } catch {
            zipError = error.localizedDescription
        }
    }

    // MARK: - Icons

    private func iconName(for item: FileItem) -> String {
        let ext = item.fileExtension.lowercased()
        if ["jpg","jpeg","png","heic","webp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        if ["txt","rtf"].contains(ext) { return "doc.text" }
        return "doc"
    }
}

private struct SBWFilesCardRowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
    }
}

private extension View {
    func sbwFilesCardRow() -> some View {
        modifier(SBWFilesCardRowModifier())
    }
}

// MARK: - Sort enums

private enum FileSort: CaseIterable, Hashable {
    case nameAsc, nameDesc
    case dateAsc, dateDesc
    case typeAsc, typeDesc

    var label: String {
        switch self {
        case .nameAsc: return "Name (A–Z)"
        case .nameDesc: return "Name (Z–A)"
        case .dateAsc: return "Date (Oldest)"
        case .dateDesc: return "Date (Newest)"
        case .typeAsc: return "Type (A–Z)"
        case .typeDesc: return "Type (Z–A)"
        }
    }

    var sort: (FileItem, FileItem) -> Bool {
        switch self {
        case .nameAsc: return { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .nameDesc: return { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedDescending }
        case .dateAsc: return { $0.createdAt < $1.createdAt }
        case .dateDesc: return { $0.createdAt > $1.createdAt }
        case .typeAsc: return { $0.fileExtension.lowercased() < $1.fileExtension.lowercased() }
        case .typeDesc: return { $0.fileExtension.lowercased() > $1.fileExtension.lowercased() }
        }
    }
}

private enum FolderSort: CaseIterable, Hashable {
    case nameAsc, nameDesc
    case dateAsc, dateDesc

    var label: String {
        switch self {
        case .nameAsc: return "Name (A–Z)"
        case .nameDesc: return "Name (Z–A)"
        case .dateAsc: return "Date (Oldest)"
        case .dateDesc: return "Date (Newest)"
        }
    }

    var sort: (Folder, Folder) -> Bool {
        switch self {
        case .nameAsc: return { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDesc: return { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .dateAsc: return { $0.createdAt < $1.createdAt }
        case .dateDesc: return { $0.createdAt > $1.createdAt }
        }
    }
}
