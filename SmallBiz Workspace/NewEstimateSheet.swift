//
//  NewEstimateSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct NewEstimateSheet: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Binding var name: String
    @Binding var client: Client?

    let onCancel: () -> Void
    let onCreate: () -> Void

    private let businessID: UUID?
    @State private var newClientDraft: Client? = nil

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
        self.businessID = businessID
        self.onCancel = onCancel
        self.onCreate = onCreate

        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _allClients = Query(
            filter: #Predicate<Client> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
    }

    private var scopedClients: [Client] {
        allClients.filter { !$0.isArchived || $0.id == client?.id }
    }

    private var effectiveBusinessID: UUID? { businessID ?? activeBiz.activeBusinessID }

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

                                if effectiveBusinessID == nil {
                                    Text("No active business selected.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Divider().opacity(0.22)

                                    Button {
                                        startNewClient()
                                    } label: {
                                        Label("New Client", systemImage: "person.badge.plus")
                                            .font(.subheadline.weight(.semibold))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .frame(minHeight: 42)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(SBWTheme.brand)

                                    if scopedClients.isEmpty {
                                        Text("No clients yet. Add one here and it’s selected for this estimate.")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
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
            .sbwNavigationBarBackdrop()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { onCreate() }
                        .fontWeight(.semibold)
                }
            }
            .sheet(item: $newClientDraft) { draft in
                NewClientSheet(draft: draft) { saved in
                    if let saved { client = saved }
                    newClientDraft = nil
                }
            }
        }
    }

    private func startNewClient() {
        guard let bizID = effectiveBusinessID else { return }
        newClientDraft = NewClientSheet.makeDraft(businessID: bizID, in: modelContext)
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
