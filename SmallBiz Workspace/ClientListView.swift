//
//  ClientListView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Filters that each answer a question: who owes me, who am I working for.
/// "Recent" and "Portal On" were here before; the second was on for nearly
/// everyone and meant nothing as a filter.
private enum ClientListFilter: String, CaseIterable {
    case all = "All"
    case owing = "Owe you"
    case active = "Active work"
    case archived = "Archived"
}

/// A client with what the list says about them, worked out once per change.
private struct ClientListEntry: Identifiable {
    let client: Client
    let overview: ClientOverview
    let isActive: Bool
    var id: UUID { client.id }
}

struct ClientListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter
    private let businessID: UUID?

    @Query private var clients: [Client]
    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    @Query private var contracts: [Contract]

    @State private var searchText = ""
    @State private var filter: ClientListFilter = .all
    @State private var newClientDraft: Client? = nil
    @State private var selectedClient: Client? = nil
    @State private var pendingDelete: Client? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _clients = Query(
            filter: #Predicate<Client> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
        _invoices = Query(filter: #Predicate<Invoice> { $0.businessID == scopedID })
        _jobs = Query(filter: #Predicate<Job> { $0.businessID == scopedID })
        _contracts = Query(filter: #Predicate<Contract> { $0.businessID == scopedID })
    }

    // MARK: - Data

    private var entries: [ClientListEntry] {
        // Group records by client once, so each overview looks at its own.
        let invoicesByClient = Dictionary(grouping: invoices.filter { $0.client != nil }) { $0.client!.id }
        let jobsByClient = Dictionary(grouping: jobs.filter { $0.clientID != nil }) { $0.clientID! }
        let contractsByClient = Dictionary(grouping: contracts.filter { $0.resolvedClient != nil }) { $0.resolvedClient!.id }
        // The new-client sheet inserts its draft up front; keep it out of
        // the list behind the sheet.
        let draftID = newClientDraft?.id

        return clients.filter { $0.id != draftID }.map { client in
            let overview = ClientOverview(
                client: client,
                invoices: invoicesByClient[client.id] ?? [],
                jobs: jobsByClient[client.id] ?? [],
                contracts: contractsByClient[client.id] ?? []
            )
            return ClientListEntry(
                client: client,
                overview: overview,
                isActive: overview.workItems.contains(where: \.isOpen)
            )
        }
    }

    private func visible(_ all: [ClientListEntry]) -> [ClientListEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matching = all.filter { entry in
            guard !query.isEmpty else { return true }
            let client = entry.client
            return client.name.lowercased().contains(query)
                || client.email.lowercased().contains(query)
                || client.phone.lowercased().contains(query)
                || client.address.lowercased().contains(query)
        }

        switch filter {
        case .all:
            // Searching finds archived clients too; browsing doesn't.
            return query.isEmpty ? matching.filter { !$0.client.isArchived } : matching
        case .owing:
            return matching
                .filter { $0.overview.owedCents > 0 }
                .sorted { lhs, rhs in
                    if (lhs.overview.overdueCents > 0) != (rhs.overview.overdueCents > 0) {
                        return lhs.overview.overdueCents > 0
                    }
                    return lhs.overview.owedCents > rhs.overview.owedCents
                }
        case .active:
            return matching.filter { $0.isActive && !$0.client.isArchived }
        case .archived:
            return matching.filter { $0.client.isArchived }
        }
    }

    // MARK: - Body

    var body: some View {
        let all = entries
        let shown = visible(all)
        let owed = all.reduce(0) { $0 + $1.overview.owedCents }
        let overdue = all.reduce(0) { $0 + $1.overview.overdueCents }

        return ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search name, email, phone, address", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button {
                            addClient()
                        } label: {
                            Image(systemName: "plus")
                                .font(.headline.weight(.semibold))
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(SBWTheme.brandBlue.opacity(0.2)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("New Client")
                    }
                    .padding(.vertical, 4)

                    if owed > 0 {
                        HStack(spacing: 10) {
                            metricTile("Owed to you", cents: owed, color: .primary) { filter = .owing }
                            metricTile("Overdue", cents: overdue, color: overdue > 0 ? .red : .primary) { filter = .owing }
                        }
                        .buttonStyle(.plain)
                    }

                    SBWFilterChips(
                        options: ClientListFilter.allCases,
                        title: { option in chipTitle(option, all: all) },
                        selection: $filter
                    )
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }

                if businessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to see its clients.")
                    )
                } else if shown.isEmpty {
                    Section { emptyState(hasClients: !all.isEmpty) }
                } else {
                    Section {
                        ForEach(shown) { entry in
                            Button {
                                Haptics.lightTap()
                                selectedClient = entry.client
                            } label: {
                                ClientListRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if let url = ClientContact.phoneURL(entry.client, scheme: "tel") {
                                    Button { openURL(url) } label: { Label("Call", systemImage: "phone.fill") }
                                        .tint(SBWTheme.brandGreen)
                                }
                                if let url = ClientContact.phoneURL(entry.client, scheme: "sms") {
                                    Button { openURL(url) } label: { Label("Text", systemImage: "message.fill") }
                                        .tint(SBWTheme.brandBlue)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    pendingDelete = entry.client
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                                Button {
                                    ClientRecords.setArchived(!entry.client.isArchived, for: entry.client, context: modelContext)
                                    Haptics.lightTap()
                                } label: {
                                    Label(entry.client.isArchived ? "Unarchive" : "Archive", systemImage: "archivebox")
                                }
                                .tint(.gray)
                            }
                        }
                    } header: {
                        if filter == .all {
                            Text("\(shown.count) client\(shown.count == 1 ? "" : "s")")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Clients")
        .navigationBarTitleDisplayMode(.large)
        .sbwNavigationBarBackdrop()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BusinessAvatarButton { businessSettingsPresenter.open() }
            }
        }
        .sheet(item: $newClientDraft) { draft in
            NewClientSheet(draft: draft) { saved in
                newClientDraft = nil
                if let saved {
                    searchText = ""
                    if filter == .archived { filter = .all }
                    DispatchQueue.main.async { selectedClient = saved }
                }
            }
        }
        .navigationDestination(item: $selectedClient) { client in
            ClientDetailView(client: client)
        }
        .confirmationDialog(
            "Delete \(pendingDelete?.displayName ?? "client")?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { client in
            if !client.isArchived && ClientDeletionImpact.forClient(client, jobs: jobs).hasHistory {
                Button("Archive Instead") {
                    ClientRecords.setArchived(true, for: client, context: modelContext)
                    pendingDelete = nil
                }
            }
            Button("Delete Client", role: .destructive) { delete(client) }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: { client in
            Text(ClientDeletionImpact.forClient(client, jobs: jobs).confirmationMessage(clientName: client.displayName))
        }
    }

    private func chipTitle(_ option: ClientListFilter, all: [ClientListEntry]) -> String {
        let count: Int
        switch option {
        case .all: return option.rawValue
        case .owing: count = all.filter { $0.overview.owedCents > 0 }.count
        case .active: count = all.filter { $0.isActive && !$0.client.isArchived }.count
        case .archived: count = all.filter { $0.client.isArchived }.count
        }
        return count > 0 ? "\(option.rawValue) \(count)" : option.rawValue
    }

    private func metricTile(_ title: String, cents: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(color == .red ? Color.red : Color.secondary)
                Text(InvoicePaymentService.currency(cents))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        }
    }

    @ViewBuilder
    private func emptyState(hasClients: Bool) -> some View {
        let isSearching = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(spacing: 8) {
            Image(systemName: "person.2")
                .font(.title2)
                .foregroundStyle(.secondary)
            if isSearching {
                Text("No clients match \"\(searchText)\"")
                    .font(.headline)
            } else if !hasClients {
                Text("Add your first client")
                    .font(.headline)
                Text("The people you quote, schedule and bill.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button { addClient() } label: { Label("New Client", systemImage: "plus") }
                    .sbwProminentButton()
                    .padding(.top, 4)
            } else {
                Text(emptyTitle)
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var emptyTitle: String {
        switch filter {
        case .all: return "No clients"
        case .owing: return "Nobody owes you right now"
        case .active: return "No open work"
        case .archived: return "No archived clients"
        }
    }

    // MARK: - Actions

    private func addClient() {
        guard let businessID else { return }
        Haptics.lightTap()
        newClientDraft = NewClientSheet.makeDraft(businessID: businessID, in: modelContext)
    }

    private func delete(_ client: Client) {
        pendingDelete = nil
        do {
            try ClientRecords.delete([client], context: modelContext)
            Haptics.success()
        } catch {
            Haptics.error()
            SBWLog.ui.problem("Failed to delete client: \(error)")
        }
    }
}

private struct ClientListRow: View {
    let entry: ClientListEntry

    private var client: Client { entry.client }
    private var overview: ClientOverview { entry.overview }

    var body: some View {
        HStack(spacing: 12) {
            Text(client.initials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(client.isArchived ? Color.secondary : SBWTheme.brandBlue)
                .frame(width: 38, height: 38)
                .background(Circle().fill((client.isArchived ? Color.secondary : SBWTheme.brandBlue).opacity(0.14)))

            VStack(alignment: .leading, spacing: 2) {
                Text(client.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(client.isArchived ? .secondary : .primary)
                    .lineLimit(1)
                Text(contextLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var trailing: some View {
        if overview.owedCents > 0 {
            let late = overview.overdueCents > 0
            VStack(alignment: .trailing, spacing: 2) {
                Text(InvoicePaymentService.currency(overview.owedCents))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(late ? Color.red : Color.primary)
                Text(late ? "Overdue" : "Owed")
                    .font(.caption2)
                    .foregroundStyle(late ? Color.red : Color.secondary)
            }
        } else if client.isArchived {
            Text("Archived")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    /// What's going on with them, in a few words.
    private var contextLine: String {
        switch overview.nextStep {
        case .overdue(let invoice):
            return "\(ClientWorkItem.documentName(invoice)) was due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))"
        case .invoiceFinishedJob(let job):
            return "\(title(job)) done · not invoiced"
        case .scheduleJob(let job):
            return "\(title(job)) · needs scheduling"
        case .finishDraft(let document):
            return document.documentType == "estimate" ? "Draft estimate" : "Draft invoice"
        case .awaitingEstimate(let estimate):
            return "Estimate sent \((estimate.sentAt ?? estimate.issueDate).formatted(date: .abbreviated, time: .omitted))"
        case .awaitingPayment(let invoice):
            return "Invoice due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))"
        case .upcomingJob(let job):
            return JobDisplayStatus(job) == .inProgress
                ? "\(title(job)) · in progress"
                : "\(title(job)) · \(job.startDate.formatted(date: .abbreviated, time: .omitted))"
        case .addContact:
            return "No email or phone"
        case .startWork:
            if let last = overview.lastActivity {
                return "Last work \(last.formatted(date: .abbreviated, time: .omitted))"
            }
            let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
            return email.isEmpty ? client.phone : email
        }
    }

    private func title(_ job: Job) -> String {
        let trimmed = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Job" : trimmed
    }
}

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension ClientListView: Equatable {
    static func == (lhs: ClientListView, rhs: ClientListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
