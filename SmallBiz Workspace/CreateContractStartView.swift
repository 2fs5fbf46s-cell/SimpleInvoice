//
//  CreateContractStartView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct CreateContractStartView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?
    let onCreated: (Contract) -> Void
    let onCancel: () -> Void

    private var scopedInvoices: [Invoice] {
        guard let bizID = businessID else { return [] }
        return invoices.filter { $0.businessID == bizID }
    }

    private var scopedClients: [Client] {
        guard let bizID = businessID else { return [] }
        return clients.filter { $0.businessID == bizID && (!$0.isArchived || $0.id == selectedClient?.id) }
    }


    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Query private var profiles: [BusinessProfile]

    @State private var selectedTemplate: ContractTemplate?
    /// Start from a client; filling from an invoice or estimate is opt-in.
    @State private var useInvoice: Bool = false

    @State private var selectedInvoice: Invoice?
    @State private var selectedClient: Client?

    @State private var previewText: String = ""
    @State private var showingPreview = false

    @State private var createError: String?
    @State private var showJobsPicker = false
    @State private var showingMusicSplitSheetForm = false
    @State private var selectedJobIDs: [UUID] = []
    @State private var primaryJobID: UUID? = nil

    init(
        businessID: UUID? = nil,
        client: Client? = nil,
        job: Job? = nil,
        onCreated: @escaping (Contract) -> Void = { _ in },
        onCancel: @escaping () -> Void = {}
    ) {
        self.businessID = businessID
        self.onCreated = onCreated
        self.onCancel = onCancel
        // Started from a client or a job: fill from that client, not an invoice.
        if let client {
            _selectedClient = State(initialValue: client)
            _useInvoice = State(initialValue: false)
        }
        if let job {
            _selectedJobIDs = State(initialValue: [job.id])
            _primaryJobID = State(initialValue: job.id)
        }

        let scopedID = BusinessScoped.queryBusinessID(businessID)
        _invoices = Query(
            filter: #Predicate<Invoice> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
        )
        _clients = Query(
            filter: #Predicate<Client> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Client.name)]
        )
        _jobs = Query(
            filter: #Predicate<Job> { $0.businessID == scopedID },
            sort: [SortDescriptor(\Job.startDate, order: .reverse)]
        )
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
                                            // The name already says what it's for; the category
                                            // doubled it ("DJ Services Agreement (Basic) (DJ)").
                                            Text(t.name).tag(Optional(t))
                                        }
                                    }
                                    .labelsHidden()
                                    .pickerStyle(.menu)
                                }
                            }

                            // Only for the split sheet: it was shown to every
                            // business, music or not.
                            if selectedTemplate?.category == "Music / Entertainment" {
                                Button {
                                    showingMusicSplitSheetForm = true
                                } label: {
                                    Label("Fill In the Split Sheet Form", systemImage: "music.note.list")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }

                    card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Source")
                                .font(.headline)

                            Toggle("Fill from an invoice or estimate", isOn: $useInvoice)
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
                                                Text("\(ClientWorkItem.documentName(inv)) — \(inv.displayClientName)")
                                                    .tag(Optional(inv))
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }

                                    if let inv = selectedInvoice {
                                        Text("Client: \(inv.displayClientName)")
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
        .sbwNavigationBarBackdrop()
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
                .sbwNavigationBarBackdrop()
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
                .sbwNavigationBarBackdrop()
            }
        }
        .sheet(isPresented: $showingMusicSplitSheetForm) {
            NavigationStack {
                MusicSplitSheetFormView(
                    businessID: businessID,
                    linkedClient: resolvedClient,
                    linkedInvoice: useInvoice ? selectedInvoice : nil
                ) { contract in
                    showingMusicSplitSheetForm = false
                    onCreated(contract)
                    dismiss()
                }
            }
            .presentationDetents([.large])
        }
        .alert("Couldn’t Create Contract", isPresented: Binding(
            get: { createError != nil },
            set: { if !$0 { createError = nil } }
        ), actions: {
            Button("OK") { createError = nil }
        }, message: {
            Text(createError ?? "Unknown error.")
        })
        .onAppear {
            // Helpful defaults
            // The general agreement fits most work; alphabetical order put
            // the DJ agreement first.
            if selectedTemplate == nil {
                selectedTemplate = templates.first { $0.category == "General" } ?? templates.first
            }
            // No client or invoice is picked for you: a guessed default made
            // it easy to send a contract to the wrong person.
            applyDefaultJobsFromInvoiceIfNeeded()
        }
        
        .onChange(of: useInvoice) { _, newValue in
            if newValue {
                selectedClient = nil
                applyDefaultJobsFromInvoiceIfNeeded()
            } else {
                selectedInvoice = nil
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
            .frame(maxWidth: .infinity, alignment: .leading)
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
        guard let bizID = businessID else { return nil }
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
        guard let bizID = businessID else { return [] }
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

        guard let bizID = businessID else {
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

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
// Compared by what it shows; callbacks and bindings are ignored.
extension CreateContractStartView: Equatable {
    static func == (lhs: CreateContractStartView, rhs: CreateContractStartView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
