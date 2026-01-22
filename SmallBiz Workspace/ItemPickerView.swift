import SwiftUI
import SwiftData

struct ItemPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CatalogItem.name) private var catalog: [CatalogItem]
    @Query private var profiles: [BusinessProfile]

    @State private var searchText: String = ""
    @State private var selectedCategory: String = "All"

    let onPick: (CatalogItem) -> Void

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

        // Always include General
        var set = Set(lines)
        set.insert("General")

        return Array(set).sorted()
    }

    private var categories: [String] {
        // Union of profile categories + categories currently used by items
        let itemCats = Set(catalog.map { normalizedCategory($0.category) })
        let profCats = Set(profileCategories)

        let union = profCats.union(itemCats)
        return ["All"] + union.sorted()
    }

    private var filteredCatalog: [CatalogItem] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return catalog.filter { item in
            let cat = normalizedCategory(item.category)
            let matchesCategory = (selectedCategory == "All") || (cat == selectedCategory)
            if !matchesCategory { return false }

            if q.isEmpty { return true }
            return item.name.lowercased().contains(q) || item.details.lowercased().contains(q)
        }
    }

    var body: some View {
        List {
            if filteredCatalog.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No Saved Items" : "No Results",
                    systemImage: "tray",
                    description: Text(searchText.isEmpty
                                      ? "Go to Saved Items and add some services/products first."
                                      : "Try a different search or category.")
                )
            } else {
                ForEach(filteredCatalog) { item in
                    Button {
                        onPick(item)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name.isEmpty ? "Item" : item.name)
                                .font(.headline)

                            HStack {
                                Text(normalizedCategory(item.category))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(item.details)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer()

                                Text(item.unitPrice, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Pick Saved Item")
        .searchable(text: $searchText, prompt: "Search items")
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
    }
}
