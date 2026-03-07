import SwiftUI
import SwiftData

struct BusinessInsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    private let businessID: UUID?
    @Query private var businesses: [Business]

    @State private var cashInWeekCents: Int = 0
    @State private var cashInMonthCents: Int = 0
    @State private var outstandingTotalCents: Int = 0
    @State private var overdueTotalCents: Int = 0
    @State private var draftCount: Int = 0
    @State private var sentUnpaidCount: Int = 0
    @State private var estimateCount: Int = 0
    @State private var isLoadingInsights = false
    @State private var hasAnyRecords = false
    @State private var loadGeneration = UUID()

    init(businessID: UUID? = nil) {
        self.businessID = businessID
        if let businessID {
            _businesses = Query(
                filter: #Predicate<Business> { business in
                    business.id == businessID
                }
            )
        } else {
            _businesses = Query()
        }
    }

    private var effectiveBusinessID: UUID? {
        businessID ?? activeBiz.activeBusinessID
    }

    private var currentBusiness: Business? {
        guard let bizID = effectiveBusinessID else { return nil }
        return businesses.first(where: { $0.id == bizID })
    }

    private var currencyCode: String {
        InsightsCurrency.normalizedCode(currentBusiness?.currencyCode) ?? "USD"
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if effectiveBusinessID == nil {
                ContentUnavailableView(
                    "No Business Selected",
                    systemImage: "building.2",
                    description: Text("Select a business to view insights.")
                )
            } else if let bizID = effectiveBusinessID {
                ScrollView {
                    VStack(spacing: 12) {
                        if isLoadingInsights {
                            loadingCard
                        } else if !hasAnyRecords {
                            emptyInsightsCard
                        } else {
                            cashInCard
                            outstandingCard(businessID: bizID)
                            pipelineCard
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Business Insights")
        .navigationBarTitleDisplayMode(.large)
        .task(id: effectiveBusinessID?.uuidString ?? "none") {
            guard let bizID = effectiveBusinessID else {
                resetState()
                return
            }
            await loadInsights(for: bizID)
        }
    }

    private var loadingCard: some View {
        SBWCardContainer {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading insights...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyInsightsCard: some View {
        SBWCardContainer {
            ContentUnavailableView(
                "No insights yet",
                systemImage: "chart.bar.xaxis",
                description: Text("Create your first invoice to start tracking revenue and outstanding balances.")
            )
        }
    }

    private var cashInCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cash In")
                    .font(.headline)

                valueRow(
                    label: "Paid this week",
                    value: currencyString(from: cashInWeekCents)
                )

                Divider().opacity(0.35)

                valueRow(
                    label: "Paid this month",
                    value: currencyString(from: cashInMonthCents)
                )
            }
        }
    }

    private func outstandingCard(businessID: UUID) -> some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Outstanding")
                    .font(.headline)

                NavigationLink {
                    OutstandingBalancesView(
                        businessID: businessID,
                        mode: .outstandingAll,
                        currencyCode: currencyCode
                    )
                } label: {
                    navigationValueRow(
                        label: "Outstanding total",
                        value: currencyString(from: outstandingTotalCents)
                    )
                }
                .buttonStyle(.plain)

                Divider().opacity(0.35)

                NavigationLink {
                    OutstandingBalancesView(
                        businessID: businessID,
                        mode: .overdueOnly,
                        currencyCode: currencyCode
                    )
                } label: {
                    navigationValueRow(
                        label: "Overdue total",
                        value: currencyString(from: overdueTotalCents)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var pipelineCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pipeline")
                    .font(.headline)

                valueRow(label: "Draft count", value: "\(draftCount)")
                Divider().opacity(0.35)
                valueRow(label: "Sent/unpaid count", value: "\(sentUnpaidCount)")
                Divider().opacity(0.35)
                valueRow(label: "Estimates", value: "\(estimateCount)")
            }
        }
    }

    private func valueRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minHeight: 28)
    }

    private func navigationValueRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(minHeight: 28)
    }

    private func currencyString(from cents: Int) -> String {
        InsightsCurrency.string(cents: cents, code: currencyCode)
    }

    private func resetState() {
        cashInWeekCents = 0
        cashInMonthCents = 0
        outstandingTotalCents = 0
        overdueTotalCents = 0
        draftCount = 0
        sentUnpaidCount = 0
        estimateCount = 0
        hasAnyRecords = false
        isLoadingInsights = false
        loadGeneration = UUID()
    }

    @MainActor
    private func loadInsights(for businessID: UUID) async {
        let token = UUID()
        loadGeneration = token
        isLoadingInsights = true
        hasAnyRecords = false

        let startedAt = Date()
        #if DEBUG
        print("[BusinessInsights] load start business=\(businessID.uuidString)")
        #endif

        do {
            let now = Date()
            var fd = FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID
                },
                sortBy: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
            fd.fetchLimit = 3000

            let invoices = try modelContext.fetch(fd)
            guard loadGeneration == token else { return }

            let snapshot = computeSnapshot(from: invoices, now: now)
            guard loadGeneration == token else { return }

            hasAnyRecords = !snapshot.records.isEmpty
            cashInWeekCents = snapshot.paidWeekCents
            cashInMonthCents = snapshot.paidMonthCents
            outstandingTotalCents = snapshot.outstandingCents
            overdueTotalCents = snapshot.overdueCents
            draftCount = snapshot.draftCount
            sentUnpaidCount = snapshot.sentUnpaidCount
            estimateCount = snapshot.estimateCount
            isLoadingInsights = false

            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[BusinessInsights] load done rows=\(snapshot.records.count) loadMs=\(loadMs)")
            #endif
        } catch {
            guard loadGeneration == token else { return }
            isLoadingInsights = false
            hasAnyRecords = false

            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[BusinessInsights] load failed loadMs=\(loadMs) error=\(error)")
            #endif
        }
    }

    private func computeSnapshot(from invoices: [Invoice], now: Date) -> InsightsSnapshot {
        let nonEstimates = invoices.filter { inv in
            inv.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "estimate"
        }
        let estimates = invoices.filter { inv in
            inv.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "estimate"
        }

        let sentUnpaid = nonEstimates.filter { inv in
            !inv.isPaid && !(inv.items ?? []).isEmpty
        }
        let draftUnpaid = nonEstimates.filter { inv in
            !inv.isPaid && (inv.items ?? []).isEmpty
        }
        let overdue = sentUnpaid.filter { $0.dueDate < now }

        let weekInterval = InsightsDateSupport.calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = InsightsDateSupport.calendar.dateInterval(of: .month, for: now)

        var paidWeekCents = 0
        var paidMonthCents = 0

        for invoice in nonEstimates where invoice.isPaid {
            guard let paidDate = InsightsDateSupport.resolvedPaidDate(for: invoice) else {
                continue
            }
            let amount = max(0, invoice.totalCents)
            if let weekInterval, weekInterval.contains(paidDate) {
                paidWeekCents += amount
            }
            if let monthInterval, monthInterval.contains(paidDate) {
                paidMonthCents += amount
            }
        }

        let outstandingCents = sentUnpaid.reduce(0) { $0 + max(0, $1.remainingDueCents) }
        let overdueCents = overdue.reduce(0) { $0 + max(0, $1.remainingDueCents) }

        return InsightsSnapshot(
            paidWeekCents: paidWeekCents,
            paidMonthCents: paidMonthCents,
            outstandingCents: outstandingCents,
            overdueCents: overdueCents,
            draftCount: draftUnpaid.count,
            sentUnpaidCount: sentUnpaid.count,
            estimateCount: estimates.count,
            records: invoices
        )
    }
}

private struct InsightsSnapshot {
    let paidWeekCents: Int
    let paidMonthCents: Int
    let outstandingCents: Int
    let overdueCents: Int
    let draftCount: Int
    let sentUnpaidCount: Int
    let estimateCount: Int
    let records: [Invoice]
}

private enum InsightsDateSupport {
    static let calendar: Calendar = .autoupdatingCurrent

    static func resolvedPaidDate(for invoice: Invoice) -> Date? {
        guard invoice.isPaid else { return nil }

        if let paidAt = readDate(from: invoice, key: "paidAt") {
            return paidAt
        }
        if let paidDate = readDate(from: invoice, key: "paidDate") {
            return paidDate
        }
        if let paidAtMs = readInt(from: invoice, key: "paidAtMs"), paidAtMs > 0 {
            return Date(timeIntervalSince1970: Double(paidAtMs) / 1000.0)
        }
        return invoice.issueDate
    }

    private static func readDate(from invoice: Invoice, key: String) -> Date? {
        let mirror = Mirror(reflecting: invoice)
        guard let raw = mirror.children.first(where: { $0.label == key })?.value else {
            return nil
        }
        let unwrapped = unwrap(raw)
        if let date = unwrapped as? Date {
            return date
        }
        if let string = unwrapped as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return dateParsers.iso8601WithFractional.date(from: trimmed)
                ?? dateParsers.iso8601Plain.date(from: trimmed)
        }
        return nil
    }

    private static func readInt(from invoice: Invoice, key: String) -> Int? {
        let mirror = Mirror(reflecting: invoice)
        guard let raw = mirror.children.first(where: { $0.label == key })?.value else {
            return nil
        }
        let unwrapped = unwrap(raw)
        if let intValue = unwrapped as? Int {
            return intValue
        }
        if let int64Value = unwrapped as? Int64 {
            return Int(int64Value)
        }
        if let doubleValue = unwrapped as? Double {
            return Int(doubleValue)
        }
        if let string = unwrapped as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func unwrap(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value as Any
    }

    private enum dateParsers {
        static let iso8601WithFractional: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return formatter
        }()

        static let iso8601Plain: ISO8601DateFormatter = {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter
        }()
    }
}
