import SwiftUI
import SwiftData

private struct ClientOutstandingInvoiceRow: Identifiable {
    let id: UUID
    let invoice: Invoice
    let title: String
    let statusText: String
    let dueText: String
    let amountCents: Int
}

struct ClientOutstandingDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let businessID: UUID
    let clientID: UUID
    let mode: OutstandingMode
    let currencyCode: String

    @State private var invoiceRows: [ClientOutstandingInvoiceRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var loadGeneration = UUID()
    @State private var clientName: String = "Unknown Client"
    @State private var totalCents: Int = 0

    private var loadKey: String {
        "\(businessID.uuidString)-\(clientID.uuidString)-\(mode == .overdueOnly ? "overdue" : "outstanding")"
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
                    } else if invoiceRows.isEmpty {
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
        .task(id: loadKey) {
            await loadInvoices()
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
                    Text("\(invoiceRows.count)")
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

                ForEach(invoiceRows) { row in
                    NavigationLink {
                        InvoiceOverviewView(invoice: row.invoice)
                    } label: {
                        invoiceRow(row)
                    }
                    .buttonStyle(.plain)

                    if row.id != invoiceRows.last?.id {
                        Divider().opacity(0.35)
                    }
                }
            }
        }
    }

    private func invoiceRow(_ entry: ClientOutstandingInvoiceRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 8) {
                    SBWStatusPill(text: entry.statusText)
                    Text(entry.dueText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(InsightsCurrency.string(cents: entry.amountCents, code: currencyCode))
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

    @MainActor
    private func loadInvoices() async {
        let generation = UUID()
        loadGeneration = generation
        isLoading = true
        loadError = nil

        let startedAt = Date()
        #if DEBUG
        print("[ClientOutstandingDetail] load start business=\(businessID.uuidString) client=\(clientID.uuidString) mode=\(mode == .overdueOnly ? "overdue" : "outstanding")")
        #endif

        do {
            let now = Date()
            var fd: FetchDescriptor<Invoice>
            if mode == .overdueOnly {
                fd = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.businessID == businessID &&
                        invoice.clientID == clientID &&
                        invoice.isPaid == false &&
                        invoice.documentType != "estimate" &&
                        invoice.dueDate < now
                    }
                )
            } else {
                fd = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.businessID == businessID &&
                        invoice.clientID == clientID &&
                        invoice.isPaid == false &&
                        invoice.documentType != "estimate"
                    }
                )
            }
            fd.fetchLimit = 500

            let invoices = try modelContext.fetch(fd)

            guard loadGeneration == generation else { return }

            let rows = invoices.map { invoice in
                let isOverdue = invoice.dueDate < now
                let dueText: String
                let due = invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
                if isOverdue {
                    let overdueDays = max(1, calendarDaysBetween(invoice.dueDate, and: now))
                    dueText = "Due \(due) • Overdue \(overdueDays) day\(overdueDays == 1 ? "" : "s")"
                } else {
                    dueText = "Due \(due)"
                }

                return ClientOutstandingInvoiceRow(
                    id: invoice.id,
                    invoice: invoice,
                    title: invoice.invoiceNumber.isEmpty ? "Invoice" : invoice.invoiceNumber,
                    statusText: isOverdue ? "OVERDUE" : "UNPAID",
                    dueText: dueText,
                    amountCents: max(0, invoice.remainingDueCents)
                )
            }

            guard loadGeneration == generation else { return }

            clientName = (invoices.first?.client?.name ?? "Unknown Client").trimmingCharacters(in: .whitespacesAndNewlines)
            if clientName.isEmpty { clientName = "Unknown Client" }
            totalCents = rows.reduce(0) { $0 + $1.amountCents }
            invoiceRows = rows
            isLoading = false

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] load done rows=\(rows.count) totalMs=\(ms)")
            #endif
        } catch {
            guard loadGeneration == generation else { return }
            invoiceRows = []
            isLoading = false
            totalCents = 0
            loadError = error.localizedDescription

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] load failed loadMs=\(ms) error=\(error)")
            #endif
        }
    }

    private func calendarDaysBetween(_ from: Date, and to: Date) -> Int {
        let calendar = Calendar.autoupdatingCurrent
        return max(0, calendar.dateComponents([.day], from: from, to: to).day ?? 0)
    }
}
