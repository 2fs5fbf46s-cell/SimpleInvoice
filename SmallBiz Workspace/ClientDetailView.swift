//
//  ClientDetailView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

/// One screen per client, the same shape as the estimate, job and invoice
/// screens: who they are and how to reach them, then a Next step card with
/// the one thing most worth doing for them, what they owe, all their work,
/// and your notes. Details, the portal and files collapse below.
///
/// It replaces a summary of seven collapsed cards (with raw IDs under
/// Advanced and a "Notes" card that showed a job's notes) and a separate
/// edit screen that held the portal, template, jobs and files. The contact
/// form is now only the Edit sheet.
struct ClientDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Bindable var client: Client

    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    @Query private var contracts: [Contract]
    @Query private var profiles: [BusinessProfile]
    @Query private var businesses: [Business]

    @State private var showEdit = false
    @State private var documentRoute: Invoice? = nil
    @State private var jobRoute: Job? = nil
    @State private var contractRoute: Contract? = nil
    @State private var showAllWork = false

    @State private var paymentInvoice: Invoice? = nil
    @State private var reminderInvoice: Invoice? = nil
    @State private var sendingReminder = false

    @State private var showNewEstimate = false
    @State private var draftEstimateName = ""
    @State private var draftEstimateClient: Client? = nil
    @State private var showNewInvoice = false
    @State private var newJobDraft: Job? = nil
    @State private var showNewContract = false

    @State private var showDetails = false
    @State private var showPortal = false
    @State private var showFiles = false
    @State private var showTemplatePicker = false
    @State private var confirmDelete = false

    @State private var notice: String? = nil
    @State private var errorText: String? = nil

    init(client: Client) {
        self.client = client
        let businessID = client.businessID
        _invoices = Query(
            filter: #Predicate<Invoice> { $0.businessID == businessID },
            sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
        )
        _jobs = Query(
            filter: #Predicate<Job> { $0.businessID == businessID },
            sort: [SortDescriptor(\Job.startDate, order: .reverse)]
        )
        _contracts = Query(
            filter: #Predicate<Contract> { $0.businessID == businessID },
            sort: [SortDescriptor(\Contract.updatedAt, order: .reverse)]
        )
        _profiles = Query(filter: #Predicate<BusinessProfile> { $0.businessID == businessID })
        _businesses = Query(filter: #Predicate<Business> { $0.id == businessID })
    }

    private var overview: ClientOverview {
        ClientOverview(client: client, invoices: invoices, jobs: jobs, contracts: contracts)
    }

    private var businessName: String? {
        let name = (profiles.first?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    var body: some View {
        let overview = overview
        return ScrollView {
            VStack(spacing: 12) {
                header(overview)
                contactRow
                if client.isArchived { archivedNote }
                nextStepCard(overview)
                if overview.hasBillingHistory { moneyTiles(overview) }
                workCard(overview)
                notesCard
                detailsGroup
                portalGroup
                filesGroup
                recordActions
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 32)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Client")
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEdit = true }
            }
        }
        .navigationDestination(item: $documentRoute) { document in
            InvoiceDetailView(invoice: document)
        }
        .navigationDestination(item: $jobRoute) { job in
            JobDetailView(job: job)
        }
        .navigationDestination(item: $contractRoute) { contract in
            ContractDetailView(contract: contract)
        }
        .navigationDestination(isPresented: $showAllWork) {
            ClientWorkListView(client: client)
        }
        .modifier(sheets)
        .confirmationDialog(
            "Send a reminder?",
            isPresented: Binding(
                get: { reminderInvoice != nil },
                set: { if !$0 { reminderInvoice = nil } }
            ),
            titleVisibility: .visible,
            presenting: reminderInvoice
        ) { invoice in
            Button("Send Reminder") { sendReminder(invoice) }
            Button("Cancel", role: .cancel) { reminderInvoice = nil }
        } message: { invoice in
            Text(InvoiceSendService.confirmationMessage(for: invoice, kind: .reminder))
        }
        .confirmationDialog(
            "Delete \(client.displayName)?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            if !client.isArchived && ClientDeletionImpact.forClient(client, jobs: jobs).hasHistory {
                Button("Archive Instead") { setArchived(true) }
            }
            Button("Delete Client", role: .destructive) { deleteClient() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(ClientDeletionImpact.forClient(client, jobs: jobs).confirmationMessage(clientName: client.displayName))
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

    // MARK: - Sheets

    private var sheets: ClientDetailSheets {
        ClientDetailSheets(
            client: client,
            showEdit: $showEdit,
            paymentInvoice: $paymentInvoice,
            showNewEstimate: $showNewEstimate,
            draftEstimateName: $draftEstimateName,
            draftEstimateClient: $draftEstimateClient,
            showNewInvoice: $showNewInvoice,
            newJobDraft: $newJobDraft,
            showNewContract: $showNewContract,
            showTemplatePicker: $showTemplatePicker,
            businessDefaultTemplate: businessDefaultTemplate,
            onEstimate: createEstimate,
            onInvoiceCreated: { invoice in
                showNewInvoice = false
                documentRoute = invoice
            },
            onJobSaved: { job in jobRoute = job },
            onContractCreated: { contract in
                showNewContract = false
                contractRoute = contract
            }
        )
    }

    // MARK: - Header

    private func header(_ overview: ClientOverview) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(client.initials)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SBWTheme.brandBlue)
                .frame(width: 52, height: 52)
                .background(Circle().fill(SBWTheme.brandBlue.opacity(0.14)))

            VStack(alignment: .leading, spacing: 3) {
                Text(client.displayName)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                if let since = overview.clientSince {
                    Text("Client since \(since.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            statusPill(overview)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func statusPill(_ overview: ClientOverview) -> some View {
        if client.isArchived {
            pill("Archived", color: .secondary)
        } else if overview.overdueCents > 0 {
            pill("Owes \(InvoicePaymentService.currency(overview.owedCents))", color: .red)
        } else if overview.owedCents > 0 {
            pill("Owes \(InvoicePaymentService.currency(overview.owedCents))", color: .orange)
        }
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }

    private var archivedNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "archivebox")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("Archived \(client.archivedAt?.formatted(date: .abbreviated, time: .omitted) ?? "")")
                    .font(.subheadline.weight(.semibold))
                Text("Hidden from your client list and pickers. Their records are kept.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Unarchive") { setArchived(false) }
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .clientCard()
    }

    // MARK: - Contact

    private var contactRow: some View {
        let phone = ClientContact.phoneURL(client, scheme: "tel")
        let sms = ClientContact.phoneURL(client, scheme: "sms")
        let email = ClientContact.emailURL(client)
        let directions = ClientContact.directionsURL(client)
        return HStack {
            contactButton("Call", icon: "phone.fill", url: phone)
            contactButton("Text", icon: "message.fill", url: sms)
            contactButton("Email", icon: "envelope.fill", url: email)
            contactButton("Directions", icon: "location.fill", url: directions)
        }
        .buttonStyle(.borderless)
        .clientCard()
    }

    private func contactButton(_ title: String, icon: String, url: URL?) -> some View {
        Button {
            if let url { openURL(url) } else { showEdit = true }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(url != nil ? SBWTheme.brandBlue : Color.secondary.opacity(0.5))
        }
        .accessibilityHint(url == nil ? "Missing. Opens Edit to add it." : "")
    }

    // MARK: - Next step

    private func nextStepCard(_ overview: ClientOverview) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Next step")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SBWTheme.brandBlue)

            switch overview.nextStep {
            case .overdue(let invoice):
                let days = daysLate(invoice)
                stepTitle(
                    "\(ClientWorkItem.documentName(invoice)) is \(days) day\(days == 1 ? "" : "s") overdue",
                    detail: owedDetail(invoice)
                )
                HStack(spacing: 10) {
                    Button { reminderInvoice = invoice } label: {
                        Label(sendingReminder ? "Sending…" : "Send Reminder", systemImage: "bell")
                    }
                    .sbwProminentButton(.red)
                    .disabled(sendingReminder)
                    Button { paymentInvoice = invoice } label: { Label("Record Payment", systemImage: "dollarsign") }
                        .buttonStyle(.bordered)
                }
                openLink("Open invoice") { documentRoute = invoice }

            case .invoiceFinishedJob(let job):
                stepTitle(
                    "Bill for \(jobName(job))",
                    detail: "Finished \((job.completedAt ?? job.startDate).formatted(date: .abbreviated, time: .omitted)). There's no invoice for it yet."
                )
                HStack(spacing: 10) {
                    Button { createInvoice(for: job) } label: { Label("Create Invoice", systemImage: "doc.badge.plus") }
                        .sbwProminentButton()
                    Button { jobRoute = job } label: { Label("Open Job", systemImage: "wrench.and.screwdriver") }
                        .buttonStyle(.bordered)
                }

            case .scheduleJob(let job):
                stepTitle(
                    "Schedule \(jobName(job))",
                    detail: job.sourceEstimateId == nil
                        ? "It isn't on your calendar yet."
                        : "They accepted the estimate. Pick when the work happens."
                )
                Button { jobRoute = job } label: { Label("Schedule Job", systemImage: "calendar.badge.plus") }
                    .sbwProminentButton()

            case .finishDraft(let document):
                let isEstimate = document.documentType == "estimate"
                stepTitle(
                    "Finish \(ClientWorkItem.documentName(document, lowercased: true))",
                    detail: "Draft, \(InvoicePaymentService.currency(document.totalCents)). \(client.displayName) hasn't seen it yet."
                )
                Button { documentRoute = document } label: {
                    Label(isEstimate ? "Open Estimate" : "Open Invoice", systemImage: "square.and.pencil")
                }
                .sbwProminentButton()

            case .awaitingEstimate(let estimate):
                stepTitle(
                    "Waiting on \(ClientWorkItem.documentName(estimate, lowercased: true))",
                    detail: "\(InvoicePaymentService.currency(estimate.totalCents)), sent \((estimate.sentAt ?? estimate.issueDate).formatted(date: .abbreviated, time: .omitted)). Follow up if you haven't heard back."
                )
                HStack(spacing: 10) {
                    Button { documentRoute = estimate } label: { Label("Open Estimate", systemImage: "doc.text.magnifyingglass") }
                        .sbwProminentButton()
                    if let url = ClientContact.phoneURL(client, scheme: "sms") {
                        Button { openURL(url) } label: { Label("Text", systemImage: "message") }
                            .buttonStyle(.bordered)
                    }
                }

            case .awaitingPayment(let invoice):
                stepTitle(
                    "Waiting on payment for \(ClientWorkItem.documentName(invoice, lowercased: true))",
                    detail: "\(owedDetail(invoice)) Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))."
                )
                HStack(spacing: 10) {
                    Button { paymentInvoice = invoice } label: { Label("Record Payment", systemImage: "dollarsign") }
                        .sbwProminentButton()
                    Button { documentRoute = invoice } label: { Label("Open", systemImage: "doc.plaintext") }
                        .buttonStyle(.bordered)
                }

            case .upcomingJob(let job):
                let display = JobDisplayStatus(job)
                stepTitle(
                    display == .inProgress ? "\(jobName(job)) is in progress" : "\(jobName(job)) is scheduled",
                    detail: job.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
                )
                Button { jobRoute = job } label: { Label("Open Job", systemImage: "wrench.and.screwdriver") }
                    .sbwProminentButton()

            case .addContact:
                stepTitle(
                    "Add a way to reach \(client.displayName)",
                    detail: "An email lets you send estimates and invoices. A phone number lets you call and text."
                )
                Button { showEdit = true } label: { Label("Add Contact Info", systemImage: "person.crop.circle.badge.plus") }
                    .sbwProminentButton()

            case .startWork:
                stepTitle(
                    client.isArchived ? "Nothing open" : "Nothing open right now",
                    detail: "Quote the next piece of work, or put a job on the calendar."
                )
                HStack(spacing: 10) {
                    Button { startNewEstimate() } label: { Label("New Estimate", systemImage: "doc.text.magnifyingglass") }
                        .sbwProminentButton()
                    Button { startNewJob() } label: { Label("New Job", systemImage: "wrench.and.screwdriver") }
                        .buttonStyle(.bordered)
                }
            }
        }
        .clientCard()
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

    private func openLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                Image(systemName: "chevron.right").font(.caption2)
            }
            .font(.subheadline)
        }
        .buttonStyle(.borderless)
    }

    private func daysLate(_ invoice: Invoice) -> Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: invoice.dueDate),
            to: calendar.startOfDay(for: .now)
        ).day ?? 0
        return max(1, days)
    }

    private func owedDetail(_ invoice: Invoice) -> String {
        let balance = InvoicePaymentService.currency(invoice.balanceDueCents)
        var text = invoice.paidCents > 0
            ? "\(balance) left of \(InvoicePaymentService.currency(invoice.totalCents))."
            : "\(balance) owed."
        if let reminded = invoice.lastReminderAt {
            text += " Reminded \(reminded.formatted(date: .abbreviated, time: .omitted))."
        }
        return text
    }

    private func jobName(_ job: Job) -> String {
        let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "the job" : title
    }

    // MARK: - Money

    private func moneyTiles(_ overview: ClientOverview) -> some View {
        HStack(spacing: 12) {
            moneyTile(
                "Owed",
                value: InvoicePaymentService.currency(overview.owedCents),
                detail: overview.overdueInvoices.isEmpty
                    ? (overview.openInvoices.isEmpty ? "All paid up" : "\(overview.openInvoices.count) open")
                    : "\(overview.overdueInvoices.count) overdue",
                color: overview.overdueCents > 0 ? .red : .primary
            )
            moneyTile(
                "Paid this year",
                value: InvoicePaymentService.currency(overview.paidThisYearCents),
                detail: "Since Jan 1",
                color: .primary
            )
        }
    }

    private func moneyTile(_ title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .clientCard()
    }

    // MARK: - Work

    private func workCard(_ overview: ClientOverview) -> some View {
        let items = overview.workItems
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Work")
                    .font(.headline)
                Spacer()
                newMenu
            }

            if items.isEmpty {
                Text("No estimates, invoices, jobs or contracts yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items.prefix(5)) { item in
                    Button { open(item) } label: { ClientWorkRow(item: item) }
                        .buttonStyle(.plain)
                    if item.id != items.prefix(5).last?.id { Divider() }
                }
                if items.count > 5 {
                    Button { showAllWork = true } label: {
                        HStack(spacing: 4) {
                            Text("See all \(items.count)")
                            Image(systemName: "chevron.right").font(.caption2)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, 2)
                }
            }
        }
        .clientCard()
    }

    private var newMenu: some View {
        Menu {
            Button { startNewEstimate() } label: { Label("New Estimate", systemImage: "doc.text.magnifyingglass") }
            Button { showNewInvoice = true } label: { Label("New Invoice", systemImage: "doc.plaintext") }
            Button { startNewJob() } label: { Label("New Job", systemImage: "wrench.and.screwdriver") }
            Button { showNewContract = true } label: { Label("New Contract", systemImage: "signature") }
        } label: {
            Label("New", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
        }
    }

    private func open(_ item: ClientWorkItem) {
        switch item.target {
        case .document(let document): documentRoute = document
        case .job(let job): jobRoute = job
        case .contract(let contract): contractRoute = contract
        }
    }

    // MARK: - Notes

    private var notesCard: some View {
        let notes = client.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return Button { showEdit = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Notes")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: notes.isEmpty ? "plus" : "square.and.pencil")
                        .font(.subheadline)
                        .foregroundStyle(SBWTheme.brandBlue)
                }
                Text(notes.isEmpty ? "Gate codes, preferences, anything to remember. Only you see these." : notes)
                    .font(.subheadline)
                    .foregroundStyle(notes.isEmpty ? .secondary : .primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .clientCard()
    }

    // MARK: - More

    private var detailsGroup: some View {
        DisclosureGroup(isExpanded: $showDetails) {
            VStack(alignment: .leading, spacing: 10) {
                detailRow("Email", client.email)
                detailRow("Phone", client.phone)
                detailRow("Address", client.address)
                Divider()
                Button { showTemplatePicker = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Invoice template")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(templateSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 10)
        } label: {
            groupLabel("Details", icon: "person.text.rectangle", detail: "Contact, template")
        }
        .tint(.secondary)
        .clientCard()
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack(alignment: .top) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
            if trimmed.isEmpty {
                Button("Add") { showEdit = true }
                    .font(.subheadline)
            } else {
                Text(trimmed)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button { UIPasteboard.general.string = trimmed } label: {
                            Label("Copy \(label)", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
    }

    private var portalGroup: some View {
        DisclosureGroup(isExpanded: $showPortal) {
            ClientPortalCard(client: client, businessName: businessName)
                .padding(.top, 10)
        } label: {
            groupLabel("Client portal", icon: "person.2.badge.gearshape", detail: client.portalEnabled ? "On" : "Off")
        }
        .tint(.secondary)
        .clientCard()
    }

    private var filesGroup: some View {
        DisclosureGroup(isExpanded: $showFiles) {
            ClientFilesCard(client: client)
                .padding(.top, 10)
        } label: {
            groupLabel(
                "Files",
                icon: "paperclip",
                detail: (client.attachments ?? []).isEmpty ? "None yet" : "\((client.attachments ?? []).count)"
            )
        }
        .tint(.secondary)
        .clientCard()
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

    private var recordActions: some View {
        VStack(spacing: 10) {
            Button {
                setArchived(!client.isArchived)
            } label: {
                Label(client.isArchived ? "Unarchive Client" : "Archive Client", systemImage: "archivebox")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.secondary)

            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Delete Client", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)

            if !client.isArchived {
                Text("Archiving hides \(client.displayName) from your list and pickers and keeps everything. Delete removes the client for good.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .font(.subheadline.weight(.semibold))
        .padding(.top, 8)
    }

    // MARK: - Template

    private var businessDefaultTemplate: InvoiceTemplateKey {
        if let raw = businesses.first?.defaultInvoiceTemplateKey, let key = InvoiceTemplateKey.from(raw) {
            return key
        }
        return .modern_clean
    }

    private var templateSummary: String {
        if let preferred = InvoiceTemplateKey.from(client.preferredInvoiceTemplateKey) {
            return preferred.displayName
        }
        return "Business default (\(businessDefaultTemplate.displayName))"
    }

    // MARK: - Actions

    private func startNewEstimate() {
        draftEstimateName = ""
        draftEstimateClient = client
        showNewEstimate = true
    }

    private func createEstimate() {
        do {
            let estimate = try EstimateDrafts.make(
                name: draftEstimateName,
                client: draftEstimateClient ?? client,
                businessID: client.businessID,
                context: modelContext
            )
            showNewEstimate = false
            documentRoute = estimate
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func startNewJob() {
        let job = Job(
            businessID: client.businessID,
            clientID: client.id,
            title: "",
            startDate: .now,
            endDate: Calendar.current.date(byAdding: .hour, value: 2, to: .now) ?? .now
        )
        job.status = "scheduled"
        job.locationName = client.address
        newJobDraft = job
    }

    private func createInvoice(for job: Job) {
        do {
            documentRoute = try JobInvoiceBuilder.makeInvoice(
                for: job,
                client: client,
                profile: profiles.first,
                context: modelContext
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func sendReminder(_ invoice: Invoice) {
        reminderInvoice = nil
        guard !sendingReminder else { return }
        sendingReminder = true
        Task {
            defer { sendingReminder = false }
            do {
                switch try await InvoiceSendService.send(
                    invoice,
                    kind: .reminder,
                    context: modelContext,
                    businessName: EstimateSendService.businessName(for: invoice, profiles: profiles)
                ) {
                case .emailed(let email):
                    Haptics.success()
                    notice = "Reminder sent to \(email)."
                case .publishedNotEmailed(let link, _):
                    if let link { UIPasteboard.general.string = link }
                    errorText = link == nil
                        ? "The reminder email didn't go out. Try again in a moment."
                        : "The reminder email didn't go out. The invoice link is copied, so you can paste it to \(client.displayName)."
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    private func setArchived(_ archived: Bool) {
        ClientRecords.setArchived(archived, for: client, context: modelContext)
        Haptics.lightTap()
    }

    private func deleteClient() {
        do {
            try ClientRecords.delete([client], context: modelContext)
            Haptics.success()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// One row in the client's Work card and the full work list.
struct ClientWorkRow: View {
    let item: ClientWorkItem

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.kind.systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(item.status)
                .font(.caption.weight(.semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(item.statusColor.opacity(0.14)))
                .foregroundStyle(item.statusColor)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Everything done for a client, grouped by kind.
struct ClientWorkListView: View {
    let client: Client

    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    @Query private var contracts: [Contract]

    @State private var documentRoute: Invoice? = nil
    @State private var jobRoute: Job? = nil
    @State private var contractRoute: Contract? = nil

    init(client: Client) {
        self.client = client
        let businessID = client.businessID
        _invoices = Query(filter: #Predicate<Invoice> { $0.businessID == businessID })
        _jobs = Query(filter: #Predicate<Job> { $0.businessID == businessID })
        _contracts = Query(filter: #Predicate<Contract> { $0.businessID == businessID })
    }

    var body: some View {
        let items = ClientOverview(client: client, invoices: invoices, jobs: jobs, contracts: contracts).workItems
        List {
            ForEach(ClientWorkItem.Kind.allCases, id: \.self) { kind in
                let group = items.filter { $0.kind == kind }
                if !group.isEmpty {
                    Section(kind.rawValue) {
                        ForEach(group) { item in
                            Button { open(item) } label: { ClientWorkRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $documentRoute) { InvoiceDetailView(invoice: $0) }
        .navigationDestination(item: $jobRoute) { JobDetailView(job: $0) }
        .navigationDestination(item: $contractRoute) { ContractDetailView(contract: $0) }
    }

    private func open(_ item: ClientWorkItem) {
        switch item.target {
        case .document(let document): documentRoute = document
        case .job(let job): jobRoute = job
        case .contract(let contract): contractRoute = contract
        }
    }
}

/// The client screen's sheets, kept off its body so the type checker
/// doesn't give up on one long modifier chain.
private struct ClientDetailSheets: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    let client: Client
    @Binding var showEdit: Bool
    @Binding var paymentInvoice: Invoice?
    @Binding var showNewEstimate: Bool
    @Binding var draftEstimateName: String
    @Binding var draftEstimateClient: Client?
    @Binding var showNewInvoice: Bool
    @Binding var newJobDraft: Job?
    @Binding var showNewContract: Bool
    @Binding var showTemplatePicker: Bool
    let businessDefaultTemplate: InvoiceTemplateKey
    let onEstimate: () -> Void
    let onInvoiceCreated: (Invoice) -> Void
    let onJobSaved: (Job) -> Void
    let onContractCreated: (Contract) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $showEdit) {
                ClientEditSheet(client: client)
            }
            .sheet(item: $paymentInvoice) { invoice in
                RecordPaymentSheet(invoice: invoice)
            }
            .sheet(isPresented: $showNewEstimate) {
                NewEstimateSheet(
                    name: $draftEstimateName,
                    client: $draftEstimateClient,
                    businessID: client.businessID,
                    onCancel: { showNewEstimate = false },
                    onCreate: onEstimate
                )
            }
            .sheet(isPresented: $showNewInvoice) {
                NewInvoiceView(businessID: client.businessID, client: client, onCreated: onInvoiceCreated)
            }
            .sheet(item: $newJobDraft) { draft in
                NavigationStack {
                    JobDetailView(job: draft, isDraft: true)
                        .navigationTitle("New Job")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { newJobDraft = nil }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Save") { saveJob(draft) }
                                    .fontWeight(.semibold)
                                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                        }
                }
                .interactiveDismissDisabled()
            }
            .sheet(isPresented: $showNewContract) {
                NavigationStack {
                    CreateContractStartView(
                        businessID: client.businessID,
                        client: client,
                        onCreated: onContractCreated,
                        onCancel: { showNewContract = false }
                    )
                }
            }
            .sheet(isPresented: $showTemplatePicker) {
                NavigationStack {
                    InvoiceTemplatePickerSheet(
                        mode: .clientPreferred,
                        businessDefault: businessDefaultTemplate,
                        currentEffective: InvoiceTemplateKey.from(client.preferredInvoiceTemplateKey) ?? businessDefaultTemplate,
                        currentSelection: InvoiceTemplateKey.from(client.preferredInvoiceTemplateKey),
                        onSelectTemplate: { selected in
                            client.preferredInvoiceTemplateKey = selected.rawValue
                            try? modelContext.save()
                        },
                        onUseBusinessDefault: {
                            client.preferredInvoiceTemplateKey = nil
                            try? modelContext.save()
                        }
                    )
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showTemplatePicker = false }
                        }
                    }
                }
            }
    }

    private func saveJob(_ job: Job) {
        modelContext.insert(job)
        do {
            try modelContext.save()
            _ = try? WorkspaceProvisioningService.ensureJobWorkspace(job: job, context: modelContext)
            newJobDraft = nil
            onJobSaved(job)
        } catch {
            SBWLog.ui.problem("Failed to save new job: \(error)")
        }
    }
}

private struct ClientCard: ViewModifier {
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
    func clientCard() -> some View { modifier(ClientCard()) }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension ClientDetailView: Equatable {
    static func == (lhs: ClientDetailView, rhs: ClientDetailView) -> Bool {
        lhs.client.persistentModelID == rhs.client.persistentModelID
    }
}

extension ClientWorkListView: Equatable {
    static func == (lhs: ClientWorkListView, rhs: ClientWorkListView) -> Bool {
        lhs.client.persistentModelID == rhs.client.persistentModelID
    }
}
