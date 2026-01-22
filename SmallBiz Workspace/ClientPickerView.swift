import Foundation
import SwiftUI
import SwiftData

struct ClientPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Client.name) private var clients: [Client]
    @Binding var selectedClient: Client?

    // Safe editing route (single client at a time)
    @State private var editingClient: Client? = nil

    // New Client Sheet (draft fields, not a SwiftData model)
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
                    // ✅ SAFE context menu: Button only (no NavigationLink)
                    .contextMenu {
                        Button("Edit") {
                            editingClient = client
                        }
                    }
                }
                .onDelete(perform: deleteClients)
            }
        }
        .navigationTitle("Client")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // reset draft fields
                    draftName = ""
                    draftEmail = ""
                    draftPhone = ""
                    draftAddress = ""
                    showingNewClient = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }

        // ✅ Edit existing client (single sheet, not N NavigationLinks)
        .sheet(item: $editingClient) { client in
            NavigationStack {
                ClientEditView(client: client)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { editingClient = nil }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }

        // ✅ Create new client safely (create+insert on Save)
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
            print("Failed to save new client: \(error)")
        }
    }

    private func deleteClients(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(clients[index])
        }
        do {
            try modelContext.save()
        } catch {
            print("Failed to save deletes: \(error)")
        }
    }
}
