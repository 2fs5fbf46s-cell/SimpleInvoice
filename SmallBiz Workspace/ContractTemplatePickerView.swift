//
//  ContractTemplatePickerView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractTemplatePickerView: View {
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?

    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    // Drives navigation to newly created contract
    @State private var navigateToContract: Contract? = nil

    // Setup sheet
    @State private var showingSetup = false
    @State private var showingMusicSplitSheetForm = false
    @State private var selectedTemplate: ContractTemplate? = nil

    @State private var createError: String? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID
    }

    private func normalizedCategory(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "General" : t
    }

    private var categories: [String] {
        var set = Set(templates.map { normalizedCategory($0.category) })
        set.insert(MusicSplitSheetDraft.templateCategory)
        return ["All"] + set.sorted()
    }

    private var shouldShowSmartMusicSplitSheet: Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matchesCategory = selectedCategory == "All" || selectedCategory == MusicSplitSheetDraft.templateCategory
        guard matchesCategory else { return false }

        if q.isEmpty { return true }

        return MusicSplitSheetDraft.smartFormSearchText.contains(q)
    }

    private var filteredTemplates: [ContractTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return templates.filter { t in
            let cat = normalizedCategory(t.category)
            let matchesCategory = (selectedCategory == "All") || (cat == selectedCategory)
            if !matchesCategory { return false }

            if q.isEmpty { return true }
            return t.name.lowercased().contains(q) || t.body.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash
            SBWTheme.headerWash()

            List {
                if shouldShowSmartMusicSplitSheet {
                    Section {
                        MusicSplitSheetSmartEntryCard {
                            showingMusicSplitSheetForm = true
                        }
                    }
                    .modifier(SBWCardRowStyle())
                }

                if filteredTemplates.isEmpty {
                    if shouldShowSmartMusicSplitSheet {
                        EmptyView()
                    } else {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Templates" : "No Results",
                            systemImage: "doc.text.magnifyingglass",
                            description: Text(searchText.isEmpty
                                              ? "No templates are available yet."
                                              : "Try a different search or category.")
                        )
                    }
                } else {
                    ForEach(filteredTemplates) { template in
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(template.name.isEmpty ? "Template" : template.name)
                                        .font(.headline)

                                    Spacer(minLength: 8)

                                    Text(normalizedCategory(template.category).uppercased())
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(SBWTheme.brandBlue.opacity(0.16))
                                        .clipShape(Capsule())
                                        .foregroundStyle(.secondary)
                                }

                                Text(template.body)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)

                                Button {
                                    selectedTemplate = template
                                    showingSetup = true
                                } label: {
                                    Label("Use This Template", systemImage: "wand.and.stars")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(.vertical, 6)
                        }
                        .modifier(SBWCardRowStyle())
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Templates")
        .searchable(text: $searchText, prompt: "Search templates")
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(categories, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 4)

                Divider()
            }
            .background(.ultraThinMaterial)
        }
        .navigationDestination(item: $navigateToContract) { contract in
            ContractDetailView(contract: contract)
        }
        .sheet(isPresented: $showingSetup) {
            NavigationStack {
                ContractDraftSetupContainerView(
                    businessID: businessID,
                    templateName: selectedTemplate?.name ?? "Template"
                ) { businessProfile, selectedClient, selectedInvoice in
                    createDraftFromSelectedTemplate(
                        businessProfile: businessProfile,
                        selectedClient: selectedClient,
                        selectedInvoice: selectedInvoice
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingSetup = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
        .sheet(isPresented: $showingMusicSplitSheetForm) {
            NavigationStack {
                MusicSplitSheetFormView(businessID: businessID) { contract in
                    showingMusicSplitSheetForm = false
                    DispatchQueue.main.async {
                        navigateToContract = contract
                    }
                }
            }
            .presentationDetents([.large])
        }
        .alert("Couldn’t Create Contract", isPresented: Binding(
            get: { createError != nil },
            set: { if !$0 { createError = nil } }
        )) {
            Button("OK", role: .cancel) { createError = nil }
        } message: {
            Text(createError ?? "")
        }
    }

    // MARK: - Create draft + autofill + push

    private func createDraftFromSelectedTemplate(
        businessProfile: BusinessProfile?,
        selectedClient: Client?,
        selectedInvoice: Invoice?
    ) {
        guard let template = selectedTemplate else { return }
        guard let businessID else {
            createError = "No business selected."
            return
        }

        do {
            let draft = try ContractCreation.create(
                context: modelContext,
                template: template,
                businessID: businessID,
                business: businessProfile,
                client: selectedClient,
                invoice: selectedInvoice
            )
            showingSetup = false

            // Push into detail view after the sheet dismisses
            DispatchQueue.main.async {
                navigateToContract = draft
            }
        } catch {
            createError = error.localizedDescription
        }
    }
}

// MARK: - Setup screen (select Client + Invoice)

private struct ContractDraftSetupContainerView: View {
    private let businessID: UUID?
    let templateName: String
    let onCreate: (BusinessProfile?, Client?, Invoice?) -> Void

    @Query private var profiles: [BusinessProfile]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]

    @State private var selectedClient: Client? = nil
    @State private var selectedInvoice: Invoice? = nil

    init(
        businessID: UUID?,
        templateName: String,
        onCreate: @escaping (BusinessProfile?, Client?, Invoice?) -> Void
    ) {
        self.businessID = businessID
        self.templateName = templateName
        self.onCreate = onCreate

        if let businessID {
            _profiles = Query(
                filter: #Predicate<BusinessProfile> { profile in
                    profile.businessID == businessID
                },
                sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]
            )

            _clients = Query(
                filter: #Predicate<Client> { client in
                    client.businessID == businessID
                },
                sort: [SortDescriptor(\Client.name, order: .forward)]
            )

            _invoices = Query(
                filter: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID
                },
                sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
        } else {
            _profiles = Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)])
            _clients = Query(sort: \Client.name)
            _invoices = Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
        }
    }

    private var businessProfile: BusinessProfile? {
        profiles.first
    }

    var body: some View {
        ContractDraftSetupView(
            templateName: templateName,
            clients: clients,
            invoices: invoices,
            selectedClient: $selectedClient,
            selectedInvoice: $selectedInvoice
        ) {
            onCreate(businessProfile, selectedClient, selectedInvoice)
        }
    }
}

private struct ContractDraftSetupView: View {
    let templateName: String
    let clients: [Client]
    let invoices: [Invoice]

    @Binding var selectedClient: Client?
    @Binding var selectedInvoice: Invoice?

    let onCreate: () -> Void

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            Form {
                Section("Template") {
                    Text(templateName)
                        .font(.headline)
                }

                Section("Autofill Sources (Optional)") {
                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(Client?.none)
                        ForEach(clients) { c in
                            Text(c.name.isEmpty ? "Client" : c.name).tag(Client?.some(c))
                        }
                    }

                    Picker("Invoice", selection: $selectedInvoice) {
                        Text("None").tag(Invoice?.none)
                        ForEach(invoices) { inv in
                            Text(inv.invoiceNumber).tag(Invoice?.some(inv))
                        }
                    }

                    Text("Tip: If you select a Client or Invoice, tokens like {{Client.Name}} or {{Invoice.Total}} will be filled automatically.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        onCreate()
                    } label: {
                        Label("Create Draft Contract", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Create Draft")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SBWCardRowStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
    }
}

// MARK: - Smart Music Split Sheet

struct MusicSplitSheetContributor: Identifiable, Equatable {
    var id: UUID = UUID()
    var legalName: String = ""
    var stageNameOrCompany: String = ""
    var role: String = MusicSplitSheetContributor.roles.first ?? "Writer"
    var email: String = ""
    var phone: String = ""
    var proAffiliation: String = ""
    var ipiCaeNumber: String = ""
    var publisherName: String = ""
    var writerSharePercent: Double = 0
    var publishingSharePercent: Double = 0
    var masterOwnershipPercent: Double = 0
    var producerPointsPercent: Double = 0
    var isWorkForHire: Bool = false
    var flatFeeAmount: String = ""
    var flatFeePaidDate: String = ""
    var royaltyNotes: String = ""

    static let roles = [
        "Writer",
        "Producer",
        "Artist",
        "Featured Artist",
        "Engineer",
        "Mixer",
        "Mastering Engineer",
        "Publisher",
        "Other"
    ]

    var displayName: String {
        let trimmedName = legalName.trimmedForMusicSplitSheet
        if !trimmedName.isEmpty { return trimmedName }

        let stage = stageNameOrCompany.trimmedForMusicSplitSheet
        if !stage.isEmpty { return stage }

        return "Unnamed Contributor"
    }
}

struct MusicSplitSheetDraft: Equatable {
    static let templateName = "Music Split Sheet (Smart Form)"
    static let templateCategory = "Music / Entertainment"
    static let smartFormSearchText = """
    music split sheet smart form music entertainment define songwriting publishing master recording producer contributor splits before release royalty percentage validation
    """

    var songTitle: String = ""
    var artistName: String = ""
    var alternateTitles: String = ""
    var dateCreated: String = ""
    var recordingLocation: String = ""
    var isrc: String = ""
    var releaseDate: String = ""
    var distributor: String = ""

    var contributors: [MusicSplitSheetContributor] = []

    var usesSamples: Bool = false
    var sampleSource: String = ""
    var clearanceResponsibility: String = ""
    var clearanceStatus: String = "Not Required"

    var proRegistrationResponsibleParty: String = ""
    var distributorUploadResponsibleParty: String = ""
    var paymentReportingSchedule: String = ""

    static let clearanceStatuses = [
        "Not Required",
        "Pending",
        "Cleared",
        "Denied",
        "Unknown"
    ]

    var writerShareTotal: Double {
        contributors.reduce(0) { $0 + $1.writerSharePercent }
    }

    var publishingShareTotal: Double {
        contributors.reduce(0) { $0 + $1.publishingSharePercent }
    }

    var masterOwnershipTotal: Double {
        contributors.reduce(0) { $0 + $1.masterOwnershipPercent }
    }

    var validationWarnings: [String] {
        var warnings: [String] = []

        if contributors.isEmpty {
            warnings.append("Add at least one contributor.")
        }

        appendTotalWarning(
            total: writerShareTotal,
            label: "Writer share total",
            to: &warnings
        )
        appendTotalWarning(
            total: publishingShareTotal,
            label: "Publishing share total",
            to: &warnings
        )
        appendTotalWarning(
            total: masterOwnershipTotal,
            label: "Master ownership total",
            to: &warnings
        )

        for (index, contributor) in contributors.enumerated() {
            let contributorLabel = contributor.displayName == "Unnamed Contributor"
                ? "Contributor \(index + 1)"
                : contributor.displayName

            if contributor.legalName.trimmedForMusicSplitSheet.isEmpty {
                warnings.append("\(contributorLabel) is missing a legal name.")
            }

            appendPercentWarnings(
                value: contributor.writerSharePercent,
                field: "Writer share",
                contributor: contributorLabel,
                to: &warnings
            )
            appendPercentWarnings(
                value: contributor.publishingSharePercent,
                field: "Publishing share",
                contributor: contributorLabel,
                to: &warnings
            )
            appendPercentWarnings(
                value: contributor.masterOwnershipPercent,
                field: "Master ownership",
                contributor: contributorLabel,
                to: &warnings
            )
            appendPercentWarnings(
                value: contributor.producerPointsPercent,
                field: "Producer points",
                contributor: contributorLabel,
                to: &warnings
            )
        }

        return warnings
    }

    var canGenerateContract: Bool {
        validationWarnings.isEmpty
    }

    func contractBody(preparedBy business: BusinessProfile? = nil, generatedAt: Date = .now) -> String {
        let preparedBy = business?.name.trimmedForMusicSplitSheet ?? ""
        let preparedByLine = preparedBy.isEmpty ? "" : "\nPrepared By: \(preparedBy)"
        let contributorDetails = contributors.enumerated().map { index, contributor in
            """
            Contributor \(index + 1)
            Legal Name: \(value(contributor.legalName))
            Stage Name / Company: \(value(contributor.stageNameOrCompany))
            Role: \(value(contributor.role))
            Email: \(value(contributor.email))
            Phone: \(value(contributor.phone))
            PRO Affiliation: \(value(contributor.proAffiliation))
            IPI / CAE Number: \(value(contributor.ipiCaeNumber))
            Publisher Name: \(value(contributor.publisherName))
            """
        }.joined(separator: "\n\n")

        let publishingRows = contributors.map {
            "\($0.displayName) | \(value($0.role)) | \(percent($0.writerSharePercent)) | \(percent($0.publishingSharePercent))"
        }.joined(separator: "\n")

        let masterRows = contributors.map {
            "\($0.displayName) | \(percent($0.masterOwnershipPercent)) | \(percent($0.producerPointsPercent)) | \(value($0.royaltyNotes))"
        }.joined(separator: "\n")

        let workForHireRows = contributors.map { contributor in
            let status = contributor.isWorkForHire ? "Yes" : "No"
            let flatFee = value(contributor.flatFeeAmount)
            let paidDate = value(contributor.flatFeePaidDate)
            let notes = value(contributor.royaltyNotes)
            return "\(contributor.displayName): Work-for-hire: \(status). Flat fee: \(flatFee). Paid date: \(paidDate). Royalty notes: \(notes)."
        }.joined(separator: "\n")

        let sampleText: String
        if usesSamples {
            sampleText = """
            Samples / Interpolations Used: Yes
            Sample Source: \(value(sampleSource))
            Clearance Responsibility: \(value(clearanceResponsibility))
            Clearance Status: \(value(clearanceStatus))
            """
        } else {
            sampleText = """
            Samples / Interpolations Used: No
            Sample Source: Not applicable
            Clearance Responsibility: Not applicable
            Clearance Status: \(value(clearanceStatus))
            """
        }

        let signatureBlocks = contributors.map { contributor in
            """
            Contributor Name: \(contributor.displayName)
            Signature: ______________________________
            Date: __________________
            """
        }.joined(separator: "\n\n")

        return """
        MUSIC SPLIT SHEET

        Date Prepared: \(Self.dateString(generatedAt))\(preparedByLine)

        1. SONG INFORMATION
        Song Title: \(value(songTitle))
        Artist / Performing Artist: \(value(artistName))
        Alternate Title(s): \(value(alternateTitles))
        Date Created: \(value(dateCreated))
        Recording Location / Studio: \(value(recordingLocation))
        ISRC / Release Info: \(value(isrc))
        Release Date: \(value(releaseDate))
        Distributor: \(value(distributor))

        2. CONTRIBUTORS
        \(contributorDetails.isEmpty ? "No contributors listed." : contributorDetails)

        3. SONGWRITING / PUBLISHING SPLITS
        Contributor | Role | Writer Share | Publishing Share
        \(publishingRows.isEmpty ? "No publishing splits listed." : publishingRows)

        Writer Share Total: \(percent(writerShareTotal))
        Publishing Share Total: \(percent(publishingShareTotal))
        Total songwriting and publishing splits must equal 100%.

        4. MASTER RECORDING SPLITS
        Contributor | Master Ownership | Producer Royalty / Points | Mechanical / Streaming Payout Notes
        \(masterRows.isEmpty ? "No master recording splits listed." : masterRows)

        Master Ownership Total: \(percent(masterOwnershipTotal))
        Total master recording splits must equal 100%.

        5. WORK-FOR-HIRE / BUYOUT TERMS
        \(workForHireRows.isEmpty ? "No work-for-hire or buyout terms listed." : workForHireRows)

        A listed flat fee only replaces future royalties if that treatment is stated in the royalty notes or otherwise agreed to in writing by the affected parties.

        6. SAMPLES / INTERPOLATIONS
        \(sampleText)

        7. DISTRIBUTION / ADMINISTRATION
        Distributor: \(value(distributor))
        Release Date: \(value(releaseDate))
        PRO / Publishing Admin Registration Responsibility: \(value(proRegistrationResponsibleParty))
        Distributor Upload Responsibility: \(value(distributorUploadResponsibleParty))
        Payment Reporting Schedule: \(value(paymentReportingSchedule))

        8. AGREEMENT TERMS
        All parties agree that the percentages listed in this split sheet represent their agreed ownership and/or royalty participation for the song and master recording identified above. Any future changes must be agreed to in writing by all affected parties.

        Each party confirms that the information they provide is accurate and that they have authority to agree to the splits and terms listed in this document.

        9. SIGNATURES
        \(signatureBlocks.isEmpty ? "Contributor Name: ______________________________\nSignature: ______________________________\nDate: __________________" : signatureBlocks)
        """
    }

    private func appendTotalWarning(total: Double, label: String, to warnings: inout [String]) {
        guard abs(total - 100) > 0.01 else { return }
        warnings.append("\(label) must equal 100%. Current total: \(percent(total)).")
    }

    private func appendPercentWarnings(
        value: Double,
        field: String,
        contributor: String,
        to warnings: inout [String]
    ) {
        if value < 0 {
            warnings.append("\(contributor) \(field.lowercased()) cannot be negative.")
        }

        if value > 100 {
            warnings.append("\(contributor) \(field.lowercased()) should not exceed 100%.")
        }
    }

    private func value(_ text: String) -> String {
        let trimmed = text.trimmedForMusicSplitSheet
        return trimmed.isEmpty ? "[Not specified]" : trimmed
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

private func percent(_ value: Double) -> String {
    if value.rounded() == value {
        return "\(Int(value))%"
    }

    return String(format: "%.2f%%", value)
}

struct MusicSplitSheetSmartEntryCard: View {
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(MusicSplitSheetDraft.templateName)
                    .font(.headline)

                Spacer(minLength: 8)

                Text(MusicSplitSheetDraft.templateCategory.uppercased())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SBWTheme.brandBlue.opacity(0.16))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }

            Text("Guided split sheet with contributor rows, ownership totals, and percentage validation.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                onSelect()
            } label: {
                Label("Use Smart Form", systemImage: "music.note.list")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 6)
    }
}

struct MusicSplitSheetFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let businessID: UUID?
    private let linkedJob: Job?
    private let linkedClient: Client?
    private let linkedInvoice: Invoice?
    let onCreated: (Contract) -> Void

    @Query private var profiles: [BusinessProfile]

    @State private var draft = MusicSplitSheetDraft()
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

        if let resolvedBusinessID {
            _profiles = Query(
                filter: #Predicate<BusinessProfile> { profile in
                    profile.businessID == resolvedBusinessID
                },
                sort: [SortDescriptor(\BusinessProfile.name, order: .forward)]
            )
        } else {
            _profiles = Query(sort: [SortDescriptor(\BusinessProfile.name, order: .forward)])
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
        .alert("Couldn’t Generate Contract", isPresented: Binding(
            get: { createError != nil },
            set: { if !$0 { createError = nil } }
        )) {
            Button("OK", role: .cancel) { createError = nil }
        } message: {
            Text(createError ?? "")
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

            if draft.validationWarnings.isEmpty {
                Label("Ready to generate", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                ForEach(draft.validationWarnings, id: \.self) { warning in
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
            .disabled(!draft.canGenerateContract)
        }
    }

    @MainActor
    private func generateContract() {
        guard draft.canGenerateContract else { return }

        guard let businessID else {
            createError = "No business selected."
            return
        }

        let resolvedJob = linkedJob ?? linkedInvoice?.job
        let contract = Contract(
            businessID: businessID,
            title: titleForContract(),
            createdAt: .now,
            updatedAt: .now,
            templateName: MusicSplitSheetDraft.templateName,
            templateCategory: MusicSplitSheetDraft.templateCategory,
            renderedBody: draft.contractBody(preparedBy: businessProfile),
            statusRaw: ContractStatus.draft.rawValue,
            client: linkedClient ?? linkedInvoice?.client ?? fetchLinkedClient(),
            invoice: linkedInvoice,
            linkedJobIDsCSV: resolvedJob?.id.uuidString ?? ""
        )

        contract.job = resolvedJob

        modelContext.insert(contract)

        do {
            try modelContext.save()
            dismiss()
            onCreated(contract)
        } catch {
            createError = error.localizedDescription
        }
    }

    private func titleForContract() -> String {
        let title = draft.songTitle.trimmedForMusicSplitSheet
        return title.isEmpty ? "Music Split Sheet" : "Music Split Sheet - \(title)"
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

    private func fetchLinkedClient() -> Client? {
        guard let clientID = linkedJob?.clientID else { return nil }
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate<Client> { client in
            client.id == clientID
        })
        return try? modelContext.fetch(descriptor).first
    }
}

private struct MusicContributorEditorState: Identifiable {
    let id = UUID()
    let existingID: UUID?
    var contributor: MusicSplitSheetContributor
}

private struct MusicSplitSheetContributorEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var contributor: MusicSplitSheetContributor
    let onSave: (MusicSplitSheetContributor) -> Void
    let onCancel: () -> Void

    init(
        contributor: MusicSplitSheetContributor,
        onSave: @escaping (MusicSplitSheetContributor) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _contributor = State(initialValue: contributor)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            Form {
                Section("Identity") {
                    TextField("Legal name", text: $contributor.legalName)
                    TextField("Stage name / company", text: $contributor.stageNameOrCompany)

                    Picker("Role", selection: $contributor.role) {
                        ForEach(MusicSplitSheetContributor.roles, id: \.self) { role in
                            Text(role).tag(role)
                        }
                    }
                }

                Section("Contact") {
                    TextField("Email", text: $contributor.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Phone", text: $contributor.phone)
                        .keyboardType(.phonePad)
                }

                Section("Publishing") {
                    TextField("PRO affiliation", text: $contributor.proAffiliation)
                    TextField("IPI / CAE number", text: $contributor.ipiCaeNumber)
                    TextField("Publisher name", text: $contributor.publisherName)
                    MusicSplitSheetPercentField(title: "Writer Share", value: $contributor.writerSharePercent)
                    MusicSplitSheetPercentField(title: "Publishing Share", value: $contributor.publishingSharePercent)
                }

                Section("Master") {
                    MusicSplitSheetPercentField(title: "Master Ownership", value: $contributor.masterOwnershipPercent)
                    MusicSplitSheetPercentField(title: "Producer Points", value: $contributor.producerPointsPercent)
                    TextField("Royalty notes", text: $contributor.royaltyNotes, axis: .vertical)
                }

                Section("Work-for-Hire / Buyout") {
                    Toggle("Work-for-hire", isOn: $contributor.isWorkForHire)
                    TextField("Flat fee amount", text: $contributor.flatFeeAmount)
                        .keyboardType(.decimalPad)
                    TextField("Flat fee paid date", text: $contributor.flatFeePaidDate)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Contributor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(contributor)
                    dismiss()
                }
            }
        }
    }
}

private struct MusicSplitSheetPercentField: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", value: $value, format: .number)
                .multilineTextAlignment(.trailing)
                .keyboardType(.decimalPad)
                .frame(maxWidth: 96)
            Text("%")
                .foregroundStyle(.secondary)
        }
    }
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

private extension String {
    var trimmedForMusicSplitSheet: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
