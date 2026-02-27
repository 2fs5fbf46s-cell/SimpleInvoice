import SwiftUI
import SwiftData

struct ClientOutstandingDetailView: View {
    @Environment(\.modelContext) private var modelContext

    private let businessID: UUID
    private let clientID: UUID
    private let mode: OutstandingMode
    private let currencyCode: String

    @State private var isLoading = true
    @State private var clientName: String = "Client"
    @State private var rows: [OutstandingInvoiceRowModel] = []
    @State private var totalCents: Int = 0
    @State private var invoiceCount: Int = 0
    @State private var loadGeneration = UUID()

    init(businessID: UUID, clientID: UUID, mode: OutstandingMode, currencyCode: String) {
        self.businessID = businessID
        self.clientID = clientID
        self.mode = mode
        self.currencyCode = InsightsCurrency.normalizedCode(currencyCode) ?? "USD"
    }

    private var routeKey: String {
        "\(businessID.uuidString)-\(clientID.uuidString)-\(mode.isOverdueOnly ? "overdue" : "outstanding")"
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
                    } else if rows.isEmpty {
                        emptyState
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
        .task(id: routeKey) {
            await loadData()
        }
    }

    private var summaryCard: some View {
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
                    Text("\(invoiceCount)")
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

    private var loadingCard: some View {
        SBWCardContainer {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
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
            }
        }
    }

    private var invoicesCard: some View {
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

    @MainActor
    private func loadData() async {
        let generation = UUID()
        loadGeneration = generation
        isLoading = true

        let startedAt = Date()

        #if DEBUG
        print("[ClientOutstandingDetail] route business=\(businessID.uuidString) client=\(clientID.uuidString) mode=\(mode.isOverdueOnly ? "overdueOnly" : "outstandingAll")")
        #endif

        do {
            let invoiceDescriptor: FetchDescriptor<Invoice>
            let now = Date()
            if mode.isOverdueOnly {
                invoiceDescriptor = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.businessID == businessID &&
                        invoice.client?.id == clientID &&
                        invoice.isPaid == false &&
                        invoice.dueDate < now
                    },
                    sortBy: [SortDescriptor(\Invoice.dueDate, order: .forward)]
                )
            } else {
                invoiceDescriptor = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.businessID == businessID &&
                        invoice.client?.id == clientID &&
                        invoice.isPaid == false
                    },
                    sortBy: [SortDescriptor(\Invoice.dueDate, order: .forward)]
                )
            }

            let clientDescriptor = FetchDescriptor<Client>(
                predicate: #Predicate<Client> { client in
                    client.businessID == businessID && client.id == clientID
                },
                sortBy: [SortDescriptor(\Client.name, order: .forward)]
            )

            let fetchedInvoices = try modelContext.fetch(invoiceDescriptor)
            let fetchedClients = try modelContext.fetch(clientDescriptor)

            let matchingRows = OutstandingAggregation.invoiceRows(
                invoices: fetchedInvoices,
                businessID: businessID,
                clientID: clientID,
                mode: mode
            )
            let summary = OutstandingAggregation.summary(for: matchingRows)

            guard loadGeneration == generation else { return }

            let trimmedName = fetchedClients.first?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            clientName = trimmedName.isEmpty ? "Client" : trimmedName
            rows = matchingRows
            totalCents = summary.totalCents
            invoiceCount = summary.count
            isLoading = false

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] fetchedInvoices=\(fetchedInvoices.count) matchedRows=\(matchingRows.count) loadMs=\(ms)")
            #endif
        } catch {
            guard loadGeneration == generation else { return }
            clientName = "Client"
            rows = []
            totalCents = 0
            invoiceCount = 0
            isLoading = false

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] load failed after \(ms)ms: \(error)")
            #endif
        }
    }
}
