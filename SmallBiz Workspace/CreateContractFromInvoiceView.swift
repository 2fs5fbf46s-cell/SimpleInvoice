import SwiftUI
import SwiftData

struct CreateContractFromInvoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Bindable var invoice: Invoice

    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]
    @Query(sort: [SortDescriptor(\Job.startDate, order: .reverse)]) private var jobs: [Job]
    @Query private var profiles: [BusinessProfile]

    @State private var selectedTemplate: ContractTemplate?
    @State private var previewText: String = ""
    @State private var showPreview = false
    @State private var errorText: String?
    @State private var selectedJobIDs: [UUID] = []
    @State private var primaryJobID: UUID? = nil
    @State private var showJobsPicker = false

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
                                    description: Text("Templates should seed on launch.")
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
                            Text("Invoice")
                                .font(.headline)

                            Text("Invoice \(invoice.invoiceNumber)")
                            Text(invoice.client?.name ?? "No Client")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
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
                                Label("Preview", systemImage: "doc.richtext")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(selectedTemplate == nil)

                            Button {
                                saveDraft()
                            } label: {
                                Label("Save Draft", systemImage: "tray.and.arrow.down")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedTemplate == nil)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .navigationTitle("Create Contract")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
        .sheet(isPresented: $showPreview) {
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
                        Button("Close") { showPreview = false }
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
        .alert("Error", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "Unknown error.")
        }
        .onAppear {
            if selectedTemplate == nil { selectedTemplate = templates.first }
            if selectedJobIDs.isEmpty, let invoiceJobID = invoice.job?.id {
                selectedJobIDs = [invoiceJobID]
                primaryJobID = invoiceJobID
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

    // If you want this scoped later, we can fetch by businessID.
    private var business: BusinessProfile? {
        InvoicePDFService.resolvedBusinessProfile(for: invoice, profiles: profiles)
    }

    private var scopedJobs: [Job] {
        jobs.filter { $0.businessID == invoice.businessID }
    }

    private var selectedJobs: [Job] {
        let ids = Set(selectedJobIDs)
        return scopedJobs.filter { ids.contains($0.id) }.sorted { $0.startDate > $1.startDate }
    }

    private func generatePreview() {
        guard let template = selectedTemplate else { return }
        let ctx = ContractContext(business: business, client: invoice.client, invoice: invoice)
        previewText = ContractTemplateEngine.render(template: template.body, context: ctx)
        showPreview = true
    }

    private func saveDraft() {
        guard let template = selectedTemplate else { return }

        guard let bizID = activeBiz.activeBusinessID else {
            errorText = "No active business selected."
            return
        }

        do {
            let contract = try ContractCreation.create(
                context: modelContext,
                template: template,
                businessID: bizID,
                business: business,
                client: invoice.client,
                invoice: invoice
            )

            let primary = scopedJobs.first(where: { $0.id == primaryJobID })
            contract.job = primary ?? invoice.job

            var linked = Set(selectedJobIDs)
            if let primaryID = contract.job?.id {
                linked.insert(primaryID)
            }
            contract.linkedJobIDsCSV = linked.map(\.uuidString).joined(separator: ",")
            try? modelContext.save()

            dismiss()
        } catch {
            errorText = "Failed to create contract: \(error.localizedDescription)"
        }
    }
}
