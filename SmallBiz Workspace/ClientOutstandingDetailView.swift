import SwiftUI
import SwiftData

private struct SelectedInvoice: Identifiable, Hashable {
    let id: UUID
}

private struct ClientOutstandingInvoiceRow: Identifiable, Sendable {
    let id: UUID
    let title: String
    let statusText: String
    let dueText: String
    let amountCents: Int
}

private struct ClientOutstandingLoadResult: Sendable {
    let rows: [ClientOutstandingInvoiceRow]
    let totalCents: Int
}

struct ClientOutstandingDetailView: View {
    @Environment(\.modelContext) private var modelContext

    let businessID: UUID
    let clientID: UUID
    let mode: OutstandingMode
    let currencyCode: String
    let clientName: String

    @State private var invoiceRows: [ClientOutstandingInvoiceRow] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var loadGeneration = UUID()
    @State private var displayClientName: String = "Unknown Client"
    @State private var totalCents: Int = 0
    @State private var selectedInvoice: SelectedInvoice?

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
        .navigationDestination(item: $selectedInvoice) { sel in
            InvoiceOverviewRouteView(invoiceID: sel.id)
        }
    }

    private var summaryCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 8) {
                Text(displayClientName)
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
                    Button {
                        selectedInvoice = SelectedInvoice(id: row.id)
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
            let container = modelContext.container
            let businessID = self.businessID
            let clientID = self.clientID
            let mode = self.mode
            let resolvedName = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveClientName = resolvedName.isEmpty ? "Unknown Client" : resolvedName

            let result: ClientOutstandingLoadResult = try await Task.detached(priority: .userInitiated) {
                let bg = ModelContext(container)
                let now = Date()
                let calendar = Calendar(identifier: .gregorian)
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .none

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

                let invoices = try bg.fetch(fd)
                var rows: [ClientOutstandingInvoiceRow] = []
                rows.reserveCapacity(invoices.count)
                var total = 0

                for invoice in invoices {
                    let amount = max(0, invoice.remainingDueCents)
                    total += amount

                    let isOverdue = invoice.dueDate < now
                    let baseDueText = formatter.string(from: invoice.dueDate)
                    let dueText: String
                    if isOverdue {
                        let overdueDays = max(
                            1,
                            calendar.dateComponents([.day], from: invoice.dueDate, to: now).day ?? 0
                        )
                        dueText = "Due \(baseDueText) • Overdue \(overdueDays) day\(overdueDays == 1 ? "" : "s")"
                    } else {
                        dueText = "Due \(baseDueText)"
                    }

                    let invoiceNumber = invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                    rows.append(
                        ClientOutstandingInvoiceRow(
                            id: invoice.id,
                            title: invoiceNumber.isEmpty ? "Invoice" : invoiceNumber,
                            statusText: isOverdue ? "OVERDUE" : "UNPAID",
                            dueText: dueText,
                            amountCents: amount
                        )
                    )
                }

                return ClientOutstandingLoadResult(rows: rows, totalCents: total)
            }.value

            guard loadGeneration == generation else { return }

            displayClientName = effectiveClientName
            invoiceRows = result.rows
            totalCents = result.totalCents
            isLoading = false

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] load done rows=\(result.rows.count) totalMs=\(ms)")
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
}

private struct InvoiceOverviewRouteView: View {
    @Environment(\.modelContext) private var modelContext
    let invoiceID: UUID

    @State private var invoice: Invoice?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let invoice {
                InvoiceOverviewView(invoice: invoice)
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn’t Load Invoice",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView("Loading invoice...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .task(id: invoiceID) {
            do {
                let fd = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.id == invoiceID
                    }
                )
                invoice = try modelContext.fetch(fd).first
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
