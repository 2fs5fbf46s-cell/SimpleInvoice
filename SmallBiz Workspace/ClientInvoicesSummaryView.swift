import SwiftUI
import SwiftData

private enum ClientInvoiceSummaryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case unpaid = "Unpaid"
    case overdue = "Overdue"
    case paid = "Paid"

    var id: String { rawValue }
}

private struct ClientInvoiceSummaryRowModel: Identifiable {
    let invoice: Invoice
    let title: String
    let statusText: String
    let detail: String
    let amountText: String

    var id: UUID { invoice.id }
}

private struct ClientInvoiceSelection: Identifiable, Hashable {
    let id: UUID
}

struct ClientInvoicesSummaryView: View {
    let businessID: UUID
    let clientID: UUID
    let clientName: String
    @Query private var invoices: [Invoice]
    @Query private var businesses: [Business]

    @State private var filter: ClientInvoiceSummaryFilter = .all
    @State private var searchText = ""
    @State private var selectedInvoice: ClientInvoiceSelection?

    init(businessID: UUID, clientID: UUID, clientName: String) {
        self.businessID = businessID
        self.clientID = clientID
        self.clientName = clientName
        _invoices = Query(
            filter: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
            },
            sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
        )
        _businesses = Query(
            filter: #Predicate<Business> { business in
                business.id == businessID
            }
        )
    }

    private var displayCurrencyCode: String {
        InsightsCurrency.normalizedCode(businesses.first?.currencyCode)
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    private var clientTitle: String {
        let trimmed = clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client" : trimmed
    }

    private var clientInvoices: [Invoice] {
        invoices.filter { invoice in
            invoice.documentType != "estimate" && belongsToClient(invoice)
        }
    }

    private var filteredInvoices: [Invoice] {
        let base: [Invoice]
        switch filter {
        case .all:
            base = clientInvoices
        case .unpaid:
            base = clientInvoices.filter { !$0.isPaid }
        case .overdue:
            base = clientInvoices.filter { !$0.isPaid && $0.dueDate < Date() }
        case .paid:
            base = clientInvoices.filter(\.isPaid)
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }

        return base.filter { invoice in
            invoice.invoiceNumber.localizedCaseInsensitiveContains(query) ||
            invoice.notes.localizedCaseInsensitiveContains(query) ||
            invoice.paymentTerms.localizedCaseInsensitiveContains(query)
        }
    }

    private var visibleRows: [ClientInvoiceSummaryRowModel] {
        filteredInvoices.map(makeRowModel(for:))
    }

    private var totalInvoiceCount: Int {
        clientInvoices.count
    }

    private var paidInvoiceCount: Int {
        clientInvoices.filter(\.isPaid).count
    }

    private var outstandingCents: Int {
        clientInvoices
            .filter { !$0.isPaid }
            .reduce(0) { partial, invoice in
                partial + max(0, invoice.remainingDueCents)
            }
    }

    private var overdueCents: Int {
        clientInvoices
            .filter { !$0.isPaid && $0.dueDate < Date() }
            .reduce(0) { partial, invoice in
                partial + max(0, invoice.remainingDueCents)
            }
    }

    private var paidCents: Int {
        clientInvoices
            .filter(\.isPaid)
            .reduce(0) { partial, invoice in
                partial + max(0, invoice.totalCents)
            }
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            List {
                summarySection
                filtersSection
                invoicesSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("All Invoices")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedInvoice) { selection in
            ClientInvoiceSummaryInvoiceRouteView(invoiceID: selection.id)
        }
    }

    private var summarySection: some View {
        Section {
            SummaryKit.SummaryCard {
                SummaryKit.SummaryHeader(
                    title: clientTitle,
                    subtitle: "Invoice Summary",
                    status: totalInvoiceCount == 0 ? "EMPTY" : "\(totalInvoiceCount) TOTAL"
                )

                metricRow(label: "Outstanding", value: InsightsCurrency.string(cents: outstandingCents, code: displayCurrencyCode))
                metricRow(label: "Overdue", value: InsightsCurrency.string(cents: overdueCents, code: displayCurrencyCode))
                metricRow(label: "Collected", value: InsightsCurrency.string(cents: paidCents, code: displayCurrencyCode))
                metricRow(label: "Paid Invoices", value: "\(paidInvoiceCount)")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    private var filtersSection: some View {
        Section {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search this client's invoices", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(ClientInvoiceSummaryFilter.allCases) { option in
                            Button {
                                filter = option
                            } label: {
                                Text(option.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        Capsule()
                                            .fill(filter == option ? SBWTheme.brandBlue.opacity(0.22) : Color.primary.opacity(0.08))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var invoicesSection: some View {
        Section("Invoices") {
            if visibleRows.isEmpty {
                ContentUnavailableView(
                    totalInvoiceCount == 0 ? "No invoices for this client" : "No matching invoices",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(totalInvoiceCount == 0
                        ? "Create an invoice for this client to see it here."
                        : "Try a different filter or search term.")
                )
            } else {
                ForEach(visibleRows) { row in
                    Button {
                        selectedInvoice = ClientInvoiceSelection(id: row.invoice.id)
                    } label: {
                        invoiceRow(row)
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
            }
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        SummaryKit.SummaryKeyValueRow(label: label, value: value)
    }

    private func invoiceRow(_ row: ClientInvoiceSummaryRowModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(SBWTheme.chipFill(for: "Invoices"))
                Image(systemName: "doc.plaintext")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Text(row.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    SBWStatusPill(text: row.statusText)
                }

                Text(row.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(row.amountText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 68, alignment: .topLeading)
    }

    private func makeRowModel(for invoice: Invoice) -> ClientInvoiceSummaryRowModel {
        let issueText = invoice.issueDate.formatted(date: .abbreviated, time: .omitted)
        let dueLabel = invoice.isPaid ? "Paid" : "Due"
        let dueText = invoice.dueDate.formatted(date: .abbreviated, time: .omitted)
        let statusText = invoiceStatus(for: invoice)
        let detail = "Issued \(issueText) • \(dueLabel) \(dueText)"

        let amountText: String
        if invoice.isPaid {
            amountText = "Total \(InsightsCurrency.string(cents: invoice.totalCents, code: displayCurrencyCode))"
        } else {
            amountText = "Balance \(InsightsCurrency.string(cents: invoice.remainingDueCents, code: displayCurrencyCode)) of \(InsightsCurrency.string(cents: invoice.totalCents, code: displayCurrencyCode))"
        }

        return ClientInvoiceSummaryRowModel(
            invoice: invoice,
            title: invoice.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Invoice Draft" : "Invoice \(invoice.invoiceNumber)",
            statusText: statusText,
            detail: detail,
            amountText: amountText
        )
    }

    private func invoiceStatus(for invoice: Invoice) -> String {
        if invoice.isPaid {
            return "PAID"
        }

        if invoice.dueDate < Date() {
            return "OVERDUE"
        }

        if invoice.trimmedInvoiceNumber.isEmpty {
            return "DRAFT"
        }

        return "UNPAID"
    }

    private func belongsToClient(_ invoice: Invoice) -> Bool {
        invoice.client?.id == clientID || invoice.clientID == clientID
    }
}

private struct ClientInvoiceSummaryInvoiceRouteView: View {
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
                let descriptor = FetchDescriptor<Invoice>(
                    predicate: #Predicate<Invoice> { invoice in
                        invoice.id == invoiceID
                    }
                )
                invoice = try modelContext.fetch(descriptor).first
            } catch {
                loadError = error.localizedDescription
            }
        }
    }
}
