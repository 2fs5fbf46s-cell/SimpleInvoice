//
//  ClientFilesCard.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The client's files on the client screen: their folder, and the files
/// attached to them.
///
/// There were two attachment lists for a client, one on the summary and one
/// inside the edit form's Advanced Options, and the trash button there
/// removed a file on a single tap.
struct ClientFilesCard: View {
    @Environment(\.modelContext) private var modelContext
    let client: Client

    @Query private var attachments: [ClientAttachment]

    @State private var showFileImporter = false
    @State private var showExistingPicker = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var preview: IdentifiableURL? = nil
    @State private var folderItem: FolderSheetItem? = nil
    @State private var pendingRemoval: ClientAttachment? = nil
    @State private var zipURL: IdentifiableURL? = nil
    @State private var errorText: String? = nil

    private struct FolderSheetItem: Identifiable {
        let id = UUID()
        let business: Business
        let folder: Folder
    }

    init(client: Client) {
        self.client = client
        let key = client.id.uuidString
        _attachments = Query(
            filter: #Predicate<ClientAttachment> { $0.clientKey == key },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if attachments.isEmpty {
                Text("No files attached yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { attachment in
                    fileRow(attachment)
                }
            }

            HStack(spacing: 10) {
                Menu {
                    Button { showPhotoPicker = true } label: {
                        Label("From Photos", systemImage: "photo.on.rectangle")
                    }
                    Button { showFileImporter = true } label: {
                        Label("From Files", systemImage: "folder")
                    }
                    Button { showExistingPicker = true } label: {
                        Label("A File Already in the App", systemImage: "paperclip")
                    }
                } label: {
                    Label("Add file", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    openFolder()
                } label: {
                    Label("Client folder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.semibold))
            .tint(SBWTheme.brand)

            if attachments.count > 1 {
                Button {
                    exportZip()
                } label: {
                    Label("Share all as ZIP", systemImage: "doc.zipper")
                        .font(.subheadline)
                }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: UTType.importable,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): importFiles(urls)
            case .failure(let error): errorText = error.localizedDescription
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoSelection, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        let stamp = Int(Date().timeIntervalSince1970)
                        importPhoto(data, fileName: "Photo-\(stamp)-\(UUID().uuidString.prefix(6)).jpg")
                    }
                }
                photoSelection.removeAll()
            }
        }
        .sheet(isPresented: $showExistingPicker) {
            ClientAttachmentPickerView(businessID: client.businessID) { file in attachExisting(file) }
        }
        .sheet(item: $preview) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(item: $folderItem) { item in
            NavigationStack {
                FolderBrowserView(business: item.business, folder: item.folder)
            }
        }
        .sheet(item: $zipURL) { item in
            ShareSheet(items: [item.url])
        }
        .confirmationDialog(
            "Remove \(pendingRemoval?.file?.displayName ?? "this file")?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { attachment in
            Button("Remove from Client", role: .destructive) { remove(attachment) }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { _ in
            Text("The file stays in the client's folder.")
        }
        .alert("Files", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
    }

    private func fileRow(_ attachment: ClientAttachment) -> some View {
        HStack(spacing: 10) {
            Button {
                openPreview(attachment)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: iconName(for: attachment.file))
                        .foregroundStyle(SBWTheme.brand)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(attachment.file?.displayName ?? "Missing file")
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(attachment.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(role: .destructive) {
                    pendingRemoval = attachment
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("File options")
        }
    }

    private func iconName(for file: FileItem?) -> String {
        guard let ext = file?.fileExtension.lowercased() else { return "paperclip" }
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        if ["doc", "docx", "rtf", "txt", "pages"].contains(ext) { return "doc.text" }
        return "paperclip"
    }

    // MARK: - Actions

    private func openPreview(_ attachment: ClientAttachment) {
        guard let file = attachment.file else {
            errorText = "This file's record is missing."
            return
        }
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                errorText = "This file isn't on this device."
                return
            }
            preview = IdentifiableURL(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func openFolder() {
        do {
            let folder = try WorkspaceProvisioningService.ensureClientFolder(client: client, context: modelContext)
            folderItem = FolderSheetItem(business: try business(), folder: folder)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func business() throws -> Business {
        let businessID = client.businessID
        if let match = try modelContext.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first {
            return match
        }
        return try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)
    }

    private func folder(_ kind: FolderDestinationKind) throws -> Folder {
        try WorkspaceProvisioningService.resolveFolder(
            business: try business(),
            client: client,
            job: nil,
            kind: kind,
            context: modelContext
        )
    }

    private func attachExisting(_ file: FileItem) {
        guard !attachments.contains(where: { $0.fileKey == file.id.uuidString }) else { return }
        modelContext.insert(ClientAttachment(client: client, file: file))
        save()
    }

    private func importFiles(_ urls: [URL]) {
        for url in urls {
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                let destination = try folder(.attachments)
                let ext = url.pathExtension.lowercased()
                let (rel, size) = try AppFileStore.importFile(from: url, toRelativeFolderPath: destination.relativePath)
                let file = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: UTType(filenameExtension: ext)?.identifier ?? "public.data",
                    byteCount: size,
                    folderKey: destination.id.uuidString,
                    folder: destination
                )
                modelContext.insert(file)
                modelContext.insert(ClientAttachment(client: client, file: file))
            } catch {
                errorText = error.localizedDescription
                break
            }
        }
        save()
    }

    private func importPhoto(_ data: Data, fileName: String) {
        do {
            let destination = try folder(.photos)
            let (rel, size) = try AppFileStore.importData(
                data,
                toRelativeFolderPath: destination.relativePath,
                preferredFileName: fileName
            )
            let ext = (fileName as NSString).pathExtension.lowercased()
            let file = FileItem(
                displayName: (fileName as NSString).deletingPathExtension,
                originalFileName: fileName,
                relativePath: rel,
                fileExtension: ext,
                uti: "public.jpeg",
                byteCount: size,
                folderKey: destination.id.uuidString,
                folder: destination
            )
            modelContext.insert(file)
            modelContext.insert(ClientAttachment(client: client, file: file))
            save()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func remove(_ attachment: ClientAttachment) {
        modelContext.delete(attachment)
        pendingRemoval = nil
        save()
    }

    private func exportZip() {
        let urls: [URL] = attachments.compactMap { attachment in
            guard let file = attachment.file else { return nil }
            return try? AppFileStore.absoluteURL(forRelativePath: file.relativePath)
        }
        do {
            let url = try AttachmentZipExporter.zipFiles(urls, zipName: "\(client.displayName) Files")
            zipURL = IdentifiableURL(url: url)
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
