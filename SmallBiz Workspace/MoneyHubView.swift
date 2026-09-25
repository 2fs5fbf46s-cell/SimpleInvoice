import SwiftUI
import SwiftData

/// Invoices, estimates, expenses and insights, under the three numbers an
/// owner checks first: what's owed, what's overdue, and what came in this
/// month. Worked out by MoneyMath, so they match Today and each client.
struct MoneyHubView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore
    @EnvironmentObject private var businessSettingsPresenter: BusinessSettingsPresenter

    enum Segment: String, CaseIterable, Identifiable {
        case invoices = "Invoices"
        case estimates = "Estimates"
        case expenses = "Expenses"
        case insights = "Insights"
        var id: String { rawValue }
    }

    /// Kept across launches and settable from elsewhere, like Work's.
    @AppStorage(MoneyHubView.segmentKey) private var segment: Segment = .invoices
    @State private var invoiceFilter: InvoiceListFilter? = nil

    static let segmentKey = "sbw.moneyHub.segment"

    static func show(_ segment: Segment) {
        UserDefaults.standard.set(segment.rawValue, forKey: segmentKey)
    }

    var body: some View {
        VStack(spacing: 0) {
            MoneySummaryTiles(businessID: activeBiz.activeBusinessID) { tile in
                switch tile {
                case .owed: segment = .invoices; invoiceFilter = .open
                case .overdue: segment = .invoices; invoiceFilter = .overdue
                case .received: segment = .insights
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            Picker("Money section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            switch segment {
            case .invoices:
                InvoiceListView(businessID: activeBiz.activeBusinessID, requestedFilter: invoiceFilter)
            case .estimates:
                EstimateListView(businessID: activeBiz.activeBusinessID)
            case .expenses:
                ExpenseListView(businessID: activeBiz.activeBusinessID)
            case .insights:
                BusinessInsightsView(businessID: activeBiz.activeBusinessID)
            }
        }
        .onChange(of: segment) { _, new in if new != .invoices { invoiceFilter = nil } }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                BusinessAvatarButton { businessSettingsPresenter.open() }
            }
        }
    }
}

/// Owed to you · Overdue · In this month.
struct MoneySummaryTiles: View {
    enum Tile { case owed, overdue, received }

    @Query private var invoices: [Invoice]
    @Query private var jobs: [Job]
    let onTap: (Tile) -> Void

    init(businessID: UUID?, onTap: @escaping (Tile) -> Void) {
        let scoped = BusinessScoped.queryBusinessID(businessID)
        _invoices = Query(filter: #Predicate<Invoice> { $0.businessID == scoped })
        _jobs = Query(filter: #Predicate<Job> { $0.businessID == scoped })
        self.onTap = onTap
    }

    var body: some View {
        let owed = MoneyMath.owed(invoices)
        let overdue = MoneyMath.overdue(invoices)
        let inThisMonth = MoneyMath.tally(MoneyMath.received(invoices: invoices, jobs: jobs), in: MoneyMath.thisMonth())
        HStack(spacing: 8) {
            tile("Owed to you", owed, noun: "invoice", danger: false) { onTap(.owed) }
            tile("Overdue", overdue, noun: "invoice", danger: overdue.cents > 0) { onTap(.overdue) }
            tile("In this month", inThisMonth, noun: "payment", danger: false) { onTap(.received) }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, _ tally: MoneyMath.Tally, noun: String, danger: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(danger ? Color.red : Color.secondary)
                    .lineLimit(1)
                Text(InvoicePaymentService.currency(tally.cents))
                    .font(.headline)
                    .foregroundStyle(danger ? Color.red : Color.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(tally.count) \(noun)\(tally.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(danger ? Color.red.opacity(0.8) : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(danger ? Color.red.opacity(0.1) : Color.primary.opacity(0.05))
            )
        }
        .accessibilityLabel("\(title), \(InvoicePaymentService.currency(tally.cents))")
    }
}
