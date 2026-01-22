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
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @EnvironmentObject private var activeBiz: ActiveBusinessStore


    @State private var searchText: String = ""

    // New client sheet
    @State private var showingNewClient = false
    @State private var newClientDraft: Client? = nil

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
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    scopedClients.isEmpty ? "No Clients Yet" : "No Results",
                    systemImage: "person.2",
                    description: Text(scopedClients.isEmpty
                                      ? "Tap + to add your first client."
                                      : "Try a different search.")
                )
            } else {
                ForEach(filtered) { client in
                    NavigationLink {
                        ClientEditView(client: client)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(client.name.isEmpty ? "Client" : client.name)
                                    .font(.headline)

                                Spacer(minLength: 8)

                                let count = jobsCount(for: client)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.thinMaterial, in: Capsule())
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("\(count) jobs")
                                }
                            }

                            if !client.email.isEmpty {
                                Text(client.email)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else if !client.phone.isEmpty {
                                Text(client.phone)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(" ")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .onDelete(perform: deleteFiltered)
            }
        }
        .navigationTitle("Clients")
        .searchable(text: $searchText, prompt: "Search clients")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addClientAndOpenSheet()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewClient, onDismiss: {
            // Clear draft reference after closing
            newClientDraft = nil
        }) {
            NavigationStack {
                if let newClientDraft {
                    ClientEditView(client: newClientDraft)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") {
                                    // If user cancels and it’s still empty, remove it
                                    deleteIfEmptyAndClose()
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    // If they never entered a name, treat it like cancel
                                    if newClientDraft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        deleteIfEmptyAndClose()
                                        return
                                    }

                                    do {
                                        try modelContext.save()
                                        searchText = ""     // show immediately
                                        showingNewClient = false
                                    } catch {
                                        print("Failed to save new client: \(error)")
                                    }
                                }
                            }
                        }
                } else {
                    ProgressView("Loading…")
                        .navigationTitle("New Client")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Add / Delete

    private func addClientAndOpenSheet() {
        guard let bizID = activeBiz.activeBusinessID else {
            print("❌ No active business selected")
            return
        }

        let c = Client(businessID: bizID)
        modelContext.insert(c)
        newClientDraft = c
        showingNewClient = true

        do { try modelContext.save() }
        catch { print("Failed to save new client draft: \(error)") }
    }
    
    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return clients.filter { $0.businessID == bizID }
    }



    private func deleteIfEmptyAndClose() {
        guard let c = newClientDraft else {
            showingNewClient = false
            return
        }

        // If user never entered a name, delete the draft
        if c.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            modelContext.delete(c)
        }

        do { try modelContext.save() }
        catch { print("Failed to save after cancel: \(error)") }

        showingNewClient = false
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
