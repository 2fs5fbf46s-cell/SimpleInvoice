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

    @Query(sort: \Client.name, order: .forward) private var allClients: [Client]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]

    @State private var searchText: String = ""

    // New client sheet
    @State private var newClientDraft: Client? = nil
    @State private var openExistingClient: Client? = nil
    @State private var showOpenExistingBanner = false
    @State private var selectedClient: Client? = nil

    // MARK: - Scoping

    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return allClients.filter { $0.businessID == bizID }
    }

    private var filtered: [Client] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return scopedClients }
        return scopedClients.filter {
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
                if activeBiz.activeBusinessID == nil {
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
                } else {
                    ForEach(filtered) { client in
                        Button {
                            selectedClient = client
                        } label: {
                            row(client)
                        }
                        .buttonStyle(.plain)
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
        .onAppear {
            try? activeBiz.loadOrCreateDefaultBusiness(modelContext: modelContext)
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
                                    if jobsCount(for: draft) == 0 {
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
            ClientEditView(client: client)
        }
        .navigationDestination(item: $selectedClient) { client in
            ClientEditView(client: client)
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
        let count = jobsCount(for: client)
        let name = client.name.isEmpty ? "Client" : client.name
        let contact = client.email.isEmpty ? client.phone : client.email
        let subtitle = [count > 0 ? "\(count) job\(count == 1 ? "" : "s")" : nil,
                        contact.isEmpty ? nil : contact]
            .compactMap { $0 }
            .joined(separator: " • ")

        return HStack(alignment: .top, spacing: 12) {
            // Leading icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Customers"))
                Image(systemName: "person.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            SBWNavigationRow(
                title: name,
                subtitle: subtitle.isEmpty ? " " : subtitle
            )
        }
        .padding(.vertical, 6)
    }

    // MARK: - Add / Delete

    private func addClientAndOpenSheet() {
        guard let bizID = activeBiz.activeBusinessID else {
            print("❌ No active business selected")
            return
        }

        let c = Client(businessID: bizID)
        modelContext.insert(c)
        try? modelContext.save()
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

        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }

    private func jobsCount(for client: Client) -> Int {
        let id = client.id
        return jobs.reduce(0) { partial, job in
            partial + ((job.clientID == id) ? 1 : 0)
        }
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
