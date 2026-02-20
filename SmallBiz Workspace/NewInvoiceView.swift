import Foundation
import SwiftUI
import SwiftData

struct NewInvoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    
    private var scopedClients: [Client] {
        guard let bizID = activeBiz.activeBusinessID else { return [] }
        return clients.filter { $0.businessID == bizID }
    }


    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]

    @State private var invoiceNumber: String = ""
    @State private var selectedClient: Client? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                SBWTheme.headerWash()

                ScrollView {
                    VStack(spacing: 14) {
                        card {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Invoice")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                VStack(spacing: 0) {
                                    fieldRow(title: "Invoice Number") {
                                        TextField("Invoice Number", text: $invoiceNumber)
                                            .multilineTextAlignment(.trailing)
                                            .textInputAutocapitalization(.characters)
                                            .autocorrectionDisabled()
                                    }

                                    Divider().opacity(0.22)

                                    fieldRow(title: "Client") {
                                        Picker("Client", selection: $selectedClient) {
                                            Text("None").tag(Client?.none)
                                            ForEach(scopedClients) { client in
                                                Text(client.name).tag(Client?.some(client))
                                            }
                                        }
                                        .labelsHidden()
                                        .pickerStyle(.menu)
                                    }
                                }
                            }
                        }

                        if scopedClients.isEmpty {
                            card {
                                Text("No clients yet. You can add a client from the invoice detail screen or we’ll add a Clients tab later.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("New Invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createInvoice() }
                        .disabled(invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if invoiceNumber.isEmpty {
                    invoiceNumber = generateInvoiceNumber()
                }
            }
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(SBWTheme.cardStroke, lineWidth: 1)
                    )
            )
    }

    @ViewBuilder
    private func fieldRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 10)
            content()
                .font(.subheadline)
        }
        .frame(minHeight: 42)
    }

    private func profileEnsured() -> BusinessProfile {
        guard let bizID = activeBiz.activeBusinessID else {
            fatalError("No active business selected")
        }

        if let existing = profiles.first(where: { $0.businessID == bizID }) {
            return existing
        }

        let created = BusinessProfile(businessID: bizID)
        modelContext.insert(created)
        return created
    }


    private func createInvoice() {
        let profile = profileEnsured()
                if let client = selectedClient, client.businessID != profile.businessID {
            print("❌ Client belongs to a different business")
            return
        }

        // ✅ Apply defaults to the invoice (user can override later)
        let invoice = Invoice(
            businessID: profile.businessID,
            invoiceNumber: invoiceNumber,
            thankYou: profile.defaultThankYou,
            termsAndConditions: profile.defaultTerms,
            client: selectedClient
        )

        if let preferredRaw = selectedClient?.preferredInvoiceTemplateKey,
           let preferred = InvoiceTemplateKey.from(preferredRaw) {
            invoice.invoiceTemplateKeyOverride = preferred.rawValue
        }


        let newItem = LineItem(
            itemDescription: "Service",
            quantity: 1,
            unitPrice: 0
        )

        // Ensure items array exists
        if invoice.items == nil {
            invoice.items = []
        }
        
    
        // Append safely
        invoice.items?.append(newItem)

        // Maintain inverse relationship (important for CloudKit)
        newItem.invoice = invoice

        modelContext.insert(invoice)


        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to save invoice: \(error)")
        }
    }

    private func generateInvoiceNumber() -> String {
        let profile = profileEnsured()
        let number = InvoiceNumberGenerator.generateNextNumber(profile: profile)

        do {
            try modelContext.save()
        } catch {
            print("Failed to save invoice numbering state: \(error)")
        }

        return number
    }
}
