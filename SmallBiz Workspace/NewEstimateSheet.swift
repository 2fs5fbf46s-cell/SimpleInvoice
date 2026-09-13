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

    // Scoped in the fetch rather than loading every client in the account.
    @Query private var allClients: [Client]

    init(
        name: Binding<String>,
        client: Binding<Client?>,
        businessID: UUID? = nil,
        onCancel: @escaping () -> Void,
        onCreate: @escaping () -> Void
    ) {
        _name = name
        _client = client
        self.onCancel = onCancel
        self.onCreate = onCreate

        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _allClients = Query(
            filter: #Predicate<Client> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
    }

    private var scopedClients: [Client] { allClients }

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
