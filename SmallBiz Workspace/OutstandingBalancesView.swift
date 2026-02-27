import SwiftUI
import SwiftData

struct OutstandingBalancesView: View {
    private let businessID: UUID
    private let currencyCode: String
    private let mode: OutstandingMode

    @Query private var invoices: [Invoice]

    init(businessID: UUID, currencyCode: String, mode: OutstandingMode) {
        self.businessID = businessID
        self.currencyCode = InsightsCurrency.normalizedCode(currencyCode) ?? "USD"
        self.mode = mode
        _invoices = Query(
            filter: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
            },
            sort: [SortDescriptor(\Invoice.dueDate, order: .forward)]
        )
    }

    private var rows: [ClientBalanceRowModel] {
        OutstandingAggregation.clientRows(invoices: invoices, mode: mode)
    }

    var body: some View {
        let balanceRows = rows

        return ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if balanceRows.isEmpty {
                ContentUnavailableView(
                    mode.isOverdueOnly ? "No Overdue Balances" : "No Outstanding Balances",
                    systemImage: mode.isOverdueOnly ? "calendar.badge.checkmark" : "checkmark.circle",
                    description: Text(mode.isOverdueOnly
                        ? "No overdue invoices for this business right now."
                        : "All sent invoices are paid for this business.")
                )
            } else {
                ScrollView {
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(mode.isOverdueOnly ? "Overdue by Client" : "Outstanding by Client")
                                .font(.headline)
                                .padding(.bottom, 8)

                            ForEach(Array(balanceRows.enumerated()), id: \.element.id) { index, row in
                                NavigationLink {
                                    ClientOutstandingDetailView(
                                        businessID: businessID,
                                        clientID: row.clientID,
                                        mode: mode,
                                        currencyCode: currencyCode
                                    )
                                } label: {
                                    balanceRow(
                                        name: displayName(for: row),
                                        amount: InsightsCurrency.string(cents: row.totalCents, code: currencyCode),
                                        countText: "\(row.invoiceCount) \(mode.isOverdueOnly ? "overdue" : "unpaid") invoice\(row.invoiceCount == 1 ? "" : "s")"
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
        .navigationTitle(mode.isOverdueOnly ? "Overdue Balances" : "Outstanding Balances")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func displayName(for row: ClientBalanceRowModel) -> String {
        let trimmed = row.client?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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
