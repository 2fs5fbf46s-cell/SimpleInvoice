//
//  ContractDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private struct ContractFileURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ContractFolderSheetItem: Identifiable {
    let id = UUID()
    let business: Business
    let folder: Folder
}

struct ContractDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissToDashboard) private var dismissToDashboard

    @Bindable var contract: Contract

    @Query private var profiles: [BusinessProfile]
    @Query private var allFolders: [Folder]
    @Query private var attachments: [ContractAttachment]
    @Query private var templates: [ContractTemplate]

    // Jobs (for picker)
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)])
    private var jobs: [Job]

    @State private var shareItems: [Any]? = nil
    @State private var previewItem: ContractFileURL? = nil
    @State private var exportError: String? = nil

    // autosave
    @State private var saveWorkItem: DispatchWorkItem? = nil

    // attachments UI
    @State private var showExistingFilePicker = false
    @State private var showContractAttachmentFileImporter = false
    @State private var showContractAttachmentPhotosSheet = false
    @State private var attachError: String? = nil
    @State private var attachmentPreviewItem: IdentifiableURL? = nil

    // Job picker
    @State private var showJobPicker = false
    @State private var showAdvancedOptions = false
    @State private var lastAutoRenderedBody: String = ""
    @State private var pendingTemplateRerender = false

    // Open Files (deep link)
    @State private var folderSheetItem: ContractFolderSheetItem? = nil
    @State private var workspaceError: String? = nil

    // Client Portal
    @State private var openingPortal = false
    @State private var portalURL: URL? = nil
    @State private var showPortal = false
    @State private var portalError: String? = nil
    @State private var portalAutoSyncInFlight = false
    @State private var portalAutoSyncError: String? = nil
    @State private var navigateToClientSettings: Client? = nil

    // Status transition tracking (index once when it transitions TO "sent")
    @State private var lastStatusRaw: String = ""

    init(contract: Contract) {
        self.contract = contract

        let key = contract.id.uuidString
        self._attachments = Query(
            filter: #Predicate<ContractAttachment> { a in
                a.contractKey == key
            },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            essentialsSection
            jobsSection
            statusSection
            portalSection
            contractBodySection
            advancedOptionsSection
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) { pinnedHeader }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .navigationDestination(item: $navigateToClientSettings) { client in
            ClientEditView(client: client)
        }

        .sheet(item: $folderSheetItem) { item in
            NavigationStack {
                FolderBrowserView(business: item.business, folder: item.folder)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }

        // Job picker
        .sheet(isPresented: $showJobPicker) {
            NavigationStack {
                JobsPickerView(
                    jobs: jobs,
                    selectedJobIDs: Binding(
                        get: { linkedJobIDs },
                        set: { newValue in
                            setLinkedJobs(from: newValue)
                        }
                    ),
                    primaryJobID: Binding(
                        get: { contract.job?.id },
                        set: { newValue in
                            guard let newValue else { return }
                            setPrimaryJob(to: newValue)
                        }
                    )
                )
                .navigationTitle("Select Jobs")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showJobPicker = false }
                    }
                }
            }
        }

        .sheet(item: $previewItem) { item in
            NavigationStack {
                PDFPreviewView(url: item.url)
                    .navigationTitle("Contract PDF")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Share") {
                                sharePDFWithAttachments(fromExistingPDFURL: item.url)
                            }
                        }
                    }
            }
        }

        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [])
        }

        .sheet(isPresented: $showPortal) {
            if let url = portalURL {
                SafariView(url: url, onDone: {})
            }
        }

        .sheet(isPresented: $showExistingFilePicker) {
            ContractAttachmentPickerView { file in
                attachExisting(file)
            }
        }

        .sheet(item: $attachmentPreviewItem) { item in
            QuickLookPreview(url: item.url)
        }

        .fileImporter(
            isPresented: $showContractAttachmentFileImporter,
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

        .sheet(isPresented: $showContractAttachmentPhotosSheet) {
            NavigationStack {
                List {
                    PhotosImportButton { data, suggestedName in
                        importAndAttachFromPhotos(data: data, suggestedFileName: suggestedName)
                        showContractAttachmentPhotosSheet = false
                    }
                }
                .navigationTitle("Import Photo")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showContractAttachmentPhotosSheet = false }
                    }
                }
            }
        }

        .alert("Export Failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "Unknown error.")
        }

        .alert("Attachment Error", isPresented: .constant(attachError != nil)) {
            Button("OK") { attachError = nil }
        } message: {
            Text(attachError ?? "Unknown error.")
        }

        .alert("Client Portal", isPresented: .constant(portalError != nil)) {
            Button("OK") { portalError = nil }
        } message: {
            Text(portalError ?? "")
        }

        .alert("Workspace", isPresented: .constant(workspaceError != nil)) {
            Button("OK") { workspaceError = nil }
        } message: {
            Text(workspaceError ?? "")
        }
        .confirmationDialog(
            "Overwrite Contract Body?",
            isPresented: $pendingTemplateRerender,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) {
                rerenderBodyFromTemplate(force: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You edited this contract body manually. Overwrite it with the latest template render for the selected job?")
        }

        .onAppear {
            lastStatusRaw = contract.statusRaw
            lastAutoRenderedBody = contract.renderedBody
            syncLinkedJobsOnAppear()
            Task {
                try? DocumentFileIndexService.upsertContractPDF(
                    contract: contract,
                    context: modelContext
                )
            }
        }

        .onChange(of: contract.title) { _, _ in scheduleSave() }
        .onChange(of: contract.renderedBody) { _, _ in scheduleSave() }
        .onChange(of: contract.job?.id) { _, _ in
            syncLinkedJobIDsFromPrimary()
            rerenderBodyFromTemplate()
        }

        // ✅ Single, clean status watcher (autosave + index-once when transitioning to "sent")
        .onChange(of: contract.statusRaw) { _, newValue in
            let old = lastStatusRaw
            lastStatusRaw = newValue

            scheduleSave()
            if old != newValue {
                contract.portalNeedsUpload = true
            }
        }

        .onDisappear { forceSaveNow() }
    }

    private var navTitle: String {
        let t = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Contract" : t
    }
}

// MARK: - Toolbar

private extension ContractDetailView {
    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {

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
                handleDoneTapped()
            } label: {
                Image(systemName: "checkmark")
            }
            .accessibilityLabel("Done")
        }

        ToolbarItem(placement: .topBarTrailing) {
            let portalDisabled = (openingPortal || contract.client?.portalEnabled == false)

            Button(action: openContractPortalTapped) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .disabled(portalDisabled)
            .opacity(portalDisabled ? 0.6 : 1)
            .accessibilityLabel("Open in Client Portal")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button { openContractFolder() } label: {
                Image(systemName: "folder")
            }
            .accessibilityLabel("Open Files")
        }
    }
}

// MARK: - Sections

private extension ContractDetailView {
    var pinnedHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(navTitle)
                    .font(.headline)
                    .lineLimit(1)
                Text(secondaryHeaderText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            statusPill(text: contract.statusRaw.uppercased())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            SBWTheme.brandGradient
                .opacity(0.12)
                .overlay(Color(.systemBackground).opacity(0.85))
        )
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }

    var essentialsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Essentials")
                .font(.headline)

            TextField("Title", text: $contract.title)
                .onChange(of: contract.title) { _, _ in scheduleSave() }

            LabeledContent("Template", value: contract.templateName.isEmpty ? "—" : contract.templateName)
            LabeledContent("Category", value: contract.templateCategory.isEmpty ? "General" : contract.templateCategory)
        }
        .sbwContractCardRow()
    }

    var jobsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Jobs")
                .font(.headline)

            if linkedJobsResolved.isEmpty {
                Text("No jobs linked")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(linkedJobsResolved) { job in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled Job" : job.title)
                                .lineLimit(1)
                            Text(job.status.uppercased())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if contract.job?.id == job.id {
                            Text("Primary")
                                .font(.caption2.weight(.semibold))
                                .padding(.vertical, 3)
                                .padding(.horizontal, 8)
                                .background(Capsule().fill(SBWTheme.cardStroke.opacity(0.35)))
                        }
                    }
                }
            }

            Button("Manage Jobs") { showJobPicker = true }
                .buttonStyle(.bordered)

            if !linkedJobsResolved.isEmpty {
                Button(role: .destructive) {
                    contract.job = nil
                    contract.linkedJobIDsCSV = ""
                    rerenderBodyFromTemplate()
                    try? modelContext.save()
                } label: {
                    Text("Clear Linked Jobs")
                }
            }
        }
        .sbwContractCardRow()
    }

    var portalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Client Portal")
                .font(.headline)

            let portalEnabled = contract.client?.portalEnabled == true
            let hasClient = contract.client != nil
            let canOpenPortal = hasClient && portalEnabled

            HStack(spacing: 8) {
                Text(contractPortalSyncStatusText)
                    .font(.caption)
                    .foregroundStyle(portalAutoSyncError == nil ? Color.secondary : Color.red)
                Spacer()
                if (contract.portalNeedsUpload || portalAutoSyncError != nil) && canOpenPortal {
                    Button("Retry") {
                        triggerContractPortalAutoSync()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(portalAutoSyncInFlight)
                }
            }

            if !hasClient {
                Text("Assign a client to enable portal access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !portalEnabled {
                Text("Client portal is disabled for this client.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if contract.portalNeedsUpload {
                Text("Pending upload—tap Done to sync latest changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                openContractPortalTapped()
            } label: {
                Label(openingPortal ? "Opening…" : "Open in Client Portal", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .disabled(openingPortal || !canOpenPortal)
            .opacity((openingPortal || !canOpenPortal) ? 0.6 : 1)

            if let client = contract.client, !portalEnabled {
                Button {
                    navigateToClientSettings = client
                } label: {
                    Label("Enable Client Portal", systemImage: "togglepower")
                }
                .buttonStyle(.bordered)
                .tint(SBWTheme.brandBlue)
            }
        }
        .sbwContractCardRow()
    }

    var contractBodySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Contract Body")
                .font(.headline)

            TextEditor(text: $contract.renderedBody)
                .frame(minHeight: 260)
                .font(.body)
        }
        .sbwContractCardRow()
    }

    var statusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status")
                .font(.headline)

            Picker("Status", selection: $contract.statusRaw) {
                ForEach(ContractStatus.allCases, id: \.self) { s in
                    Text(s.rawValue.capitalized).tag(s.rawValue)
                }
            }
        }
        .sbwContractCardRow()
    }

    var attachmentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.subheadline.weight(.semibold))

            if attachments.isEmpty {
                Text("No attachments yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { a in
                    Button { openAttachmentPreview(a) } label: {
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
                        Button(role: .destructive) { removeAttachment(a) } label: {
                            Label("Remove", systemImage: "trash")
                        }
                    }
                }
            }

            HStack {
                Button { showExistingFilePicker = true } label: {
                    Label("Attach Existing File", systemImage: "paperclip")
                }

                Spacer()

                Menu {
                    Button("Import from Files") { showContractAttachmentFileImporter = true }
                    Button("Import from Photos") { showContractAttachmentPhotosSheet = true }
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
        .sbwContractCardRow()
    }

    var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Export / Share")
                .font(.subheadline.weight(.semibold))

            Button { previewPDF() } label: {
                Label("Preview PDF", systemImage: "doc.richtext")
            }

            Menu {
                Button("Share PDF Only") { sharePDFOnly() }
                Button("Share PDF + Attachments") { sharePDFWithAttachments() }
                Button("Share Attachments ZIP") { shareAttachmentsZIPOnly() }
                Button("Share as Text") { shareAsText() }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        .sbwContractCardRow()
    }

    var advancedOptionsSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedOptions) {
            VStack(spacing: 12) {
                attachmentsCard
                exportCard
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text("Advanced Options")
                    .font(.headline)
                Spacer()
                Text(showAdvancedOptions ? "Hide" : "Show")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sbwContractCardRow()
    }
}

private extension ContractDetailView {
    var linkedJobIDs: [UUID] {
        parseJobIDs(contract.linkedJobIDsCSV)
    }

    var linkedJobsResolved: [Job] {
        let ids = Set(linkedJobIDs)
        let selected = jobs.filter { ids.contains($0.id) }
        if selected.isEmpty, let primary = contract.job {
            return [primary]
        }
        return selected.sorted { $0.startDate > $1.startDate }
    }

    var secondaryHeaderText: String {
        if let client = contract.client?.name.trimmingCharacters(in: .whitespacesAndNewlines), !client.isEmpty {
            return client
        }
        let template = contract.templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        return template.isEmpty ? "Contract" : template
    }

    func statusPill(text: String) -> some View {
        let colors = SBWTheme.chip(forStatus: text)
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
    }

    func parseJobIDs(_ csv: String) -> [UUID] {
        csv
            .split(separator: ",")
            .compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
    }
}

// MARK: - Actions

private extension ContractDetailView {
    @MainActor
    func rerenderBodyFromTemplate(force: Bool = false) {
        guard let template = templates.first(where: { $0.name == contract.templateName }) else { return }

        let ctx = ContractContext(
            business: profiles.first,
            client: contract.client,
            invoice: contract.invoice,
            extras: [:]
        )

        let rendered = ContractTemplateEngine.render(template: template.body, context: ctx)

        if !force, contract.renderedBody != lastAutoRenderedBody {
            pendingTemplateRerender = true
            return
        }

        pendingTemplateRerender = false
        contract.renderedBody = rendered
        lastAutoRenderedBody = rendered
        scheduleSave()
    }

    @MainActor
    func openContractInClientPortal() async {
        openingPortal = true
        portalError = nil

        do {
            let token = try await PortalBackend.shared.createContractPortalToken(contract: contract)
            let url = PortalBackend.shared.portalContractURL(contractId: contract.id.uuidString, token: token)
            portalURL = url
            showPortal = true
        } catch {
            portalError = error.localizedDescription
        }

        openingPortal = false
    }

    @MainActor
    private func openContractPortalTapped() {
        Task { await openContractInClientPortal() }
    }

    func syncLinkedJobsOnAppear() {
        var ids = Set(linkedJobIDs)
        if let primaryID = contract.job?.id {
            ids.insert(primaryID)
        }
        let resolved = jobs.filter { ids.contains($0.id) }
        if contract.job == nil, let first = resolved.sorted(by: { $0.startDate > $1.startDate }).first {
            contract.job = first
            ids.insert(first.id)
        }
        contract.linkedJobIDsCSV = ids.map(\.uuidString).joined(separator: ",")
    }

    func syncLinkedJobIDsFromPrimary() {
        guard let id = contract.job?.id else { return }
        var ids = Set(linkedJobIDs)
        ids.insert(id)
        contract.linkedJobIDsCSV = ids.map(\.uuidString).joined(separator: ",")
        scheduleSave()
    }

    func setPrimaryJob(to jobID: UUID) {
        guard let picked = jobs.first(where: { $0.id == jobID }) else { return }
        contract.job = picked
        var ids = Set(linkedJobIDs)
        ids.insert(jobID)
        contract.linkedJobIDsCSV = ids.map(\.uuidString).joined(separator: ",")
        rerenderBodyFromTemplate()
        scheduleSave()
    }

    func setLinkedJobs(from ids: [UUID]) {
        let unique = Array(Set(ids))
        let selectedJobs = jobs.filter { unique.contains($0.id) }
            .sorted { $0.startDate > $1.startDate }

        if let current = contract.job, selectedJobs.contains(where: { $0.id == current.id }) {
            contract.job = current
        } else {
            contract.job = selectedJobs.first
        }

        if contract.job == nil {
            contract.linkedJobIDsCSV = ""
        } else {
            var finalIDs = Set(unique)
            if let primaryID = contract.job?.id {
                finalIDs.insert(primaryID)
            }
            contract.linkedJobIDsCSV = finalIDs.map(\.uuidString).joined(separator: ",")
        }

        rerenderBodyFromTemplate()
        scheduleSave()
    }

    func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem {
            do {
                contract.updatedAt = .now
                try modelContext.save()
            } catch {
                print("Auto-save failed: \(error)")
            }
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    func forceSaveNow() {
        saveWorkItem?.cancel()
        do {
            contract.updatedAt = .now
            try modelContext.save()
        } catch {
            print("Force save failed: \(error)")
        }
    }

    var contractPortalSyncStatusText: String {
        if portalAutoSyncInFlight {
            return "Portal: Uploading..."
        }
        if let portalAutoSyncError, !portalAutoSyncError.isEmpty {
            return "Portal: Upload failed"
        }
        if contract.portalNeedsUpload {
            return "Portal: Pending upload"
        }
        return "Portal: Up to date"
    }

    func handleDoneTapped() {
        portalAutoSyncError = nil
        PortalAutoSyncService.markContractNeedsUploadIfChanged(contract: contract)
        forceSaveNow()
        triggerContractPortalAutoSync()
        dismiss()
    }

    func triggerContractPortalAutoSync() {
        guard PortalAutoSyncService.isEligible(contract: contract) else { return }
        let contractID = contract.id
        portalAutoSyncInFlight = true
        Task {
            let result = await PortalAutoSyncService.uploadContract(
                contractId: contractID,
                context: modelContext
            )
            await MainActor.run {
                portalAutoSyncInFlight = false
                switch result {
                case .failed(let message):
                    portalAutoSyncError = message
                case .uploaded, .skippedUnchanged:
                    portalAutoSyncError = nil
                case .ineligible:
                    break
                }
            }
        }
    }

    // ✅ Contract uses contract.job directly; fallback to Files/Contracts if nil
    func openContractFolder() {
        do {
            if let job = contract.job {
                let contractsFolder = try WorkspaceProvisioningService.fetchJobSubfolder(
                    job: job,
                    kind: .contracts,
                    context: modelContext
                )
                let biz = try fetchBusiness(for: job.businessID)
                folderSheetItem = ContractFolderSheetItem(business: biz, folder: contractsFolder)
                return
            }

            let biz = try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)
            try FolderService.bootstrapRootIfNeeded(businessID: biz.id, context: modelContext)
            guard let root = try FolderService.fetchRootFolder(businessID: biz.id, context: modelContext) else {
                workspaceError = "Files root folder could not be loaded."
                return
            }

            let rootPath = root.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let rel = rootPath.isEmpty ? "Contracts" : "\(rootPath)/Contracts"

            let contractsFolder: Folder
            if let existing = try FolderService.fetchFolder(
                businessID: biz.id,
                relativePath: rel,
                context: modelContext
            ) {
                contractsFolder = existing
            } else {
                let created = Folder(
                    businessID: biz.id,
                    name: "Contracts",
                    relativePath: rel,
                    parentFolderID: root.id
                )
                modelContext.insert(created)
                try? modelContext.save()
                contractsFolder = created
            }

            folderSheetItem = ContractFolderSheetItem(business: biz, folder: contractsFolder)
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

    private func persistContractPDFToJobFiles() throws -> URL {
        try DocumentFileIndexService.persistContractPDF(
            contract: contract,
            business: profiles.first,
            context: modelContext
        )
    }

    func previewPDF() {
        do {
            let url = try persistContractPDFToJobFiles()
            previewItem = ContractFileURL(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    func sharePDFOnly() {
        do {
            let url = try persistContractPDFToJobFiles()
            shareItems = [url]
        } catch {
            exportError = error.localizedDescription
        }
    }

    func sharePDFWithAttachments() {
        do {
            let url = try persistContractPDFToJobFiles()
            sharePDFWithAttachments(fromExistingPDFURL: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    func sharePDFWithAttachments(fromExistingPDFURL pdfURL: URL) {
        var items: [Any] = [pdfURL]
        items.append(contentsOf: attachmentURLsForContract())
        shareItems = items
    }

    func shareAttachmentsZIPOnly() {
        do {
            let urls = attachmentURLsForContract()
            let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let zipName = title.isEmpty ? "Contract-\(contract.id.uuidString)-Attachments" : "Contract-\(title)-Attachments"
            let zipURL = try AttachmentZipExporter.zipFiles(urls, zipName: zipName)
            shareItems = [zipURL]
        } catch {
            exportError = error.localizedDescription
        }
    }

    func shareAsText() {
        let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = "\(title.isEmpty ? "Contract" : title)\n\n\(body)"
        let url = writeTextToTempFile(text: combined)
        shareItems = [url]
    }

    func writeTextToTempFile(text: String) -> URL {
        let safeName = "ContractText-\(Date().timeIntervalSince1970).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safeName)
        try? text.data(using: .utf8)?.write(to: url, options: [.atomic])
        return url
    }

    func attachmentURLsForContract() -> [URL] {
        attachments.compactMap { a in
            guard let file = a.file else { return nil }
            return try? AppFileStore.absoluteURL(forRelativePath: file.relativePath)
        }
    }

    func attachExisting(_ file: FileItem) {
        let fileKey = file.id.uuidString
        if attachments.contains(where: { $0.fileKey == fileKey }) { return }
        let link = ContractAttachment(contract: contract, file: file)
        modelContext.insert(link)
        do { try modelContext.save() } catch { attachError = error.localizedDescription }
    }

    func removeAttachment(_ attachment: ContractAttachment) {
        modelContext.delete(attachment)
        do { try modelContext.save() } catch { attachError = error.localizedDescription }
    }

    func openAttachmentPreview(_ attachment: ContractAttachment) {
        guard let file = attachment.file else { attachError = "This attachment’s file record is missing."; return }
        do {
            let url = try AppFileStore.absoluteURL(forRelativePath: file.relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else { attachError = "This file is missing from local storage."; return }
            attachmentPreviewItem = IdentifiableURL(url: url)
        } catch {
            attachError = error.localizedDescription
        }
    }

    func importAndAttachFromFiles(urls: [URL]) {
        for url in urls {
            do {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }

                let folder = try resolveAttachmentFolder(kind: .attachments)

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

                let link = ContractAttachment(contract: contract, file: item)
                modelContext.insert(link)
            } catch {
                attachError = error.localizedDescription
                return
            }
        }
        do { try modelContext.save() } catch { attachError = error.localizedDescription }
    }

    func importAndAttachFromPhotos(data: Data, suggestedFileName: String) {
        do {
            let folder = try resolveAttachmentFolder(kind: .photos)
            let (rel, size) = try AppFileStore.importData(
                data,
                toRelativeFolderPath: folder.relativePath,
                preferredFileName: suggestedFileName
            )
            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = UTType(filenameExtension: ext)?.identifier ?? "public.jpeg"

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

            let link = ContractAttachment(contract: contract, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
    }

    func resolveAttachmentFolder(kind: FolderDestinationKind) throws -> Folder {
        let business = try fetchBusiness(for: contract.businessID)
        return try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: contract.resolvedClient,
            job: contract.job,
            kind: kind,
            context: modelContext
        )
    }
}

// MARK: - Inline Job Picker

private struct JobsPickerView: View {
    let jobs: [Job]
    @Binding var selectedJobIDs: [UUID]
    @Binding var primaryJobID: UUID?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [Job] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return jobs }
        return jobs.filter {
            $0.title.lowercased().contains(q) || $0.status.lowercased().contains(q)
        }
    }

    private var selectedSet: Set<UUID> {
        Set(selectedJobIDs)
    }

    var body: some View {
        List {
            if selectedJobIDs.isEmpty {
                Text("No linked jobs")
                    .foregroundStyle(.secondary)
            } else {
                Section("Linked Jobs") {
                    ForEach(jobs.filter { selectedSet.contains($0.id) }) { job in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                Text(job.status.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if primaryJobID == job.id {
                                Text("Primary")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            primaryJobID = job.id
                        }
                    }
                    Button(role: .destructive) {
                        selectedJobIDs = []
                        primaryJobID = nil
                    } label: {
                        Text("Clear All")
                    }
                }
            }

            Section("All Jobs") {
                if filtered.isEmpty {
                    Text("No jobs found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { job in
                        Button {
                            toggle(job.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                    Text(job.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedSet.contains(job.id) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search jobs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func toggle(_ id: UUID) {
        var set = Set(selectedJobIDs)
        if set.contains(id) {
            set.remove(id)
            if primaryJobID == id {
                primaryJobID = set.first
            }
        } else {
            set.insert(id)
            if primaryJobID == nil {
                primaryJobID = id
            }
        }
        selectedJobIDs = Array(set)
    }
}

private struct SBWContractCardRow: ViewModifier {
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
    func sbwContractCardRow() -> some View {
        modifier(SBWContractCardRow())
    }
}
