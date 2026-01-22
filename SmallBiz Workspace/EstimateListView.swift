import SwiftUI
import SwiftData

struct EstimateListView: View {
    @Query(sort: \Invoice.issueDate, order: .reverse)
    private var invoices: [Invoice]

    private var estimates: [Invoice] {
        invoices.filter { $0.documentType == "estimate" }
    }

    var body: some View {
        List {
            if estimates.isEmpty {
                ContentUnavailableView(
                    "No Estimates",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Create an estimate from the + Create button.")
                )
            } else {
                ForEach(estimates, id: \.id) { inv in
                    NavigationLink {
                        InvoiceDetailView(invoice: inv)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(inv.invoiceNumber.isEmpty ? "Estimate" : inv.invoiceNumber)
                                .font(.headline)
                            Text(inv.client?.name ?? "No customer")
                                .foregroundStyle(.secondary)
                            Text(currency(inv.total))
                                .font(.subheadline).bold()
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
        .navigationTitle("Estimates")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func currency(_ amount: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        return f.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}
