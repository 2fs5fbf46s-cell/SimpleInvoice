import SwiftUI
import SwiftData

struct CatalogItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [BusinessProfile]

    @Bindable var item: CatalogItem

    @State private var saveError: String? = nil
    @State private var pendingSaveTask: Task<Void, Never>? = nil

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

    private var categories: [String] {
        // From profile (one per line)
        let lines = profile.catalogCategoriesText
            .split(whereSeparator: \.isNewline)
            .map { normalizedCategory(String($0)) }
            .filter { !$0.isEmpty }

        // Always include General
        var set = Set(lines)
        set.insert("General")

        // Also include the item’s existing category (so it never disappears)
        set.insert(normalizedCategory(item.category))

        return Array(set).sorted()
    }

    var body: some View {
        Form {
            Section("Item") {
                TextField("Name", text: $item.name)
                    .onChange(of: item.name) { _, _ in scheduleAutosave() }

                TextField("Details (optional)", text: $item.details, axis: .vertical)
                    .lineLimit(2...6)
                    .onChange(of: item.details) { _, _ in scheduleAutosave() }

                Picker("Category", selection: $item.category) {
                    ForEach(categories, id: \.self) { c in
                        Text(c).tag(c)
                    }
                }
                .onChange(of: item.category) { _, _ in
                    item.category = normalizedCategory(item.category)
                    saveNow()
                }
            }

            Section("Pricing") {
                HStack {
                    Text("Default Qty")
                    Spacer()
                    TextField("1", value: $item.defaultQuantity, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: item.defaultQuantity) { _, _ in saveNow() }
                }

                HStack {
                    Text("Unit Price")
                    Spacer()
                    TextField("0.00", value: $item.unitPrice, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: item.unitPrice) { _, _ in saveNow() }
                }
            }

            Section {
                Text("Changes save automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Edit Item")
        .alert("Save Failed", isPresented: .constant(saveError != nil)) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "Unknown error.")
        }
        .onDisappear {
            pendingSaveTask?.cancel()
            saveNow()
        }
    }

    private func scheduleAutosave() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 600_000_000)
            saveNow()
        }
    }

    private func saveNow() {
        do {
            try modelContext.save()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
