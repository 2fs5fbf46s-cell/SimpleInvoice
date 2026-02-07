//
//  JobDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI

struct JobDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var job: Job
    let isDraft: Bool

    // Debounced save
    @State private var pendingSaveTask: Task<Void, Never>? = nil
    @State private var saveError: String? = nil

    // ✅ NEW: Debounced workspace rename (live folder rename)
    @State private var pendingWorkspaceRenameTask: Task<Void, Never>? = nil

    // Attachments (join records)
    @Query private var attachments: [JobAttachment]

    @State private var showExistingFilePicker = false
    @State private var showJobFileImporter = false
    @State private var showJobPhotosSheet = false

    @State private var attachError: String? = nil
    @State private var previewItem: IdentifiableURL? = nil

    // ZIP export
    @State private var zipURL: URL? = nil
    @State private var zipError: String? = nil

    // Contracts navigation (avoid SwiftData NavigationLink freeze)
    @State private var selectedContract: Contract? = nil

    init(job: Job, isDraft: Bool = false) {
        self.job = job
        self.isDraft = isDraft

        let key = job.id.uuidString
        self._attachments = Query(
            filter: #Predicate<JobAttachment> { a in
                a.jobKey == key
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        Form {
            jobInfoSection
            scheduleSection
            locationSection
            attachmentsSection
            linkedContractsOnJobSection


            Section {
                Text("Changes auto-save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedContract) { c in
            ContractDetailView(contract: c)
        }

        // Import from Files -> create FileItem -> attach
        .fileImporter(
            isPresented: $showJobFileImporter,
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

        // Import from Photos (sheet, reliable)
        .sheet(isPresented: $showJobPhotosSheet) {
            NavigationStack {
                List {
                    PhotosImportButton { data, suggestedName in
                        importAndAttachFromPhotos(data: data, suggestedFileName: suggestedName)
                        showJobPhotosSheet = false
                    }
                }
                .navigationTitle("Import Photo")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showJobPhotosSheet = false }
                    }
                }
            }
        }

        // Attach existing file picker
        .sheet(isPresented: $showExistingFilePicker) {
            JobAttachmentPickerView { file in
                attachExisting(file)
            }
        }

        // QuickLook
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }

        // Alerts
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
            if !isDraft {
                try? DocumentFileIndexService.syncJobDocuments(job: job, context: modelContext)
            }
        }

        .onDisappear {
            if isDraft { return }
            pendingSaveTask?.cancel()
            pendingSaveTask = nil

            pendingWorkspaceRenameTask?.cancel()
            pendingWorkspaceRenameTask = nil

            saveNow()

            // Final sync on exit (safe, no auto-create)
            try? WorkspaceProvisioningService.syncJobWorkspaceName(job: job, context: modelContext)
        }
    }

    // MARK: - Sections

    private var jobInfoSection: some View {
        Section("Job") {
            TextField("Title", text: $job.title)
                .onChange(of: job.title) { _, _ in
                    scheduleSave()
                    invalidateZip()

                    // ✅ Live rename (debounced)
                    scheduleWorkspaceRename()
                }

            TextField("Status (scheduled / completed / canceled)", text: $job.status)
                .textInputAutocapitalization(.never)
                .onChange(of: job.status) { _, _ in scheduleSave() }

            TextField("Notes", text: $job.notes, axis: .vertical)
                .lineLimit(2...8)
                .onChange(of: job.notes) { _, _ in scheduleSave() }
        }
    }

    private var scheduleSection: some View {
        Section("Schedule") {
            DatePicker("Start", selection: $job.startDate)
                .onChange(of: job.startDate) { _, _ in scheduleSave() }

            DatePicker("End", selection: $job.endDate)
                .onChange(of: job.endDate) { _, _ in scheduleSave() }
        }
    }

    private var locationSection: some View {
        Section("Location") {
            TextField("Location Name", text: $job.locationName)
                .onChange(of: job.locationName) { _, _ in scheduleSave() }
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
                        openPreview(a)
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
                    Button("Import from Files") { showJobFileImporter = true }
                    Button("Import from Photos") { showJobPhotosSheet = true }
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }

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
    
    private var linkedContractsOnJobSection: some View {
        Section("Contracts") {
            let contracts = (job.contracts ?? [])

            if contracts.isEmpty {
                Text("No contracts linked to this job yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(contracts) { c in
                    Button {
                        selectedContract = c
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title.isEmpty ? "Contract" : c.title)
                                Text(statusLabel(c.status))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func statusLabel(_ status: ContractStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .signed: return "Signed"
        case .cancelled: return "Cancelled"
        }
    }

    
    


    // MARK: - Save helpers

    private func scheduleSave() {
        if isDraft { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            saveNow()
        }
    }

    private func saveNow() {
        if isDraft { return }
        do { try modelContext.save() }
        catch { saveError = error.localizedDescription }
    }

    // ✅ NEW: live workspace rename (debounced)
    private func scheduleWorkspaceRename() {
        if isDraft { return }
        pendingWorkspaceRenameTask?.cancel()
        pendingWorkspaceRenameTask = Task {
            // Rename less aggressively than autosave so typing feels smooth
            try? await Task.sleep(nanoseconds: 650_000_000)
            if Task.isCancelled { return }

            // This will NO-OP if workspaceFolderKey is nil (meaning no workspace yet)
            try? WorkspaceProvisioningService.syncJobWorkspaceName(job: job, context: modelContext)
        }
    }

    // MARK: - ZIP export helpers

    private func invalidateZip() {
        zipURL = nil
        zipError = nil
    }

    private func exportAttachmentsZip() {
        do {
            let urls = attachments.compactMap { a -> URL? in
                guard let file = a.file else { return nil }
                return try? AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            }

            let name = job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Job-\(job.id.uuidString)-Attachments"
                : "\(job.title)-Attachments"

            zipURL = try AttachmentZipExporter.zipFiles(urls, zipName: name)
        } catch {
            zipError = error.localizedDescription
        }
    }

    // MARK: - Attachments helpers

    private var jobFolderKey: String {
        "job:\(job.id.uuidString)"
    }

    private func attachExisting(_ file: FileItem) {
        let fileKey = file.id.uuidString
        if attachments.contains(where: { $0.fileKey == fileKey }) { return }

        let link = JobAttachment(job: job, file: file)
        modelContext.insert(link)

        do { try modelContext.save() }
        catch { attachError = error.localizedDescription }
    }

    private func removeAttachment(_ attachment: JobAttachment) {
        modelContext.delete(attachment)
        do { try modelContext.save() }
        catch { attachError = error.localizedDescription }
    }

    private func openPreview(_ attachment: JobAttachment) {
        guard let file = attachment.file else {
            attachError = "This attachment’s file record is missing."
            return
        }
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            previewItem = IdentifiableURL(url: url)
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

                let item = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: uti,
                    byteCount: size,
                    folderKey: jobFolderKey,
                    folder: nil
                )
                modelContext.insert(item)

                let link = JobAttachment(job: job, file: item)
                modelContext.insert(link)
            } catch {
                attachError = error.localizedDescription
                return
            }
        }

        do { try modelContext.save() }
        catch { attachError = error.localizedDescription }
    }

    private func importAndAttachFromPhotos(data: Data, suggestedFileName: String) {
        do {
            let fileId = UUID()
            let (rel, size) = try AppFileStore.importData(data, fileId: fileId, preferredFileName: suggestedFileName)

            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"

            let file = FileItem(
                displayName: suggestedFileName.replacingOccurrences(of: ".\(ext)", with: ""),
                originalFileName: suggestedFileName,
                relativePath: rel,
                fileExtension: ext,
                uti: uti,
                byteCount: size,
                folderKey: jobFolderKey,
                folder: nil
            )
            modelContext.insert(file)

            let link = JobAttachment(job: job, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
    }
}
