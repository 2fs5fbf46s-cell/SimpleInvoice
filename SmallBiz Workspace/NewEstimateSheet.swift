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
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                SBWTheme.headerWash()

                ScrollView {
                    VStack(spacing: 14) {
                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Estimate")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                fieldRow(title: "Name") {
                                    TextField("Name (e.g., Jamie Testerson 1)", text: $name)
                                        .multilineTextAlignment(.trailing)
                                        .textInputAutocapitalization(.words)
                                }
                            }
                        }

                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Client")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                fieldRow(title: "Select") {
                                    Picker("Client", selection: $client) {
                                        Text("None").tag(Client?.none)

                                        ForEach(scopedClients) { c in
                                            Text(c.name).tag(Optional(c))
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }

                                if activeBiz.activeBusinessID == nil {
                                    Text("No active business selected.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else if scopedClients.isEmpty {
                                    Text("No clients found for this business.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("New Estimate")
            .navigationBarTitleDisplayMode(.inline)
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

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(SBWTheme.cardStroke, lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            content()
                .font(.subheadline)
        }
        .frame(minHeight: 42)
    }
}
