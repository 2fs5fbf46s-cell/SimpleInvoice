//
//  ClientEditView.swift
//  SmallBiz Workspace
//

import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import ZIPFoundation

struct ClientEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissToDashboard) private var dismissToDashboard
    @Bindable var client: Client

    // Debounce saves (client fields)
    @State private var pendingSaveTask: Task<Void, Never>? = nil
    @State private var saveError: String? = nil

    // ✅ Attachments
    @Query private var attachments: [ClientAttachment]
    @State private var showExistingFilePicker = false
    @State private var showClientAttachmentFileImporter = false
    @State private var showClientAttachmentPhotosSheet = false
    @State private var attachError: String? = nil
    @State private var attachmentPreviewItem: IdentifiableURL? = nil

    // ✅ ZIP export
    @State private var zipURL: URL? = nil
    @State private var zipError: String? = nil

    // ✅ Client Portal Directory
    @State private var openingClientPortal = false
    @State private var clientPortalURL: URL? = nil
    @State private var showClientPortal = false
    @State private var clientPortalError: String? = nil


    // ✅ Flow A: Client → auto-create Job + workspace
    @Query private var clientJobs: [Job]
    @State private var didAutoCreateInitialJob = false

    // ✅ Flow A/B: Navigate into a job created from this screen
    @State private var navigateToJob: Job? = nil

    init(client: Client) {
        self.client = client

        let key = client.id.uuidString
        self._attachments = Query(
            filter: #Predicate<ClientAttachment> { a in
                a.clientKey == key
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )

        // Jobs tied to this client
        let clientID = client.id
        self._clientJobs = Query(
            filter: #Predicate<Job> { j in
                j.clientID == clientID
            },
            sort: [SortDescriptor(\.startDate, order: .reverse)]
        )
    }

    var body: some View { bodyContent }



    @ViewBuilder private var bodyContent: some View {
        Form {
            clientSection
            addressSection
            jobsSection
            attachmentsSection
            
            portalSection

            Section {

                Text("Changes auto-save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(client.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Client" : "Client")
        .navigationBarTitleDisplayMode(.inline)

        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismissToDashboard?()
                } label: {
                    Image(systemName: "house")
                }
                .accessibilityLabel("Home")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    saveNow()
                    dismiss()
                } label: {
                    Image(systemName: "checkmark")
                }
                .accessibilityLabel("Done")
            }
        }

        // ✅ Client → Job navigation
        .navigationDestination(item: $navigateToJob) { job in
            JobDetailView(job: job)
        }

        // ✅ Client Portal Directory Safari
        .sheet(isPresented: $showClientPortal) {
            if let url = clientPortalURL {
                SafariView(url: url, onDone: {})
            }
        }


        // ✅ Import directly to client attachments
        .fileImporter(
            isPresented: $showClientAttachmentFileImporter,
            allowedContentTypes: UTType.importable,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                importAndAttachFromFiles(urls: urls)
            case .failure(let error):
                attachError = error.localizedDescription
            }
        }

        // ✅ Photos import sheet (reliable)
        .sheet(isPresented: $showClientAttachmentPhotosSheet) {
            NavigationStack {
                List {
                    PhotosImportButton { data, suggestedName in
                        importAndAttachFromPhotos(data: data, suggestedFileName: suggestedName)
                        showClientAttachmentPhotosSheet = false
                    }
                }
                .navigationTitle("Import Photo")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showClientAttachmentPhotosSheet = false }
                    }
                }
            }
        }

        // ✅ Pick an existing file to attach
        .sheet(isPresented: $showExistingFilePicker) {
            ClientAttachmentPickerView { file in
                attachExisting(file)
            }
        }

        // ✅ QuickLook preview for attachments
        .sheet(item: $attachmentPreviewItem) { item in
            QuickLookPreview(url: item.url)
        }

        // Errors
        

        .alert("Client Portal", isPresented: Binding(
            get: { clientPortalError != nil },
            set: { if !$0 { clientPortalError = nil } }
        )) {
            Button("OK", role: .cancel) { clientPortalError = nil }
        } message: {
            Text(clientPortalError ?? "")
        }


        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }

        .alert("Attachment Error", isPresented: Binding(
            get: { attachError != nil },
            set: { if !$0 { attachError = nil } }
        )) {
            Button("OK", role: .cancel) { attachError = nil }
        } message: {
            Text(attachError ?? "")
        }

        .alert("ZIP Export Error", isPresented: Binding(
            get: { zipError != nil },
            set: { if !$0 { zipError = nil } }
        )) {
            Button("OK", role: .cancel) { zipError = nil }
        } message: {
            Text(zipError ?? "")
        }

        .task {
            // Safety net: ensure inserted so autosaves/queries don’t lock up UI.
            modelContext.insert(client)
            try? modelContext.save()

            // ✅ Flow A: If this client has no jobs yet, auto-create 1st Job + workspace
            autoCreateInitialJobIfNeeded()
        }

        .onDisappear {
            pendingSaveTask?.cancel()
            pendingSaveTask = nil
            // Don't force-save here. Navigation transitions can deadlock if save blocks.
        }
    }

    // MARK: - Flow A: Auto-create initial job + workspace

    @MainActor
    private func autoCreateInitialJobIfNeeded() {
        guard !didAutoCreateInitialJob else { return }
        guard clientJobs.isEmpty else { return }

        didAutoCreateInitialJob = true

        // NOTE: If you later have an “active business”, swap UUID() for that businessID.
        let job = Job(
            businessID: client.businessID,
            clientID: client.id,
            title: defaultJobTitle(for: client),
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        )
        job.status = "scheduled"
        job.notes = ""

        modelContext.insert(job)

        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            return
        }

        // Provision Files workspace (Job root + default subfolders)
        do {
            _ = try WorkspaceProvisioningService.ensureJobWorkspace(job: job, context: modelContext)
        } catch {
            // Don’t block UX; just log.
            print("Workspace provisioning failed for auto-created job: \(error)")
        }
    }

    private func defaultJobTitle(for client: Client) -> String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "New Job" : "\(name) Job"
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section("Client") {
            TextField("Name", text: $client.name)
                .onChange(of: client.name) { _, _ in scheduleSave() }

            TextField("Email", text: $client.email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .onChange(of: client.email) { _, _ in scheduleSave() }

            TextField("Phone", text: $client.phone)
                .keyboardType(.phonePad)
                .onChange(of: client.phone) { _, _ in scheduleSave() }
        }
    }

    private var addressSection: some View {
        Section("Address") {
            TextField("Address", text: $client.address, axis: .vertical)
                .lineLimit(2...6)
                .onChange(of: client.address) { _, _ in scheduleSave() }
        }
    }

    // MARK: - Jobs (Client → Job → ...)

    private var jobsSection: some View {
        Section("Jobs") {
            if clientJobs.isEmpty {
                Text("No jobs yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clientJobs) { job in
                    NavigationLink {
                        JobDetailView(job: job)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title)
                                    .font(.headline)

                                Text(job.startDate, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            StatusBadge(status: job.status)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            Button {
                createAdditionalJobForClient()
            } label: {
                Label("Create Job", systemImage: "plus")
            }
        }
    }

    @MainActor
    private func createAdditionalJobForClient() {
        // NOTE: If you later track an “active business”, swap UUID() for that businessID.
        let job = Job(
            businessID: client.businessID,
            clientID: client.id,
            title: defaultJobTitle(for: client),
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        )

        job.status = "scheduled"
        modelContext.insert(job)

        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
            return
        }

        // Provision Files workspace (Job root + default subfolders)
        do {
            _ = try WorkspaceProvisioningService.ensureJobWorkspace(job: job, context: modelContext)
        } catch {
            print("Workspace provisioning failed for new client job: \(error)")
        }

        // Navigate into job immediately
        navigateToJob = job
    }

    
    private var portalSection: some View {
        Section("Client Portal") {
            Toggle("Enable Client Portal", isOn: $client.portalEnabled)

            let portalHelpText = client.portalEnabled
                ? "This client can view invoices, contracts, and shared files online."
                : "Client portal is disabled for this client."

            Text(portalHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: openClientPortalDirectory) {
                Label(openingClientPortal ? "Opening…" : "Open Client Portal Directory",
                      systemImage: "person.2.badge.gearshape")
            }
            .disabled(openingClientPortal || !client.portalEnabled)
            .opacity((openingClientPortal || !client.portalEnabled) ? 0.6 : 1)

            // Keep your existing portal preview navigation if present elsewhere
        }
    }

private var attachmentsSection: some View {
        Section("Attachments") {
            if attachments.isEmpty {
                Text("No attachments yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { a in
                    Button {
                        openAttachmentPreview(a)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.file?.displayName ?? "Missing file")
                                Text(a.file?.originalFileName ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            removeAttachment(a)
                        } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }

            HStack {
                Button {
                    showExistingFilePicker = true
                } label: {
                    Label("Attach Existing File", systemImage: "paperclip")
                }

                Spacer()

                Menu {
                    Button("Import from Files") { showClientAttachmentFileImporter = true }
                    Button("Import from Photos") { showClientAttachmentPhotosSheet = true }
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }

            // ✅ ZIP export controls (attachments-only)
            if !attachments.isEmpty {
                Button {
                    exportAttachmentsZip()
                } label: {
                    Label("Export Attachments (ZIP)", systemImage: "doc.zipper")
                }

                if let zipURL {
                    ShareLink(item: zipURL) {
                        Label("Share ZIP", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    // MARK: - Save (client fields)

    private func scheduleSave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
            if Task.isCancelled { return }
            saveNow()
        }
    }

    private func saveNow() {
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
    // MARK: - Client Portal Directory

    @MainActor
    private func openClientPortalDirectory() {
        guard client.portalEnabled else { return }

        openingClientPortal = true
        clientPortalError = nil

        Task {
            do {
                let token = try await PortalBackend.shared.createClientDirectoryPortalToken(
                    client: client,
                    mode: "live"
                )
                let url = PortalBackend.shared.buildClientDirectoryPortalURL(
                    client: client,
                    token: token
                )
                clientPortalURL = url
                showClientPortal = true
            } catch {
                clientPortalError = error.localizedDescription
            }
            openingClientPortal = false
        }
    }

    // MARK: - Attachments helpers

    private var clientFolderKey: String {
        "client:\(client.id.uuidString)"
    }

    private func attachExisting(_ file: FileItem) {
        let fileKey = file.id.uuidString
        if attachments.contains(where: { $0.fileKey == fileKey }) { return }

        let link = ClientAttachment(client: client, file: file)
        modelContext.insert(link)

        do {
            try modelContext.save()
            invalidateZip()
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func removeAttachment(_ attachment: ClientAttachment) {
        modelContext.delete(attachment)
        do {
            try modelContext.save()
            invalidateZip()
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func openAttachmentPreview(_ attachment: ClientAttachment) {
        guard let file = attachment.file else {
            attachError = "This attachment’s file record is missing."
            return
        }

        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                attachError = "This file is missing from local storage."
                return
            }
            attachmentPreviewItem = IdentifiableURL(url: url)
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func importAndAttachFromFiles(urls: [URL]) {
        for url in urls {
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                let fileId = UUID()
                let ext = url.pathExtension.lowercased()
                let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"

                let (rel, size) = try AppFileStore.importFile(from: url, fileId: fileId)

                let file = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: uti,
                    byteCount: size,
                    folderKey: clientFolderKey,
                    folder: nil
                )
                modelContext.insert(file)

                let link = ClientAttachment(client: client, file: file)
                modelContext.insert(link)
            } catch {
                attachError = error.localizedDescription
                return
            }
        }

        do {
            try modelContext.save()
            invalidateZip()
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func importAndAttachFromPhotos(data: Data, suggestedFileName: String) {
        do {
            let fileId = UUID()

            let (rel, size) = try AppFileStore.importData(
                data,
                fileId: fileId,
                preferredFileName: suggestedFileName
            )

            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = "public.jpeg"

            let file = FileItem(
                displayName: suggestedFileName.replacingOccurrences(of: ".\(ext)", with: ""),
                originalFileName: suggestedFileName,
                relativePath: rel,
                fileExtension: ext,
                uti: uti,
                byteCount: size,
                folderKey: clientFolderKey,
                folder: nil
            )
            modelContext.insert(file)

            let link = ClientAttachment(client: client, file: file)
            modelContext.insert(link)

            try modelContext.save()
            invalidateZip()
        } catch {
            attachError = error.localizedDescription
        }
    }

    // MARK: - ZIP Export

    private func exportAttachmentsZip() {
        zipError = nil
        zipURL = nil

        let urls: [URL] = attachments.compactMap { a in
            guard let file = a.file else { return nil }
            return try? AppFileStore.absoluteURL(forRelativePath: file.relativePath)
        }

        do {
            let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let zipName = name.isEmpty
                ? "Client-\(client.id.uuidString)-Attachments"
                : "Client-\(name)-Attachments"

            let url = try AttachmentZipExporter.zipFiles(urls, zipName: zipName)
            zipURL = url
        } catch {
            zipError = error.localizedDescription
        }
    }

    private func invalidateZip() {
        zipURL = nil
        zipError = nil
    }

}

// MARK: - Small UI helpers

private struct StatusBadge: View {
    let status: String

    var body: some View {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines)
        Text(s.isEmpty ? "scheduled" : s)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .foregroundStyle(.secondary)
    }
}
