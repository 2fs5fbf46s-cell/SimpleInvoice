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
import CoreLocation
import MapKit

private struct JobFolderSheetItem: Identifiable {
    let id = UUID()
    let business: Business
    let folder: Folder
}

struct JobDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var job: Job
    let isDraft: Bool

    // Debounced save
    @State private var pendingSaveTask: Task<Void, Never>? = nil
    @State private var saveError: String? = nil

    // ✅ NEW: Debounced workspace rename (live folder rename)
    @State private var pendingWorkspaceRenameTask: Task<Void, Never>? = nil

    // Attachments (join records)
    @Query private var attachments: [JobAttachment]
    @Query private var clients: [Client]

    @State private var showExistingFilePicker = false
    @State private var showJobFileImporter = false
    @State private var showJobPhotosSheet = false
    @State private var showJobCamera = false

    @State private var locationService = LocationCaptureService()
    @State private var isCapturingLocation = false
    @State private var locationCaptureError: String? = nil
    @State private var showingNewClient = false
    @State private var editingClient: Client? = nil
    @State private var draftClientName: String = ""
    @State private var draftClientEmail: String = ""
    @State private var draftClientPhone: String = ""
    @State private var draftClientAddress: String = ""

    @State private var attachError: String? = nil
    @State private var previewItem: IdentifiableURL? = nil

    // ZIP export
    @State private var zipURL: URL? = nil
    @State private var zipError: String? = nil

    // Contracts navigation (avoid SwiftData NavigationLink freeze)
    @State private var selectedContract: Contract? = nil
    @State private var showNewContract = false
    @State private var selectedPhotoAttachment: JobAttachment? = nil
    @State private var folderSheetItem: JobFolderSheetItem? = nil
    @State private var jobFolder: Folder? = nil
    @State private var jobSubfolders: [JobWorkspaceSubfolder: Folder] = [:]
    @State private var workspaceError: String? = nil
    @State private var calendarError: String? = nil
    @State private var calendarPermissionDenied = false
    @State private var calendarSheetEvent: EKEvent? = nil

    // One-screen job layout (see "Job screen" below)
    @State private var showDetails = false
    @State private var showMeasurements = false
    @State private var showFolder = false
    @State private var showReschedule = false
    @State private var scheduleStart: Date = JobDetailView.defaultScheduleStart()
    @State private var scheduleEnd: Date = JobDetailView.defaultScheduleStart().addingTimeInterval(2 * 3600)
    @State private var invoiceRoute: Invoice? = nil
    @State private var shareItems: [Any]? = nil
    @State private var confirmCancelJob = false
    @State private var confirmDeleteJob = false
    @State private var isDeleted = false
    @State private var pendingCalendarRefreshTask: Task<Void, Never>? = nil
    @State private var actionError: String? = nil

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
        let businessID = job.businessID
        self._clients = Query(
            filter: #Predicate<Client> { client in
                client.businessID == businessID
            },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
    }

    var body: some View {
        jobScreen
        .navigationDestination(item: $selectedContract) { c in
            ContractDetailView(contract: c)
        }
        .sheet(isPresented: $showNewContract) {
            NavigationStack {
                CreateContractStartView(
                    businessID: job.businessID,
                    client: linkedClient,
                    job: job,
                    onCreated: { contract in
                        showNewContract = false
                        DispatchQueue.main.async { selectedContract = contract }
                    },
                    onCancel: { showNewContract = false }
                )
            }
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
        // Take Photo (full-screen camera UI — UIImagePickerController expects this,
        // not a sheet)
        .fullScreenCover(isPresented: $showJobCamera) {
            CameraCaptureView(
                onCapture: { data, suggestedName in
                    showJobCamera = false
                    importAndAttachFromPhotos(data: data, suggestedFileName: suggestedName)
                },
                onCancel: { showJobCamera = false }
            )
            .ignoresSafeArea()
        }

        // Attach existing file picker
        .sheet(isPresented: $showExistingFilePicker) {
            JobAttachmentPickerView { file in
                attachExisting(file)
            }
        }
        .sheet(isPresented: $showingNewClient) {
            NavigationStack {
                Form {
                    Section("Client") {
                        TextField("Name", text: $draftClientName)
                        TextField("Email", text: $draftClientEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        TextField("Phone", text: $draftClientPhone)
                            .keyboardType(.phonePad)
                    }

                    Section("Address") {
                        TextField("Address", text: $draftClientAddress, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                .navigationTitle("New Client")
                .navigationBarTitleDisplayMode(.inline)
                .sbwNavigationBarBackdrop()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingNewClient = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveNewClientAndLink() }
                            .disabled(draftClientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(item: $editingClient) { client in
            NavigationStack {
                ClientEditView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { editingClient = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }

        // QuickLook
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(item: $selectedPhotoAttachment) { attachment in
            PhotoAttachmentDetailView(attachment: attachment)
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
        .alert("Location", isPresented: Binding(
            get: { locationCaptureError != nil },
            set: { if !$0 { locationCaptureError = nil } }
        )) {
            Button("OK", role: .cancel) { locationCaptureError = nil }
        } message: {
            Text(locationCaptureError ?? "")
        }
        .task {
            if !isDraft {
                provisionFolders()
                try? DocumentFileIndexService.syncJobDocuments(job: job, context: modelContext)
            }
        }

        .onDisappear {
            if isDraft || isDeleted { return }
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

    private var displayStatus: JobDisplayStatus { JobDisplayStatus(job) }

    private var linkedClient: Client? {
        guard let clientID = job.clientID else { return nil }
        return clients.first(where: { $0.id == clientID })
    }

    /// "Thu, Sep 25 · 9:00–11:00 AM" for a same-day job, else both dates.
    private var jobWhenText: String {
        switch displayStatus {
        case .needsScheduling:
            return "No date yet"
        case .inProgress:
            if let startedAt = job.startedAt {
                return "On site since \(startedAt.formatted(date: .omitted, time: .shortened))"
            }
            return "In progress"
        case .completed:
            return "Completed \((job.completedAt ?? job.endDate).formatted(date: .abbreviated, time: .omitted))"
        case .canceled:
            return "Canceled \((job.canceledAt ?? job.startDate).formatted(date: .abbreviated, time: .omitted))"
        case .scheduled:
            let start = job.startDate
            let end = job.endDate
            if Calendar.current.isDate(start, inSameDayAs: end) {
                let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
                let times = "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
                return "\(day) · \(times)"
            }
            return "\(start.formatted(date: .abbreviated, time: .shortened)) – \(end.formatted(date: .abbreviated, time: .shortened))"
        }
    }

    private var jobPlaceText: String {
        let client = linkedClient?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let place = job.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
        return [client, place].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // Solid, not material: the list scrolled visibly underneath the old one.
    private var pinnedHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(jobTitleText)
                        .font(.headline)
                        .lineLimit(2)
                    if !jobPlaceText.isEmpty {
                        Text(jobPlaceText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !isDraft {
                        Text(jobWhenText)
                            .font(.caption)
                    }
                }
                Spacer()
                if !isDraft {
                    jobStatusPill
                }
            }
            if !isDraft {
                jobStageTrack
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var jobStatusPill: some View {
        Text(displayStatus.label)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(displayStatus.foreground.opacity(0.15)))
            .foregroundStyle(displayStatus.foreground)
    }

    private var jobStageTrack: some View {
        let reached: Int
        switch displayStatus {
        case .needsScheduling: reached = 0
        case .scheduled: reached = 1
        case .inProgress: reached = 2
        case .completed, .canceled: reached = 3
        }
        let lastColor: Color = displayStatus == .canceled ? .red : SBWTheme.brandBlue
        return VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index < reached ? (index == 2 ? lastColor : SBWTheme.brandBlue) : Color.secondary.opacity(0.25))
                        .frame(height: 4)
                }
            }
            HStack {
                Text("Scheduled")
                Spacer()
                Text("In progress")
                Spacer()
                Text(displayStatus == .canceled ? "Canceled" : "Completed")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(displayStatus.label)")
    }

    // MARK: - Job screen
    //
    // One screen per job, the same shape as the estimate screen: a header
    // with a stage track, then a Next step card with what to do now —
    // schedule it, start it, finish it, bill for it — then the client
    // contact row, the job's paperwork, photos and notes. Editing details,
    // measurements and the folder collapse below. A new job (isDraft) gets
    // just the fields needed to create it.

    private var jobScreen: some View {
        List {
            if isDraft {
                jobEssentialsCard
                scheduleCard
                locationCard
                notesCard
            } else {
                nextStepCard
                contactRow
                paperworkCard
                attachmentsCard
                notesCard
                detailsGroup
                measurementsGroup
                folderGroup
            }
        }
        .listStyle(.plain)
        .listRowSeparator(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !isDraft { pinnedHeader }
        }
        .navigationTitle(isDraft ? "New Job" : "Job")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            if !isDraft {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showJobCamera = true } label: { Image(systemName: "camera") }
                            .accessibilityLabel("Take Photo")
                    }
                    jobMenu
                }
            }
        }
        .navigationDestination(item: $invoiceRoute) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
        .sheet(isPresented: Binding(
            get: { shareItems != nil },
            set: { if !$0 { shareItems = nil } }
        )) {
            ShareSheet(items: shareItems ?? [])
        }
        .confirmationDialog("Cancel this job?", isPresented: $confirmCancelJob, titleVisibility: .visible) {
            Button("Cancel Job", role: .destructive) { cancelJob() }
            Button("Keep Job", role: .cancel) {}
        } message: {
            Text("It stays in your records and comes off your calendar. You can reopen it later.")
        }
        .confirmationDialog("Delete this job?", isPresented: $confirmDeleteJob, titleVisibility: .visible) {
            Button("Delete Job", role: .destructive) { deleteJob() }
            Button("Keep Job", role: .cancel) {}
        } message: {
            Text(deleteImpactText)
        }
        .alert("Job", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: {
            Text(actionError ?? "")
        }
        // The calendar event carries the job's time, place and notes; it
        // used to go stale until the owner tapped "Update Calendar Event".
        .onChange(of: job.startDate) { _, _ in scheduleCalendarRefresh() }
        .onChange(of: job.endDate) { _, _ in scheduleCalendarRefresh() }
        .onChange(of: job.notes) { _, _ in scheduleCalendarRefresh() }
        .onChange(of: job.locationName) { _, _ in scheduleCalendarRefresh() }
    }

    // MARK: Next step

    private var nextStepCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next step")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SBWTheme.brandBlue)

            switch displayStatus {
            case .needsScheduling:
                stepTitle("Schedule it", detail: job.sourceEstimateId == nil
                    ? "Pick when the work happens. It goes on your calendar."
                    : "Created from the accepted estimate. Pick when the work happens and it goes on your calendar.")
                DatePicker("Starts", selection: $scheduleStart)
                DatePicker("Ends", selection: $scheduleEnd, in: scheduleStart...)
                Button { applySchedule() } label: {
                    Label("Schedule", systemImage: "calendar.badge.plus")
                }
                .sbwProminentButton()

            case .scheduled:
                stepTitle(startsText, detail: readinessText)
                if showReschedule {
                    DatePicker("Starts", selection: $job.startDate)
                        .onChange(of: job.startDate) { _, _ in scheduleSave() }
                    DatePicker("Ends", selection: $job.endDate, in: job.startDate...)
                        .onChange(of: job.endDate) { _, _ in scheduleSave() }
                }
                NextStepButtons {
                    Button { startJob() } label: { Label("Start Job", systemImage: "play.fill") }
                        .sbwProminentButton()
                    Button { showReschedule.toggle() } label: {
                        Label(showReschedule ? "Done" : "Reschedule", systemImage: "calendar")
                    }
                    .buttonStyle(.bordered)
                }

            case .inProgress:
                stepTitle(
                    "Job in progress",
                    detail: "\(jobWhenText). Take before and after photos as you go."
                )
                NextStepButtons {
                    Button { completeJob() } label: { Label("Complete Job", systemImage: "checkmark") }
                        .sbwProminentButton(SBWTheme.brandGreen)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button { showJobCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                            .buttonStyle(.bordered)
                    }
                }

            case .completed:
                if let invoice = finalInvoice {
                    // A draft isn't "out": it was saying so for an unsent
                    // $0.00 invoice made by Bill.
                    let sent = invoice.isPaid || invoice.wasSent
                    stepTitle(
                        invoice.isPaid ? "Paid" : sent ? "Invoice \(invoice.invoiceNumber) is out" : "Invoice \(invoice.invoiceNumber) isn't sent yet",
                        detail: invoice.isPaid
                            ? "This job is done and paid for."
                            : sent
                                ? "\(currency(invoice.total)) \(isOverdue(invoice) ? "overdue" : "unpaid")."
                                : invoice.totalCents > 0
                                    ? "\(currency(invoice.total)), ready to send."
                                    : "Add what you're charging for, then send it."
                    )
                    NextStepButtons {
                        Button { invoiceRoute = invoice } label: { Label("Open Invoice", systemImage: "doc.plaintext") }
                            .sbwProminentButton()
                        Button { shareSummary() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                } else {
                    stepTitle("Bill for it", detail: billingDetailText)
                    NextStepButtons {
                        Button { createJobInvoice() } label: { Label("Create Invoice", systemImage: "doc.badge.plus") }
                            .sbwProminentButton()
                        Button { shareSummary() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                    }
                }

            case .canceled:
                stepTitle(jobWhenText, detail: "It's off your calendar. Reopen it if the work is back on.")
                Button { reopenJob() } label: { Label("Reopen Job", systemImage: "arrow.uturn.backward") }
                    .sbwProminentButton()
            }

            if let calendarError, !calendarError.isEmpty {
                Text(calendarError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // "Enable it in Settings" with no way there was a dead end.
                if calendarError.localizedCaseInsensitiveContains("Settings"),
                   let url = URL(string: UIApplication.openSettingsURLString) {
                    Button("Open Settings") { UIApplication.shared.open(url) }
                        .font(.caption)
                        .buttonStyle(.borderless)
                }
            }
        }
        .sbwJobCardRow()
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

    private var startsText: String {
        let time = job.startDate.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        // Past its start and not started: say so, not "Starts today at" a
        // time that's gone.
        if calendar.isDateInToday(job.startDate) {
            return job.startDate < .now ? "Was set to start at \(time) today" : "Starts today at \(time)"
        }
        if calendar.isDateInTomorrow(job.startDate) { return "Starts tomorrow at \(time)" }
        if job.startDate < .now { return "Was set for \(job.startDate.formatted(date: .abbreviated, time: .shortened))" }
        return "Starts \(job.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) at \(time)"
    }

    /// Deposit and contract state, the two things worth knowing before you
    /// head out. Soft reminders, never a gate.
    private var readinessText: String {
        var parts: [String] = []
        if let cents = job.depositAmountCents, cents > 0 {
            parts.append(job.depositPaidAtMs != nil ? "Deposit paid." : "Deposit of \(currency(Double(cents) / 100)) not paid yet.")
        }
        if let contract = jobContracts.first {
            parts.append(contract.status == .signed ? "Contract signed." : "Contract not signed yet.")
        }
        return parts.joined(separator: " ")
    }

    private var billingDetailText: String {
        guard JobInvoiceBuilder.sourceEstimate(for: job, in: modelContext) != nil else {
            return "Creates an invoice for this job and client."
        }
        if job.depositPaidAtMs != nil, let cents = job.depositAmountCents, cents > 0 {
            return "Uses the estimate's line items, minus the \(currency(Double(cents) / 100)) deposit already paid."
        }
        return "Uses the estimate's line items."
    }

    // MARK: Contact

    private var clientPhoneDigits: String? {
        let raw = linkedClient?.phone ?? ""
        let digits = raw.filter { "+0123456789".contains($0) }
        return digits.isEmpty ? nil : digits
    }

    private var directionsURL: URL? {
        var comps = URLComponents(string: "http://maps.apple.com/")
        if let latitude = job.latitude, let longitude = job.longitude {
            comps?.queryItems = [URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)")]
        } else {
            let place = job.locationName.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = place.isEmpty ? (linkedClient?.address.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") : place
            guard !address.isEmpty else { return nil }
            comps?.queryItems = [URLQueryItem(name: "daddr", value: address)]
        }
        return comps?.url
    }

    private var hasCalendarEvent: Bool {
        !(job.calendarEventId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var contactRow: some View {
        HStack {
            contactButton("Call", icon: "phone.fill", enabled: clientPhoneDigits != nil) {
                if let digits = clientPhoneDigits, let url = URL(string: "tel:\(digits)") { openURL(url) }
            }
            contactButton("Text", icon: "message.fill", enabled: clientPhoneDigits != nil) {
                if let digits = clientPhoneDigits, let url = URL(string: "sms:\(digits)") { openURL(url) }
            }
            contactButton("Directions", icon: "location.fill", enabled: directionsURL != nil) {
                if let url = directionsURL { openURL(url) }
            }
            contactButton(
                hasCalendarEvent ? "Calendar" : "Add to Cal",
                icon: hasCalendarEvent ? "calendar" : "calendar.badge.plus",
                enabled: displayStatus != .needsScheduling && displayStatus != .canceled
            ) {
                Task { await syncCalendarEvent(viewAfter: hasCalendarEvent) }
            }
        }
        .buttonStyle(.borderless)
        .sbwJobCardRow()
    }

    private func contactButton(_ title: String, icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(enabled ? SBWTheme.brandBlue : Color.secondary.opacity(0.5))
        }
        .disabled(!enabled)
    }

    // MARK: Paperwork

    private var jobDocuments: [Invoice] {
        (job.invoices ?? []).sorted { $0.issueDate > $1.issueDate }
    }

    private var jobEstimates: [Invoice] {
        jobDocuments.filter { $0.documentType == "estimate" }
    }

    private var depositInvoice: Invoice? {
        guard let id = job.depositInvoiceId else { return nil }
        return jobDocuments.first { $0.id.uuidString == id }
    }

    /// Real invoices for the work, not the deposit invoice.
    private var finalInvoices: [Invoice] {
        jobDocuments.filter { $0.documentType != "estimate" && $0.id.uuidString != job.depositInvoiceId }
    }

    private var finalInvoice: Invoice? { finalInvoices.first }

    /// Every contract tied to this job: linked directly, drafted with its
    /// estimate (the job screen couldn't see these before), or listing it
    /// among several linked jobs.
    private var jobContracts: [Contract] {
        var seen = Set<UUID>()
        var result: [Contract] = []
        func add(_ contract: Contract) {
            if seen.insert(contract.id).inserted { result.append(contract) }
        }
        (job.contracts ?? []).forEach(add)
        for document in jobDocuments {
            (document.contracts ?? []).forEach(add)
            (document.estimateContracts ?? []).forEach(add)
        }
        let businessID = job.businessID
        let jobKey = job.id.uuidString
        let others = (try? modelContext.fetch(FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { $0.businessID == businessID }
        ))) ?? []
        others.filter { $0.linkedJobIDsCSV.contains(jobKey) }.forEach(add)
        return result
    }

    private var paperworkCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Paperwork")
                    .font(.headline)
                Spacer()
                Menu {
                    Button { createJobEstimate() } label: { Label("New Estimate", systemImage: "doc.text.magnifyingglass") }
                    Button { showNewContract = true } label: { Label("New Contract", systemImage: "signature") }
                } label: {
                    Label("New", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
            }

            let contracts = jobContracts
            if jobEstimates.isEmpty && depositInvoice == nil && contracts.isEmpty && finalInvoices.isEmpty {
                Text("No estimate, contract or invoice yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if JobDisplayStatus(job) != .canceled {
                    Button { createJobEstimate() } label: { Label("New Estimate", systemImage: "doc.text.magnifyingglass") }
                        .buttonStyle(.bordered)
                }
            }

            ForEach(jobEstimates) { estimate in
                paperworkRow(
                    icon: "doc.text.magnifyingglass",
                    title: "Estimate \(estimate.invoiceNumber)",
                    status: "\(estimateStatusLabel(estimate)) \(currency(estimate.total))",
                    tint: estimateTint(estimate)
                ) { invoiceRoute = estimate }
            }

            if let cents = job.depositAmountCents, cents > 0 {
                paperworkRow(
                    icon: "banknote",
                    title: "Deposit",
                    status: "\(job.depositPaidAtMs != nil ? "Paid" : "Unpaid") \(currency(Double(cents) / 100))",
                    tint: job.depositPaidAtMs != nil ? SBWTheme.brandGreen : .orange
                ) {
                    if let depositInvoice { invoiceRoute = depositInvoice }
                }
            }

            ForEach(contracts) { contract in
                let status = ContractDisplayStatus(contract)
                paperworkRow(
                    icon: "signature",
                    title: contract.title.isEmpty ? "Contract" : contract.title,
                    status: status.label,
                    tint: status.foreground
                ) { selectedContract = contract }
            }

            ForEach(finalInvoices) { invoice in
                paperworkRow(
                    icon: "doc.plaintext",
                    title: "Invoice \(invoice.invoiceNumber)",
                    status: invoice.isPaid || invoice.wasSent
                        ? "\(invoice.isPaid ? "Paid" : (isOverdue(invoice) ? "Overdue" : "Unpaid")) \(currency(invoice.total))"
                        : "Draft",
                    tint: invoice.isPaid ? SBWTheme.brandGreen : (isOverdue(invoice) ? .red : invoice.wasSent ? .orange : .secondary)
                ) { invoiceRoute = invoice }
            }
        }
        .buttonStyle(.borderless)
        .sbwJobCardRow()
    }

    private func paperworkRow(icon: String, title: String, status: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                // Explicit colors: inside a borderless button, .primary and
                // .secondary resolve to the button's blue tint.
                Image(systemName: icon)
                    .foregroundStyle(Color.secondary)
                    .frame(width: 22)
                Text(title)
                    .foregroundStyle(Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 3)
                    .padding(.horizontal, 8)
                    .background(Capsule().fill(tint.opacity(0.15)))
                    .foregroundStyle(tint)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }

    private func estimateStatusLabel(_ estimate: Invoice) -> String {
        let status = estimate.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch status {
        case "sent": return "Sent"
        case "accepted": return "Accepted"
        case "declined": return "Declined"
        default: return "Draft"
        }
    }

    private func estimateTint(_ estimate: Invoice) -> Color {
        switch estimateStatusLabel(estimate) {
        case "Accepted": return SBWTheme.brandGreen
        case "Declined": return .red
        case "Sent": return SBWTheme.brandBlue
        default: return .secondary
        }
    }

    private func isOverdue(_ invoice: Invoice) -> Bool {
        invoice.isOverdue
    }

    private func currency(_ amount: Double) -> String {
        amount.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
    }

    // MARK: Collapsed groups

    private var detailsGroup: some View {
        Section {
            DisclosureGroup(isExpanded: $showDetails) {
                jobEssentialsCard
                scheduleCard
                locationCard
                calendarCard
            } label: {
                groupLabel("Details", icon: "square.and.pencil", detail: "Title, client, schedule, location")
            }
            .sbwJobCardRow()
        }
    }

    private var measurementsGroup: some View {
        Section {
            DisclosureGroup(isExpanded: $showMeasurements) {
                measurementsCard
            } label: {
                groupLabel("Measurements", icon: "ruler", detail: job.measurements.isEmpty ? "None yet" : "\(job.measurements.count)")
            }
            .sbwJobCardRow()
        }
    }

    private var folderGroup: some View {
        Section {
            DisclosureGroup(isExpanded: $showFolder) {
                filesCard
            } label: {
                groupLabel("Job Folder", icon: "folder", detail: "Files for this job")
            }
            .sbwJobCardRow()
        }
    }

    private func groupLabel(_ title: String, icon: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(.headline)
            Spacer()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Toolbar menu

    private var jobMenu: some View {
        Menu {
            if displayStatus != .needsScheduling && displayStatus != .canceled {
                Button {
                    Task { await syncCalendarEvent(viewAfter: hasCalendarEvent) }
                } label: {
                    Label(hasCalendarEvent ? "View Calendar Event" : "Add to Calendar", systemImage: "calendar")
                }
            }
            Button { shareSummary() } label: { Label("Share Summary", systemImage: "square.and.arrow.up") }
            Button { openFolder(kind: nil) } label: { Label("Job Folder", systemImage: "folder") }
            if jobEstimates.isEmpty {
                Button { createJobEstimate() } label: { Label("New Estimate", systemImage: "doc.text.magnifyingglass") }
            }
            if finalInvoice == nil {
                Button { createJobInvoice() } label: { Label("New Invoice", systemImage: "doc.badge.plus") }
            }

            Menu {
                Button("Scheduled") { setStage(.booked) }
                Button("In Progress") { setStage(.inProgress) }
                Button("Completed") { setStage(.completed) }
            } label: {
                Label("Change Stage", systemImage: "arrow.left.arrow.right")
            }

            Divider()

            if displayStatus == .canceled {
                Button { reopenJob() } label: { Label("Reopen Job", systemImage: "arrow.uturn.backward") }
            } else {
                Button(role: .destructive) { confirmCancelJob = true } label: {
                    Label("Cancel Job", systemImage: "xmark.circle")
                }
            }
            Button(role: .destructive) { confirmDeleteJob = true } label: {
                Label("Delete Job", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    // MARK: Actions

    static func defaultScheduleStart() -> Date {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func applySchedule() {
        job.startDate = scheduleStart
        job.endDate = max(scheduleEnd, scheduleStart.addingTimeInterval(15 * 60))
        job.needsScheduling = false
        saveNow()
        Task { await syncCalendarEvent(viewAfter: false) }
    }

    private func startJob() {
        JobLifecycle.start(job)
        showReschedule = false
        saveNow()
        Haptics.success()
    }

    private func completeJob() {
        JobLifecycle.complete(job)
        saveNow()
        Haptics.success()
    }

    private func cancelJob() {
        Task {
            await JobLifecycle.cancel(job)
            saveNow()
        }
    }

    private func reopenJob() {
        JobLifecycle.reopen(job)
        saveNow()
    }

    private func setStage(_ stage: JobStage) {
        JobLifecycle.setStage(job, to: stage)
        saveNow()
    }

    private var deleteImpactText: String {
        JobDeletion.impactMessage(for: job)
    }

    private func deleteJob() {
        let eventID = job.calendarEventId
        isDeleted = true
        pendingSaveTask?.cancel()
        pendingWorkspaceRenameTask?.cancel()
        pendingCalendarRefreshTask?.cancel()
        Task {
            try? await CalendarEventService.shared.removeEvent(identifier: eventID)
        }
        modelContext.delete(job)
        try? modelContext.save()
        dismiss()
    }

    private func createJobInvoice() {
        let businessID = job.businessID
        let profile = try? modelContext.fetch(
            FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == businessID })
        ).first
        do {
            invoiceRoute = try JobInvoiceBuilder.makeInvoice(
                for: job,
                client: linkedClient,
                profile: profile,
                context: modelContext
            )
        } catch {
            actionError = error.localizedDescription
        }
    }

    /// The same draft as everywhere else (the business's validity, terms and
    /// tax, named for the job), linked to this job. It used to be a bare
    /// "EST-20260925-103130" with none of the defaults.
    private func createJobEstimate() {
        do {
            let estimate = try EstimateDrafts.make(
                name: job.title,
                client: linkedClient,
                businessID: job.businessID,
                context: modelContext
            )
            estimate.job = job
            try modelContext.save()
            invoiceRoute = estimate
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func shareSummary() {
        let lines = [
            "Job: \(jobTitleText)",
            "Status: \(displayStatus.label)",
            jobPlaceText.isEmpty ? nil : jobPlaceText,
            displayStatus == .needsScheduling ? nil : jobWhenText,
            job.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : "Notes: \(job.notes)"
        ]
        shareItems = [lines.compactMap { $0 }.joined(separator: "\n")]
    }

    private func scheduleCalendarRefresh() {
        guard !isDraft, !isDeleted, hasCalendarEvent, !job.needsScheduling, job.stage != .canceled else { return }
        pendingCalendarRefreshTask?.cancel()
        pendingCalendarRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            await syncCalendarEvent(viewAfter: false)
        }
    }

    private var jobEssentialsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Job")
                .font(.headline)

            TextField("Title", text: $job.title)
                .onChange(of: job.title) { _, _ in
                    scheduleSave()
                    invalidateZip()

                    // ✅ Live rename (debounced)
                    scheduleWorkspaceRename()
                }

            Picker("Client", selection: Binding<UUID?>(
                get: { job.clientID },
                set: { value in
                    job.clientID = value
                    scheduleSave()
                })
            ) {
                Text("No Client").tag(nil as UUID?)
                ForEach(clients.filter { !$0.isArchived || $0.id == job.clientID }) { client in
                    Text(client.name.isEmpty ? "Client" : client.name)
                        .tag(Optional(client.id))
                }
            }
            .pickerStyle(.menu)

            if let linkedClient {
                Button {
                    editingClient = linkedClient
                } label: {
                    Label("Edit Linked Client", systemImage: "person.text.rectangle")
                }
                .buttonStyle(.bordered)
            }

            Button {
                draftClientName = ""
                draftClientEmail = ""
                draftClientPhone = ""
                draftClientAddress = ""
                showingNewClient = true
            } label: {
                Label("New Client", systemImage: "plus")
            }
            .buttonStyle(.bordered)
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

            if let latitude = job.latitude, let longitude = job.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                Map(initialPosition: .region(
                    MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
                )) {
                    Marker(job.locationName.isEmpty ? "Job Site" : job.locationName, coordinate: coordinate)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            }

            Button {
                captureCurrentLocation()
            } label: {
                if isCapturingLocation {
                    ProgressView()
                } else {
                    Label(job.latitude == nil ? "Use Current Location" : "Update Current Location", systemImage: "location.fill")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isCapturingLocation)
        }
        .sbwJobCardRow()
    }

    private var measurementsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Measurements")
                .font(.headline)

            if job.measurements.isEmpty {
                Text("No measurements yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Label on its own line, value and unit below: side by side at
            // 64pt and 50pt, values and units were cut off on smaller phones.
            ForEach($job.measurements) { $measurement in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        TextField("What you measured, e.g. Fence length", text: $measurement.label)
                        Button {
                            job.measurements.removeAll { $0.id == measurement.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove measurement")
                    }
                    HStack(spacing: 8) {
                        TextField("Value", value: $measurement.value, format: .number)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                        TextField("Unit, e.g. ft", text: $measurement.unit)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 120)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: job.measurements) { _, _ in scheduleSave() }

            Button {
                job.measurements.append(JobMeasurement())
                scheduleSave()
            } label: {
                Label("Add Measurement", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .sbwJobCardRow()
    }

    private func captureCurrentLocation() {
        isCapturingLocation = true
        Task {
            defer { isCapturingLocation = false }
            do {
                let location = try await locationService.captureCurrentLocation()
                job.latitude = location.coordinate.latitude
                job.longitude = location.coordinate.longitude

                // Best-effort — never overwrites an address the owner already typed,
                // and a failed/slow geocode still leaves the pin/coordinates in place.
                if job.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
                        job.locationName = [placemark.name, placemark.locality, placemark.administrativeArea]
                            .compactMap { $0 }
                            .joined(separator: ", ")
                    }
                }

                scheduleSave()
            } catch {
                locationCaptureError = error.localizedDescription
            }
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notes")
                .font(.headline)

            TextEditor(text: $job.notes)
                .frame(minHeight: 110)
                .scrollContentBackground(.hidden)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: job.notes) { _, _ in scheduleSave() }

            Text("Included in the job's calendar event.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .sbwProminentButton()

                Button("View Calendar Event") {
                    Task { await syncCalendarEvent(viewAfter: true) }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Add to Calendar") {
                    Task { await syncCalendarEvent(viewAfter: false) }
                }
                .sbwProminentButton()
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
            HStack {
                Text("Photos and Files")
                    .font(.headline)
                Spacer()
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showJobCamera = true
                    } label: {
                        Label("Photo", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if attachments.isEmpty {
                Text("No photos or files yet")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3),
                    spacing: 12
                ) {
                    ForEach(attachments) { a in
                        attachmentTile(a)
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
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("Take Photo") { showJobCamera = true }
                    }
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
        // The whole card is a single List row, and a row full of
        // default-style buttons fires them all on one tap — tapping an
        // attachment also opened "Attach Existing File". Borderless gives
        // each control its own tap target.
        .buttonStyle(.borderless)
        .sbwJobCardRow()
    }

    private func attachmentTile(_ attachment: JobAttachment) -> some View {
        Button {
            if isImageFile(attachment.file) {
                selectedPhotoAttachment = attachment
            } else {
                openPreview(attachment)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                AttachmentThumbnailView(file: attachment.file)
                if let caption = tileCaption(for: attachment) {
                    Text(caption)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                removeAttachment(attachment)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    /// The photo's own note if it has one. A photo without one needs no label
    /// — the thumbnail is the content, and its generated file name
    /// ("Photo-1789…") says nothing. Other files show their name, since a
    /// first-page thumbnail alone can be hard to tell apart.
    private func tileCaption(for attachment: JobAttachment) -> String? {
        let note = attachment.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { return note }
        guard !isImageFile(attachment.file) else { return nil }
        return attachment.file?.displayName ?? "Missing file"
    }

    private func isImageFile(_ file: FileItem?) -> Bool {
        guard let ext = file?.fileExtension.lowercased() else { return false }
        return ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext)
    }

    private var filesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // One button and a menu: seven grey folder buttons weighed more
            // on the page than anything else for something rarely opened.
            HStack(spacing: 10) {
                Button {
                    openFolder(kind: nil)
                } label: {
                    Label("Open Job Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)

                Menu {
                    Button("Contracts") { openFolder(kind: .contracts) }
                    Button("Invoices") { openFolder(kind: .invoices) }
                    Button("Estimates") { openFolder(kind: .estimates) }
                    Button("Photos") { openFolder(kind: .photos) }
                    Button("Attachments") { openFolder(kind: .attachments) }
                    Button("Deliverables") { openFolder(kind: .deliverables) }
                    Button("Other") { openFolder(kind: .other) }
                } label: {
                    Label("Subfolder", systemImage: "chevron.down")
                }
                .buttonStyle(.bordered)
            }
        }
        .buttonStyle(.borderless)
        .sbwJobCardRow()
    }

    private func saveNewClientAndLink() {
        let name = draftClientName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let newClient = Client(businessID: job.businessID)
        newClient.name = name
        newClient.email = draftClientEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        newClient.phone = draftClientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        newClient.address = draftClientAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        modelContext.insert(newClient)
        job.clientID = newClient.id

        do {
            try modelContext.save()
            showingNewClient = false
            scheduleSave()
        } catch {
            saveError = error.localizedDescription
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

            // Straight into the caption sheet — "take a photo, note what it
            // shows" is one motion, not two separate trips into Attachments.
            selectedPhotoAttachment = link
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
