import Foundation
import SwiftUI
import SwiftData

struct NewInvoiceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    private let businessID: UUID?
    
    private var scopedClients: [Client] {
        guard let bizID = effectiveBusinessID else { return [] }
        return clients.filter { $0.businessID == bizID }
    }


    @Query(sort: \Client.name) private var clients: [Client]
    @Query private var profiles: [BusinessProfile]

    @State private var invoiceNumber: String = ""
    @State private var selectedClient: Client? = nil
    @State private var suggestedNumber: String = ""

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _clients = Query(
                filter: #Predicate<Client> { client in
                    client.businessID == businessID
                },
                sort: [SortDescriptor(\Client.name)]
            )
            _profiles = Query(
                filter: #Predicate<BusinessProfile> { profile in
                    profile.businessID == businessID
                }
            )
        } else {
            _clients = Query(sort: \Client.name)
            _profiles = Query()
        }
    }

    private var effectiveBusinessID: UUID? {
        businessID
    }

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
                    let preview = previewInvoiceNumber()
                    suggestedNumber = preview
                    invoiceNumber = preview
                }
            }

            // Manual Test Steps:
            // 1) Open New Invoice, cancel, reopen, then save; next number should not skip from canceled opens.
            // 2) Enter custom invoice number and save; verify manual value persists without forced renumbering.
            // 3) Switch business and verify client picker remains scoped.
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
        guard let bizID = effectiveBusinessID else {
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

        let trimmedNumber = invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNumber: String
        if trimmedNumber.isEmpty || trimmedNumber == suggestedNumber {
            finalNumber = InvoiceNumberGenerator.consumeNextNumber(profile: profile)
        } else {
            finalNumber = trimmedNumber
        }

        // ✅ Apply defaults to the invoice (user can override later)
        let invoice = Invoice(
            businessID: profile.businessID,
            invoiceNumber: finalNumber,
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

    private func previewInvoiceNumber() -> String {
        let profile = profileEnsured()
        return InvoiceNumberGenerator.peekNextNumber(profile: profile)
    }
}
