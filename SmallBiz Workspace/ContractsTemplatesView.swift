//
//  ContractTemplatesView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct ContractTemplatesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]

    @State private var navigateToTemplate: ContractTemplate?
    @State private var selectedCategory: String = "All"
    @State private var searchText: String = ""

    @State private var showingUseTemplates = false
    @State private var saveError: String? = nil

    private func normalizedCategory(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "General" : t
    }

    private var categories: [String] {
        let set = Set(templates.map { normalizedCategory($0.category) })
        return ["All"] + set.sorted()
    }

    private var filteredTemplates: [ContractTemplate] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return templates.filter { t in
            let cat = normalizedCategory(t.category)
            let matchesCategory = (selectedCategory == "All") || (cat == selectedCategory)

            if q.isEmpty { return matchesCategory }

            let matchesSearch =
                t.name.localizedCaseInsensitiveContains(q) ||
                t.category.localizedCaseInsensitiveContains(q) ||
                t.body.localizedCaseInsensitiveContains(q)

            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "doc.badge.gearshape",
                        description: Text("Tap + to create your first template.")
                    )
                } else {
                    Section {
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(categories, id: \.self) { c in
                                Text(c).tag(c)
                            }
                        }
                    }

                    Section {
                        if filteredTemplates.isEmpty {
                            ContentUnavailableView(
                                "No Matches",
                                systemImage: "magnifyingglass",
                                description: Text("Try a different category or search term.")
                            )
                        } else {
                            ForEach(filteredTemplates) { template in
                                Button {
                                    navigateToTemplate = template
                                } label: {
                                    HStack(spacing: 12) {
                                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                                            .fill(SBWTheme.brandBlue.opacity(0.8))
                                            .frame(width: 6)

                                        VStack(alignment: .leading, spacing: 6) {
                                            HStack(alignment: .firstTextBaseline) {
                                                Text(template.name.isEmpty ? "Template" : template.name)
                                                    .font(.headline)
                                                    .foregroundStyle(.primary)

                                                Spacer(minLength: 8)

                                                Text(normalizedCategory(template.category).uppercased())
                                                    .font(.caption.weight(.semibold))
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(SBWTheme.brandBlue.opacity(0.16))
                                                    .clipShape(Capsule())
                                                    .foregroundStyle(.secondary)
                                            }

                                            Text(template.isBuiltIn ? "Built-in template" : "Custom template")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer(minLength: 8)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteTemplates)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Templates")
        .searchable(text: $searchText, prompt: "Search templates")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingUseTemplates = true
                } label: {
                    Image(systemName: "wand.and.stars")
                }

                Button {
                    createTemplate()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .navigationDestination(item: $navigateToTemplate) { template in
            ContractTemplateDetailView(template: template)
        }
        .sheet(isPresented: $showingUseTemplates) {
            NavigationStack {
                ContractTemplatePickerView()
                    .navigationTitle("Use Template")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingUseTemplates = false }
                        }
                    }
            }
        }
        .alert("Save Failed", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("OK", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
        .task {
            // ✅ Seed built-in templates if DB is empty
            ContractTemplateSeeder.seedIfNeeded(context: modelContext)
        }
    }

    private func createTemplate() {
        let newTemplate = ContractTemplate(
            name: "",
            category: "General",
            body: "",
            isBuiltIn: false
        )

        modelContext.insert(newTemplate)

        do {
            try modelContext.save()
            navigateToTemplate = newTemplate
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func deleteTemplates(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredTemplates[$0] }
        for t in toDelete {
            if t.isBuiltIn { continue }
            modelContext.delete(t)
        }

        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
