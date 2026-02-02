//
//  SavedItemsView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct SavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    @Query(sort: \CatalogItem.name) private var items: [CatalogItem]
    @Query private var profiles: [BusinessProfile]

    @State private var searchText: String = ""

    // Clients-style draft -> sheet editor
    @State private var showingEditor = false
    @State private var editorItem: CatalogItem? = nil

    // MARK: - Scoping

    private var scopedItems: [CatalogItem] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return items.filter { $0.businessID == bizID }
    }

    private var filteredItems: [CatalogItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return scopedItems }

        return scopedItems.filter {
            $0.name.lowercased().contains(q)
            || $0.details.lowercased().contains(q)
            || $0.category.lowercased().contains(q)
        }
    }

    private var activeProfile: BusinessProfile? {
        guard let bizID = activeBiz.activeBusinessID else { return nil }
        return profiles.first(where: { $0.businessID == bizID })
    }

    private var categories: [String] {
        let raw = activeProfile?.catalogCategoriesText ?? ""
        let lines = raw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.isEmpty ? ["General"] : lines
    }

    var body: some View {
        ZStack {
            // Background
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Subtle header wash (Option A parity)
            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            List {
                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        scopedItems.isEmpty ? "No Saved Items" : "No Results",
                        systemImage: "tray",
                        description: Text(scopedItems.isEmpty
                                          ? "Tap + to add your first saved item."
                                          : "Try a different search.")
                    )
                } else {
                    ForEach(filteredItems) { item in
                        Button {
                            editorItem = item
                            showingEditor = true
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                modelContext.delete(item)
                                do { try modelContext.save() }
                                catch { print("Failed to delete item: \(error)") }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deleteFiltered)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Saved Items")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search items"
        )
        .settingsGear { BusinessProfileView() }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addDraftAndOpenEditor()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Saved Item")
            }
        }
        .sheet(isPresented: $showingEditor, onDismiss: {
            // Clean up draft if cancelled/empty
            deleteIfEmptyDraft()
            editorItem = nil
        }) {
            NavigationStack {
                if let editorItem {
                    CatalogItemEditorSheet(
                        item: editorItem,
                        categories: categories,
                        onCancel: {
                            // Force delete if it’s still empty
                            deleteIfEmptyDraft(forceDelete: true)
                            showingEditor = false
                        },
                        onDone: {
                            // If name empty, treat like cancel
                            if editorItem.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                deleteIfEmptyDraft(forceDelete: true)
                                showingEditor = false
                                return
                            }
                            do { try modelContext.save(); showingEditor = false }
                            catch { print("Failed to save item edits: \(error)") }
                        }
                    )
                } else {
                    ProgressView("Loading…")
                        .navigationTitle("Saved Item")
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Row UI (Option A)

    private func row(_ item: CatalogItem) -> some View {
        HStack(alignment: .top, spacing: 12) {

            // Leading icon chip
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AnyShapeStyle(SBWTheme.brandGradient.opacity(0.18)))
                Image(systemName: "tray")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.name.isEmpty ? "Item" : item.name)
                        .font(.headline)

                    Spacer()

                    Text(item.unitPrice, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.subheadline.weight(.semibold))
                }

                if !item.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.details)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Text(item.category.isEmpty ? "General" : item.category)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(.secondarySystemFill))
                        .clipShape(Capsule())

                    Spacer()

                    if item.defaultQuantity != 1 {
                        Text("Qty \(item.defaultQuantity, format: .number)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    // MARK: - Add / Delete

    private func addDraftAndOpenEditor() {
        guard let bizID = activeBiz.activeBusinessID else {
            print("❌ No active business selected")
            return
        }

        let draft = CatalogItem(
            name: "",
            details: "",
            unitPrice: 0,
            defaultQuantity: 1,
            category: categories.first ?? "General"
        )
        draft.businessID = bizID

        modelContext.insert(draft)
        editorItem = draft
        showingEditor = true

        do { try modelContext.save() }
        catch { print("Failed to save draft item: \(error)") }
    }

    private func deleteIfEmptyDraft(forceDelete: Bool = false) {
        guard let item = editorItem else { return }

        let nameEmpty = item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let detailsEmpty = item.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isDefault = (item.unitPrice == 0 && item.defaultQuantity == 1)
        let categoryDefault = item.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.category == "General"

        let isEmptyDraft = nameEmpty && detailsEmpty && isDefault && categoryDefault

        if forceDelete || isEmptyDraft {
            modelContext.delete(item)
            do { try modelContext.save() }
            catch { print("Failed to delete empty draft: \(error)") }
        }
    }

    private func deleteFiltered(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredItems[$0] }
        for item in toDelete { modelContext.delete(item) }

        do { try modelContext.save() }
        catch { print("Failed to save deletes: \(error)") }
    }
}

// MARK: - Editor Sheet (unique name to avoid redeclare conflicts)

private struct CatalogItemEditorSheet: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var item: CatalogItem
    let categories: [String]

    let onCancel: () -> Void
    let onDone: () -> Void

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $item.name)
                TextField("Details", text: $item.details, axis: .vertical)
                    .lineLimit(2...6)
            }

            Section("Pricing") {
                TextField("Unit Price", value: $item.unitPrice, format: .number)
                    .keyboardType(.decimalPad)

                Stepper(value: $item.defaultQuantity, in: 1...999, step: 1) {
                    Text("Default Qty: \(item.defaultQuantity, format: .number)")
                }
            }

            Section("Category") {
                Picker("Category", selection: $item.category) {
                    ForEach(categories, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
            }
        }
        .navigationTitle("Saved Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onDone() }
                    .fontWeight(.semibold)
            }
        }
    }
}
