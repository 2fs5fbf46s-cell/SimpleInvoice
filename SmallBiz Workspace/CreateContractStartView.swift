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
    let onCreated: (Contract) -> Void
    let onCancel: () -> Void

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
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Query private var profiles: [BusinessProfile]

    @State private var selectedTemplate: ContractTemplate?
    @State private var useInvoice: Bool = true

    @State private var selectedInvoice: Invoice?
    @State private var selectedClient: Client?

    @State private var previewText: String = ""
    @State private var showingPreview = false

    @State private var createError: String?
    @State private var showJobsPicker = false
    @State private var selectedJobIDs: [UUID] = []
    @State private var primaryJobID: UUID? = nil

    init(
        onCreated: @escaping (Contract) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.onCreated = onCreated
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            ScrollView {
                VStack(spacing: 14) {
                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Template")
                                .font(.headline)

                            if templates.isEmpty {
                                ContentUnavailableView(
                                    "No Templates Found",
                                    systemImage: "doc.badge.gearshape",
                                    description: Text("Templates should seed on launch. Try closing/reopening the app.")
                                )
                            } else {
                                fieldRow(title: "Choose") {
                                    Picker("Choose Template", selection: $selectedTemplate) {
                                        Text("Select…").tag(Optional<ContractTemplate>.none)
                                        ForEach(templates) { t in
                                            Text("\(t.name) (\(t.category))").tag(Optional(t))
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Source")
                                .font(.headline)

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
                                    fieldRow(title: "Invoice") {
                                        Picker("Select Invoice", selection: $selectedInvoice) {
                                            Text("Select…").tag(Optional<Invoice>.none)
                                            ForEach(scopedInvoices) { inv in
                                                Text("Invoice \(inv.invoiceNumber) — \(inv.client?.name ?? "No Client")")
                                                    .tag(Optional(inv))
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }

                                    if let inv = selectedInvoice {
                                        Text("Client: \(inv.client?.name ?? "No Client")")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                if scopedClients.isEmpty {
                                    Text("No clients yet.")
                                        .foregroundStyle(.secondary)
                                } else {
                                    fieldRow(title: "Client") {
                                        Picker("Select Client", selection: $selectedClient) {
                                            Text("Select…").tag(Optional<Client>.none)
                                            ForEach(scopedClients) { c in
                                                Text(c.name.isEmpty ? "Client" : c.name).tag(Optional(c))
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Jobs")
                                .font(.headline)

                            if selectedJobs.isEmpty {
                                Text("No linked jobs")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(selectedJobs) { job in
                                    HStack {
                                        Text(job.title.isEmpty ? "Untitled Job" : job.title)
                                        Spacer()
                                        if primaryJobID == job.id {
                                            Text("Primary")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }

                            Button("Manage Jobs") {
                                showJobsPicker = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    card {
                        VStack(spacing: 10) {
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
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle("New Contract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    onCancel()
                    dismiss()
                }
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
        .sheet(isPresented: $showJobsPicker) {
            NavigationStack {
                ContractJobsPickerSheet(
                    jobs: scopedJobs,
                    selectedJobIDs: $selectedJobIDs,
                    primaryJobID: $primaryJobID
                )
                .navigationTitle("Select Jobs")
                .navigationBarTitleDisplayMode(.inline)
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
            applyDefaultJobsFromInvoiceIfNeeded()
        }
        
        .onChange(of: useInvoice) { _, newValue in
            if newValue {
                selectedClient = nil
                selectedInvoice = scopedInvoices.first
                applyDefaultJobsFromInvoiceIfNeeded()
            } else {
                selectedInvoice = nil
                selectedClient = scopedClients.first
            }
        }
        .onChange(of: selectedInvoice?.id) { _, _ in
            applyDefaultJobsFromInvoiceIfNeeded()
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

    private var scopedJobs: [Job] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return jobs.filter { $0.businessID == bizID }
    }

    private var selectedJobs: [Job] {
        let ids = Set(selectedJobIDs)
        return scopedJobs.filter { ids.contains($0.id) }.sorted { $0.startDate > $1.startDate }
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

        guard let bizID = activeBiz.activeBusinessID else {
            createError = "No active business selected."
            return
        }

        let inv = useInvoice ? selectedInvoice : nil
        let client = resolvedClient

        do {
            let contract = try ContractCreation.create(
                context: modelContext,
                template: template,
                businessID: bizID,          // ✅ now defined
                business: business,
                client: client,
                invoice: inv,
                extras: [:]
            )
            let primary = scopedJobs.first(where: { $0.id == primaryJobID })
            let fallback = inv?.job
            contract.job = primary ?? fallback

            var linked = Set(selectedJobIDs)
            if let primaryID = contract.job?.id {
                linked.insert(primaryID)
            }
            contract.linkedJobIDsCSV = linked.map(\.uuidString).joined(separator: ",")
            try? modelContext.save()
            onCreated(contract)
            dismiss()
        } catch {
            createError = error.localizedDescription
        }
    }

    private func applyDefaultJobsFromInvoiceIfNeeded() {
        guard selectedJobIDs.isEmpty else { return }
        guard useInvoice, let invoiceJobID = selectedInvoice?.job?.id else { return }
        selectedJobIDs = [invoiceJobID]
        primaryJobID = invoiceJobID
    }
}
