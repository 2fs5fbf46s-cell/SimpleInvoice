import SwiftUI
import SwiftData
import UIKit

private enum ClientSummarySection: Hashable {
    case invoices
    case contracts
    case jobsBookings
    case attachments
    case notes
    case activity
    case advanced
}

private struct ClientSharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

private struct DraftInvoiceInput {
    var issueDate: Date
    var dueDate: Date
    var notes: String
}

struct ClientSummaryView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var client: Client

    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]) private var invoices: [Invoice]
    @Query(sort: [SortDescriptor(\Contract.updatedAt, order: .reverse)]) private var contracts: [Contract]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Query(sort: [SortDescriptor(\ClientAttachment.createdAt, order: .reverse)]) private var allAttachments: [ClientAttachment]
    @Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]) private var profiles: [BusinessProfile]

    @State private var expandedSection: ClientSummarySection? = nil
    @State private var showEditSheet = false
    @State private var selectedInvoice: Invoice? = nil
    @State private var selectedContract: Contract? = nil
    @State private var selectedJob: Job? = nil
    @State private var showAllInvoices = false
    @State private var showAllContracts = false
    @State private var showAllJobs = false
    @State private var showCreateInvoiceDraft = false
    @State private var draftInvoice = DraftInvoiceInput(issueDate: .now, dueDate: Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now, notes: "")
    @State private var sharePayload: ClientSharePayload? = nil
    @State private var notice: String? = nil
    @State private var errorMessage: String? = nil

    private var linkedInvoices: [Invoice] {
        invoices.filter { $0.client?.id == client.id }
    }

    private var linkedContracts: [Contract] {
        contracts.filter { $0.resolvedClient?.id == client.id }
    }

    private var linkedJobs: [Job] {
        jobs.filter { $0.clientID == client.id }
    }

    private var attachments: [ClientAttachment] {
        allAttachments.filter { $0.clientKey == client.id.uuidString }
    }

    private var openInvoicesCount: Int {
        linkedInvoices.filter { $0.documentType != "estimate" && !$0.isPaid }.count
    }

    private var totalOutstanding: Double {
        linkedInvoices
            .filter { $0.documentType != "estimate" && !$0.isPaid }
            .reduce(0) { $0 + $1.total }
    }

    private var lastInteractionDate: Date? {
        let invoiceDate = linkedInvoices.map(\.issueDate).max()
        let contractDate = linkedContracts.map(\.updatedAt).max()
        let jobDate = linkedJobs.map(\.startDate).max()
        return [invoiceDate, contractDate, jobDate].compactMap { $0 }.max()
    }

    private var preferredContactMethod: String {
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = client.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty { return "Email" }
        if !phone.isEmpty { return "Phone" }
        return "Not set"
    }

    private var statusText: String {
        client.portalEnabled ? "ACTIVE" : "ARCHIVED"
    }

    private var clientTitle: String {
        let name = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Client" : name
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: clientTitle,
                    subtitle: "Client Summary",
                    status: statusText
                )
                SummaryKit.SummaryKeyValueRow(label: "Email", value: displayOrDash(client.email))
                SummaryKit.SummaryKeyValueRow(label: "Phone", value: displayOrDash(client.phone))
                SummaryKit.SummaryKeyValueRow(label: "Preferred Contact", value: preferredContactMethod)
                SummaryKit.SummaryKeyValueRow(label: "Open Invoices", value: "\(openInvoicesCount)")
                SummaryKit.SummaryKeyValueRow(
                    label: "Outstanding",
                    value: totalOutstanding.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
                )
                SummaryKit.SummaryKeyValueRow(
                    label: "Last Interaction",
                    value: lastInteractionDate?.formatted(date: .abbreviated, time: .omitted) ?? "No activity"
                )
            }
            .listRowBackground(Color.clear)

            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Primary Actions")
                SummaryKit.PrimaryActionRow(actions: [
                    .init(title: "Message / Email", systemImage: "envelope") {
                        messageOrEmail()
                    },
                    .init(title: "Create Invoice", systemImage: "doc.badge.plus") {
                        startCreateInvoiceDraft()
                    },
                    .init(title: "Edit Client", systemImage: "square.and.pencil") {
                        showEditSheet = true
                    }
                ])

                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Invoices",
                subtitle: "Billing overview",
                icon: "doc.plaintext",
                isExpanded: expandedSection == .invoices,
                onToggle: { toggle(.invoices) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if linkedInvoices.isEmpty {
                        Text("No invoices")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
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
                    Button("View All") { showAllInvoices = true }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Contracts",
                subtitle: "Agreements and signatures",
                icon: "doc.text",
                isExpanded: expandedSection == .contracts,
                onToggle: { toggle(.contracts) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if linkedContracts.isEmpty {
                        Text("No contracts")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedContracts.prefix(3)) { contract in
                            Button {
                                selectedContract = contract
                            } label: {
                                SummaryKit.SummaryListRow(
                                    icon: "doc.text",
                                    title: contract.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contract" : contract.title,
                                    secondary: contract.statusRaw.capitalized
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("View All") { showAllContracts = true }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Jobs / Bookings",
                subtitle: "Scheduled work",
                icon: "calendar",
                isExpanded: expandedSection == .jobsBookings,
                onToggle: { toggle(.jobsBookings) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if linkedJobs.isEmpty {
                        Text("No jobs")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(linkedJobs.prefix(3)) { job in
                            Button {
                                selectedJob = job
                            } label: {
                                SummaryKit.SummaryListRow(
                                    icon: "calendar.badge.clock",
                                    title: job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title,
                                    secondary: job.startDate.formatted(date: .abbreviated, time: .omitted)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button("View All") { showAllJobs = true }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Attachments",
                subtitle: "Client files",
                icon: "paperclip",
                isExpanded: expandedSection == .attachments,
                onToggle: { toggle(.attachments) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if attachments.isEmpty {
                        Text("No attachments")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(attachments.prefix(5)) { attachment in
                            Text(attachment.file?.displayName ?? "File")
                                .font(.subheadline)
                                .lineLimit(1)
                        }
                    }
                    Button("Manage in Editor") { showEditSheet = true }
                        .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Notes",
                subtitle: "Recent notes",
                icon: "note.text",
                isExpanded: expandedSection == .notes,
                onToggle: { toggle(.notes) }
            ) {
                let noteText = linkedJobs.first(where: { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })?.notes ?? "No notes tracked for this client yet."
                Text(noteText)
                    .font(.subheadline)
                    .foregroundStyle(noteText == "No notes tracked for this client yet." ? .secondary : .primary)
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Activity / Timeline",
                subtitle: "Recent interactions",
                icon: "clock.arrow.circlepath",
                isExpanded: expandedSection == .activity,
                onToggle: { toggle(.activity) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(activityRows.prefix(5), id: \.title) { row in
                        SummaryKit.SummaryKeyValueRow(label: row.title, value: row.detail)
                    }
                }
            }
            .listRowBackground(Color.clear)

            SummaryKit.CollapsibleSectionCard(
                title: "Advanced",
                subtitle: "Identifiers",
                icon: "slider.horizontal.3",
                isExpanded: expandedSection == .advanced,
                onToggle: { toggle(.advanced) }
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryKit.SummaryKeyValueRow(label: "Client ID", value: client.id.uuidString)
                    SummaryKit.SummaryKeyValueRow(label: "Business ID", value: client.businessID.uuidString)
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
        .navigationTitle("Client Summary")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                ClientEditView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showEditSheet = false }
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
        .sheet(item: $selectedContract) { contract in
            NavigationStack {
                ContractSummaryView(contract: contract)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedContract = nil }
                        }
                    }
            }
        }
        .sheet(item: $selectedJob) { job in
            NavigationStack {
                JobSummaryView(job: job)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { selectedJob = nil }
                        }
                    }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(items: payload.items)
        }
        .sheet(isPresented: $showCreateInvoiceDraft) {
            NavigationStack {
                Form {
                    Section("Invoice") {
                        LabeledContent("Invoice Number") {
                            Text("Assigned on Save")
                                .foregroundStyle(.secondary)
                        }
                        DatePicker("Issue Date", selection: $draftInvoice.issueDate, displayedComponents: .date)
                        DatePicker("Due Date", selection: $draftInvoice.dueDate, displayedComponents: .date)
                    }
                    Section("Client") {
                        Text(clientTitle)
                        Text(displayOrDash(client.email))
                            .foregroundStyle(.secondary)
                    }
                    Section("Notes") {
                        TextField("Notes", text: $draftInvoice.notes, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                .navigationTitle("New Invoice")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showCreateInvoiceDraft = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            finalizeCreateInvoiceDraft()
                        }
                    }
                }
            }
        }
        .navigationDestination(isPresented: $showAllInvoices) {
            ClientInvoicesView(client: client)
        }
        .navigationDestination(isPresented: $showAllContracts) {
            ClientContractsView(client: client)
        }
        .navigationDestination(isPresented: $showAllJobs) {
            ClientJobsBookingsView(client: client)
        }
        .alert("Clients", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var activityRows: [(title: String, detail: String)] {
        var rows: [(String, String)] = []
        if let invoice = linkedInvoices.first {
            rows.append(("Latest Invoice", "\(invoice.invoiceNumber) • \(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))"))
        }
        if let contract = linkedContracts.first {
            rows.append(("Latest Contract", "\(contract.statusRaw.capitalized) • \(contract.updatedAt.formatted(date: .abbreviated, time: .omitted))"))
        }
        if let job = linkedJobs.first {
            rows.append(("Latest Job", "\(job.startDate.formatted(date: .abbreviated, time: .omitted)) • \(job.stageRaw)"))
        }
        if rows.isEmpty {
            rows.append(("Activity", "No activity yet"))
        }
        return rows
    }

    private func toggle(_ section: ClientSummarySection) {
        if expandedSection == section {
            expandedSection = nil
        } else {
            expandedSection = section
        }
    }

    private func messageOrEmail() {
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !email.isEmpty, let url = URL(string: "mailto:\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }

        if !email.isEmpty {
            UIPasteboard.general.string = email
            notice = "Email copied"
            clearNoticeSoon()
            return
        }

        let phone = client.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phone.isEmpty {
            UIPasteboard.general.string = phone
            notice = "Phone copied"
            clearNoticeSoon()
            return
        }

        errorMessage = "No contact method available for this client."
    }

    private func startCreateInvoiceDraft() {
        draftInvoice.issueDate = .now
        draftInvoice.dueDate = Calendar.current.date(byAdding: .day, value: 14, to: .now) ?? .now
        draftInvoice.notes = ""
        showCreateInvoiceDraft = true
    }

    private func finalizeCreateInvoiceDraft() {
        let profile = profileEnsured(for: client.businessID)
        let number = InvoiceNumberGenerator.generateNextNumber(profile: profile)
        let invoice = Invoice(
            businessID: client.businessID,
            invoiceNumber: number,
            issueDate: draftInvoice.issueDate,
            dueDate: draftInvoice.dueDate,
            notes: draftInvoice.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            isPaid: false,
            documentType: "invoice",
            client: client,
            job: nil,
            items: []
        )

        modelContext.insert(invoice)
        do {
            try modelContext.save()
            showCreateInvoiceDraft = false
            selectedInvoice = invoice
        } catch {
            modelContext.delete(invoice)
            errorMessage = error.localizedDescription
        }
    }

    private func profileEnsured(for businessID: UUID) -> BusinessProfile {
        if let profile = profiles.first(where: { $0.businessID == businessID }) {
            return profile
        }
        let created = BusinessProfile(businessID: businessID)
        modelContext.insert(created)
        return created
    }

    private func clearNoticeSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            notice = nil
        }
    }

    private func displayOrDash(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }
}

struct ClientJobsBookingsView: View {
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Bindable var client: Client

    private var filtered: [Job] {
        jobs.filter { $0.clientID == client.id }
    }

    var body: some View {
        List {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(title: "Jobs / Bookings")
                if filtered.isEmpty {
                    Text("No jobs")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { job in
                        NavigationLink {
                            JobSummaryView(job: job)
                        } label: {
                            SummaryKit.SummaryListRow(
                                icon: "calendar.badge.clock",
                                title: job.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Job" : job.title,
                                secondary: job.startDate.formatted(date: .abbreviated, time: .omitted)
                            )
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Jobs / Bookings")
    }
}
