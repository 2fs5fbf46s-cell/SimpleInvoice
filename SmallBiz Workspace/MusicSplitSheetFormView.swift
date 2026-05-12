import SwiftUI
import SwiftData

struct MusicSplitSheetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let businessID: UUID?
    private let linkedJob: Job?
    private let linkedClient: Client?
    private let linkedInvoice: Invoice?
    let onCreated: (Contract) -> Void

    @Query private var profiles: [BusinessProfile]
    @Query(sort: \Client.name) private var clients: [Client]

    @State private var draft = MusicSplitSheetDraft()
    @State private var selectedClient: Client?
    @State private var showingClientPicker = false
    @State private var contributorEditor: MusicContributorEditorState?
    @State private var createError: String?

    init(
        businessID: UUID?,
        linkedJob: Job? = nil,
        linkedClient: Client? = nil,
        linkedInvoice: Invoice? = nil,
        onCreated: @escaping (Contract) -> Void
    ) {
        let resolvedBusinessID = businessID ?? linkedJob?.businessID ?? linkedInvoice?.businessID ?? linkedClient?.businessID
        self.businessID = resolvedBusinessID
        self.linkedJob = linkedJob
        self.linkedClient = linkedClient
        self.linkedInvoice = linkedInvoice
        self.onCreated = onCreated
        _selectedClient = State(initialValue: linkedClient ?? linkedInvoice?.client)

        if let resolvedBusinessID {
            _profiles = Query(
                filter: #Predicate<BusinessProfile> { profile in
                    profile.businessID == resolvedBusinessID
                },
                sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]
            )

            _clients = Query(
                filter: #Predicate<Client> { client in
                    client.businessID == resolvedBusinessID
                },
                sort: [SortDescriptor(\Client.name, order: .forward)]
            )
        } else {
            _profiles = Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)])
            _clients = Query(sort: \Client.name)
        }
    }

    private var businessProfile: BusinessProfile? {
        profiles.first
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            Form {
                clientSelectionSection
                songInformationSection
                contributorsSection
                publishingSplitsSection
                masterSplitsSection
                workForHireSection
                samplesSection
                administrationSection
                reviewSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Music Split Sheet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .sheet(item: $contributorEditor) { editor in
            NavigationStack {
                MusicSplitSheetContributorEditView(
                    contributor: editor.contributor,
                    onSave: { savedContributor in
                        saveContributor(savedContributor, existingID: editor.existingID)
                    },
                    onCancel: {
                        contributorEditor = nil
                    }
                )
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingClientPicker) {
            NavigationStack {
                MusicSplitSheetClientPickerView(
                    clients: clients,
                    selectedClient: $selectedClient
                )
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Couldn’t Generate Contract", isPresented: Binding(
            get: { createError != nil },
            set: { if !$0 { createError = nil } }
        )) {
            Button("OK", role: .cancel) { createError = nil }
        } message: {
            Text(createError ?? "")
        }
        .onAppear {
            preselectClientIfNeeded()
        }
        .onChange(of: clients.count) { _, _ in
            preselectClientIfNeeded()
        }
    }

    private var clientSelectionSection: some View {
        Section("Client / Primary Artist") {
            if let selectedClient {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedClient.name.isEmpty ? "Client" : selectedClient.name)
                        .font(.subheadline.weight(.semibold))

                    if !selectedClient.email.isEmpty {
                        Text(selectedClient.email)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if !selectedClient.phone.isEmpty {
                        Text(selectedClient.phone)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Label("Select a client before generating the split sheet.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Button(selectedClient == nil ? "Select Client" : "Change Client") {
                showingClientPicker = true
            }
        }
    }

    private var songInformationSection: some View {
        Section("Song Information") {
            TextField("Song title", text: $draft.songTitle)
            TextField("Artist / performing artist", text: $draft.artistName)
            TextField("Alternate title(s)", text: $draft.alternateTitles, axis: .vertical)
            TextField("Date created", text: $draft.dateCreated)
            TextField("Recording location / studio", text: $draft.recordingLocation)
            TextField("ISRC / release info", text: $draft.isrc)
        }
    }

    private var contributorsSection: some View {
        Section("Contributors") {
            if draft.contributors.isEmpty {
                Text("No contributors added.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(draft.contributors) { contributor in
                    Button {
                        contributorEditor = MusicContributorEditorState(
                            existingID: contributor.id,
                            contributor: contributor
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contributor.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)

                            Text(contributor.role)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            deleteContributor(contributor)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteContributors)
            }

            Button {
                contributorEditor = MusicContributorEditorState(
                    existingID: nil,
                    contributor: MusicSplitSheetContributor()
                )
            } label: {
                Label("Add Contributor", systemImage: "plus.circle")
            }
        }
    }

    private var publishingSplitsSection: some View {
        Section("Publishing Splits") {
            MusicSplitSheetTotalRow(label: "Writer Share Total", value: draft.writerShareTotal)
            MusicSplitSheetTotalRow(label: "Publishing Share Total", value: draft.publishingShareTotal)

            ForEach($draft.contributors) { $contributor in
                VStack(alignment: .leading, spacing: 10) {
                    Text(contributor.displayName)
                        .font(.subheadline.weight(.semibold))

                    MusicSplitSheetPercentField(
                        title: "Writer Share",
                        value: $contributor.writerSharePercent
                    )

                    MusicSplitSheetPercentField(
                        title: "Publishing Share",
                        value: $contributor.publishingSharePercent
                    )
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var masterSplitsSection: some View {
        Section("Master Splits") {
            MusicSplitSheetTotalRow(label: "Master Ownership Total", value: draft.masterOwnershipTotal)

            ForEach($draft.contributors) { $contributor in
                VStack(alignment: .leading, spacing: 10) {
                    Text(contributor.displayName)
                        .font(.subheadline.weight(.semibold))

                    MusicSplitSheetPercentField(
                        title: "Master Ownership",
                        value: $contributor.masterOwnershipPercent
                    )

                    MusicSplitSheetPercentField(
                        title: "Producer Points",
                        value: $contributor.producerPointsPercent
                    )

                    TextField("Mechanical / streaming payout notes", text: $contributor.royaltyNotes, axis: .vertical)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var workForHireSection: some View {
        Section("Work-for-Hire / Buyout") {
            if draft.contributors.isEmpty {
                Text("Add contributors first.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($draft.contributors) { $contributor in
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(contributor.displayName, isOn: $contributor.isWorkForHire)
                        TextField("Flat fee amount", text: $contributor.flatFeeAmount)
                            .keyboardType(.decimalPad)
                        TextField("Flat fee paid date", text: $contributor.flatFeePaidDate)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var samplesSection: some View {
        Section("Samples / Interpolations") {
            Toggle("Uses samples", isOn: $draft.usesSamples)

            if draft.usesSamples {
                TextField("Sample source", text: $draft.sampleSource, axis: .vertical)
                TextField("Clearance responsibility", text: $draft.clearanceResponsibility)
            }

            Picker("Clearance status", selection: $draft.clearanceStatus) {
                ForEach(MusicSplitSheetDraft.clearanceStatuses, id: \.self) { status in
                    Text(status).tag(status)
                }
            }
        }
    }

    private var administrationSection: some View {
        Section("Distribution / Administration") {
            TextField("Distributor", text: $draft.distributor)
            TextField("Release date", text: $draft.releaseDate)
            TextField("PRO / publishing admin responsible party", text: $draft.proRegistrationResponsibleParty)
            TextField("Distributor upload responsible party", text: $draft.distributorUploadResponsibleParty)
            TextField("Payment reporting schedule", text: $draft.paymentReportingSchedule)
        }
    }

    private var reviewSection: some View {
        Section("Review & Generate") {
            MusicSplitSheetTotalRow(label: "Writer", value: draft.writerShareTotal)
            MusicSplitSheetTotalRow(label: "Publishing", value: draft.publishingShareTotal)
            MusicSplitSheetTotalRow(label: "Master", value: draft.masterOwnershipTotal)

            let warnings = draft.validationWarnings(selectedClient: selectedClient)
            if warnings.isEmpty {
                Label("Ready to generate", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.footnote)
                }
            }

            Button {
                generateContract()
            } label: {
                Label("Generate Contract", systemImage: "doc.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!draft.canGenerateContract(selectedClient: selectedClient))
        }
    }

    @MainActor
    private func generateContract() {
        guard draft.canGenerateContract(selectedClient: selectedClient) else { return }

        guard let businessID else {
            createError = "No business selected."
            return
        }

        guard let selectedClient else {
            createError = "Select a client before generating the split sheet."
            return
        }

        let contract = draft.makeContract(
            businessID: businessID,
            business: businessProfile,
            selectedClient: selectedClient,
            linkedJob: linkedJob,
            linkedInvoice: linkedInvoice
        )

        modelContext.insert(contract)

        do {
            try modelContext.save()
            dismiss()
            onCreated(contract)
        } catch {
            createError = error.localizedDescription
        }
    }

    private func saveContributor(_ contributor: MusicSplitSheetContributor, existingID: UUID?) {
        if let existingID,
           let index = draft.contributors.firstIndex(where: { $0.id == existingID }) {
            draft.contributors[index] = contributor
        } else {
            draft.contributors.append(contributor)
        }

        contributorEditor = nil
    }

    private func deleteContributors(at offsets: IndexSet) {
        draft.contributors.remove(atOffsets: offsets)
    }

    private func deleteContributor(_ contributor: MusicSplitSheetContributor) {
        draft.contributors.removeAll { $0.id == contributor.id }
    }

    private func preselectClientIfNeeded() {
        guard selectedClient == nil else { return }

        if let linkedClient {
            selectedClient = linkedClient
            return
        }

        if let invoiceClient = linkedInvoice?.client {
            selectedClient = invoiceClient
            return
        }

        if let jobClientID = linkedJob?.clientID,
           let jobClient = clients.first(where: { $0.id == jobClientID }) {
            selectedClient = jobClient
        }
    }
}

private struct MusicContributorEditorState: Identifiable {
    let id = UUID()
    let existingID: UUID?
    var contributor: MusicSplitSheetContributor
}

private struct MusicSplitSheetTotalRow: View {
    let label: String
    let value: Double

    private var isValid: Bool {
        abs(value - 100) <= 0.01
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(percent(value))
                .fontWeight(.semibold)
                .foregroundStyle(isValid ? .green : .orange)
        }
    }
}
