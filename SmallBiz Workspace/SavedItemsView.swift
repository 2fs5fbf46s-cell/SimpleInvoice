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
    @State private var selectedCategory: String = "All"

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
        let base = scopedItems.filter { item in
            if selectedCategory == "All" { return true }
            return item.category.trimmingCharacters(in: .whitespacesAndNewlines) == selectedCategory
        }

        guard !q.isEmpty else { return base }

        return base.filter {
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

    private var categoryOptions: [String] {
        var out = ["All"]
        out.append(contentsOf: categories)
        return out
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
                categoriesRow
                categoryFilterRow

                if filteredItems.isEmpty {
                    ContentUnavailableView(
                        scopedItems.isEmpty ? "No Saved Items" : "No Results",
                        systemImage: "tray",
                        description: Text(scopedItems.isEmpty
                                          ? "Tap + to add your first saved item."
                                          : "Try a different search.")
                    )
                    .listRowBackground(Color.clear)
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
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.large)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search items"
        )
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
        .onChange(of: activeProfile?.catalogCategoriesText ?? "") { _, _ in
            try? modelContext.save()
        }
    }

    private var categoriesRow: some View {
        NavigationLink {
            CategoriesEditorView(profile: activeProfile)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AnyShapeStyle(SBWTheme.brandGradient.opacity(0.18)))
                    Image(systemName: "tag")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Categories")
                        .font(.headline)
                    Text("Edit the list used for saved items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .sbwCardRow()
    }

    private var categoryFilterRow: some View {
        WrapRow(items: categoryOptions) { option in
            Button {
                selectedCategory = option
            } label: {
                Text(option)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(filterBackground(for: option))
                    .foregroundStyle(filterForeground(for: option))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .sbwCardRow()
    }

    private func filterBackground(for option: String) -> Color {
        if option == selectedCategory {
            return SBWTheme.brandBlue.opacity(0.20)
        }
        return Color(.secondarySystemFill)
    }

    private func filterForeground(for option: String) -> Color {
        if option == selectedCategory {
            return SBWTheme.brandBlue
        }
        return .secondary
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

// MARK: - Categories Editor

private struct CategoriesEditorView: View {
    @Environment(\.modelContext) private var modelContext
    let profile: BusinessProfile?
    @State private var draftCategories: [String] = []

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            SBWTheme.brandGradient
                .opacity(SBWTheme.headerWashOpacity)
                .blur(radius: SBWTheme.headerWashBlur)
                .frame(height: SBWTheme.headerWashHeight)
                .frame(maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()

            List {
                if let profile {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Categories")
                            .font(.headline)

                        Text("These labels help you organize saved items.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        let tags = categories(from: profile)
                        WrapRow(items: tags) { tag in
                            CategoryTagView(text: tag)
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Edit list")
                                .font(.subheadline.weight(.semibold))
                            Text("Tap + to add a new line, then type the category.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        ForEach(draftCategories.indices, id: \.self) { idx in
                            CategoryLineRow(
                                text: bindingForCategory(idx),
                                onDelete: {
                                    draftCategories.remove(at: idx)
                                    persistDraft(profile)
                                }
                            )
                        }

                        Button {
                            draftCategories.append("")
                        } label: {
                            Label("Add Category", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SBWTheme.brandBlue)
                    }
                    .sbwCardRow()
                    .listRowBackground(Color.clear)
                } else {
                    Text("Select a business to edit categories.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .sbwCardRow()
                }
            }
            .listStyle(.plain)
            .listRowSeparator(.hidden)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let profile else { return }
            draftCategories = categories(from: profile)
        }
        .onChange(of: draftCategories) { _, _ in
            if let profile { persistDraft(profile) }
        }
    }

    private func categories(from profile: BusinessProfile) -> [String] {
        let raw = profile.catalogCategoriesText
        let lines = raw
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.isEmpty ? ["General"] : lines
    }

    private func persistDraft(_ profile: BusinessProfile) {
        let cleaned = draftCategories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        profile.catalogCategoriesText = cleaned.joined(separator: "\n")
        try? modelContext.save()
    }

    private func bindingForCategory(_ idx: Int) -> Binding<String> {
        Binding(
            get: { draftCategories[safe: idx] ?? "" },
            set: { newValue in
                guard draftCategories.indices.contains(idx) else { return }
                draftCategories[idx] = newValue
            }
        )
    }
}

private struct CategoryTagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemFill))
            .clipShape(Capsule())
    }
}

private struct CategoryLineRow: View {
    @Binding var text: String
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Category", text: $text)
                .textInputAutocapitalization(.words)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(SBWTheme.cardStroke, lineWidth: 1)
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

private struct WrapRow<Item: Hashable, Content: View>: View {
    let items: [Item]
    let content: (Item) -> Content

    var body: some View {
        var rows: [[Item]] = [[]]
        var currentWidth: CGFloat = 0
        let spacing: CGFloat = 8
        let maxWidth: CGFloat = UIScreen.main.bounds.width - 64

        for item in items {
            let label = UIHostingController(rootView: content(item)).view
            let size = label?.intrinsicContentSize ?? CGSize(width: 80, height: 24)
            if currentWidth + size.width + spacing > maxWidth, !rows[rows.count - 1].isEmpty {
                rows.append([item])
                currentWidth = size.width
            } else {
                rows[rows.count - 1].append(item)
                currentWidth += size.width + spacing
            }
        }

        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(rows.indices, id: \.self) { idx in
                HStack(spacing: spacing) {
                    ForEach(rows[idx], id: \.self) { item in
                        content(item)
                    }
                }
            }
        }
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

private struct SBWCardRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(SBWTheme.cardStroke, lineWidth: 1)
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(Color.clear)
    }
}

private extension View {
    func sbwCardRow() -> some View {
        modifier(SBWCardRow())
    }
}
