import SwiftUI
import SwiftData

struct ClientOutstandingDetailView: View {
    private let businessID: UUID
    private let clientID: UUID
    private let mode: OutstandingMode
    private let currencyCode: String

    @Query private var invoices: [Invoice]
    @Query private var clients: [Client]

    init(businessID: UUID, clientID: UUID, mode: OutstandingMode, currencyCode: String) {
        self.businessID = businessID
        self.clientID = clientID
        self.mode = mode
        self.currencyCode = InsightsCurrency.normalizedCode(currencyCode) ?? "USD"
        _invoices = Query(
            filter: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
            },
            sort: [SortDescriptor(\Invoice.dueDate, order: .forward)]
        )
        _clients = Query(
            filter: #Predicate<Client> { client in
                client.businessID == businessID
            },
            sort: [SortDescriptor(\Client.name, order: .forward)]
        )
    }

    private var client: Client? {
        clients.first(where: { $0.id == clientID })
    }

    private var detailRows: [OutstandingInvoiceRowModel] {
        OutstandingAggregation.invoiceRows(
            invoices: invoices,
            businessID: businessID,
            clientID: clientID,
            mode: mode
        )
    }

    private var summary: (totalCents: Int, count: Int) {
        OutstandingAggregation.summary(for: detailRows)
    }

    private var clientName: String {
        let trimmed = client?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Client" : trimmed
    }

    var body: some View {
        let rows = detailRows
        let totals = summary

        return ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        summaryCard(totalCents: totals.totalCents, count: totals.count)
                        invoicesCard(rows: rows)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Client Outstanding")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "No outstanding invoices",
                systemImage: "doc.text.magnifyingglass",
                description: Text(mode.isOverdueOnly
                    ? "This client has no overdue invoices."
                    : "This client has no outstanding invoices.")
            )

            NavigationLink {
                InvoiceListView(businessID: businessID)
            } label: {
                Label("View All Invoices", systemImage: "doc.text")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SBWTheme.brandBlue)
            .padding(.horizontal, 16)
        }
    }

    private func summaryCard(totalCents: Int, count: Int) -> some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(clientName)
                    .font(.headline)

                HStack {
                    Text("Outstanding")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(InsightsCurrency.string(cents: totalCents, code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                HStack {
                    Text("Invoice count")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                if mode.isOverdueOnly {
                    Divider().opacity(0.35)
                    Text("Overdue only")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func invoicesCard(rows: [OutstandingInvoiceRowModel]) -> some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("Invoices")
                    .font(.headline)
                    .padding(.bottom, 8)

                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    NavigationLink {
                        InvoiceOverviewView(invoice: row.invoice)
                    } label: {
                        invoiceRow(row)
                    }
                    .buttonStyle(.plain)

                    if index < rows.count - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func invoiceRow(_ row: OutstandingInvoiceRowModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoiceTitle(for: row.invoice))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    SBWStatusPill(text: row.isOverdue ? "OVERDUE" : "UNPAID")
                    Text(dueText(for: row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(InsightsCurrency.string(cents: row.amountCents, code: currencyCode))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 10)
    }

    private func invoiceTitle(for invoice: Invoice) -> String {
        let number = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? "Invoice" : "Invoice \(number)"
    }

    private func dueText(for row: OutstandingInvoiceRowModel) -> String {
        let due = row.invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
        if row.isOverdue {
            return "Due \(due) • Overdue \(row.overdueDays) day\(row.overdueDays == 1 ? "" : "s")"
        }
        return "Due \(due)"
    }
}
