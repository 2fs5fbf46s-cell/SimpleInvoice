import SwiftUI
import SwiftData

struct ClientOutstandingDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let businessID: UUID
    let row: ClientBalanceRowModel
    let mode: OutstandingMode

    @State private var invoices: [Invoice] = []
    @State private var isLoading = true
    @State private var loadError: String? = nil

    private var currencyCode: String {
        Locale.current.currency?.identifier ?? "USD"
    }

    private var titleName: String {
        let trimmed = row.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown Client" : trimmed
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            ScrollView {
                VStack(spacing: 12) {
                    summaryCard

                    if isLoading {
                        loadingCard
                    } else if let loadError {
                        errorCard(loadError)
                    } else if invoices.isEmpty {
                        emptyCard
                    } else {
                        invoicesCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("Client Outstanding")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: row.invoiceIDs) {
            await loadInvoices()
        }
    }

    private var summaryCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(titleName)
                    .font(.headline)

                HStack {
                    Text("Outstanding")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(InsightsCurrency.string(cents: row.totalCents, code: currencyCode))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                HStack {
                    Text("Invoice count")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(row.invoiceCount)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }

                if mode == .overdueOnly {
                    Divider().opacity(0.35)
                    Text("Overdue only")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var loadingCard: some View {
        SBWCardContainer {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading invoices...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func errorCard(_ message: String) -> some View {
        SBWCardContainer {
            ContentUnavailableView(
                "Couldn’t Load Invoices",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        }
    }

    private var emptyCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                ContentUnavailableView(
                    "No outstanding invoices",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(mode == .overdueOnly
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
            }
        }
    }

    private var invoicesCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 0) {
                Text("Invoices")
                    .font(.headline)
                    .padding(.bottom, 8)

                ForEach(Array(invoices.enumerated()), id: \.element.id) { index, invoice in
                    NavigationLink {
                        InvoiceOverviewView(invoice: invoice)
                    } label: {
                        invoiceRow(invoice)
                    }
                    .buttonStyle(.plain)

                    if index < invoices.count - 1 {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func invoiceRow(_ invoice: Invoice) -> some View {
        let isOverdue = !invoice.isPaid && invoice.dueDate < Date()
        let status = isOverdue ? "OVERDUE" : "UNPAID"

        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(invoiceTitle(invoice))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    SBWStatusPill(text: status)
                    Text(dueText(invoice: invoice, isOverdue: isOverdue))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(InsightsCurrency.string(cents: max(0, invoice.remainingDueCents), code: currencyCode))
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

    private func invoiceTitle(_ invoice: Invoice) -> String {
        let number = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return number.isEmpty ? "Invoice" : "Invoice \(number)"
    }

    private func dueText(invoice: Invoice, isOverdue: Bool) -> String {
        let due = invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
        if isOverdue {
            let overdueDays = max(1, Calendar.autoupdatingCurrent.dateComponents([.day], from: invoice.dueDate, to: Date()).day ?? 1)
            return "Due \(due) • Overdue \(overdueDays) day\(overdueDays == 1 ? "" : "s")"
        }
        return "Due \(due)"
    }

    @MainActor
    private func loadInvoices() async {
        isLoading = true
        loadError = nil

        let wantedIDs = Set(row.invoiceIDs)
        guard !wantedIDs.isEmpty else {
            invoices = []
            isLoading = false
            return
        }

        do {
            var descriptor = FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { inv in
                    inv.businessID == businessID && inv.isPaid == false
                },
                sortBy: [SortDescriptor(\Invoice.dueDate, order: .forward)]
            )
            descriptor.fetchLimit = 5000
            let candidates = try modelContext.fetch(descriptor)
            invoices = candidates.filter { wantedIDs.contains($0.id) }
            isLoading = false
        } catch {
            invoices = []
            isLoading = false
            loadError = error.localizedDescription
        }
    }
}
