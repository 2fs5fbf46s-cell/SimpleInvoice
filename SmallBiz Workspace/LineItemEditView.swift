//
//  LineItemEditView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct LineItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: LineItem

    // Local editing state (so UI isn't prefilled)
    @State private var descriptionText: String = ""
    @State private var quantityText: String = ""
    @State private var unitPriceText: String = ""

    var body: some View {
        Form {
            Section("Item") {
                TextField(
                    "Description",
                    text: $descriptionText,
                    prompt: Text("e.g. DJ Services, Photography Session")
                )

                TextField(
                    "Quantity",
                    text: $quantityText,
                    prompt: Text("e.g. 1")
                )
                .keyboardType(.decimalPad)

                TextField(
                    "Unit Price",
                    text: $unitPriceText,
                    prompt: Text("e.g. 250")
                )
                .keyboardType(.decimalPad)
            }

            Section("Line Total") {
                HStack {
                    Text("Total")
                    Spacer()
                    Text(currentLineTotal, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                        .font(.headline)
                }
            }
        }
        .navigationTitle("Line Item")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadFromModel() }
        .onChange(of: descriptionText) { _, _ in saveToModel() }
        .onChange(of: quantityText) { _, _ in saveToModel() }
        .onChange(of: unitPriceText) { _, _ in saveToModel() }
    }

    // MARK: - Helpers

    private func loadFromModel() {
        // Description
        descriptionText = item.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        // Quantity
        if item.quantity > 0 {
            quantityText = String(item.quantity)
        } else {
            quantityText = ""
        }

        // Unit Price
        if item.unitPrice > 0 {
            unitPriceText = String(item.unitPrice)
        } else {
            unitPriceText = ""
        }
    }

    private func saveToModel() {
        item.itemDescription = descriptionText

        if let qty = Double(quantityText) {
            item.quantity = qty
        } else {
            item.quantity = 0
        }

        if let price = Double(unitPriceText) {
            item.unitPrice = price
        } else {
            item.unitPrice = 0
        }

        try? modelContext.save()
    }

    private var currentLineTotal: Double {
        let qty = Double(quantityText) ?? 0
        let price = Double(unitPriceText) ?? 0
        return qty * price
    }
}
