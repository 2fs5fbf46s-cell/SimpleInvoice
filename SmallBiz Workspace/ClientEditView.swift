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
import UIKit
import Contacts
import ContactsUI

private struct ClientFolderSheetItem: Identifiable {
    let id = UUID()
    let business: Business
    let folder: Folder
}

struct ClientEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dismissToDashboard) private var dismissToDashboard
    @Bindable var client: Client
    let isDraft: Bool
    let onOpenExisting: ((Client) -> Void)?

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
    
    // ✅ Send Portal Link UI
    @State private var showSendPortalSheet = false
    @State private var sendingPortalLink = false
    @State private var sendPortalError: String? = nil
    @State private var lastSentPortalLink: String? = nil

    @State private var sendByEmail = true
    @State private var sendBySms = true
    @State private var ttlDays: Int = 7
    @State private var customMessage: String = ""
    @State private var showingContactPicker = false
    @State private var suppressAutoSave = false
    @State private var showContactImportBanner = false
    @State private var contactImportError: String? = nil
    @State private var pendingContact: CNContact? = nil
    @State private var duplicateCandidate: Client? = nil
    @State private var showDuplicateDialog = false
    @State private var navigateToExistingClient: Client? = nil
    @State private var showAdvancedOptions = false
    @State private var contactAccessDenied = false
    @State private var clientFolderSheetItem: ClientFolderSheetItem? = nil
    @State private var clientFolder: Folder? = nil
    @State private var workspaceError: String? = nil


    @Query private var businessClients: [Client]
    @Query private var clientJobs: [Job]

    // ✅ Flow A/B: Navigate into a job created from this screen
    @State private var navigateToJob: Job? = nil
    @State private var selectedJob: Job? = nil

    init(client: Client, isDraft: Bool = false, onOpenExisting: ((Client) -> Void)? = nil) {
        self.client = client
        self.isDraft = isDraft
        self.onOpenExisting = onOpenExisting

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

        let businessID = client.businessID
        self._businessClients = Query(
            filter: #Predicate<Client> { c in
                c.businessID == businessID
            },
            sort: [SortDescriptor(\.name, order: .forward)]
        )
    }

    var body: some View { lifecycleView }

    private var baseListView: some View {
        List {
            clientEssentialsSection
            clientAddressSection
            clientPortalSection
            linkedItemsSection
            clientFilesSection
            advancedOptionsSection
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top) { pinnedHeader }
        .navigationTitle("Client")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .erased()
    }

    private var navigationAndSheetsView: some View {
        baseListView
            .navigationDestination(item: $navigateToJob) { job in
                JobDetailView(job: job)
            }
            .navigationDestination(item: $selectedJob) { job in
                JobDetailView(job: job)
            }
            .navigationDestination(item: $navigateToExistingClient) { existing in
                ClientEditView(client: existing)
            }
            .sheet(item: $clientFolderSheetItem) { item in
                NavigationStack {
                    FolderBrowserView(business: item.business, folder: item.folder)
                }
            }
            .sheet(isPresented: $showClientPortal) {
                if let url = clientPortalURL {
                    SafariView(url: url, onDone: {})
                }
            }
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
            .sheet(isPresented: $showExistingFilePicker) {
                ClientAttachmentPickerView { file in
                    attachExisting(file)
                }
            }
            .sheet(item: $attachmentPreviewItem) { item in
                QuickLookPreview(url: item.url)
            }
            .sheet(isPresented: $showSendPortalSheet) {
                sendPortalSheetView
            }
        .sheet(isPresented: $showingContactPicker) {
            ContactPicker(isPresented: $showingContactPicker) { contact in
                handleContactSelection(contact)
            } onCancel: {
            }
        }
        .erased()
    }

    private var alertsAndOverlaysView: some View {
        navigationAndSheetsView
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
            .alert("Send Portal Link", isPresented: Binding(
                get: { sendPortalError != nil },
                set: { if !$0 { sendPortalError = nil } }
            )) {
                Button("OK", role: .cancel) { sendPortalError = nil }
            } message: {
                Text(sendPortalError ?? "")
            }
            .alert("Import from Contacts Failed", isPresented: Binding(
                get: { contactImportError != nil },
                set: { if !$0 { contactImportError = nil } }
            )) {
                Button("OK", role: .cancel) { contactImportError = nil }
            } message: {
                Text(contactImportError ?? "")
            }
        .alert("Workspace", isPresented: Binding(
            get: { workspaceError != nil },
            set: { if !$0 { workspaceError = nil } }
        )) {
            Button("OK", role: .cancel) { workspaceError = nil }
        } message: {
            Text(workspaceError ?? "")
        }
        .erased()
        .confirmationDialog(
                "Existing Client Found",
                isPresented: $showDuplicateDialog,
                presenting: duplicateCandidate
            ) { match in
                Button("Open Existing") {
                    if let onOpenExisting {
                        onOpenExisting(match)
                    } else if isDraft {
                        dismiss()
                    } else {
                        navigateToExistingClient = match
                    }
                    pendingContact = nil
                    duplicateCandidate = nil
                }
                Button("Create New Anyway") {
                    if let contact = pendingContact {
                        applyContactToClient(contact)
                    }
                    pendingContact = nil
                    duplicateCandidate = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingContact = nil
                    duplicateCandidate = nil
                }
            } message: { match in
                Text("A client with the same email or phone already exists: \(match.name.isEmpty ? "Client" : match.name).")
            }
            .overlay(alignment: .top) {
                if showContactImportBanner {
                    ContactImportBanner()
                        .padding(.top, 8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
    }

    private var lifecycleView: some View {
        alertsAndOverlaysView
            .onDisappear {
                pendingSaveTask?.cancel()
                pendingSaveTask = nil
                // Don't force-save here. Navigation transitions can deadlock if save blocks.
            }
            .onAppear {
                refreshContactsPermissionState()
                guard !isDraft else { return }
                clientFolder = try? WorkspaceProvisioningService.ensureClientFolder(client: client, context: modelContext)
            }
    }

    private var sendPortalSheetView: some View {
        NavigationStack {
            Form {
                Section("Send via") {
                    Toggle("Email", isOn: $sendByEmail)
                    Toggle("SMS", isOn: $sendBySms)
                }

                Section("Recipient") {
                    HStack {
                        Text("Email")
                        Spacer()
                        Text(client.email.isEmpty ? "Missing" : client.email)
                            .foregroundStyle(client.email.isEmpty ? .red : .secondary)
                            .lineLimit(1)
                    }

                    HStack {
                        Text("Phone")
                        Spacer()
                        Text(client.phone.isEmpty ? "Missing" : client.phone)
                            .foregroundStyle(client.phone.isEmpty ? .red : .secondary)
                            .lineLimit(1)
                    }
                }

                Section("Link Settings") {
                    Stepper("Expires in \(ttlDays) day(s)", value: $ttlDays, in: 1...30)
                }

                Section("Optional Message") {
                    TextField("Custom message (optional)", text: $customMessage, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Button {
                        sendPortalLinkNow()
                    } label: {
                        HStack {
                            Spacer()
                            if sendingPortalLink {
                                ProgressView()
                            } else {
                                Text("Send Portal Link")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(sendingPortalLink || (!sendByEmail && !sendBySms))
                }

                if let link = lastSentPortalLink, !link.isEmpty {
                    Section("Last Link") {
                        Text(link)
                            .font(.footnote)
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = link
                        } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                        }

                        if let url = URL(string: link) {
                            ShareLink(item: url) {
                                Label("Share…", systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Send Portal Link")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showSendPortalSheet = false }
                }
            }
        }
    }

    private var clientDisplayName: String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? (isDraft ? "New Client" : "Client") : name
    }

    private var clientSecondarySummary: String {
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = client.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty, !phone.isEmpty { return "\(email) • \(phone)" }
        if !email.isEmpty { return email }
        if !phone.isEmpty { return phone }
        return "No contact details yet"
    }

    private func defaultJobTitle(for client: Client) -> String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "New Job" : "\(name) Job"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if !isDraft {
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

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if !client.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Copy Email") {
                        UIPasteboard.general.string = client.email
                    }
                }
                if !client.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Copy Phone") {
                        UIPasteboard.general.string = client.phone
                    }
                }
                Button("Copy Contact Info") {
                    UIPasteboard.general.string = "\(client.name)\n\(client.email)\n\(client.phone)".trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("More Actions")
        }
    }

    // MARK: - Sections

    private var pinnedHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(clientDisplayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(clientSecondarySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            portalStatusPill
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var portalStatusPill: some View {
        let text = client.portalEnabled ? "PORTAL ON" : "PORTAL OFF"
        let colors = SBWTheme.chip(forStatus: text)
        return Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(colors.bg))
            .foregroundStyle(colors.fg)
    }

    private var clientEssentialsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Essentials")
                .font(.headline)

            TextField("Name", text: $client.name)
                .textInputAutocapitalization(.words)
                .onChange(of: client.name) { _, _ in scheduleSave() }

            TextField("Email", text: $client.email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .onChange(of: client.email) { _, _ in scheduleSave() }

            TextField("Phone", text: $client.phone)
                .keyboardType(.phonePad)
                .onChange(of: client.phone) { _, _ in scheduleSave() }

            Button {
                attemptContactImport()
            } label: {
                Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(SBWTheme.brandBlue)

            if contactAccessDenied {
                contactPermissionNotice
            }
        }
        .sbwCardRow()
    }

    private var contactPermissionNotice: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Contacts Access Needed")
                    .font(.caption.weight(.semibold))
                Text("Allow access in Settings to import contacts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var clientAddressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Address")
                .font(.headline)

            TextField("Address", text: $client.address, axis: .vertical)
                .lineLimit(2...6)
                .onChange(of: client.address) { _, _ in scheduleSave() }
        }
        .sbwCardRow()
    }

    private var clientPortalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Portal")
                .font(.headline)

            Toggle("Enable Client Portal", isOn: $client.portalEnabled)

            Text(client.portalEnabled
                 ? "Clients can access invoices, contracts, and pay online."
                 : "Client portal is disabled for this client.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sbwCardRow()
    }

    // MARK: - Jobs (Client -> Job -> ...)

    private var linkedItemsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Linked Items")
                .font(.headline)

            if clientJobs.isEmpty {
                Text("No jobs yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(clientJobs) { job in
                    Button {
                        selectedJob = job
                    } label: {
                        SBWNavigationRow(
                            title: job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title,
                            subtitle: "\(job.startDate.formatted(date: .abbreviated, time: .omitted)) • \(job.status)"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Button {
                createAdditionalJobForClient()
            } label: {
                Label("Create Job", systemImage: "plus")
            }
            .disabled(isDraft)

        }
        .sbwCardRow()
    }

    private var clientFilesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Client Files")
                .font(.headline)

            Button {
                openClientFolder()
            } label: {
                Label("Open Client Folder", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .tint(SBWTheme.brandBlue)
            .disabled(isDraft)
        }
        .sbwCardRow()
    }

    @MainActor
    private func createAdditionalJobForClient() {
        if isDraft { return }
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

    private func openClientFolder() {
        do {
            let resolvedFolder: Folder
            if let existing = clientFolder {
                resolvedFolder = existing
            } else {
                resolvedFolder = try WorkspaceProvisioningService.ensureClientFolder(
                    client: client,
                    context: modelContext
                )
            }
            clientFolder = resolvedFolder
            let business = try fetchBusiness(for: client.businessID)
            clientFolderSheetItem = ClientFolderSheetItem(business: business, folder: resolvedFolder)
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

    
    private var advancedOptionsSection: some View {
        DisclosureGroup(isExpanded: $showAdvancedOptions) {
            VStack(alignment: .leading, spacing: 14) {
                advancedPortalActionsCard
                advancedAttachmentsCard

                Text("Changes auto-save.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 10)
        } label: {
            HStack {
                Text("Advanced Options")
                    .font(.headline)
                Spacer()
            }
        }
        .sbwCardRow()
    }

    private var advancedPortalActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Portal Actions")
                .font(.subheadline.weight(.semibold))

            Button(action: openClientPortalDirectory) {
                Label(openingClientPortal ? "Opening..." : "Open Client Portal Directory",
                      systemImage: "person.2.badge.gearshape")
            }
            .disabled(openingClientPortal || !client.portalEnabled)
            .opacity((openingClientPortal || !client.portalEnabled) ? 0.6 : 1)

            Button {
                sendByEmail = !client.email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                sendBySms = !client.phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ttlDays = 7
                customMessage = ""
                lastSentPortalLink = nil
                showSendPortalSheet = true
            } label: {
                Label("Send Portal Link", systemImage: "paperplane")
            }
            .disabled(!client.portalEnabled)
            .opacity(!client.portalEnabled ? 0.6 : 1)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var advancedAttachmentsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Attachments")
                .font(.subheadline.weight(.semibold))

            if attachments.isEmpty {
                Text("No attachments yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(attachments) { a in
                    HStack(spacing: 8) {
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
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            removeAttachment(a)
                        } label: {
                            Image(systemName: "trash")
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

    // MARK: - Save (client fields)

    private func scheduleSave() {
        if isDraft { return }
        if suppressAutoSave { return }
        pendingSaveTask?.cancel()
        pendingSaveTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s
            if Task.isCancelled { return }
            saveNow()
        }
    }

    private func saveNow() {
        if isDraft { return }
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func refreshContactsPermissionState() {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        contactAccessDenied = (status == .denied || status == .restricted)
    }

    private func attemptContactImport() {
        refreshContactsPermissionState()
        guard !contactAccessDenied else { return }
        showingContactPicker = true
    }

    private func handleContactSelection(_ contact: CNContact) {
        let fields = ContactImportMapper.fields(from: contact)
        if let match = ContactImportMapper.findDuplicateClient(
            in: businessClients,
            fields: fields,
            businessID: client.businessID
        ), match.persistentModelID != client.persistentModelID {
            pendingContact = contact
            duplicateCandidate = match
            showDuplicateDialog = true
            return
        }

        applyContactToClient(contact)
    }

    private func applyContactToClient(_ contact: CNContact) {
        suppressAutoSave = true
        ContactImportMapper.apply(contact: contact, to: client)
        do {
            try modelContext.save()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.easeOut(duration: 0.18)) {
                showContactImportBanner = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                dismiss()
                withAnimation(.easeOut(duration: 0.18)) {
                    showContactImportBanner = false
                }
            }
        } catch {
            contactImportError = error.localizedDescription
        }
        DispatchQueue.main.async {
            suppressAutoSave = false
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
    
    @MainActor
    private func sendPortalLinkNow() {
        guard client.portalEnabled else {
            sendPortalError = "Client portal is disabled for this client."
            return
        }

        // Validate chosen channels
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = client.phone.trimmingCharacters(in: .whitespacesAndNewlines)

        if sendByEmail && email.isEmpty {
            sendPortalError = "Client email is missing."
            return
        }
        if sendBySms && phone.isEmpty {
            sendPortalError = "Client phone is missing."
            return
        }

        sendingPortalLink = true
        sendPortalError = nil

        Task {
            do {
                let message = customMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                let link = try await PortalBackend.shared.sendPortalLink(
                    businessId: client.businessID.uuidString,
                    clientId: client.id.uuidString,
                    clientEmail: sendByEmail ? email : nil,
                    clientPhone: sendBySms ? phone : nil,
                    businessName: "SmallBiz Workspace",
                    sendEmail: sendByEmail,
                    sendSms: sendBySms,
                    ttlDays: ttlDays,
                    message: message.isEmpty ? nil : message
                )

                lastSentPortalLink = link
            } catch {
                sendPortalError = error.localizedDescription
            }

            sendingPortalLink = false
        }
    }

    // MARK: - Attachments helpers

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

                let folder = try resolveClientAttachmentFolder(kind: .attachments)

                let ext = url.pathExtension.lowercased()
                let uti = (UTType(filenameExtension: ext)?.identifier) ?? "public.data"

                let (rel, size) = try AppFileStore.importFile(
                    from: url,
                    toRelativeFolderPath: folder.relativePath
                )

                let file = FileItem(
                    displayName: url.deletingPathExtension().lastPathComponent,
                    originalFileName: url.lastPathComponent,
                    relativePath: rel,
                    fileExtension: ext,
                    uti: uti,
                    byteCount: size,
                    folderKey: folder.id.uuidString,
                    folder: folder
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
            let folder = try resolveClientAttachmentFolder(kind: .photos)

            let (rel, size) = try AppFileStore.importData(
                data,
                toRelativeFolderPath: folder.relativePath,
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
                folderKey: folder.id.uuidString,
                folder: folder
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

    private func resolveClientAttachmentFolder(kind: FolderDestinationKind) throws -> Folder {
        let business = try fetchBusiness(for: client.businessID)
        return try WorkspaceProvisioningService.resolveFolder(
            business: business,
            client: client,
            job: nil,
            kind: kind,
            context: modelContext
        )
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

private struct SBWClientCardRow: ViewModifier {
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
    func sbwCardRow() -> some View {
        modifier(SBWClientCardRow())
    }

    func erased() -> AnyView {
        AnyView(self)
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

private struct ContactImportBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(SBWTheme.brandGreen)
            Text("Imported from Contacts")
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.thinMaterial)
                .overlay(Capsule().stroke(SBWTheme.cardStroke, lineWidth: 1))
        )
        .foregroundStyle(.primary)
        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
    }
}
