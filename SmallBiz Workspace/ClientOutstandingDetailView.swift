import SwiftUI
import SwiftData

private struct ClientOutstandingInvoiceRow: Identifiable {
    let id: UUID
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

    @Query private var businesses: [Business]

    @State private var invoiceRows: [ClientOutstandingInvoiceRow] = []
    private struct SelectedInvoiceRoute: Identifiable, Hashable {
        let id: UUID
    }
    @State private var selectedInvoice: SelectedInvoiceRoute? = nil
    @State private var invoiceDestinationCache: [UUID: Invoice] = [:]
    @State private var isLoading = true
    @State private var loadError: String? = nil
    @State private var loadGeneration = UUID()
    @State private var clientName: String = "Unknown Client"

    init(businessID: UUID, clientID: UUID, mode: OutstandingMode) {
        self.businessID = businessID
        self.clientID = clientID
        self.mode = mode
        _businesses = Query(
            filter: #Predicate<Business> { business in
                business.id == businessID
            }
        )
    }

    private var currencyCode: String {
        if let code = InsightsCurrency.normalizedCode(businesses.first?.currencyCode) {
            return code
        }
        return Locale.current.currency?.identifier ?? "USD"
    }

    private var loadKey: String {
        "\(businessID.uuidString)-\(clientID.uuidString)-\(mode == .overdueOnly ? "overdue" : "outstanding")"
    }

    private var totalCents: Int {
        invoiceRows.reduce(0) { $0 + $1.amountCents }
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
        .onAppear {
            #if DEBUG
            print("[ClientOutstandingDetail] tap/open business=\(businessID.uuidString) client=\(clientID.uuidString) mode=\(mode == .overdueOnly ? "overdue" : "outstanding")")
            #endif
        }
        .task(id: loadKey) {
            await loadInvoices()
        }
        .navigationDestination(item: $selectedInvoice) { selected in
            if let invoice = invoiceDestinationCache[selected.id] {
                InvoiceOverviewView(invoice: invoice)
            } else {
                ContentUnavailableView(
                    "Invoice Unavailable",
                    systemImage: "doc",
                    description: Text("Couldn’t load this invoice.")
                )
            }
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

                ForEach(Array(invoiceRows.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        Task { await openInvoice(entry.id) }
                    } label: {
                        invoiceRow(entry)
                    }
                    .buttonStyle(.plain)

                    if index < invoiceRows.count - 1 {
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
        selectedInvoice = nil
        invoiceDestinationCache = [:]

        let startedAt = Date()
        #if DEBUG
        print("[ClientOutstandingDetail] open business=\(businessID.uuidString) client=\(clientID.uuidString) mode=\(mode == .overdueOnly ? "overdue" : "outstanding")")
        #endif

        do {
            let now = Date()
            let calendar = Calendar.autoupdatingCurrent
            let fetchStart = Date()
            let dataActor = InsightsDataActor(modelContainer: modelContext.container)
            let snapshots = try await dataActor.fetchClientUnpaidInvoices(
                businessID: businessID,
                clientID: clientID,
                mode: mode
            )
            let fetchMs = Int(Date().timeIntervalSince(fetchStart) * 1000)

            guard loadGeneration == generation else { return }

            let transformStart = Date()
            let rowModels: [ClientOutstandingInvoiceRow] = await Task.detached(priority: .userInitiated) {
                snapshots.map { snap in
                    let isOverdue = snap.dueDate.map { $0 < now } ?? false
                    let dueText: String
                    if let dueDate = snap.dueDate {
                        let due = dueDate.formatted(date: .abbreviated, time: .omitted)
                        if isOverdue {
                            let overdueDays = max(1, calendar.dateComponents([.day], from: dueDate, to: now).day ?? 1)
                            dueText = "Due \(due) • Overdue \(overdueDays) day\(overdueDays == 1 ? "" : "s")"
                        } else {
                            dueText = "Due \(due)"
                        }
                    } else {
                        dueText = "No due date"
                    }
                    return ClientOutstandingInvoiceRow(
                        id: snap.invoiceID,
                        title: "Invoice",
                        statusText: isOverdue ? "OVERDUE" : "UNPAID",
                        dueText: dueText,
                        amountCents: snap.amountCents
                    )
                }
            }.value
            let transformMs = Int(Date().timeIntervalSince(transformStart) * 1000)

            guard loadGeneration == generation else { return }

            let nameCandidate = snapshots.first?.clientName ?? "Unknown Client"
            let trimmedName = nameCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
            clientName = trimmedName.isEmpty ? "Unknown Client" : trimmedName

            invoiceRows = rowModels
            isLoading = false

            #if DEBUG
            let totalMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] fetchMs=\(fetchMs) transformMs=\(transformMs) totalMs=\(totalMs) fetched=\(snapshots.count) shown=\(rowModels.count)")
            #endif
        } catch {
            guard loadGeneration == generation else { return }
            invoiceRows = []
            isLoading = false
            loadError = error.localizedDescription

            #if DEBUG
            let ms = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[ClientOutstandingDetail] load failed loadMs=\(ms) error=\(error)")
            #endif
        }
    }

    @MainActor
    private func openInvoice(_ invoiceID: UUID) async {
        do {
            guard let invoice = try fetchInvoice(by: invoiceID) else { return }
            invoiceDestinationCache[invoice.id] = invoice
            selectedInvoice = SelectedInvoiceRoute(id: invoice.id)
        } catch {
            #if DEBUG
            print("[ClientOutstandingDetail] invoice fetch failed id=\(invoiceID.uuidString) error=\(error)")
            #endif
        }
    }

    @MainActor
    private func fetchInvoice(by invoiceID: UUID) throws -> Invoice? {
        var descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { inv in
                inv.id == invoiceID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }
}
