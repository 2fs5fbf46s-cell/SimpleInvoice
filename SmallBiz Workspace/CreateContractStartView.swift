//
//  CreateContractStartView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct CreateContractStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    private var scopedInvoices: [Invoice] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return invoices.filter { $0.businessID == bizID }
    }

    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return clients.filter { $0.businessID == bizID }
    }


    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]

    @State private var selectedTemplate: ContractTemplate?
    @State private var useInvoice: Bool = true

    @State private var selectedInvoice: Invoice?
    @State private var selectedClient: Client?

    @State private var previewText: String = ""
    @State private var showingPreview = false

    @State private var createError: String?

    var body: some View {
        Form {
            Section("Template") {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates Found",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Templates should seed on launch. Try closing/reopening the app.")
                    )
                } else {
                    Picker("Choose Template", selection: $selectedTemplate) {
                        Text("Select…").tag(Optional<ContractTemplate>.none)
                        ForEach(templates) { t in
                            Text("\(t.name) (\(t.category))").tag(Optional(t))
                        }
                    }
                }
            }
            
            Section("Source") {
                Toggle("Fill from Invoice", isOn: $useInvoice)
                    .onChange(of: useInvoice) { _, newValue in
                        if newValue {
                            selectedClient = nil
                        } else {
                            selectedInvoice = nil
                        }
                    }
                
                if useInvoice {
                    if scopedInvoices.isEmpty {
                        Text("No invoices yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Invoice", selection: $selectedInvoice) {
                            Text("Select…").tag(Optional<Invoice>.none)
                            ForEach(scopedInvoices) { inv in
                                Text("Invoice \(inv.invoiceNumber) — \(inv.client?.name ?? "No Client")")
                                    .tag(Optional(inv))
                            }
                        }
                        
                        if let inv = selectedInvoice {
                            Text("Client: \(inv.client?.name ?? "No Client")")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    if scopedClients.isEmpty {
                        Text("No clients yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Select Client", selection: $selectedClient) {
                            Text("Select…").tag(Optional<Client>.none)
                            ForEach(scopedClients) { c in
                                Text(c.name.isEmpty ? "Client" : c.name).tag(Optional(c))
                            }
                        }
                    }
                }
            }
            
            Section {
                Button {
                    generatePreview()
                } label: {
                    Label("Preview Contract", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed)
                
                Button {
                    saveDraft()
                } label: {
                    Label("Save Draft Contract", systemImage: "tray.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!canProceed)
            }
        }
        .navigationTitle("New Contract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showingPreview) {
            NavigationStack {
                ScrollView {
                    Text(previewText.isEmpty ? "Nothing to preview." : previewText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") { showingPreview = false }
                    }
                }
            }
        }
        .alert("Couldn’t Create Contract", isPresented: .constant(createError != nil), actions: {
            Button("OK") { createError = nil }
        }, message: {
            Text(createError ?? "Unknown error.")
        })
        .onAppear {
            // Helpful defaults
            if selectedTemplate == nil { selectedTemplate = templates.first }
            if useInvoice && selectedInvoice == nil { selectedInvoice = scopedInvoices.first }
            if !useInvoice && selectedClient == nil { selectedClient = scopedClients.first }
        }
        
        .onChange(of: useInvoice) { _, newValue in
            if newValue {
                selectedClient = nil
                selectedInvoice = scopedInvoices.first
            } else {
                selectedInvoice = nil
                selectedClient = scopedClients.first
            }
        }
    }


    private var business: BusinessProfile? {
        guard let bizID = activeBiz.activeBusinessID else { return nil }
        return profiles.first(where: { $0.businessID == bizID })
    }


    private var resolvedClient: Client? {
        if useInvoice { return selectedInvoice?.client }
        return selectedClient
    }

    private var canProceed: Bool {
        selectedTemplate != nil && (useInvoice ? selectedInvoice != nil : selectedClient != nil)
    }

    private func generatePreview() {
        guard let template = selectedTemplate else { return }

        let inv = useInvoice ? selectedInvoice : nil
        let client = resolvedClient

        let ctx = ContractContext(
            business: business,
            client: client,
            invoice: inv,
            extras: [:]
        )

        previewText = ContractTemplateEngine.render(template: template.body, context: ctx)
        showingPreview = true
    }

    private func saveDraft() {
        guard let template = selectedTemplate else { return }

        let inv = useInvoice ? selectedInvoice : nil
        let client = resolvedClient

        do {
            _ = try ContractCreation.create(
                context: modelContext,
                template: template,
                business: business,
                client: client,
                invoice: inv,
                extras: [:]
            )
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }
}
