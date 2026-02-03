//
//  NewEstimateSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct NewEstimateSheet: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var client: Client?

    let onCancel: () -> Void
    let onCreate: () -> Void

    // Pull all clients; filter after based on active business.
    @Query(sort: \Client.name, order: .forward)
    private var allClients: [Client]

    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return allClients.filter { $0.businessID == bizID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Estimate") {
                    TextField("Name (e.g., Jamie Testerson 1)", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Client") {
                    Picker("Client", selection: $client) {
                        Text("None").tag(Client?.none)

                        ForEach(scopedClients) { c in
                            Text(c.name).tag(Optional(c))
                        }
                    }

                    if activeBiz.activeBusinessID == nil {
                        Text("No active business selected.")
                            .foregroundStyle(.secondary)
                    } else if scopedClients.isEmpty {
                        Text("No clients found for this business.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Estimate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
