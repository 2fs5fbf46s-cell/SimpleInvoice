import Foundation
import SwiftUI
import SwiftData

struct ClientPickerManualFetchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedClient: Client?

    // ✅ Manual fetch state (no @Query)
    @State private var clients: [Client] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil

    // Edit existing client
    @State private var editingClient: Client? = nil

    // New client draft fields
    @State private var showingNewClient = false
    @State private var draftName: String = ""
    @State private var draftEmail: String = ""
    @State private var draftPhone: String = ""
    @State private var draftAddress: String = ""

    var body: some View {
        List {
            Section {
                Button {
                    selectedClient = nil
                    dismiss()
                } label: {
                    HStack {
                        Text("No Client")
                        Spacer()
                        if selectedClient == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
            }

            Section("Clients") {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Loading clients…")
                            .foregroundStyle(.secondary)
                    }
                } else if clients.isEmpty {
                    Text("No clients yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(clients) { client in
                        Button {
                            selectedClient = client
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(client.name.isEmpty ? "Client" : client.name)

                                    if !client.email.isEmpty {
                                        Text(client.email)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    } else if !client.phone.isEmpty {
                                        Text(client.phone)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()

                                if selectedClient?.persistentModelID == client.persistentModelID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .contextMenu {
                            Button("Edit") { editingClient = client }
                        }
                    }
                    .onDelete(perform: deleteClients)
                }
            }
        }
        .navigationTitle("Client")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    draftName = ""
                    draftEmail = ""
                    draftPhone = ""
                    draftAddress = ""
                    showingNewClient = true
                } label: {
                    Image(systemName: "plus")
                }
            }

            ToolbarItem(placement: .topBarLeading) {
                Button {
                    loadClients()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            // ✅ fetch once when view appears
            loadClients()
        }
        .alert("Client Load Failed", isPresented: Binding(
            get: { loadError != nil },
            set: { if !$0 { loadError = nil } }
        )) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
        .sheet(item: $editingClient) { client in
            NavigationStack {
                ClientEditView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                editingClient = nil
                                loadClients() // refresh list after edits
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingNewClient) {
            NavigationStack {
                Form {
                    Section("Client") {
                        TextField("Name", text: $draftName)
                        TextField("Email", text: $draftEmail)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                        TextField("Phone", text: $draftPhone)
                            .keyboardType(.phonePad)
                    }

                    Section("Address") {
                        TextField("Address", text: $draftAddress, axis: .vertical)
                            .lineLimit(2...6)
                    }
                }
                .navigationTitle("New Client")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingNewClient = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { saveNewClient() }
                            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Manual Fetch

    private func loadClients() {
        isLoading = true
        loadError = nil

        do {
            let descriptor = FetchDescriptor<Client>(
                sortBy: [SortDescriptor(\Client.name, order: .forward)]
            )
            // (No predicate — keep simple and stable)

            let results = try modelContext.fetch(descriptor)
            clients = results
            isLoading = false
        } catch {
            isLoading = false
            loadError = error.localizedDescription
        }
    }

    private func saveNewClient() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let newClient = Client()
        newClient.name = name
        newClient.email = draftEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        newClient.phone = draftPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        newClient.address = draftAddress.trimmingCharacters(in: .whitespacesAndNewlines)

        modelContext.insert(newClient)

        do {
            try modelContext.save()
            selectedClient = newClient
            showingNewClient = false
            dismiss()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func deleteClients(at offsets: IndexSet) {
        for index in offsets {
            guard index < clients.count else { continue }
            modelContext.delete(clients[index])
        }

        do {
            try modelContext.save()
            loadClients()
        } catch {
            loadError = error.localizedDescription
        }
    }
}
