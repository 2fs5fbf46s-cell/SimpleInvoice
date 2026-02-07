//
//  ContractTemplatePickerView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractTemplatePickerView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]
    @Query private var profiles: [BusinessProfile]
    @Query(sort: \Client.name) private var clients: [Client]
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    // Drives navigation to newly created contract
    @State private var navigateToContract: Contract? = nil

    // Setup sheet
    @State private var showingSetup = false
    @State private var selectedTemplate: ContractTemplate? = nil

    // Draft setup selections
    @State private var selectedClient: Client? = nil
    @State private var selectedInvoice: Invoice? = nil

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

    private var businessProfile: BusinessProfile? {
        profiles.first
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
                                    // Open setup (select client/invoice)
                                    selectedTemplate = template
                                    selectedClient = nil
                                    selectedInvoice = nil
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
                ContractDraftSetupView(
                    templateName: selectedTemplate?.name ?? "Template",
                    clients: clients,
                    invoices: invoices,
                    selectedClient: $selectedClient,
                    selectedInvoice: $selectedInvoice
                ) {
                    createDraftFromSelectedTemplate()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingSetup = false }
                    }
                }
            }
            .presentationDetents([.large])
        }
    }

    // MARK: - Create draft + autofill + push

    private func createDraftFromSelectedTemplate() {
        guard let template = selectedTemplate else { return }

        // Optional: if invoice chosen but different client, keep both (you can enforce later).
        let rendered = ContractTokenRenderer.render(
            templateBody: template.body,
            business: businessProfile,
            client: selectedClient,
            invoice: selectedInvoice
        )

        let draft = Contract(
            title: template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contract" : template.name,
            createdAt: .now,
            updatedAt: .now,
            templateName: template.name,
            templateCategory: template.category,
            renderedBody: rendered,
            statusRaw: ContractStatus.draft.rawValue,
            client: selectedClient,
            invoice: selectedInvoice
        )

        modelContext.insert(draft)

        do {
            try modelContext.save()
            showingSetup = false

            // Push into detail view after the sheet dismisses
            DispatchQueue.main.async {
                navigateToContract = draft
            }
        } catch {
            print("Failed to create draft contract: \(error)")
        }
    }
}

// MARK: - Setup screen (select Client + Invoice)

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
