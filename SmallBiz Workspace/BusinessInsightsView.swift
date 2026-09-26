import SwiftUI
import SwiftData
import Charts

/// How money is moving: money in per week, this month against expenses, and
/// who owes you.
///
/// Every number comes from MoneyMath, the same as the Money tiles, Today and
/// each client. This screen used to count its own way: "Paid this week" was
/// dated by the invoice's issue date (the paid date it looked for didn't
/// exist), part payments never counted, drafts the client never saw were
/// "outstanding", and the Unknown Client row opened an empty screen.
struct BusinessInsightsView: View {
    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    @Query private var expenses: [Expense]
    @Query private var clients: [Client]

    @State private var showNoClient = false

    init(businessID: UUID?) {
        let scoped = BusinessScoped.queryBusinessID(businessID)
        _invoices = Query(filter: #Predicate<Invoice> { $0.businessID == scoped })
        _jobs = Query(filter: #Predicate<Job> { $0.businessID == scoped })
        _expenses = Query(filter: #Predicate<Expense> { $0.businessID == scoped })
        _clients = Query(filter: #Predicate<Client> { $0.businessID == scoped })
    }

    var body: some View {
        let received = MoneyMath.received(invoices: invoices, jobs: jobs)
        let weeks = MoneyMath.weekly(received, weeks: 8)
        let month = MoneyMath.thisMonth()
        let inThisMonth = MoneyMath.tally(received, in: month)
        let spent = MoneyMath.spent(expenses, in: month)
        let balances = MoneyMath.byClient(invoices)

        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Money in, last 8 weeks").font(.headline)
                        Spacer()
                        Text("by payment date").font(.caption).foregroundStyle(.secondary)
                    }
                    Chart(weeks, id: \.start) { week in
                        BarMark(
                            x: .value("Week", week.start, unit: .weekOfYear),
                            y: .value("Money in", Double(week.cents) / 100)
                        )
                        .foregroundStyle(week.start == weeks.last?.start ? Color.accentColor : Color.accentColor.opacity(0.35))
                        .cornerRadius(3)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let dollars = value.as(Double.self) { Text(Self.shortCurrency(dollars)) }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 2)) {
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .frame(height: 160)
                    Text("This week: \(InvoicePaymentService.currency(weeks.last?.cents ?? 0))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                LabeledContent("Money in", value: InvoicePaymentService.currency(inThisMonth.cents))
                LabeledContent("Spent", value: InvoicePaymentService.currency(spent.cents))
                LabeledContent {
                    Text(InvoicePaymentService.currency(inThisMonth.cents - spent.cents))
                        .foregroundStyle(inThisMonth.cents - spent.cents < 0 ? .red : .primary)
                        .fontWeight(.semibold)
                } label: {
                    Text("Profit")
                }
            } header: {
                Text(month.start.formatted(.dateTime.month(.wide)))
            } footer: {
                Text("Profit is money in less expenses this month, before tax.")
            }
            .monospacedDigit()

            Section {
                if balances.isEmpty {
                    Text("Nobody owes you anything right now.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(balances) { balance in
                        if let clientID = balance.clientID, let client = client(clientID) {
                            NavigationLink { ClientDetailView(client: client) } label: { balanceRow(balance) }
                        } else {
                            Button { showNoClient = true } label: { balanceRow(balance) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            } header: {
                Text("Who owes you")
            }

            Section("Pipeline") {
                LabeledContent("Invoices not sent yet", value: "\(draftCount)")
                LabeledContent("Invoices waiting on payment", value: "\(MoneyMath.open(invoices).count)")
                LabeledContent("Estimates waiting on the client", value: "\(estimatesWaiting)")
            }

            if !leadSourceBreakdown.isEmpty {
                Section {
                    ForEach(leadSourceBreakdown, id: \.source) { entry in
                        HStack {
                            Text(entry.source.displayName)
                            Spacer()
                            Text("\(entry.count)")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                } header: {
                    Text("Clients by Source")
                } footer: {
                    Text("From \(leadSourceBreakdown.reduce(0) { $0 + $1.count }) of \(clients.count) client\(clients.count == 1 ? "" : "s") with a source set.")
                }
            }
        }
        .navigationTitle("Insights")
        .navigationDestination(isPresented: $showNoClient) { NoClientInvoicesView(invoices: noClientInvoices) }
    }

    private func balanceRow(_ balance: MoneyMath.ClientBalance) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(balance.name)
                    .foregroundStyle(.primary)
                Text(balance.overdueCount > 0
                     ? "\(balance.overdueCount) overdue"
                     : "\(balance.invoiceCount) invoice\(balance.invoiceCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(balance.overdueCount > 0 ? .red : .secondary)
            }
            Spacer()
            Text(InvoicePaymentService.currency(balance.owedCents))
                .monospacedDigit()
                .foregroundStyle(balance.overdueCount > 0 ? .red : .primary)
        }
        .contentShape(Rectangle())
    }

    private func client(_ id: UUID) -> Client? {
        invoices.first { $0.client?.id == id }?.client
    }

    private var noClientInvoices: [Invoice] {
        MoneyMath.open(invoices).filter { $0.client == nil && $0.clientID == nil }
    }

    private var draftCount: Int {
        MoneyMath.billed(invoices).filter { !$0.wasSent && !$0.isPaid }.count
    }

    private var estimatesWaiting: Int {
        invoices.filter { $0.documentType == "estimate" && $0.estimateStatus == "sent" }.count
    }

    /// Only sources at least one client actually has, biggest first — an
    /// all-zero row for every case would just be noise on a small client list.
    private var leadSourceBreakdown: [(source: LeadSource, count: Int)] {
        LeadSource.allCases
            .map { source in (source: source, count: clients.filter { $0.leadSource == source }.count) }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
    }

    static func shortCurrency(_ dollars: Double) -> String {
        if dollars >= 1000 { return "$\(Int((dollars / 1000).rounded()))k" }
        return "$\(Int(dollars.rounded()))"
    }
}

/// Invoices with no client that are still owed.
private struct NoClientInvoicesView: View {
    let invoices: [Invoice]
    @State private var selected: Invoice?

    var body: some View {
        List(invoices) { invoice in
            Button { selected = invoice } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(invoice.invoiceNumber.isEmpty ? "Invoice" : invoice.invoiceNumber)
                        Text("Due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(invoice.isOverdue ? .red : .secondary)
                    }
                    Spacer()
                    Text(InvoicePaymentService.currency(invoice.balanceDueCents)).monospacedDigit()
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("No Client")
        .navigationDestination(item: $selected) { InvoiceOverviewView(invoice: $0) }
    }
}

// Pushed onto a NavigationStack; see InvoiceDetailView's Equatable conformance.
extension BusinessInsightsView: Equatable {
    static func == (_: BusinessInsightsView, _: BusinessInsightsView) -> Bool { true }
}
