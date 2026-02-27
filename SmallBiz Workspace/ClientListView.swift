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
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    private let businessID: UUID?

    @Query private var allClients: [Client]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]) private var invoices: [Invoice]

    @State private var searchText: String = ""
    @State private var filter: Filter = .all

    // New client sheet
    @State private var newClientDraft: Client? = nil
    @State private var openExistingClient: Client? = nil
    @State private var showOpenExistingBanner = false
    @State private var selectedClient: Client? = nil

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
        businessID ?? activeBiz.activeBusinessID
    }

    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case recent = "Recent"
        case favorites = "Favorites"

        var id: String { rawValue }
    }

    private struct ClientStats {
        var jobsCount: Int = 0
        var outstandingBalance: Double = 0
        var lastActivity: Date = .distantPast
    }

    // MARK: - Scoping

    private var scopedClients: [Client] {
        guard let bizID = effectiveBusinessID else { return [] }
        return allClients.filter { $0.businessID == bizID }
    }

    private var clientStatsByID: [UUID: ClientStats] {
        var stats: [UUID: ClientStats] = [:]

        for job in jobs {
            guard let clientID = job.clientID else { continue }
            var current = stats[clientID] ?? ClientStats()
            current.jobsCount += 1
            current.lastActivity = max(current.lastActivity, job.startDate)
            stats[clientID] = current
        }

        for invoice in invoices {
            guard let clientID = invoice.client?.id else { continue }
            var current = stats[clientID] ?? ClientStats()
            if !invoice.isPaid && invoice.documentType != "estimate" {
                current.outstandingBalance += invoice.total
            }
            current.lastActivity = max(current.lastActivity, invoice.issueDate)
            stats[clientID] = current
        }

        return stats
    }

    private var filtered: [Client] {
        let base: [Client]
        switch filter {
        case .all:
            base = scopedClients
        case .recent:
            base = scopedClients.filter { (clientStatsByID[$0.id]?.lastActivity ?? .distantPast) > Calendar.current.date(byAdding: .day, value: -45, to: .now)! }
        case .favorites:
            base = scopedClients.filter { $0.portalEnabled }
        }

        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return base }
        return base.filter {
            $0.name.lowercased().contains(q)
            || $0.email.lowercased().contains(q)
            || $0.phone.lowercased().contains(q)
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
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        scopedClients.isEmpty ? "No Clients Yet" : "No Results",
                        systemImage: "person.2",
                        description: Text(scopedClients.isEmpty
                                          ? "Tap + to add your first client."
                                          : "Try a different search.")
                    )
                    Button("Add Client") {
                        addClientAndOpenSheet()
                    }
                    .buttonStyle(.plain)
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filter != .all {
                        Button("Clear Filters") {
                            searchText = ""
                            filter = .all
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    ForEach(filtered) { client in
                        Button {
                            Haptics.lightTap()
                            selectedClient = client
                        } label: {
                            row(client)
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
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search clients"
        )
        .toolbar {
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
                        deleteIfEmptyAndClose()
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
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                deleteIfEmptyAndClose()
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                if draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    deleteIfEmptyAndClose()
                                    return
                                }

                                do {
                                    try modelContext.save()
                                    if (clientStatsByID[draft.id]?.jobsCount ?? 0) == 0 {
                                        _ = try JobWorkspaceFactory.createInitialJobAndWorkspace(
                                            context: modelContext,
                                            businessID: draft.businessID,
                                            client: draft
                                        )
                                    }
                                    searchText = ""
                                    newClientDraft = nil
                                } catch {
                                    print("Failed to save new client: \(error)")
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
        .overlay(alignment: .top) {
            if showOpenExistingBanner {
                OpenExistingClientBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Row UI (Option A parity)

    private func row(_ client: Client) -> some View {
        let stats = clientStatsByID[client.id] ?? ClientStats()
        let count = stats.jobsCount
        let name = client.name.isEmpty ? "Client" : client.name
        let contact = client.email.isEmpty ? client.phone : client.email
        let outstanding = stats.outstandingBalance
        let subtitle = [count > 0 ? "\(count) job\(count == 1 ? "" : "s")" : nil,
                        contact.isEmpty ? nil : contact,
                        outstanding > 0 ? "Outstanding \(outstanding.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))" : nil]
            .compactMap { $0 }
            .joined(separator: " • ")

        return ClientRowView(
            name: name,
            subtitle: subtitle.isEmpty ? " " : subtitle
        )
    }

    // MARK: - Add / Delete

    private func addClientAndOpenSheet() {
        guard let bizID = effectiveBusinessID else {
            print("❌ No active business selected")
            return
        }

        let c = Client(businessID: bizID)
        modelContext.insert(c)
        try? modelContext.save()
        Haptics.lightTap()
        newClientDraft = c
    }

    private func deleteIfEmptyAndClose() {
        if let draft = newClientDraft {
            let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = draft.email.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = draft.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            let address = draft.address.trimmingCharacters(in: .whitespacesAndNewlines)

            if name.isEmpty && email.isEmpty && phone.isEmpty && address.isEmpty {
                modelContext.delete(draft)
                try? modelContext.save()
            }
        }
        newClientDraft = nil
    }


    private func deleteFiltered(at offsets: IndexSet) {
        let toDelete = offsets.map { filtered[$0] }
        for c in toDelete { modelContext.delete(c) }

        do {
            try modelContext.save()
            Haptics.success()
        }
        catch {
            Haptics.error()
            print("Failed to save deletes: \(error)")
        }
    }

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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            SBWNavigationRow(title: name, subtitle: subtitle)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }
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
