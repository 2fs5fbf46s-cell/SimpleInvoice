import OSLog
//
//  ClientListView.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/12/26.
//

import SwiftUI
import SwiftData

struct ClientListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter
    private let businessID: UUID?

    @Query private var allClients: [Client]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]) private var invoices: [Invoice]

    @State private var searchText: String = ""
    @State private var filter: Filter = .all
    @State private var visibleClients: [Client] = []
    @State private var visibleClientRows: [ClientListRowModel] = []
    @State private var clientStatsCache: [UUID: ClientStats] = [:]

    // New client sheet
    @State private var newClientDraft: Client? = nil
    @State private var openExistingClient: Client? = nil
    @State private var showOpenExistingBanner = false
    @State private var selectedClient: Client? = nil

    // Delete confirmation
    @State private var pendingDeletion: PendingClientDeletion? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _allClients = Query(
                filter: #Predicate<Client> { client in
                    client.businessID == businessID
                },
                sort: [SortDescriptor(\Client.name, order: .forward)]
            )
            _jobs = Query(
                filter: #Predicate<Job> { job in
                    job.businessID == businessID
                },
                sort: [SortDescriptor(\Job.startDate, order: .reverse)]
            )
            _invoices = Query(
                filter: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID
                },
                sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
        } else {
            _allClients = Query(sort: [SortDescriptor(\Client.name, order: .forward)])
            _jobs = Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)])
            _invoices = Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
        }
    }

    private var effectiveBusinessID: UUID? {
        businessID
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        /// Was labelled "Favorites", but it filters on `portalEnabled` — which
        /// defaults to true for every client — and nothing in the app can
        /// favorite anyone. The control now says what it actually does.
        case portalOn = "Portal On"

        var id: String { rawValue }
    }

    private struct ClientStats {
        var jobsCount: Int = 0
        var outstandingBalance: Double = 0
        var lastActivity: Date = .distantPast
    }

    // MARK: - Scoping

    private var scopedClients: [Client] {
        allClients.scoped(to: effectiveBusinessID)
    }

    private var clientContentSignature: [String] {
        allClients.map {
            "\($0.id.uuidString)|\($0.name)|\($0.email)|\($0.phone)|\($0.portalEnabled)"
        }
    }

    private func recomputeVisibleClients() {
        let scopedClients: [Client]
        let scopedJobs: [Job]
        let scopedInvoices: [Invoice]
        scopedClients = allClients.scoped(to: effectiveBusinessID)
        scopedJobs = jobs.scoped(to: effectiveBusinessID)
        scopedInvoices = invoices.scoped(to: effectiveBusinessID)

        var computedStats: [UUID: ClientStats] = [:]
        for job in scopedJobs {
            guard let clientID = job.clientID else { continue }
            var current = computedStats[clientID] ?? ClientStats()
            current.jobsCount += 1
            current.lastActivity = max(current.lastActivity, job.startDate)
            computedStats[clientID] = current
        }

        for invoice in scopedInvoices {
            guard let clientID = invoice.client?.id else { continue }
            var current = computedStats[clientID] ?? ClientStats()
            if !invoice.isPaid && invoice.documentType != "estimate" {
                current.outstandingBalance += invoice.total
            }
            current.lastActivity = max(current.lastActivity, invoice.issueDate)
            computedStats[clientID] = current
        }

        // The new-client sheet inserts its draft up front, so without this the
        // half-typed record shows as a live row in the list behind the sheet.
        let draftID = newClientDraft?.id
        let listable = draftID == nil
            ? scopedClients
            : scopedClients.filter { $0.id != draftID }

        let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: .now) ?? .distantPast
        let base: [Client]
        switch filter {
        case .all:
            base = listable
        case .recent:
            base = listable.filter { (computedStats[$0.id]?.lastActivity ?? .distantPast) > cutoff }
        case .portalOn:
            base = listable.filter { $0.portalEnabled }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered: [Client]
        if q.isEmpty {
            filtered = base
        } else {
            filtered = base.filter {
                $0.name.lowercased().contains(q)
                || $0.email.lowercased().contains(q)
                || $0.phone.lowercased().contains(q)
            }
        }

        clientStatsCache = computedStats
        visibleClients = filtered
        visibleClientRows = filtered.map { client in
            makeRowModel(for: client, stats: computedStats[client.id] ?? ClientStats())
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A)
            SBWTheme.headerWash()

            List {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search clients", text: $searchText)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                }

                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(Filter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if effectiveBusinessID == nil {
                    ContentUnavailableView(
                        "No Business Selected",
                        systemImage: "building.2",
                        description: Text("Select a business to view clients.")
                    )
                } else if visibleClients.isEmpty {
                    let isFiltered = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || filter != .all
                    SBWEmptyState(
                        title: scopedClients.isEmpty ? "No Clients Yet" : "No Results",
                        message: scopedClients.isEmpty
                            ? "Add the people you invoice and they'll show up here."
                            : "No clients match this filter. Try a different one, or clear your search.",
                        systemImage: "person.2",
                        actionTitle: scopedClients.isEmpty ? "Add Client" : nil,
                        action: scopedClients.isEmpty ? { addClientAndOpenSheet() } : nil,
                        secondaryTitle: isFiltered ? "Clear Filters" : nil,
                        secondaryAction: isFiltered ? {
                            searchText = ""
                            filter = .all
                        } : nil
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(visibleClientRows) { rowModel in
                        Button {
                            Haptics.lightTap()
                            selectedClient = rowModel.client
                        } label: {
                            row(rowModel)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    .onDelete(perform: deleteFiltered)
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
            ToolbarItem(placement: .topBarTrailing) {
                Button { addClientAndOpenSheet() } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $newClientDraft) { draft in
            NavigationStack {
                ClientEditView(
                    client: draft,
                    isDraft: true,
                    onOpenExisting: { existing in
                        discardDraftAndClose()
                        DispatchQueue.main.async {
                            openExistingClient = existing
                            showOpenExistingBanner = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                                showOpenExistingBanner = false
                            }
                        }
                    }
                )
                    .navigationTitle("New Client")
                    .navigationBarTitleDisplayMode(.inline)
                    .sbwNavigationBarBackdrop()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                discardDraftAndClose()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    discardDraftAndClose()
                                    return
                                }

                                do {
                                    try modelContext.save()
                                    if (clientStatsCache[draft.id]?.jobsCount ?? 0) == 0 {
                                        _ = try JobWorkspaceFactory.createInitialJobAndWorkspace(
                                            context: modelContext,
                                            businessID: draft.businessID,
                                            client: draft
                                        )
                                    }
                                    searchText = ""
                                    newClientDraft = nil
                                } catch {
                                    SBWLog.ui.problem("Failed to save new client: \(error)")
                                }
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .navigationDestination(item: $openExistingClient) { client in
            ClientSummaryView(client: client)
        }
        .navigationDestination(item: $selectedClient) { client in
            ClientSummaryView(client: client)
        }
        .task(id: effectiveBusinessID) {
            recomputeVisibleClients()
        }
        .onChange(of: filter) {
            recomputeVisibleClients()
        }
        .onChange(of: searchText) {
            recomputeVisibleClients()
        }
        .onChange(of: clientContentSignature) {
            recomputeVisibleClients()
        }
        .onChange(of: jobs.count) {
            recomputeVisibleClients()
        }
        .onChange(of: invoices.count) {
            recomputeVisibleClients()
        }
        .onChange(of: newClientDraft?.id) {
            // Show or hide the in-flight draft row as the sheet opens and closes.
            recomputeVisibleClients()
        }
        .alert(
            "Delete \(pendingDeletion?.name ?? "client")?",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { pending in
            Button("Delete", role: .destructive) { confirmDeletion(pending) }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: { pending in
            Text(pending.impact.confirmationMessage(clientName: pending.name))
        }
        .overlay(alignment: .top) {
            if showOpenExistingBanner {
                OpenExistingClientBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }

        // Manual Test Steps:
        // 1) Switch business and confirm list + client stats remain correctly scoped.
        // 2) Create, cancel, create, save and verify editor opens with populated data immediately.
        // 3) Scroll large client list to validate lightweight row rendering.
    }

    // MARK: - Row UI (Option A parity)

    private func row(_ rowModel: ClientListRowModel) -> some View {
        ClientRowView(
            name: rowModel.name,
            subtitle: rowModel.subtitle
        )
    }

    private func makeRowModel(for client: Client, stats: ClientStats) -> ClientListRowModel {
        let count = stats.jobsCount
        let name = client.name.isEmpty ? "Client" : client.name
        let contact = client.email.isEmpty ? client.phone : client.email
        let outstanding = stats.outstandingBalance
        let subtitle = [count > 0 ? "\(count) job\(count == 1 ? "" : "s")" : nil,
                        contact.isEmpty ? nil : contact,
                        outstanding > 0 ? "Outstanding \(outstanding.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))" : nil]
            .compactMap { $0 }
            .joined(separator: " • ")

        return ClientListRowModel(
            client: client,
            name: name,
            subtitle: subtitle.isEmpty ? " " : subtitle
        )
    }

    // MARK: - Add / Delete

    private func addClientAndOpenSheet() {
        guard let bizID = effectiveBusinessID else {
            SBWLog.ui.problem("❌ No active business selected")
            return
        }

        let c = Client(businessID: bizID)
        modelContext.insert(c)
        try? modelContext.save()
        Haptics.lightTap()
        newClientDraft = c
    }

    /// Throw the draft away.
    ///
    /// This used to delete only when *every* field was still blank, so typing a
    /// single character into a new client and then tapping Cancel saved them
    /// anyway. The record exists at all only because `addClientAndOpenSheet`
    /// inserts one up front to give attachments a stable ID — from the user's
    /// side nothing existed before this sheet opened, so cancelling has to
    /// leave nothing behind.
    private func discardDraftAndClose() {
        if let draft = newClientDraft {
            modelContext.delete(draft)
            do {
                try modelContext.save()
            } catch {
                SBWLog.ui.problem("Failed to discard new client draft: \(error)")
            }
        }
        newClientDraft = nil
    }


    /// Swipe-to-delete used to destroy the client immediately, with no
    /// confirmation and no hint that invoices, jobs or contracts referenced it.
    /// Now it asks, and says what else is involved.
    private func deleteFiltered(at offsets: IndexSet) {
        let toDelete = offsets.map { visibleClients[$0] }
        guard !toDelete.isEmpty else { return }

        let impacts = toDelete.map { ClientDeletionImpact.forClient($0, jobs: jobs) }
        let combined = impacts.reduce(into: ClientDeletionImpact()) { total, next in
            total.invoices += next.invoices
            total.estimates += next.estimates
            total.jobs += next.jobs
            total.contracts += next.contracts
        }

        pendingDeletion = PendingClientDeletion(
            clients: toDelete,
            impact: combined,
            name: toDelete.count == 1
                ? toDelete[0].name
                : "\(toDelete.count) clients"
        )
    }

    private func confirmDeletion(_ pending: PendingClientDeletion) {
        // Every invoice already carries its own copy of the client it was sent
        // to, so deleting the record does not blank the documents. Take one last
        // snapshot for anything that somehow missed it.
        for client in pending.clients {
            for invoice in client.invoices ?? [] {
                invoice.captureClientSnapshotIfNeeded()
            }
            for contract in client.contracts ?? [] {
                contract.captureClientSnapshotIfNeeded()
            }
            modelContext.delete(client)
        }

        do {
            try modelContext.save()
            Haptics.success()
        }
        catch {
            Haptics.error()
            SBWLog.ui.problem("Failed to save deletes: \(error)")
        }

        pendingDeletion = nil
    }

}

/// A delete the user has asked for but not yet confirmed.
private struct PendingClientDeletion: Identifiable {
    let id = UUID()
    let clients: [Client]
    let impact: ClientDeletionImpact
    let name: String
}

private struct ClientRowView: View {
    let name: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Customers"))
                Image(systemName: "person.fill")
                    .font(.scaledSystem(size: 14, weight: .semibold, relativeTo: .footnote))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            SBWNavigationRow(title: name, subtitle: subtitle)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }
}

private struct ClientListRowModel: Identifiable {
    let client: Client
    let name: String
    let subtitle: String
    var id: UUID { client.id }
}

private struct OpenExistingClientBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.turn.down.right")
                .foregroundStyle(SBWTheme.brandBlue)
            Text("Opened existing client")
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

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension ClientListView: Equatable {
    static func == (lhs: ClientListView, rhs: ClientListView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
