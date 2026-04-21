import Foundation
import SwiftData
import SwiftUI

struct ClientInvoicesView: View {
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]
    @Bindable var client: Client

    @State private var searchText: String = ""
    @State private var newInvoice: Invoice? = nil

    private var filteredInvoices: [Invoice] {
        let filtered = invoices.filter { invoice in
            invoice.client?.id == client.id
        }
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return filtered
        }
        let lowercasedQuery = searchText.lowercased()
        return filtered.filter { invoice in
            invoice.invoiceNumber.lowercased().contains(lowercasedQuery) ||
            invoice.notes.lowercased().contains(lowercasedQuery)
        }
    }

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            SBWCardContainer {
                SBWSectionHeaderRow(title: "Invoices")
                if filteredInvoices.isEmpty {
                    Text("No invoices found.")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .padding(.vertical, 12)
                } else {
                    ForEach(filteredInvoices) { invoice in
                        NavigationLink(value: invoice) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(invoice.invoiceNumber)
                                        .fontWeight(.semibold)
                                    Text(invoice.issueDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(invoice.isPaid ? "PAID" : "UNPAID")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(invoice.isPaid ? .green : .red)
                                    Text(invoice.total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                                        .fontWeight(.semibold)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    createInvoiceForClient()
                } label: {
                    Label("Create Invoice", systemImage: "doc.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
                .padding(.top, filteredInvoices.isEmpty ? 0 : 8)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .navigationTitle("Invoices")
        .searchable(text: $searchText, prompt: "Search invoices by number or notes")
        .navigationDestination(for: Invoice.self) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
        .navigationDestination(item: $newInvoice) { invoice in
            InvoiceOverviewView(invoice: invoice)
        }
    }

    private func createInvoiceForClient() {
        let number = "INV-\(Int(Date().timeIntervalSince1970))"
        let invoice = Invoice(invoiceNumber: number, client: client)
        invoice.businessID = client.businessID
        modelContext.insert(invoice)
        try? modelContext.save()
        newInvoice = invoice
    }
}
