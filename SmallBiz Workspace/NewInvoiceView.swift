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
            Form {
                Section("Invoice") {
                    TextField("Invoice Number", text: $invoiceNumber)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()

                    Picker("Client", selection: $selectedClient) {
                        Text("None").tag(Client?.none)
                        ForEach(scopedClients) { client in
                            Text(client.name).tag(Client?.some(client))
                        }
                    }
                }

                if scopedClients.isEmpty {
                    Section {
                        Text("No clients yet. You can add a client from the invoice detail screen or we’ll add a Clients tab later.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("New Invoice")
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
