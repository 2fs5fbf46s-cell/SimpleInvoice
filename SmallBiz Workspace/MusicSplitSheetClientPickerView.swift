import SwiftUI

struct MusicSplitSheetClientPickerView: View {
    @Environment(\.dismiss) private var dismiss

    let clients: [Client]
    @Binding var selectedClient: Client?

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section("Clients") {
                    if clients.isEmpty {
                        ContentUnavailableView(
                            "No Clients",
                            systemImage: "person.crop.circle.badge.exclamationmark",
                            description: Text("Add a client before generating a portal-ready split sheet.")
                        )
                    } else {
                        ForEach(clients) { client in
                            Button {
                                selectedClient = client
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(client.name.isEmpty ? "Client" : client.name)
                                            .foregroundStyle(.primary)

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

                                    if selectedClient?.id == client.id {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Select Client")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
