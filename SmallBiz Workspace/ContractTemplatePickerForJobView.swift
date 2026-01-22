//
//  ContractTemplatePickerForJobView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// A lightweight template picker used from a Job context.
/// Creates a Draft Contract linked to the provided Job and auto-fills tokens
/// using the current BusinessProfile + the Job's Client (if available).
struct ContractTemplatePickerForJobView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let job: Job
    let onCreated: (Contract) -> Void

    @Query(sort: \ContractTemplate.name) private var templates: [ContractTemplate]
    @Query private var profiles: [BusinessProfile]

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

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

    private var businessProfile: BusinessProfile? { profiles.first }

    var body: some View {
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
                            Text(template.name.isEmpty ? "Template" : template.name)
                                .font(.headline)

                            Text(normalizedCategory(template.category))
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(template.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(4)

                            Button {
                                createDraft(from: template)
                            } label: {
                                Label("Use This Template", systemImage: "wand.and.stars")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    @MainActor
    private func createDraft(from template: ContractTemplate) {
        let client = fetchClientIfPossible()

        let rendered = ContractTokenRenderer.render(
            templateBody: template.body,
            business: businessProfile,
            client: client,
            invoice: nil
        )

        let draft = Contract(
            title: template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Contract" : template.name,
            createdAt: .now,
            updatedAt: .now,
            templateName: template.name,
            templateCategory: template.category,
            renderedBody: rendered,
            statusRaw: ContractStatus.draft.rawValue,
            client: client,
            invoice: nil
        )

        // ✅ Link to Job hub
        draft.job = job

        modelContext.insert(draft)

        do {
            try modelContext.save()
            dismiss()
            onCreated(draft)
        } catch {
            print("Failed to create job-linked draft contract: \(error)")
        }
    }

    private func fetchClientIfPossible() -> Client? {
        guard let clientID = job.clientID else { return nil }
        let descriptor = FetchDescriptor<Client>(predicate: #Predicate<Client> { $0.id == clientID })
        return try? modelContext.fetch(descriptor).first
    }
}
