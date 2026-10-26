//
//  PaymentRequestSheet.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import UIKit

/// Ask a client to pay part of an invoice now — typically a deposit — with a
/// link to share by text or email. See PaymentRequestService.
struct PaymentRequestSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var invoice: Invoice
    let businessName: String?
    /// False when no payment method is on, so the client couldn't pay.
    let canPayOnline: Bool
    var onSetUpPayments: (() -> Void)? = nil

    @State private var amountText: String = ""
    @State private var label: String = "Deposit"
    @State private var errorText: String? = nil
    @State private var creating = false
    @State private var link: URL? = nil
    @State private var requestedCents: Int = 0
    @State private var copied = false

    private var balanceCents: Int { invoice.balanceDueCents }
    private var enteredCents: Int? { InvoiceAmountParser.cents(from: amountText) }
    private var clientName: String {
        let name = (invoice.client?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "your client" : name
    }

    var body: some View {
        NavigationStack {
            Group {
                if let link {
                    linkReady(link)
                } else {
                    requestForm
                }
            }
            .navigationTitle(link == nil ? "Request Payment" : "Payment Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(link == nil ? "Cancel" : "Done") { dismiss() }
                }
                if link == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { create() } label: {
                            if creating { ProgressView() } else { Text("Create") }
                        }
                        .fontWeight(.semibold)
                        .disabled(creating || (enteredCents ?? 0) <= 0)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(creating)
    }

    private var requestForm: some View {
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
                HStack(spacing: 8) {
                    quickAmount("25%", cents: balanceCents / 4)
                    quickAmount("50%", cents: balanceCents / 2)
                    quickAmount("Full balance", cents: balanceCents)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                TextField("What it's for", text: $label)
                    .textInputAutocapitalization(.words)
            } footer: {
                if let errorText {
                    Text(errorText).foregroundStyle(.red)
                } else {
                    Text(amountFooter)
                }
            }

            Section {
                Label(
                    "\(clientName) opens the invoice and pays just this amount. You'll get a notification when it's paid.",
                    systemImage: "link"
                )
                .font(.footnote)
                if invoice.isUnsentDocument {
                    Label(
                        "This also sends the invoice: it's marked sent and shows in \(clientName)'s portal.",
                        systemImage: "paperplane"
                    )
                    .font(.footnote)
                }
                if !canPayOnline {
                    Button {
                        dismiss()
                        onSetUpPayments?()
                    } label: {
                        Label("No way to pay online is turned on. Set up payment methods", systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(SBWTheme.attention)
                }
            }
        }
    }

    private var amountFooter: String {
        guard let cents = enteredCents, cents > 0 else {
            return "\(InvoicePaymentService.currency(balanceCents)) is owed on this invoice."
        }
        if cents < balanceCents {
            return "\(InvoicePaymentService.currency(balanceCents - cents)) will still be owed after this."
        }
        if cents == balanceCents {
            return "The full balance."
        }
        return "That's more than the \(InvoicePaymentService.currency(balanceCents)) still owed."
    }

    private func quickAmount(_ title: String, cents: Int) -> some View {
        Button(title) {
            amountText = String(format: "%.2f", Double(cents) / 100)
        }
        .disabled(cents <= 0)
    }

    private func linkReady(_ url: URL) -> some View {
        let message = PaymentRequestService.shareMessage(
            for: invoice,
            amountCents: requestedCents,
            label: label,
            businessName: businessName,
            url: url
        )
        return Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(InvoicePaymentService.currency(requestedCents)) \(label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())")
                        .font(.headline)
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            } footer: {
                Text("Works once: after \(clientName) pays it, the link shows it's paid. The link expires in 30 days.")
            }

            Section {
                ShareLink(item: message) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                Button {
                    UIPasteboard.general.string = url.absoluteString
                    copied = true
                    Haptics.success()
                } label: {
                    Label(copied ? "Copied" : "Copy Link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
            }
        }
    }

    private func create() {
        guard let cents = enteredCents, cents > 0 else {
            errorText = PaymentRequestService.RequestError.notPositive.errorDescription
            return
        }
        do {
            try PaymentRequestService.validate(invoice, amountCents: cents)
        } catch {
            errorText = error.localizedDescription
            return
        }

        creating = true
        errorText = nil
        Task {
            defer { creating = false }
            do {
                let url = try await PaymentRequestService.createLink(
                    for: invoice,
                    amountCents: cents,
                    label: label,
                    context: modelContext,
                    businessName: businessName
                )
                requestedCents = cents
                link = url
                Haptics.success()
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
