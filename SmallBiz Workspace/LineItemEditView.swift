//
//  LineItemEditView.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

struct LineItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var item: LineItem
    private let businessID: UUID?

    // Local editing state (so UI isn't prefilled)
    @State private var nameText: String = ""
    @State private var detailsText: String = ""
    @State private var quantityValue: Double = 1
    @State private var unitPriceValue: Double = 0
    @State private var showingSavedItemPicker = false
    @State private var pendingCatalogSaveTask: Task<Void, Never>? = nil
    @State private var sessionCatalogItem: CatalogItem? = nil

    init(item: LineItem, businessID: UUID? = nil) {
        self.item = item
        self.businessID = businessID
    }

    var body: some View {
        Form {
            Section("Item") {
                Button {
                    showingSavedItemPicker = true
                } label: {
                    Label("Choose Saved Item", systemImage: "tray")
                }

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
        .onDisappear {
            pendingCatalogSaveTask?.cancel()
            autoSaveCatalogItem()
        }
        .sheet(isPresented: $showingSavedItemPicker) {
            NavigationStack {
                ItemPickerView(businessID: businessID) { picked in
                    applySavedItem(picked)
                }
            }
        }
    }

    // MARK: - Helpers

    private func loadFromModel() {
        let parts = CatalogItemAutoSaveService.parseLineItemDescription(item.itemDescription)
        nameText = parts.name
        detailsText = parts.details
        quantityValue = item.quantity
        unitPriceValue = item.unitPrice
    }

    private func saveToModel() {
        item.itemDescription = CatalogItemAutoSaveService.combineLineItemDescription(
            name: nameText,
            details: detailsText
        )
        item.quantity = quantityValue
        item.unitPrice = unitPriceValue

        try? modelContext.save()
        scheduleCatalogAutosave()
    }

    private var currentLineTotal: Double {
        quantityValue * unitPriceValue
    }

    private func applySavedItem(_ picked: CatalogItem) {
        nameText = picked.name
        detailsText = picked.details
        unitPriceValue = picked.unitPrice
        if quantityValue <= 0 || quantityValue == 1 {
            quantityValue = 1
        }
        sessionCatalogItem = nil
        saveToModel()
    }

    private func scheduleCatalogAutosave() {
        pendingCatalogSaveTask?.cancel()
        pendingCatalogSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            autoSaveCatalogItem()
        }
    }

    private func autoSaveCatalogItem() {
        do {
            let result = try CatalogItemAutoSaveService.save(
                name: nameText,
                details: detailsText,
                unitPrice: unitPriceValue,
                quantity: quantityValue,
                businessID: businessID,
                context: modelContext,
                sessionCatalogItem: sessionCatalogItem
            )
            if result?.created == true {
                sessionCatalogItem = result?.item
            }
        } catch {
            print("Failed to auto-save catalog item: \(error)")
        }
    }
}
