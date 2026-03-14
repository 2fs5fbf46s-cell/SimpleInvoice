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
        let set = Set(templates.map { normalizedCategory($0.category) })
        return ["All"] + set.sorted()
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
                if filteredTemplates.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Templates" : "No Results",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(searchText.isEmpty
                                          ? "No templates are available yet."
                                          : "Try a different search or category.")
                    )
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
