//
//  NewEstimateSheet.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 2/1/26.
//

import Foundation
import SwiftUI
import SwiftData

struct NewEstimateSheet: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Client.name, order: .forward)
    private var clients: [Client]

    @Binding var name: String
    @Binding var client: Client?

    let onCancel: () -> Void
    let onCreate: () -> Void

    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return clients.filter { $0.businessID == bizID }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("New Estimate")
                    .font(.largeTitle.bold())
                    .padding(.top, 8)

                VStack(spacing: 0) {
                    HStack {
                        Text("Estimate")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.bottom, 8)

                    TextField("Name (e.g., Jamie Testerson 1)", text: $name)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled(false)

                    Divider().padding(.vertical, 10)

                    HStack {
                        Text("Client")
                        Spacer()

                        Picker("Client", selection: Binding(
                            get: { client?.id },
                            set: { id in
                                if let id {
                                    client = scopedClients.first(where: { $0.id == id })
                                } else {
                                    client = nil
                                }
                            }
                        )) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(scopedClients, id: \.id) { c in
                                Text(c.name).tag(Optional(c.id))
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.horizontal)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        onCreate()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
