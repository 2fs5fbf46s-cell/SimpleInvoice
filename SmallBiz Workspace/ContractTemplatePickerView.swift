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
    @Query private var businessProfiles: [BusinessProfile]

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    // Drives navigation to newly created contract
    @State private var navigateToContract: Contract? = nil

    // Setup sheet
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

    /// The template as it will actually read, not as it is stored.
    ///
    /// This previewed `template.body` directly, so someone choosing a legal
    /// document was shown "Date: {{Today}}" and "DJ/Provider: {{Business.Name}}".
    /// Running it through the same engine the real contract uses resolves what
    /// is known now and strips the rest, which is exactly what the created
    /// contract looks like before a client is attached.
    private func previewBody(for template: ContractTemplate) -> String {
        let context = ContractContext(
            business: businessProfiles.first,
            client: nil,
            invoice: nil
        )
        let rendered = ContractTemplateEngine
            .render(template: template.body, context: context)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return rendered.isEmpty ? template.body : rendered
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
                                HStack(alignment: .top) {
                                    Text(template.name.isEmpty ? "Template" : template.name)
                                        .font(.headline)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 8)

                                    Text(normalizedCategory(template.category).uppercased())
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(SBWTheme.brand.opacity(0.16))
                                        .clipShape(Capsule())
                                        .foregroundStyle(.secondary)
                                        .fixedSize()
                                }

                                Text(previewBody(for: template))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(4)

                                Button {
                                    selectedTemplate = template
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
        .navigationBarTitleDisplayMode(.inline)
        .sbwNavigationBarBackdrop()
        .searchable(text: $searchText, prompt: "Search templates")
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                SBWFilterChips(options: categories, title: { $0 }, selection: $selectedCategory)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                Divider()
            }
            .background(.ultraThinMaterial)
        }
        .navigationDestination(item: $navigateToContract) { contract in
            ContractDetailView(contract: contract)
        }
        // Driven by the selection, not a separate flag. With `isPresented` the
        // sheet body could be built before `selectedTemplate` had propagated, so
        // the Template row fell back to the literal word "Template" instead of
        // naming the template the user had just chosen.
        .sheet(item: $selectedTemplate) { template in
            NavigationStack {
                ContractDraftSetupContainerView(
                    businessID: businessID,
                    templateName: template.name.isEmpty ? "Untitled template" : template.name
                ) { businessProfile, selectedClient, selectedInvoice in
                    createDraftFromSelectedTemplate(
                        businessProfile: businessProfile,
                        selectedClient: selectedClient,
                        selectedInvoice: selectedInvoice
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { selectedTemplate = nil }
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
            selectedTemplate = nil

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
                        ForEach(clients.filter { !$0.isArchived || $0.id == selectedClient?.id }) { c in
                            Text(c.name.isEmpty ? "Client" : c.name).tag(Client?.some(c))
                        }
                    }

                    Picker("Invoice", selection: $selectedInvoice) {
                        Text("None").tag(Invoice?.none)
                        ForEach(invoices) { inv in
                            Text(inv.invoiceNumber).tag(Invoice?.some(inv))
                        }
                    }

                    Text("Pick a client or invoice and their details — name, address, amounts — are filled into the contract for you.")
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
        .sbwNavigationBarBackdrop()
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

// MARK: - Smart Music Split Sheet Launcher

struct MusicSplitSheetSmartEntryCard: View {
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(MusicSplitSheetDraft.templateName)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Text(MusicSplitSheetDraft.templateCategory.uppercased())
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(SBWTheme.brand.opacity(0.16))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
                    .fixedSize()
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

// Pushed onto a NavigationStack and not comparable field-by-field, so it
// could re-render in a loop; see InvoiceDetailView's Equatable conformance.
extension ContractTemplatePickerView: Equatable {
    static func == (lhs: ContractTemplatePickerView, rhs: ContractTemplatePickerView) -> Bool {
        lhs.businessID == rhs.businessID
    }
}
