import SwiftUI
import SwiftData

struct SavedItemsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CatalogItem.name) private var items: [CatalogItem]

    @State private var showAdd = false

    var body: some View {
        List {
            if items.isEmpty {
                Text("No saved items yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(items, id: \.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name)
                            .font(.headline)

                        if !item.details.isEmpty {
                            Text(item.details)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Text(currency(item.unitPrice))
                            .font(.subheadline)
                            .bold()
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .navigationTitle("Saved Items")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Add Saved Item")
            }
        }
        .sheet(isPresented: $showAdd) {
            NewSavedItemSheet()
        }
    }

    private func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: amount)) ?? "$0.00"
    }

    // Minimal add sheet (fast + safe)
    private struct NewSavedItemSheet: View {
        @Environment(\.dismiss) private var dismiss
        @Environment(\.modelContext) private var modelContext

        @State private var name = ""
        @State private var details = ""
        @State private var unitPrice = ""

        var body: some View {
            NavigationStack {
                Form {
                    TextField("Name", text: $name)
                    TextField("Details", text: $details)
                    TextField("Unit Price", text: $unitPrice)
                        .keyboardType(.decimalPad)
                }
                .navigationTitle("New Item")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            let item = CatalogItem(
                                name: name,
                                details: details,
                                unitPrice: Double(unitPrice) ?? 0
                            )
                            modelContext.insert(item)
                            dismiss()
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
    }
}
