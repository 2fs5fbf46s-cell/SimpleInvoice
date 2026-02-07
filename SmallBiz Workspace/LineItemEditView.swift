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
    @State private var nameText: String = ""
    @State private var detailsText: String = ""
    @State private var quantityValue: Double = 1
    @State private var unitPriceValue: Double = 0

    var body: some View {
        Form {
            Section("Item") {
                TextField(
                    "Name",
                    text: $nameText,
                    prompt: Text("e.g. DJ Services, Photography Session")
                )

                TextEditor(text: $detailsText)
                    .frame(minHeight: 90)
                    .overlay(alignment: .topLeading) {
                        if detailsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Enter description…")
                                .foregroundStyle(.secondary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                    }
                    .accessibilityLabel("Details")
            }

            Section("Pricing") {
                HStack {
                    Text("Quantity")
                    Spacer()
                    Stepper("", value: $quantityValue, in: 0...100000, step: 1)
                        .labelsHidden()
                        .accessibilityLabel("Quantity")
                    Text(quantityValue, format: .number)
                        .frame(minWidth: 50, alignment: .trailing)
                }

                HStack {
                    Text("Unit Price")
                    Spacer()
                    TextField(
                        "$0.00",
                        value: $unitPriceValue,
                        format: .currency(code: Locale.current.currency?.identifier ?? "USD")
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                }
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
        .onChange(of: nameText) { _, _ in saveToModel() }
        .onChange(of: detailsText) { _, _ in saveToModel() }
        .onChange(of: quantityValue) { _, _ in saveToModel() }
        .onChange(of: unitPriceValue) { _, _ in saveToModel() }
    }

    // MARK: - Helpers

    private func loadFromModel() {
        let parts = splitDescription(item.itemDescription)
        nameText = parts.name
        detailsText = parts.details
        quantityValue = item.quantity
        unitPriceValue = item.unitPrice
    }

    private func saveToModel() {
        item.itemDescription = combineDescription(name: nameText, details: detailsText)
        item.quantity = quantityValue
        item.unitPrice = unitPriceValue

        try? modelContext.save()
    }

    private var currentLineTotal: Double {
        quantityValue * unitPriceValue
    }

    private func splitDescription(_ value: String) -> (name: String, details: String) {
        let lines = value.components(separatedBy: .newlines)
        let name = (lines.first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let details = lines.dropFirst().joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, details)
    }

    private func combineDescription(name: String, details: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return trimmedDetails }
        if trimmedDetails.isEmpty { return trimmedName }
        return "\(trimmedName)\n\(trimmedDetails)"
    }
}
