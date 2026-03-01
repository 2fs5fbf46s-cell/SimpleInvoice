import SwiftUI
import SwiftData

struct OutstandingBalancesView: View {
    @Environment(\.modelContext) private var modelContext

    let businessID: UUID
    let mode: OutstandingMode

    private struct SelectedClient: Identifiable, Equatable, Hashable {
        let id: UUID
    }

    @StateObject private var vm = OutstandingBalancesViewModel()
    @State private var selectedClient: SelectedClient? = nil

    @Query private var businesses: [Business]

    init(businessID: UUID, mode: OutstandingMode) {
        self.businessID = businessID
        self.mode = mode
        _businesses = Query(
            filter: #Predicate<Business> { business in
                business.id == businessID
            }
        )
    }

    private var currencyCode: String {
        InsightsCurrency.normalizedCode(businesses.first?.currencyCode) ?? "USD"
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
                    systemImage: mode == .overdueOnly ? "calendar.badge.checkmark" : "checkmark.circle",
                    description: Text(mode == .overdueOnly
                        ? "No overdue invoices for this business right now."
                        : "All sent invoices are paid for this business.")
                )
            } else {
                ScrollView {
                    SBWCardContainer {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(mode == .overdueOnly ? "Overdue by Client" : "Outstanding by Client")
                                .font(.headline)
                                .padding(.bottom, 8)

                            ForEach(Array(vm.rows.enumerated()), id: \.element.clientID) { index, row in
                                Button {
                                    Haptics.lightTap()
                                    selectedClient = SelectedClient(id: row.clientID)
                                } label: {
                                    balanceRow(
                                        name: row.clientName,
                                        amount: InsightsCurrency.string(cents: row.totalCents, code: currencyCode),
                                        countText: "\(row.invoiceCount) \(mode == .overdueOnly ? "overdue" : "unpaid") invoice\(row.invoiceCount == 1 ? "" : "s")"
                                    )
                                }
                                .buttonStyle(.plain)

                                if index < vm.rows.count - 1 {
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
        .navigationDestination(item: $selectedClient) { sel in
            ClientOutstandingDetailView(
                businessID: businessID,
                clientID: sel.id,
                mode: mode
            )
        }
        .task(id: "\(businessID.uuidString)-\(mode == .overdueOnly ? "overdue" : "outstanding")") {
            await vm.load(modelContext: modelContext, businessID: businessID, mode: mode)
        }
    }

    private func balanceRow(name: String, amount: String, countText: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown Client" : name)
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
