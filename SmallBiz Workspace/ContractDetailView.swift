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

    // Open Files (deep link)
    @State private var folderSheetItem: ContractFolderSheetItem? = nil
    @State private var workspaceError: String? = nil

    // Client Portal
    @State private var openingPortal = false
    @State private var portalURL: URL? = nil
    @State private var showPortal = false
    @State private var portalError: String? = nil

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
        Form {
            headerSection
            jobSection
            bodySection
            statusSection
            attachmentsSection
            exportSection
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }

        .sheet(item: $folderSheetItem) { item in
            NavigationStack {
                FolderBrowserView(business: item.business, folder: item.folder)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }

        // Job picker
        .sheet(isPresented: $showJobPicker) {
            NavigationStack {
                JobPickerView(
                    jobs: jobs,
                    selected: Binding(
                        get: { contract.job },
                        set: { newValue in
                            contract.job = newValue
                            try? modelContext.save()
                        }
                    )
                )
                .navigationTitle("Select Job")
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

        .onAppear {
            lastStatusRaw = contract.statusRaw
        }

        .onChange(of: contract.title) { _, _ in scheduleSave() }
        .onChange(of: contract.renderedBody) { _, _ in scheduleSave() }

        // ✅ Single, clean status watcher (autosave + index-once when transitioning to "sent")
        .onChange(of: contract.statusRaw) { _, newValue in
            let old = lastStatusRaw
            lastStatusRaw = newValue

            scheduleSave()

            guard old != "sent", newValue == "sent" else { return }

            Task {
                do {
                    // 1) Upload PDF -> Blob (writes contractPdfUrl + contractPdfFileName into KV)
                    guard let client = contract.client else { return }

                    let fileName: String = {
                        let t = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        return (t.isEmpty ? "Contract" : t).replacingOccurrences(of: "/", with: "-") + ".pdf"
                    }()

                    // Generate PDF (on-device)
                    let pdfData = ContractPDFGenerator.makePDFData(contract: contract, business: profiles.first)

                    // Upload to backend -> Blob -> KV
                    _ = try await PortalBackend.shared.uploadContractPDFToBlob(
                        businessId: client.businessID.uuidString,
                        contractId: contract.id.uuidString,
                        fileName: fileName,
                        pdfData: pdfData
                    )

                    // 2) Index contract into directory (so directory token passes NOT_IN_DIRECTORY)
                    try await PortalBackend.shared.indexContractForPortalDirectory(contract: contract)

                } catch {
                    print("Portal contract upload/index failed:", error.localizedDescription)
                }
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
                forceSaveNow()
                dismiss()
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

    var headerSection: some View {
        Section("Template Info") {
            LabeledContent("Template", value: contract.templateName.isEmpty ? "—" : contract.templateName)
            LabeledContent("Category", value: contract.templateCategory.isEmpty ? "General" : contract.templateCategory)
        }
    }

    var jobSection: some View {
        Section("Job / Project") {
            HStack {
                Text("Job")
                Spacer()
                Text(contract.job?.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                     ? (contract.job?.title ?? "")
                     : "None")
                    .foregroundStyle(contract.job == nil ? .secondary : .primary)
                    .lineLimit(1)
            }

            Button("Select Job") { showJobPicker = true }

            if contract.job != nil {
                Button(role: .destructive) {
                    contract.job = nil
                    try? modelContext.save()
                } label: {
                    Text("Clear Job")
                }
            }
        }
    }

    var bodySection: some View {
        Section("Contract Body") {
            TextEditor(text: $contract.renderedBody)
                .frame(minHeight: 260)
                .font(.body)
        }
    }

    var statusSection: some View {
        Section("Status") {
            Picker("Status", selection: $contract.statusRaw) {
                ForEach(ContractStatus.allCases, id: \.self) { s in
                    Text(s.rawValue.capitalized).tag(s.rawValue)
                }
            }
        }
    }

    var attachmentsSection: some View {
        Section("Attachments") {
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
    }

    var exportSection: some View {
        Section("Export / Share") {
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
    }
}

// MARK: - Actions

private extension ContractDetailView {

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

    // ✅ Contract uses contract.job directly; fallback to Files/Contracts if nil
    func openContractFolder() {
        do {
            let biz = try ActiveBusinessProvider.getOrCreateActiveBusiness(in: modelContext)

            try FolderService.bootstrapRootIfNeeded(businessID: biz.id, context: modelContext)
            guard let root = try FolderService.fetchRootFolder(businessID: biz.id, context: modelContext) else {
                workspaceError = "Files root folder could not be loaded."
                return
            }

            // If job exists -> open JOB…/Contracts
            if let job = contract.job {
                let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayTitle = title.isEmpty ? "Project" : title
                let shortID = job.id.uuidString.prefix(8)
                let jobFolderName = "JOB-\(shortID) \(displayTitle)"

                let jobFolder: Folder
                if let existing = allFolders.first(where: { f in
                    f.businessID == biz.id && f.parentFolderID == root.id && f.name == jobFolderName
                }) {
                    jobFolder = existing
                } else {
                    jobFolder = createJobWorkspaceFolder(businessID: biz.id, root: root, jobFolderName: jobFolderName)
                }

                let contractsFolder: Folder
                if let existingContracts = allFolders.first(where: { f in
                    f.businessID == biz.id && f.parentFolderID == jobFolder.id && f.name == "Contracts"
                }) {
                    contractsFolder = existingContracts
                } else {
                    let parentPath = jobFolder.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    let rel = parentPath.isEmpty ? "Contracts" : "\(parentPath)/Contracts"
                    let created = Folder(
                        businessID: biz.id,
                        name: "Contracts",
                        relativePath: rel,
                        parentFolderID: jobFolder.id
                    )
                    modelContext.insert(created)
                    try? modelContext.save()
                    contractsFolder = created
                }

                folderSheetItem = ContractFolderSheetItem(business: biz, folder: contractsFolder)
                return
            }

            // Fallback: Files root -> Contracts
            let contractsFolder: Folder
            if let existingContracts = allFolders.first(where: { f in
                f.businessID == biz.id && f.parentFolderID == root.id && f.name == "Contracts"
            }) {
                contractsFolder = existingContracts
            } else {
                let rootPath = root.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let rel = rootPath.isEmpty ? "Contracts" : "\(rootPath)/Contracts"
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

    func createJobWorkspaceFolder(businessID: UUID, root: Folder, jobFolderName: String) -> Folder {
        let rootPath = root.relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let jobRel = rootPath.isEmpty ? jobFolderName : "\(rootPath)/\(jobFolderName)"

        let jobFolder = Folder(
            businessID: businessID,
            name: jobFolderName,
            relativePath: jobRel,
            parentFolderID: root.id
        )
        modelContext.insert(jobFolder)

        let subs = ["Contracts", "Invoices", "Media", "Deliverables", "Reference"]
        for sub in subs {
            let subRel = "\(jobRel)/\(sub)"
            let f = Folder(
                businessID: businessID,
                name: sub,
                relativePath: subRel,
                parentFolderID: jobFolder.id
            )
            modelContext.insert(f)
        }

        try? modelContext.save()
        return jobFolder
    }

    func previewPDF() {
        do {
            let business = profiles.first
            let pdfData = ContractPDFGenerator.makePDFData(contract: contract, business: business)
            let filename = "Contract-\(Date().timeIntervalSince1970)"
            let url = try ContractPDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
            previewItem = ContractFileURL(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    func sharePDFOnly() {
        do {
            let business = profiles.first
            let pdfData = ContractPDFGenerator.makePDFData(contract: contract, business: business)
            let filename = "Contract-\(Date().timeIntervalSince1970)"
            let url = try ContractPDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
            shareItems = [url]
        } catch {
            exportError = error.localizedDescription
        }
    }

    func sharePDFWithAttachments() {
        do {
            let business = profiles.first
            let pdfData = ContractPDFGenerator.makePDFData(contract: contract, business: business)
            let filename = "Contract-\(Date().timeIntervalSince1970)"
            let url = try ContractPDFGenerator.writePDFToTemporaryFile(data: pdfData, filename: filename)
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

    var contractFolderKey: String { "contract:\(contract.id.uuidString)" }

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
                    folderKey: contractFolderKey,
                    folder: nil
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
            let fileId = UUID()
            let (rel, size) = try AppFileStore.importData(data, fileId: fileId, preferredFileName: suggestedFileName)
            let ext = (suggestedFileName as NSString).pathExtension.lowercased()
            let uti = UTType(filenameExtension: ext)?.identifier ?? "public.jpeg"

            let file = FileItem(
                displayName: suggestedFileName.replacingOccurrences(of: ".\(ext)", with: ""),
                originalFileName: suggestedFileName,
                relativePath: rel,
                fileExtension: ext,
                uti: uti,
                byteCount: size,
                folderKey: contractFolderKey,
                folder: nil
            )
            modelContext.insert(file)

            let link = ContractAttachment(contract: contract, file: file)
            modelContext.insert(link)

            try modelContext.save()
        } catch {
            attachError = error.localizedDescription
        }
    }
}

// MARK: - Inline Job Picker

private struct JobPickerView: View {
    let jobs: [Job]
    @Binding var selected: Job?

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    private var filtered: [Job] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return jobs }
        return jobs.filter { $0.title.lowercased().contains(q) || $0.status.lowercased().contains(q) }
    }

    var body: some View {
        List {
            Button {
                selected = nil
                dismiss()
            } label: {
                HStack {
                    Text("None")
                    Spacer()
                    if selected == nil {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }

            Section("Jobs") {
                if filtered.isEmpty {
                    Text("No jobs found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { job in
                        Button {
                            selected = job
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                    Text(job.status.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected?.id == job.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search jobs")
    }
}
