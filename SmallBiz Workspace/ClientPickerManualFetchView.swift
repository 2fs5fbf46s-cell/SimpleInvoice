import Foundation
import SwiftUI
import SwiftData
import Contacts
import ContactsUI

struct ClientPickerManualFetchView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

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
    @State private var showingContactPicker = false
    @State private var pendingContact: CNContact? = nil
    @State private var duplicateCandidate: Client? = nil
    @State private var showDuplicateDialog = false
    @State private var openExistingClient: Client? = nil
    @State private var showOpenExistingBanner = false

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
                    Section {
                        Button {
                            showingContactPicker = true
                        } label: {
                            Label("Import from Contacts", systemImage: "person.crop.circle.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SBWTheme.brandBlue)
                    }

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
        .sheet(isPresented: $showingContactPicker) {
            ContactPicker(isPresented: $showingContactPicker) { contact in
                handleContactSelection(contact)
            } onCancel: {
            }
        }
        .navigationDestination(item: $openExistingClient) { client in
            ClientEditView(client: client)
        }
        .overlay(alignment: .top) {
            if showOpenExistingBanner {
                OpenExistingClientBanner()
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .confirmationDialog(
            "Existing Client Found",
            isPresented: $showDuplicateDialog,
            presenting: duplicateCandidate
        ) { match in
            Button("Open Existing") {
                showingNewClient = false
                editingClient = nil
                openExistingClient = match
                showOpenExistingBanner = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    showOpenExistingBanner = false
                }
                pendingContact = nil
                duplicateCandidate = nil
            }
            Button("Create New Anyway") {
                if let contact = pendingContact {
                    applyContactToDraft(contact)
                }
                pendingContact = nil
                duplicateCandidate = nil
            }
            Button("Cancel", role: .cancel) {
                pendingContact = nil
                duplicateCandidate = nil
            }
        } message: { match in
            Text("A client with the same email or phone already exists: \(match.name.isEmpty ? "Client" : match.name).")
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

    private func applyContactToDraft(_ contact: CNContact) {
        let f = ContactImportMapper.fields(from: contact)
        applyContactFieldsToDraft(f)
    }

    private func applyContactFieldsToDraft(_ fields: ContactImportFields) {
        draftName = fields.name
        draftEmail = fields.email
        draftPhone = fields.phone
        draftAddress = fields.address
    }

    private func handleContactSelection(_ contact: CNContact) {
        let fields = ContactImportMapper.fields(from: contact)
        let scopedClients = scopedDuplicateClients()
        if let match = ContactImportMapper.findDuplicateClient(
            in: scopedClients,
            fields: fields,
            businessID: activeBiz.activeBusinessID
        ) {
            pendingContact = contact
            duplicateCandidate = match
            showDuplicateDialog = true
            return
        }

        applyContactFieldsToDraft(fields)
    }

    private func scopedDuplicateClients() -> [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return clients }
        return clients.filter { $0.businessID == bizID }
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
