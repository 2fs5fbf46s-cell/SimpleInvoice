import SwiftUI
import SwiftData

private enum JobSummarySection: Hashable {
    case schedule
    case notes
    case attachments
    case linked
    case activity
    case advanced
}

private struct JobSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

struct JobSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Bindable var job: Job

    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]) private var invoices: [Invoice]
    @Query(sort: [SortDescriptor(\Contract.createdAt, order: .reverse)]) private var contracts: [Contract]
    @Query private var clients: [Client]
    @Query private var profiles: [BusinessProfile]
    @Query private var attachments: [JobAttachment]

    @State private var expandedSection: JobSummarySection? = nil
    @State private var showEditor = false
    @State private var selectedInvoice: Invoice? = nil
    @State private var sharePayload: JobSharePayload? = nil
    @State private var errorMessage: String? = nil
    @State private var notesDraft: String = ""

    init(job: Job) {
        self.job = job
    }

    private var client: Client? {
        guard let id = job.clientID else { return nil }
        return clients.first(where: { $0.id == id })
    }

    private var clientName: String {
        let text = client?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "No Client" : text
    }

    private var statusText: String {
        switch job.stage {
        case .booked:
            let raw = job.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if raw == "pending" || raw == "requested" {
                return "REQUESTED"
            }
            return "SCHEDULED"
        case .inProgress:
            return "IN PROGRESS"
        case .completed:
            return "COMPLETED"
        case .canceled:
            return "CANCELLED"
        }
    }

    private var linkedInvoices: [Invoice] {
        invoices.filter { $0.job?.id == job.id }
    }

    private var linkedContracts: [Contract] {
        contracts.filter { contract in
            if contract.job?.id == job.id { return true }
            return contract.invoice?.job?.id == job.id
        }
    }

    private var linkedInvoiceForPrimaryAction: Invoice? {
        if let match = linkedInvoices.first(where: { $0.documentType != "estimate" }) {
            return match
        }
        return linkedInvoices.first
    }

    private var jobAttachments: [JobAttachment] {
        attachments.filter { $0.jobKey == job.id.uuidString }
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title,
                    subtitle: "Job Summary",
                    status: statusText
                )
                SummaryKit.SummaryKeyValueRow(label: "Client", value: clientName)
                SummaryKit.SummaryKeyValueRow(
                    label: "Start",
                    value: job.startDate.formatted(date: .abbreviated, time: .shortened)
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "End",
                    value: job.endDate.formatted(date: .abbreviated, time: .shortened)
                )
                if !job.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    SummaryKit.SummaryKeyValueRow(label: "Location", value: job.locationName)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Primary Actions")
                SummaryKit.PrimaryActionRow(actions: [
                    .init(title: "Edit / Details", systemImage: "square.and.pencil") {
                        showEditor = true
                    },
                    .init(title: "Share", systemImage: "square.and.arrow.up") {
                        shareJob()
                    },
                    .init(title: linkedInvoiceForPrimaryAction == nil ? "Create Invoice" : "Open Invoice", systemImage: "doc.plaintext") {
                        openOrCreateInvoice()
                    }
                ])
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Schedule",
                subtitle: "Date and time",
                icon: "calendar",
                isExpanded: expandedSection == .schedule,
                onToggle: { toggle(.schedule) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Starts", value: job.startDate.formatted(date: .complete, time: .shortened))
                    SummaryKit.SummaryKeyValueRow(label: "Ends", value: job.endDate.formatted(date: .complete, time: .shortened))
                    if let eventID = job.calendarEventId, !eventID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SummaryKit.SummaryKeyValueRow(label: "Calendar", value: "Linked")
                    }
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Scope / Notes",
                subtitle: "Job details",
                icon: "text.alignleft",
                isExpanded: expandedSection == .notes,
                onToggle: { toggle(.notes) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    TextEditor(text: $notesDraft)
                        .frame(minHeight: 110)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .onChange(of: notesDraft) { _, newValue in
                            let normalized = newValue.trimmingCharacters(in: .newlines)
                            if job.notes != normalized {
                                job.notes = normalized
                                try? modelContext.save()
                            }
                        }
                    Text("Changes save automatically.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Attachments",
                subtitle: "\(jobAttachments.count) files",
                icon: "paperclip",
                isExpanded: expandedSection == .attachments,
                onToggle: { toggle(.attachments) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if jobAttachments.isEmpty {
                        Text("No attachments")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(jobAttachments.prefix(3)) { attachment in
                            HStack(spacing: 8) {
                                Image(systemName: attachmentIconName(for: attachment.file))
                                    .foregroundStyle(.secondary)
                                Text(attachment.file?.displayName ?? "File")
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                        }
                    }
                    NavigationLink {
                        AttachmentsManagerView(job: job)
                    } label: {
                        Label("Manage Attachments", systemImage: "paperclip")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.subheadline.weight(.semibold))
                    }
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Linked Items",
                subtitle: "Invoice, contract, estimate, booking",
                icon: "link",
                isExpanded: expandedSection == .linked,
                onToggle: { toggle(.linked) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if linkedInvoices.isEmpty {
                        SummaryKit.SummaryKeyValueRow(label: "Invoices", value: "None")
                    } else {
                        ForEach(linkedInvoices.prefix(3)) { invoice in
                            Button {
                                selectedInvoice = invoice
                            } label: {
                                SummaryKit.SummaryListRow(
                                    icon: invoice.documentType == "estimate" ? "doc.text.magnifyingglass" : "doc.plaintext",
                                    title: invoice.documentType == "estimate" ? "Estimate \(invoice.invoiceNumber)" : "Invoice \(invoice.invoiceNumber)",
                                    secondary: invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    SummaryKit.SummaryKeyValueRow(label: "Contracts", value: linkedContracts.isEmpty ? "None" : "\(linkedContracts.count)")
                    SummaryKit.SummaryKeyValueRow(label: "Booking", value: bookingLinkSummary)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Activity / Timeline",
                subtitle: "Recent updates",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSection == .activity,
                onToggle: { toggle(.activity) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Status", value: statusText)
                    SummaryKit.SummaryKeyValueRow(label: "Start", value: job.startDate.formatted(date: .abbreviated, time: .shortened))
                    SummaryKit.SummaryKeyValueRow(label: "End", value: job.endDate.formatted(date: .abbreviated, time: .shortened))
                    if let invoice = linkedInvoiceForPrimaryAction {
                        SummaryKit.SummaryKeyValueRow(label: "Billing", value: invoice.isPaid ? "Invoice Paid" : "Invoice Outstanding")
                    }
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Advanced",
                subtitle: "IDs and diagnostics",
                icon: "slider.horizontal.3",
                isExpanded: expandedSection == .advanced,
                onToggle: { toggle(.advanced) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Job ID", value: job.id.uuidString)
                    SummaryKit.SummaryKeyValueRow(label: "Business ID", value: job.businessID.uuidString)
                    if let requestID = job.sourceBookingRequestId, !requestID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SummaryKit.SummaryKeyValueRow(label: "Booking Request", value: requestID)
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()
        }
        .navigationTitle("Job Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                JobDetailView(job: job)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showEditor = false }
                        }
                    }
            }
        }
        .sheet(item: $selectedInvoice) { invoice in
            NavigationStack {
                InvoiceOverviewView(invoice: invoice)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedInvoice = nil }
                        }
                    }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .alert("Jobs", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            notesDraft = job.notes
        }
    }

    private var bookingLinkSummary: String {
        let id = job.sourceBookingRequestId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? "None" : id
    }

    private func toggle(_ section: JobSummarySection) {
        if expandedSection == section {
            expandedSection = nil
        } else {
            expandedSection = section
        }
    }

    private func attachmentIconName(for file: FileItem?) -> String {
        guard let ext = file?.fileExtension.lowercased() else { return "paperclip" }
        if ["jpg", "jpeg", "png", "heic", "gif", "webp"].contains(ext) { return "photo" }
        if ext == "pdf" { return "doc.richtext" }
        if ["doc", "docx", "rtf", "txt", "pages"].contains(ext) { return "doc.text" }
        return "paperclip"
    }

    private func openOrCreateInvoice() {
        if let linked = linkedInvoiceForPrimaryAction {
            selectedInvoice = linked
            return
        }

        let profile = profileForJobBusiness()
        let number: String
        if let profile {
            number = InvoiceNumberGenerator.generateNextNumber(profile: profile)
        } else {
            number = "INV-\(Int(Date().timeIntervalSince1970))"
        }

        let invoice = Invoice(
            businessID: job.businessID,
            invoiceNumber: number,
            issueDate: Date(),
            dueDate: Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date(),
            isPaid: false,
            documentType: "invoice",
            client: client,
            job: job,
            items: []
        )

        modelContext.insert(invoice)
        do {
            try modelContext.save()
            selectedInvoice = invoice
        } catch {
            modelContext.delete(invoice)
            errorMessage = error.localizedDescription
        }
    }

    private func shareJob() {
        if let portalURL = bookingPortalURLIfAvailable() {
            sharePayload = JobSharePayload(items: [portalURL])
            return
        }

        let summary = """
        Job: \(job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title)
        Status: \(statusText)
        Client: \(clientName)
        Start: \(job.startDate.formatted(date: .abbreviated, time: .shortened))
        End: \(job.endDate.formatted(date: .abbreviated, time: .shortened))
        \(job.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "Location: \(job.locationName)")
        """
            .trimmingCharacters(in: .whitespacesAndNewlines)

        sharePayload = JobSharePayload(items: [summary])
    }

    private func profileForJobBusiness() -> BusinessProfile? {
        if let existing = profiles.first(where: { $0.businessID == job.businessID }) {
            return existing
        }
        if let activeBusinessID = activeBiz.activeBusinessID,
           let active = profiles.first(where: { $0.businessID == activeBusinessID }) {
            return active
        }
        return profiles.first
    }

    private func bookingPortalURLIfAvailable() -> URL? {
        guard let profile = profiles.first(where: { $0.businessID == job.businessID }) else { return nil }
        let base = profile.bookingURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty, let url = URL(string: base) else { return nil }

        guard let requestID = job.sourceBookingRequestId?.trimmingCharacters(in: .whitespacesAndNewlines), !requestID.isEmpty else {
            return url
        }

        guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        var query = comps.queryItems ?? []
        if !query.contains(where: { $0.name == "requestId" }) {
            query.append(URLQueryItem(name: "requestId", value: requestID))
        }
        comps.queryItems = query
        return comps.url ?? url
    }
}
