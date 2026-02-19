//
//  JobDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PhotosUI
import EventKit
import UIKit

private struct JobFolderSheetItem: Identifiable {
    let id = UUID()
    let business: Business
    let folder: Folder
}

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
    @State private var showAdvancedOptions = false
    @State private var folderSheetItem: JobFolderSheetItem? = nil
    @State private var jobFolder: Folder? = nil
    @State private var jobSubfolders: [JobWorkspaceSubfolder: Folder] = [:]
    @State private var workspaceError: String? = nil
    @State private var calendarError: String? = nil
    @State private var calendarPermissionDenied = false
    @State private var calendarSheetEvent: EKEvent? = nil

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
        List {
            jobEssentialsCard
            scheduleCard
            locationCard
            calendarCard
            linkedContractsCard
            filesCard
            advancedOptionsCard
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top) { pinnedHeader }
        .navigationTitle("Job")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedContract) { c in
            ContractDetailView(contract: c)
        }
        .sheet(item: $folderSheetItem) { item in
            NavigationStack {
                FolderBrowserView(business: item.business, folder: item.folder)
            }
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
        .sheet(isPresented: Binding(
            get: { calendarSheetEvent != nil },
            set: { if !$0 { calendarSheetEvent = nil } }
        )) {
            if let event = calendarSheetEvent {
                CalendarEventViewer(event: event)
            } else {
                Text("No event selected.")
            }
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
        .alert("Workspace", isPresented: Binding(
            get: { workspaceError != nil },
            set: { if !$0 { workspaceError = nil } }
        )) {
            Button("OK", role: .cancel) { workspaceError = nil }
        } message: {
            Text(workspaceError ?? "")
        }
        .task {
            if !isDraft {
                provisionFolders()
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

    private var jobTitleText: String {
        let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Job" : title
    }

    private var jobStatusText: String {
        switch job.stage {
        case .booked:
            return "SCHEDULED"
        case .inProgress:
            return "IN PROGRESS"
        case .completed:
            return "COMPLETED"
        case .canceled:
            return "CANCELED"
        }
    }

    private var jobScheduleSummary: String {
        "\(job.startDate.formatted(date: .abbreviated, time: .omitted)) - \(job.endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private var pinnedHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(jobTitleText)
                    .font(.headline)
                    .lineLimit(1)
                Text(jobScheduleSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            jobStatusPill
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var jobStatusPill: some View {
        let colors = SBWTheme.chip(forStatus: jobStatusText)
        return Text(jobStatusText)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
    }

    private var jobEssentialsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Essentials")
                .font(.headline)

            TextField("Title", text: $job.title)
                .onChange(of: job.title) { _, _ in
                    scheduleSave()
                    invalidateZip()

                    // ✅ Live rename (debounced)
                    scheduleWorkspaceRename()
                }

            Picker("Stage", selection: $job.stageRaw) {
                Text("Booked").tag(JobStage.booked.rawValue)
                Text("In Progress").tag(JobStage.inProgress.rawValue)
                Text("Completed").tag(JobStage.completed.rawValue)
                Text("Canceled").tag(JobStage.canceled.rawValue)
            }
            .pickerStyle(.menu)
            .onChange(of: job.stageRaw) { _, _ in
                scheduleSave()
            }
        }
        .sbwJobCardRow()
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Schedule")
                .font(.headline)

            DatePicker("Start", selection: $job.startDate)
                .onChange(of: job.startDate) { _, _ in scheduleSave() }

            DatePicker("End", selection: $job.endDate)
                .onChange(of: job.endDate) { _, _ in scheduleSave() }
        }
        .sbwJobCardRow()
    }

    private var locationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Location")
                .font(.headline)

            TextField("Location Name", text: $job.locationName)
                .onChange(of: job.locationName) { _, _ in scheduleSave() }
        }
        .sbwJobCardRow()
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Calendar")
                .font(.headline)

            if let eventID = job.calendarEventId,
               !eventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button("Update Calendar Event") {
                    Task { await syncCalendarEvent(viewAfter: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)

                Button("View Calendar Event") {
                    Task { await syncCalendarEvent(viewAfter: true) }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Add to Calendar") {
                    Task { await syncCalendarEvent(viewAfter: false) }
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }

            if calendarPermissionDenied {
                Text("Calendar permission is denied. Enable access in Settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.bordered)
            }

            if let calendarError, !calendarError.isEmpty {
                Text(calendarError)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .sbwJobCardRow()
    }

    private var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.subheadline.weight(.semibold))

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
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
    
    private var linkedContractsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contracts")
                .font(.headline)

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
        .sbwJobCardRow()
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job Files")
                .font(.headline)

            Button("Open Job Folder") {
                openFolder(kind: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(SBWTheme.brandBlue)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ], spacing: 10) {
                quickFolderButton(title: "Contracts", kind: .contracts)
                quickFolderButton(title: "Invoices", kind: .invoices)
                quickFolderButton(title: "Estimates", kind: .estimates)
                quickFolderButton(title: "Photos", kind: .photos)
                quickFolderButton(title: "Attachments", kind: .attachments)
                quickFolderButton(title: "Deliverables", kind: .deliverables)
                quickFolderButton(title: "Other", kind: .other)
            }
        }
        .sbwJobCardRow()
    }

    @ViewBuilder
    private func quickFolderButton(title: String, kind: JobWorkspaceSubfolder) -> some View {
        Button(title) {
            openFolder(kind: kind)
        }
        .buttonStyle(.bordered)
        .tint(.gray)
    }

    private var advancedOptionsCard: some View {
        DisclosureGroup(isExpanded: $showAdvancedOptions) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notes")
                        .font(.subheadline.weight(.semibold))

                    TextField("Notes", text: $job.notes, axis: .vertical)
                        .lineLimit(2...8)
                        .onChange(of: job.notes) { _, _ in scheduleSave() }
                }
                .padding(10)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                attachmentsCard

                Text("Changes auto-save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            HStack {
                Text("Advanced Options")
                    .font(.headline)
                Spacer()
            }
        }
        .sbwJobCardRow()
    }

    private func statusLabel(_ status: ContractStatus) -> String {
        switch status {
        case .draft: return "Draft"
        case .sent: return "Sent"
        case .signed: return "Signed"
        case .cancelled: return "Cancelled"
        }
    }

    private func openFolder(kind: JobWorkspaceSubfolder?) {
        do {
            let folder: Folder
            if let kind {
                if let cached = jobSubfolders[kind] {
                    folder = cached
                } else {
                    folder = try WorkspaceProvisioningService.fetchJobSubfolder(
                        job: job,
                        kind: kind,
                        context: modelContext
                    )
                    jobSubfolders[kind] = folder
                }
            } else {
                if let cached = jobFolder {
                    folder = cached
                } else {
                    let ensured = try WorkspaceProvisioningService.ensureJobWorkspace(
                        job: job,
                        context: modelContext
                    )
                    jobFolder = ensured
                    folder = ensured
                }
            }
            let business = try fetchBusiness(for: job.businessID)
            folderSheetItem = JobFolderSheetItem(business: business, folder: folder)
        } catch {
            workspaceError = error.localizedDescription
        }
    }

    private func provisionFolders() {
        do {
            if let clientID = job.clientID,
               let client = try modelContext.fetch(
                FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientID })
               ).first {
                _ = try WorkspaceProvisioningService.ensureClientFolder(client: client, context: modelContext)
            }

            let ensuredJobFolder = try WorkspaceProvisioningService.ensureJobWorkspace(
                job: job,
                context: modelContext
            )
            jobFolder = ensuredJobFolder
            jobSubfolders = try WorkspaceProvisioningService.ensureJobSubfolders(
                jobFolder: ensuredJobFolder,
                jobId: job.id,
                context: modelContext
            )
        } catch {
            workspaceError = error.localizedDescription
        }
    }

    private func fetchBusiness(for businessID: UUID) throws -> Business {
        if let match = try modelContext.fetch(
            FetchDescriptor<Business>(predicate: #Predicate { $0.id == businessID })
        ).first {
            return match
        }
        return try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)
    }

    @MainActor
    private func syncCalendarEvent(viewAfter: Bool) async {
        do {
            let client: Client?
            if let clientID = job.clientID {
                client = try modelContext.fetch(
                    FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientID })
                ).first
            } else {
                client = nil
            }

            let business = try fetchBusiness(for: job.businessID)
            let event = try await CalendarEventService.shared.createOrUpdateEvent(
                for: job,
                businessName: business.name,
                clientName: trimmed(client?.name),
                clientEmail: trimmed(client?.email),
                clientPhone: trimmed(client?.phone)
            )

            job.calendarEventId = event.eventIdentifier
            try modelContext.save()

            calendarPermissionDenied = false
            calendarError = nil

            if viewAfter {
                calendarSheetEvent = event
            }
        } catch let error as CalendarEventServiceError {
            if case .accessDenied = error {
                calendarPermissionDenied = true
            } else if case .accessRestricted = error {
                calendarPermissionDenied = true
            }
            calendarError = error.localizedDescription
        } catch {
            calendarError = error.localizedDescription
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
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

                let folder = try resolveDestinationFolder(kind: .attachments)

                let ext = url.pathExtension.lowercased()
                let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"
                let (rel, size) = try AppFileStore.importFile(
                    from: url,
                    toRelativeFolderPath: folder.relativePath
                )

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
            let folder = try resolveDestinationFolder(kind: .photos)
            let (rel, size) = try AppFileStore.importData(
                data,
                toRelativeFolderPath: folder.relativePath,
                preferredFileName: suggestedFileName
            )

            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"

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

            let link = JobAttachment(job: job, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
    }

    private func resolveDestinationFolder(kind: FolderDestinationKind) throws -> Folder {
        let business = try fetchBusiness(for: job.businessID)
        let client: Client?
        if let clientID = job.clientID {
            client = try modelContext.fetch(
                FetchDescriptor<Client>(predicate: #Predicate { $0.id == clientID })
            ).first
        } else {
            client = nil
        }
        return try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: client,
            job: job,
            kind: kind,
            context: modelContext
        )
    }
}

private struct SBWJobCardRow: ViewModifier {
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
    func sbwJobCardRow() -> some View {
        modifier(SBWJobCardRow())
    }
}
