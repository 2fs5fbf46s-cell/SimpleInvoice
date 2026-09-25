//
//  ContractDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

/// One screen per contract, the same shape as the estimate, job, invoice and
/// client screens: a header with a Draft → Sent → Signed track, a Next step
/// card (send it, wait for the signature, see it signed), the terms, what it's
/// linked to, and Details, Files and Activity collapsed below.
///
/// It replaces a summary screen (with a raw contract ID under Advanced and a
/// "Send" that only shared a PDF) and an editor with a free status picker, a
/// house button and a checkmark that had to be tapped to publish anything.
/// Terms can be edited only while it's a draft; "Revise terms" takes a sent
/// contract back from the client first.
struct ContractDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var contract: Contract

    @Query private var jobs: [Job]
    @Query private var clients: [Client]

    /// What's in flight, so only that button says so.
    @State private var sendingKind: ContractSendService.Kind? = nil
    @State private var copyingLink = false
    private var busy: Bool { sendingKind != nil || copyingLink }
    @State private var pendingSend: ContractSendService.Kind? = nil
    @State private var confirmRevise = false
    @State private var confirmCancel = false
    @State private var confirmDelete = false
    @State private var showMarkSigned = false
    @State private var showJobPicker = false
    @State private var showSplitSheetEditor = false
    @State private var splitSheetDraft: MusicSplitSheetDraft? = nil

    @State private var showDetails = false
    @State private var showFiles = false
    @State private var showActivity = false
    @State private var showAllTerms = false

    @State private var clientRoute: Client? = nil
    @State private var jobRoute: Job? = nil
    @State private var documentRoute: Invoice? = nil
    @State private var previewItem: IdentifiableURL? = nil
    @State private var safariURL: IdentifiableURL? = nil
    @State private var shareItems: [Any]? = nil

    @State private var notice: String? = nil
    @State private var errorText: String? = nil
    @State private var saveWorkItem: DispatchWorkItem? = nil

    init(contract: Contract) {
        self.contract = contract
        let businessID = contract.businessID
        _jobs = Query(
            filter: #Predicate<Job> { $0.businessID == businessID },
            sort: [SortDescriptor(\Job.startDate, order: .reverse)]
        )
        _clients = Query(
            filter: #Predicate<Client> { $0.businessID == businessID },
            sort: [SortDescriptor(\Client.name)]
        )
    }

    private var display: ContractDisplayStatus { ContractDisplayStatus(contract) }
    private var isEditable: Bool { contract.status == .draft }
    private var client: Client? { contract.resolvedClient }

    private var titleText: String {
        let t = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Contract" : t
    }

    private var clientName: String {
        let name = (contract.clientForRendering?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "your client" : name
    }

    private func checkForSignature() async {
        await ContractActivityPullService.pull(context: modelContext, businessID: contract.businessID)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                nextStepCard
                termsCard
                linkedCard
                detailsGroup
                filesGroup
                activityGroup
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .refreshable { await checkForSignature() }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) { header }
        // A contract out for signature may have been signed since the last
        // launch; look now rather than waiting for the next foreground.
        .task(id: contract.persistentModelID) {
            if contract.status == .sent { await checkForSignature() }
        }
        .navigationTitle("Contract")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { moreMenu }
        }
        .modifier(ContractDetailSheets(
            contract: contract,
            jobs: jobs,
            showJobPicker: $showJobPicker,
            showMarkSigned: $showMarkSigned,
            showSplitSheetEditor: $showSplitSheetEditor,
            splitSheetDraft: $splitSheetDraft,
            previewItem: $previewItem,
            safariURL: $safariURL,
            shareItems: $shareItems,
            defaultSignerName: client?.name ?? "",
            onMarkSigned: markSignedInPerson,
            onJobsChanged: scheduleSave
        ))
        .navigationDestination(item: $clientRoute) { ClientDetailView(client: $0) }
        .navigationDestination(item: $jobRoute) { JobDetailView(job: $0) }
        .navigationDestination(item: $documentRoute) { InvoiceDetailView(invoice: $0) }
        .modifier(ContractDetailDialogs(
            contract: contract,
            clientName: clientName,
            pendingSend: $pendingSend,
            confirmRevise: $confirmRevise,
            confirmCancel: $confirmCancel,
            confirmDelete: $confirmDelete,
            notice: $notice,
            errorText: $errorText,
            onSend: send,
            onRevise: revise,
            onCancel: cancelContract,
            onDelete: deleteContract
        ))
        .onChange(of: contract.title) { _, _ in scheduleSave() }
        .onChange(of: contract.renderedBody) { _, _ in scheduleSave() }
        .onDisappear { saveNow() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(.headline)
                        .lineLimit(2)
                    Text(headerSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(display.label)
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(Capsule().fill(display.foreground.opacity(0.15)))
                    .foregroundStyle(display.foreground)
            }
            stageTrack
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var headerSubtitle: String {
        var parts: [String] = []
        if contract.clientForRendering != nil { parts.append(clientName) }
        if let job = contract.job {
            let t = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(t.isEmpty ? "Job" : t)
        }
        if parts.isEmpty {
            let template = contract.templateName.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(template.isEmpty ? "No client yet" : template)
        }
        return parts.joined(separator: " · ")
    }

    private var stageTrack: some View {
        // Which of Draft / Sent / Signed-or-Canceled were reached. A contract
        // canceled before it was ever sent skips Sent.
        let wasSent = contract.sentAt != nil || contract.portalLastUploadedAtMs != nil
        let filled: [Bool]
        switch display {
        case .draft: filled = [true, false, false]
        case .sent: filled = [true, true, false]
        case .signed: filled = [true, true, true]
        case .canceled: filled = [true, wasSent, true]
        }
        let lastColor: Color = display == .canceled ? .red : SBWTheme.brandGreen
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(filled[index] ? (index == 2 ? lastColor : SBWTheme.brandBlue) : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            HStack {
                Text("Draft")
                Spacer()
                Text("Sent")
                Spacer()
                Text(display == .canceled ? "Canceled" : "Signed")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(display.label)")
    }

    // MARK: - Next step

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next step")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SBWTheme.brandBlue)

            switch display {
            case .draft:
                draftStep
            case .sent:
                stepTitle(
                    "Waiting for \(clientName) to sign",
                    detail: sentDetail
                )
                NextStepButtons {
                    Button { pendingSend = .reminder } label: {
                        Label(sendingKind == .reminder ? "Sending…" : "Send Reminder", systemImage: "bell")
                    }
                    .sbwProminentButton()
                    .disabled(busy)
                    Button { copyClientLink() } label: { Label("Copy Link", systemImage: "link") }
                        .buttonStyle(.bordered)
                        .disabled(busy)
                }
                Button("Signed on paper? Mark as signed") { showMarkSigned = true }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
            case .signed:
                stepTitle(signedTitle, detail: signedDetail)
                NextStepButtons {
                    if let url = contract.signedPDFURL.flatMap(URL.init(string:)) {
                        Button { safariURL = IdentifiableURL(url: url) } label: {
                            Label("Signed PDF", systemImage: "checkmark.seal")
                        }
                        .sbwProminentButton(SBWTheme.brandGreen)
                    } else {
                        Button { previewPDF() } label: { Label("View PDF", systemImage: "doc.richtext") }
                            .sbwProminentButton(SBWTheme.brandGreen)
                    }
                    Button { sharePDF() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
            case .canceled:
                stepTitle(
                    "Canceled\(contract.canceledAt.map { " \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "")",
                    detail: contract.sentAt == nil
                        ? "It was never sent. Reopen it to edit and send it."
                        : "\(clientName.capitalizedFirst) sees it as canceled and can't sign it. Reopen it to edit and send it again."
                )
                Button { Task { await ContractLifecycle.reopen(contract, context: modelContext) } } label: {
                    Label("Reopen as Draft", systemImage: "arrow.uturn.backward")
                }
                .sbwProminentButton()
            }
        }
        .contractCard()
    }

    @ViewBuilder
    private var draftStep: some View {
        let hasTerms = !contract.renderedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if client == nil {
            stepTitle("Choose who it's with", detail: "Pick the client who'll sign this contract.")
            clientPicker
        } else if !hasTerms {
            stepTitle("Write the terms", detail: "Add the contract text below, then send it for signature.")
        } else if case let blanks = ContractTemplateEngine.blanks(in: contract.renderedBody), !blanks.isEmpty {
            // The client signs these terms; don't send "[add total]".
            stepTitle(
                "Fill in the blanks",
                detail: "Replace \(blanks.map { "[add \($0)]" }.joined(separator: ", ")) in the terms below, then send it for signature."
            )
            Button { previewPDF() } label: { Label("Preview", systemImage: "doc.richtext") }
                .buttonStyle(.bordered)
        } else {
            stepTitle(
                contract.sentAt == nil ? "Send it for signature" : "Send the revised terms",
                detail: contract.sentAt == nil
                    ? "Emails \(clientName) a link to review and sign. The terms lock while it's out."
                    : "It's off \(clientName)'s portal while you revise. Sending emails them the new version to sign."
            )
            NextStepButtons {
                Button { pendingSend = .send } label: {
                    Label(sendingKind == .send ? "Sending…" : "Send for Signature", systemImage: "paperplane")
                }
                .sbwProminentButton()
                .disabled(busy)
                Button { previewPDF() } label: { Label("Preview", systemImage: "doc.richtext") }
                    .buttonStyle(.bordered)
            }
        }
    }

    private func stepTitle(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
            if !detail.isEmpty {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sentDetail: String {
        var parts: [String] = []
        if let sent = contract.sentAt {
            parts.append("Emailed \(sent.formatted(date: .abbreviated, time: .omitted)).")
        } else {
            parts.append("In their client portal.")
        }
        if let reminded = contract.lastReminderAt {
            parts.append("Reminded \(reminded.formatted(date: .abbreviated, time: .omitted)).")
        }
        parts.append("The terms are locked while it's out for signature.")
        return parts.joined(separator: " ")
    }

    private var signedTitle: String {
        let who = contract.signedByName.trimmingCharacters(in: .whitespacesAndNewlines)
        return who.isEmpty ? "Signed" : "Signed by \(who)"
    }

    private var signedDetail: String {
        let when = contract.signedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? ""
        let how = contract.signedMethod == "in_person" ? "on paper or in person" : "in the client portal"
        return when.isEmpty ? "Signed \(how)." : "\(when), \(how). The terms can't change now."
    }

    // MARK: - Terms

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Terms")
                    .font(.headline)
                Spacer()
                if contract.status == .sent {
                    Button { confirmRevise = true } label: {
                        Label("Revise", systemImage: "lock.open")
                            .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                }
            }

            if isEditable && MusicSplitSheetDraft.isSmartMusicSplitSheet(contract) {
                Button { openSplitSheetEditor() } label: {
                    Label("Edit Split Sheet", systemImage: "music.note.list")
                }
                .buttonStyle(.bordered)
            }

            if isEditable {
                TextEditor(text: $contract.renderedBody)
                    .frame(minHeight: 240)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(.tertiarySystemFill)))
            } else {
                Text(contract.renderedBody)
                    .font(.subheadline)
                    .lineLimit(showAllTerms ? nil : 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                if contract.renderedBody.components(separatedBy: "\n").count > 10 || contract.renderedBody.count > 600 {
                    Button(showAllTerms ? "Show less" : "Show all") { showAllTerms.toggle() }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
                Label(lockText, systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contractCard()
    }

    private var lockText: String {
        switch contract.status {
        case .signed: return contract.signedLockDescription
        case .sent: return "Locked while \(clientName) reviews it. Revise to change it."
        case .cancelled: return "Reopen the contract to change it."
        case .draft: return ""
        }
    }

    // MARK: - Linked

    private var linkedJobs: [Job] {
        let ids = Set(contract.linkedJobIDsCSV.split(separator: ",").compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) })
        var result = jobs.filter { ids.contains($0.id) }
        if let primary = contract.job, !result.contains(where: { $0.id == primary.id }) {
            result.insert(primary, at: 0)
        }
        return result
    }

    private var linkedDocument: Invoice? { contract.invoice ?? contract.estimate }

    private var linkedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Linked to")
                    .font(.headline)
                Spacer()
                Button { showJobPicker = true } label: {
                    Label("Jobs", systemImage: "plus")
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
            }

            if let client {
                linkRow(icon: "person", title: client.displayName, detail: "Client") { clientRoute = client }
            } else if let snapshot = contract.clientSnapshot {
                linkRow(icon: "person", title: snapshot.name, detail: "Client (deleted)", action: nil)
            }
            if let document = linkedDocument {
                linkRow(
                    icon: document.documentType == "estimate" ? "doc.text.magnifyingglass" : "doc.plaintext",
                    title: ClientWorkItem.documentName(document),
                    detail: document.documentType == "estimate" ? "Estimate" : "Invoice"
                ) { documentRoute = document }
            }
            ForEach(linkedJobs) { job in
                let status = JobDisplayStatus(job)
                linkRow(
                    icon: "wrench.and.screwdriver",
                    title: job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title,
                    detail: status.label
                ) { jobRoute = job }
            }
            if client == nil && linkedDocument == nil && linkedJobs.isEmpty {
                Text("Nothing yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .contractCard()
    }

    private func linkRow(icon: String, title: String, detail: String, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if action != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    // MARK: - Details

    private var detailsGroup: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 12) {
                if isEditable {
                    TextField("Title", text: $contract.title)
                        .textFieldStyle(.roundedBorder)
                    clientPicker
                } else {
                    LabeledContent("Title", value: titleText)
                    LabeledContent("Client", value: clientName)
                }
                LabeledContent("Template", value: contract.templateName.isEmpty ? "None" : contract.templateName)
                LabeledContent("Created", value: contract.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let job = contract.job {
                    Button { createOrOpenJobInvoice(for: job) } label: {
                        Label(jobInvoice(for: job) == nil ? "Create Invoice for the Job" : "Open the Job's Invoice", systemImage: "doc.plaintext")
                    }
                    .buttonStyle(.borderless)
                }
            }
            .font(.subheadline)
            .padding(.top, 10)
        } label: {
            groupLabel("Details", icon: "square.and.pencil", detail: isEditable ? "Title, client" : "Template, dates")
        }
        .tint(.secondary)
        .contractCard()
    }

    private var clientPicker: some View {
        Picker("Client", selection: Binding<UUID?>(
            get: { contract.client?.id ?? client?.id },
            set: { id in
                contract.client = clients.first { $0.id == id }
                contract.clientSnapshot = nil
                contract.captureClientSnapshotIfNeeded()
                scheduleSave()
            }
        )) {
            Text("No client").tag(UUID?.none)
            ForEach(clients.filter { !$0.isArchived || $0.id == client?.id }) { c in
                Text(c.displayName).tag(Optional(c.id))
            }
        }
        .pickerStyle(.menu)
        .tint(SBWTheme.brandBlue)
    }

    private var filesGroup: some View {
        DisclosureGroup(isExpanded: $showFiles) {
            ContractFilesCard(contract: contract)
                .padding(.top, 10)
        } label: {
            groupLabel(
                "Files",
                icon: "paperclip",
                detail: (contract.attachments ?? []).isEmpty ? "None yet" : "\((contract.attachments ?? []).count)"
            )
        }
        .tint(.secondary)
        .contractCard()
    }

    private var activityGroup: some View {
        DisclosureGroup(isExpanded: $showActivity) {
            VStack(alignment: .leading, spacing: 8) {
                activityRow("Created", contract.createdAt)
                activityRow("Emailed", contract.sentAt)
                activityRow("Reminded", contract.lastReminderAt)
                activityRow("Signed", contract.signedAt)
                activityRow("Canceled", contract.canceledAt)
                if let error = contract.portalLastUploadError?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
                    HStack {
                        Text("Portal sync failed: \(error)")
                            .font(.caption)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Retry") { retrySync() }
                            .font(.caption.weight(.semibold))
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            groupLabel("Activity", icon: "clock.arrow.circlepath", detail: "")
        }
        .tint(.secondary)
        .contractCard()
    }

    @ViewBuilder
    private func activityRow(_ label: String, _ date: Date?) -> some View {
        if let date {
            LabeledContent(label, value: date.formatted(date: .abbreviated, time: .shortened))
                .font(.subheadline)
        }
    }

    private func groupLabel(_ title: String, icon: String, detail: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(SBWTheme.brandBlue)
                .frame(width: 22)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Menu

    private var moreMenu: some View {
        Menu {
            Button { previewPDF() } label: { Label("Preview PDF", systemImage: "doc.richtext") }
            Button { sharePDF() } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
            if contract.status != .draft {
                Button { openInPortal() } label: { Label("View in Client Portal", systemImage: "safari") }
            }
            if contract.status == .sent {
                Button { showMarkSigned = true } label: { Label("Mark as Signed", systemImage: "signature") }
            }
            if contract.status == .draft || contract.status == .sent {
                Divider()
                Button(role: .destructive) { confirmCancel = true } label: {
                    Label("Cancel Contract", systemImage: "xmark.circle")
                }
            }
            if ContractLifecycle.canDelete(contract) {
                Button(role: .destructive) { confirmDelete = true } label: {
                    Label("Delete Draft", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    // MARK: - Actions

    private func scheduleSave() {
        saveWorkItem?.cancel()
        let work = DispatchWorkItem {
            contract.updatedAt = .now
            contract.captureClientSnapshotIfNeeded()
            try? modelContext.save()
        }
        saveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func saveNow() {
        saveWorkItem?.cancel()
        try? modelContext.save()
    }

    private func send(_ kind: ContractSendService.Kind) {
        pendingSend = nil
        guard !busy else { return }
        saveNow()
        sendingKind = kind
        Task {
            defer { sendingKind = nil }
            do {
                switch try await ContractSendService.send(contract, kind: kind, context: modelContext) {
                case .emailed(let email):
                    Haptics.success()
                    notice = kind == .reminder ? "Reminder sent to \(email)." : "Sent to \(email) to sign."
                case .publishedNotEmailed(let link, _):
                    if let link { UIPasteboard.general.string = link }
                    errorText = link == nil
                        ? "It's in \(clientName)'s portal, but the email didn't go out. Try again in a moment."
                        : "It's in \(clientName)'s portal, but the email didn't go out. The link is copied, so you can paste it to them."
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func revise() {
        Task { await ContractLifecycle.revise(contract, context: modelContext) }
    }

    private func cancelContract() {
        Task { await ContractLifecycle.cancel(contract, context: modelContext) }
    }

    private func markSignedInPerson(name: String, date: Date) {
        Task {
            await ContractLifecycle.markSignedInPerson(contract, signerName: name, signedAt: date, context: modelContext)
            Haptics.success()
        }
    }

    private func deleteContract() {
        modelContext.delete(contract)
        try? modelContext.save()
        dismiss()
    }

    private func retrySync() {
        contract.portalNeedsUpload = true
        Task { _ = await PortalAutoSyncService.uploadContract(contractId: contract.id, context: modelContext) }
    }

    private func copyClientLink() {
        copyingLink = true
        Task {
            defer { copyingLink = false }
            do {
                let token = try await PortalBackend.shared.createContractPortalToken(
                    contract: contract,
                    businessName: ContractBusiness.name(for: contract, in: modelContext)
                )
                UIPasteboard.general.string = PortalBackend.shared.buildContractPortalURL(contract: contract, token: token).absoluteString
                notice = "Link copied. It opens this contract for \(clientName) to sign."
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func openInPortal() {
        Task {
            do {
                let token = try await PortalBackend.shared.createContractPortalToken(
                    contract: contract,
                    businessName: ContractBusiness.name(for: contract, in: modelContext)
                )
                safariURL = IdentifiableURL(url: PortalBackend.shared.buildContractPortalURL(contract: contract, token: token))
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func pdfURL() throws -> URL {
        try DocumentFileIndexService.persistContractPDF(
            contract: contract,
            business: ContractBusiness.profile(for: contract, in: modelContext),
            context: modelContext
        )
    }

    private func previewPDF() {
        do { previewItem = IdentifiableURL(url: try pdfURL()) } catch { errorText = error.localizedDescription }
    }

    private func sharePDF() {
        do { shareItems = [try pdfURL()] } catch { errorText = error.localizedDescription }
    }

    private func openSplitSheetEditor() {
        guard let draft = MusicSplitSheetDraft.decodeJSONString(contract.smartTemplateJSON) else {
            errorText = "The split sheet's details couldn't be opened. You can still edit the terms below."
            return
        }
        splitSheetDraft = draft
        showSplitSheetEditor = true
    }

    private func jobInvoice(for job: Job) -> Invoice? {
        (job.invoices ?? []).first { $0.documentType != "estimate" && $0.id.uuidString != job.depositInvoiceId }
    }

    private func createOrOpenJobInvoice(for job: Job) {
        if let existing = jobInvoice(for: job) {
            documentRoute = existing
            return
        }
        do {
            documentRoute = try JobInvoiceBuilder.makeInvoice(
                for: job,
                client: client,
                profile: ContractBusiness.profile(for: contract, in: modelContext),
                context: modelContext
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Sheets and dialogs

/// The contract screen's sheets, kept off its body so the type checker
/// doesn't give up on one long modifier chain.
private struct ContractDetailSheets: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let contract: Contract
    let jobs: [Job]
    @Binding var showJobPicker: Bool
    @Binding var showMarkSigned: Bool
    @Binding var showSplitSheetEditor: Bool
    @Binding var splitSheetDraft: MusicSplitSheetDraft?
    @Binding var previewItem: IdentifiableURL?
    @Binding var safariURL: IdentifiableURL?
    @Binding var shareItems: [Any]?
    let defaultSignerName: String
    let onMarkSigned: (String, Date) -> Void
    let onJobsChanged: () -> Void

    private var linkedJobIDs: [UUID] {
        contract.linkedJobIDsCSV.split(separator: ",").compactMap { UUID(uuidString: String($0).trimmingCharacters(in: .whitespaces)) }
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showJobPicker) {
                NavigationStack {
                    ContractJobsPickerSheet(
                        jobs: jobs,
                        selectedJobIDs: Binding(
                            get: { linkedJobIDs },
                            set: { ids in
                                let unique = Set(ids)
                                if let primary = contract.job, !unique.contains(primary.id) { contract.job = nil }
                                if contract.job == nil {
                                    contract.job = jobs.filter { unique.contains($0.id) }.sorted { $0.startDate > $1.startDate }.first
                                }
                                contract.linkedJobIDsCSV = unique.map(\.uuidString).sorted().joined(separator: ",")
                                onJobsChanged()
                            }
                        ),
                        primaryJobID: Binding(
                            get: { contract.job?.id },
                            set: { id in
                                guard let id, let job = jobs.first(where: { $0.id == id }) else { return }
                                contract.job = job
                                onJobsChanged()
                            }
                        )
                    )
                    .navigationTitle("Linked Jobs")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            .sheet(isPresented: $showMarkSigned) {
                MarkContractSignedSheet(defaultName: defaultSignerName) { name, date in
                    onMarkSigned(name, date)
                }
            }
            .sheet(isPresented: $showSplitSheetEditor) {
                NavigationStack {
                    if let draft = splitSheetDraft {
                        MusicSplitSheetFormView(contract: contract, draft: draft) { _ in
                            showSplitSheetEditor = false
                            splitSheetDraft = nil
                        }
                    }
                }
                .presentationDetents([.large])
            }
            .sheet(item: $previewItem) { item in
                NavigationStack {
                    PDFPreviewView(url: item.url)
                        .navigationTitle("Contract PDF")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { previewItem = nil }
                            }
                            ToolbarItem(placement: .topBarTrailing) {
                                ShareLink(item: item.url) { Image(systemName: "square.and.arrow.up") }
                            }
                        }
                }
            }
            .sheet(item: $safariURL) { item in
                SafariView(url: item.url, onDone: {})
            }
            .sheet(isPresented: Binding(
                get: { shareItems != nil },
                set: { if !$0 { shareItems = nil } }
            )) {
                ShareSheet(items: shareItems ?? [])
            }
    }
}

private struct ContractDetailDialogs: ViewModifier {
    let contract: Contract
    let clientName: String
    @Binding var pendingSend: ContractSendService.Kind?
    @Binding var confirmRevise: Bool
    @Binding var confirmCancel: Bool
    @Binding var confirmDelete: Bool
    @Binding var notice: String?
    @Binding var errorText: String?
    let onSend: (ContractSendService.Kind) -> Void
    let onRevise: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                pendingSend == .reminder ? "Send a reminder?" : "Send for signature?",
                isPresented: Binding(
                    get: { pendingSend != nil },
                    set: { if !$0 { pendingSend = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingSend
            ) { kind in
                Button(kind == .reminder ? "Send Reminder" : "Send") { onSend(kind) }
                Button("Cancel", role: .cancel) { pendingSend = nil }
            } message: { kind in
                Text(ContractSendService.confirmationMessage(for: contract, kind: kind))
            }
            .confirmationDialog("Revise the terms?", isPresented: $confirmRevise, titleVisibility: .visible) {
                Button("Revise Terms") { onRevise() }
                Button("Keep as Sent", role: .cancel) {}
            } message: {
                Text("It comes off \(clientName)'s portal and can't be signed until you send the new version.")
            }
            .confirmationDialog("Cancel this contract?", isPresented: $confirmCancel, titleVisibility: .visible) {
                Button("Cancel Contract", role: .destructive) { onCancel() }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text(contract.status == .sent
                     ? "\(clientName) will see it as canceled and won't be able to sign it. You can reopen it later."
                     : "It stays in your records. You can reopen it later.")
            }
            .confirmationDialog("Delete this draft?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Draft", role: .destructive) { onDelete() }
                Button("Keep It", role: .cancel) {}
            } message: {
                Text("It was never sent. This can't be undone.")
            }
            .alert("Done", isPresented: Binding(
                get: { notice != nil },
                set: { if !$0 { notice = nil } }
            )) {
                Button("OK", role: .cancel) { notice = nil }
            } message: {
                Text(notice ?? "")
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
    }
}

/// "Mark as signed" for a contract signed on paper or in person.
private struct MarkContractSignedSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onConfirm: (String, Date) -> Void

    @State private var name: String
    @State private var date: Date = .now

    init(defaultName: String, onConfirm: @escaping (String, Date) -> Void) {
        self.onConfirm = onConfirm
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Who signed", text: $name)
                        .textInputAutocapitalization(.words)
                    DatePicker("Signed on", selection: $date, in: ...Date.now)
                } footer: {
                    Text("Locks the terms and shows it signed in the client's portal. This can't be undone.")
                }
            }
            .navigationTitle("Mark as Signed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark Signed") {
                        onConfirm(name, date)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

private struct ContractCard: ViewModifier {
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
    }
}

private extension View {
    func contractCard() -> some View { modifier(ContractCard()) }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension ContractDetailView: Equatable {
    static func == (lhs: ContractDetailView, rhs: ContractDetailView) -> Bool {
        lhs.contract.persistentModelID == rhs.contract.persistentModelID
    }
}
