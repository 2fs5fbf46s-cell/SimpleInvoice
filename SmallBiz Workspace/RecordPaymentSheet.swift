//
//  RecordPaymentSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// Records a payment the client made outside the portal — cash, a check,
/// Zelle. Starts at the full balance; change the amount for a part payment.
struct RecordPaymentSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice

    @State private var amountText: String = ""
    @State private var method: String = "check"
    @State private var paidAt: Date = .now
    @State private var note: String = ""
    @State private var errorText: String? = nil

    private var balanceCents: Int { invoice.balanceDueCents }

    private var enteredCents: Int? {
        InvoiceAmountParser.cents(from: amountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: amountText) { _, _ in errorText = nil }
                    }
                    Picker("Method", selection: $method) {
                        ForEach(InvoicePayment.methods, id: \.key) { option in
                            Text(option.label).tag(option.key)
                        }
                    }
                    DatePicker("Date", selection: $paidAt, in: ...Date.now, displayedComponents: .date)
                    TextField(method == "check" ? "Check number (optional)" : "Note (optional)", text: $note)
                } footer: {
                    if let errorText {
                        Text(errorText).foregroundStyle(.red)
                    } else if let cents = enteredCents, cents > 0, cents < balanceCents {
                        Text("Part payment. \(InvoicePaymentService.currency(balanceCents - cents)) will still be owed.")
                    } else {
                        Text("\(InvoicePaymentService.currency(balanceCents)) is owed on this invoice.")
                    }
                }
            }
            .navigationTitle("Record Payment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled((enteredCents ?? 0) <= 0)
                }
            }
            .onAppear {
                if amountText.isEmpty {
                    amountText = String(format: "%.2f", Double(balanceCents) / 100)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard let cents = enteredCents else {
            errorText = "Enter the amount you received."
            return
        }
        do {
            try InvoicePaymentService.record(
                on: invoice,
                amountCents: cents,
                paidAt: paidAt,
                method: method,
                note: method == "check" && !note.isEmpty && !note.hasPrefix("#") ? "Check #\(note)" : note,
                context: modelContext
            )
            Haptics.success()
            let invoice = invoice
            let context = modelContext
            Task { await InvoicePaymentService.publishIfSent(invoice, context: context) }
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}
