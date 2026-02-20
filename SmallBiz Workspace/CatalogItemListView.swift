import SwiftUI
import SwiftData

struct CatalogItemListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CatalogItem.name) private var items: [CatalogItem]
    @Query private var profiles: [BusinessProfile]

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"
    @State private var selectedItem: CatalogItem? = nil

    private func normalizedCategory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "General" : trimmed
    }

    private var profile: BusinessProfile {
        profiles.first ?? {
            let created = BusinessProfile()
            modelContext.insert(created)
            return created
        }()
    }

    private var profileCategories: [String] {
        let lines = profile.catalogCategoriesText
            .split(whereSeparator: \.isNewline)
            .map { normalizedCategory(String($0)) }
            .filter { !$0.isEmpty }

        var set = Set(lines)
        set.insert("General")
        return Array(set).sorted()
    }

    private var categories: [String] {
        let itemCats = Set(items.map { normalizedCategory($0.category) })
        let profCats = Set(profileCategories)
        let union = profCats.union(itemCats)
        return ["All"] + union.sorted()
    }

    private var filteredItems: [CatalogItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return items.filter { item in
            let cat = normalizedCategory(item.category)

            let matchesCategory = (selectedCategory == "All") || (cat == selectedCategory)
            if !matchesCategory { return false }

            if q.isEmpty { return true }
            return item.name.lowercased().contains(q) || item.details.lowercased().contains(q)
        }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        ForEach(categories, id: \.self) { c in
                            Text(c).tag(c)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Button { add() } label: {
                        Label("Add Saved Item", systemImage: "plus.circle.fill")
                    }
                }

                Section {
                    if filteredItems.isEmpty {
                        ContentUnavailableView(
                            searchText.isEmpty ? "No Saved Items" : "No Results",
                            systemImage: "tray",
                            description: Text(searchText.isEmpty
                                              ? "Tap “Add Saved Item” to create your first one."
                                              : "Try a different search or category.")
                        )
                    } else {
                        ForEach(filteredItems) { item in
                            Button {
                                selectedItem = item
                            } label: {
                                row(item)
                            }
                            .buttonStyle(.plain)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }
                        .onDelete(perform: deleteFiltered)
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Saved Items")
        .searchable(text: $searchText, prompt: "Search saved items")
        .navigationDestination(item: $selectedItem) { item in
            CatalogItemEditView(item: item)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { add() } label: { Image(systemName: "plus") }
            }
        }
    }

    private func row(_ item: CatalogItem) -> some View {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Item" : item.name
        let category = normalizedCategory(item.category)
        let details = item.details.trimmingCharacters(in: .whitespacesAndNewlines)
        let price = item.unitPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))
        let subtitleParts = [category, details.isEmpty ? nil : details, price]
            .compactMap { $0 }
            .joined(separator: " • ")

        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Saved Items"))
                Image(systemName: "tray")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            SBWNavigationRow(title: name, subtitle: subtitleParts)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 56, alignment: .topLeading)
    }

    private func add() {
        let item = CatalogItem(
            name: "",
            details: "",
            unitPrice: 0,
            defaultQuantity: 1,
            category: "General"
        )
        modelContext.insert(item)

        do {
            try modelContext.save()
        } catch {
            print("Failed to save new catalog item: \(error)")
        }
    }

    private func deleteFiltered(at offsets: IndexSet) {
        let toDelete = offsets.map { filteredItems[$0] }
        for item in toDelete {
            modelContext.delete(item)
        }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save deletes: \(error)")
        }
    }
}
