import SwiftUI
import SwiftData

struct OverdueBalancesView: View {
    private let currencyCode: String

    @Query private var invoices: [Invoice]

    init(businessID: UUID, currencyCode: String) {
        self.currencyCode = InsightsCurrency.normalizedCode(currencyCode) ?? "USD"
        _invoices = Query(
            filter: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
            },
            sort: [SortDescriptor(\Invoice.dueDate, order: .forward)]
        )
    }

    private var rows: [ClientBalanceRowModel] {
        ClientBalanceAggregation.rows(invoices: invoices, scope: .overdue)
    }

    var body: some View {
        let balanceRows = rows

        return ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if balanceRows.isEmpty {
                ContentUnavailableView(
                    "No Overdue Balances",
                    systemImage: "calendar.badge.checkmark",
                    description: Text("No overdue invoices for this business right now.")
                )
            } else {
                ScrollView {
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Overdue by Client")
                                .font(.headline)
                                .padding(.bottom, 8)

                            ForEach(Array(balanceRows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink {
                                    ClientSummaryView(client: row.client)
                                } label: {
                                    balanceRow(
                                        name: displayName(for: row.client),
                                        amount: InsightsCurrency.string(cents: row.totalCents, code: currencyCode),
                                        countText: "\(row.invoiceCount) overdue invoice\(row.invoiceCount == 1 ? "" : "s")"
                                    )
                                }
                                .buttonStyle(.plain)

                                if index < balanceRows.count - 1 {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Overdue Balances")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func displayName(for client: Client) -> String {
        let trimmed = client.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unnamed Client" : trimmed
    }

    private func balanceRow(name: String, amount: String, countText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(amount)
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
}
