import SwiftUI
import SwiftData

struct OutstandingBalancesView: View {
    @Environment(\.modelContext) private var modelContext

    let businessID: UUID
    let mode: OutstandingMode
    let currencyCode: String

    @StateObject private var vm = OutstandingBalancesViewModel()
    init(businessID: UUID, mode: OutstandingMode, currencyCode: String) {
        self.businessID = businessID
        self.mode = mode
        self.currencyCode = currencyCode
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if vm.isLoading {
                ScrollView {
                    SBWCardContainer {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Loading balances...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            } else if let error = vm.errorMessage {
                ContentUnavailableView(
                    "Couldn’t Load Balances",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if vm.rows.isEmpty {
                ContentUnavailableView(
                    mode == .overdueOnly ? "No Overdue Balances" : "No Outstanding Balances",
                    systemImage: mode == .overdueOnly ? "calendar.badge.clock" : "checkmark.circle",
                    description: Text(mode == .overdueOnly
                        ? "No overdue invoices for this business right now."
                        : "All sent invoices are paid for this business.")
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            } else {
                ScrollView {
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(mode == .overdueOnly ? "Overdue by Client" : "Outstanding by Client")
                                .font(.headline)
                                .padding(.bottom, 8)

                            ForEach(vm.rows) { row in
                                NavigationLink {
                                    ClientOutstandingDetailView(
                                        businessID: businessID,
                                        clientID: row.clientID,
                                        mode: mode,
                                        currencyCode: currencyCode,
                                        clientName: row.clientName
                                    )
                                } label: {
                                    balanceRow(
                                        name: row.clientName,
                                        amount: InsightsCurrency.string(cents: row.totalCents, code: currencyCode),
                                        countText: "\(row.invoiceCount) \(mode == .overdueOnly ? "overdue" : "unpaid") invoice\(row.invoiceCount == 1 ? "" : "s")"
                                    )
                                }
                                .buttonStyle(.plain)

                                if row.id != vm.rows.last?.id {
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
        .navigationTitle(mode == .overdueOnly ? "Overdue Balances" : "Outstanding Balances")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: "\(businessID.uuidString)-\(mode == .overdueOnly ? "overdue" : "outstanding")") {
            await vm.load(modelContext: modelContext, businessID: businessID, mode: mode)
        }
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
