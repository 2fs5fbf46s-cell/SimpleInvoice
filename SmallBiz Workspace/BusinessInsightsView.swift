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

    private var displayCurrencyCode: String {
        if let businessCode = InsightsCurrency.normalizedCode(currentBusiness?.currencyCode) {
            return businessCode
        }
        return "USD"
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
                        cashInCard
                        outstandingCard(businessID: bizID)
                        pipelineCard
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
                resetInsightsState()
                return
            }
            await loadInsights(businessID: bizID)
        }
    }

    private var cashInCard: some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Cash In")
                        .font(.headline)
                    Spacer()
                    if isLoadingInsights {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                valueRow(
                    label: "Paid this week",
                    value: currencyOrPlaceholder(cashInWeekCents)
                )

                Divider().opacity(0.35)

                valueRow(
                    label: "Paid this month",
                    value: currencyOrPlaceholder(cashInMonthCents)
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
                        mode: .outstandingAll
                    )
                } label: {
                    navigationValueRow(
                        label: "Outstanding total",
                        value: currencyOrPlaceholder(outstandingTotalCents)
                    )
                }
                .buttonStyle(.plain)

                Divider().opacity(0.35)

                NavigationLink {
                    OutstandingBalancesView(
                        businessID: businessID,
                        mode: .overdueOnly
                    )
                } label: {
                    navigationValueRow(
                        label: "Overdue total",
                        value: currencyOrPlaceholder(overdueTotalCents)
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

                valueRow(label: "Draft invoices", value: countOrPlaceholder(draftCount))

                Divider().opacity(0.35)

                valueRow(label: "Sent/unpaid invoices", value: countOrPlaceholder(sentUnpaidCount))

                Divider().opacity(0.35)

                valueRow(label: "Estimates", value: countOrPlaceholder(estimateCount))
            }
        }
    }

    private func valueRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }

    private func navigationValueRow(label: String, value: String) -> some View {
        HStack(spacing: 10) {
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
        .contentShape(Rectangle())
    }

    private func currencyOrPlaceholder(_ cents: Int) -> String {
        if isLoadingInsights { return "—" }
        return InsightsCurrency.string(cents: cents, code: displayCurrencyCode)
    }

    private func countOrPlaceholder(_ count: Int) -> String {
        isLoadingInsights ? "—" : "\(count)"
    }

    @MainActor
    private func loadInsights(businessID: UUID) async {
        let generation = UUID()
        loadGeneration = generation
        isLoadingInsights = true

        let startedAt = Date()
        #if DEBUG
        print("[BusinessInsights] load start business=\(businessID.uuidString)")
        #endif

        do {
            let descriptor = FetchDescriptor<Invoice>(
                predicate: #Predicate<Invoice> { invoice in
                    invoice.businessID == businessID
                },
                sortBy: [SortDescriptor(\Invoice.issueDate, order: .reverse)]
            )
            let fetchedInvoices = try modelContext.fetch(descriptor)
            let summary = BusinessInsightsSummary.compute(from: fetchedInvoices, now: Date())

            guard loadGeneration == generation else { return }

            cashInWeekCents = summary.paidWeekCents
            cashInMonthCents = summary.paidMonthCents
            outstandingTotalCents = summary.outstandingCents
            overdueTotalCents = summary.overdueCents
            draftCount = summary.draftCount
            sentUnpaidCount = summary.sentUnpaidCount
            estimateCount = summary.estimateCount
            isLoadingInsights = false

            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[BusinessInsights] load done invoices=\(fetchedInvoices.count) loadMs=\(loadMs)")
            #endif
        } catch {
            guard loadGeneration == generation else { return }
            resetInsightsState()
            isLoadingInsights = false

            #if DEBUG
            let loadMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            print("[BusinessInsights] load failed loadMs=\(loadMs) error=\(error)")
            #endif
        }
    }

    private func resetInsightsState() {
        cashInWeekCents = 0
        cashInMonthCents = 0
        outstandingTotalCents = 0
        overdueTotalCents = 0
        draftCount = 0
        sentUnpaidCount = 0
        estimateCount = 0
        isLoadingInsights = false
    }
}

private struct BusinessInsightsSummary {
    let paidWeekCents: Int
    let paidMonthCents: Int
    let outstandingCents: Int
    let overdueCents: Int
    let draftCount: Int
    let sentUnpaidCount: Int
    let estimateCount: Int

    static func compute(from invoices: [Invoice], now: Date) -> BusinessInsightsSummary {
        let nonEstimates = invoices.filter {
            $0.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "estimate"
        }
        let estimates = invoices.filter {
            $0.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "estimate"
        }

        let sentUnpaid = nonEstimates.filter {
            !$0.isPaid && !($0.items ?? []).isEmpty
        }
        let draftUnpaid = nonEstimates.filter {
            !$0.isPaid && ($0.items ?? []).isEmpty
        }
        let overdue = sentUnpaid.filter { $0.dueDate < now }

        let weekInterval = BusinessInsightsDateSupport.calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = BusinessInsightsDateSupport.calendar.dateInterval(of: .month, for: now)

        var paidWeekCents = 0
        var paidMonthCents = 0

        for invoice in nonEstimates where invoice.isPaid {
            guard let paidDate = BusinessInsightsDateSupport.resolvedPaidDate(for: invoice) else { continue }
            let amountCents = max(0, invoice.totalCents)

            if let weekInterval, weekInterval.contains(paidDate) {
                paidWeekCents += amountCents
            }
            if let monthInterval, monthInterval.contains(paidDate) {
                paidMonthCents += amountCents
            }
        }

        return BusinessInsightsSummary(
            paidWeekCents: paidWeekCents,
            paidMonthCents: paidMonthCents,
            outstandingCents: sentUnpaid.reduce(0) { $0 + max(0, $1.remainingDueCents) },
            overdueCents: overdue.reduce(0) { $0 + max(0, $1.remainingDueCents) },
            draftCount: draftUnpaid.count,
            sentUnpaidCount: sentUnpaid.count,
            estimateCount: estimates.count
        )
    }
}

private enum BusinessInsightsDateSupport {
    static let calendar: Calendar = .autoupdatingCurrent

    static func resolvedPaidDate(for invoice: Invoice) -> Date? {
        guard invoice.isPaid else { return nil }

        let mirror = Mirror(reflecting: invoice)
        if let date = readDate(from: mirror, key: "paidAt") {
            return date
        }
        if let date = readDate(from: mirror, key: "paidDate") {
            return date
        }
        if let paidAtMs = readInt(from: mirror, key: "paidAtMs"), paidAtMs > 0 {
            return Date(timeIntervalSince1970: TimeInterval(paidAtMs) / 1000.0)
        }

        return invoice.issueDate
    }

    private static func readValue(from mirror: Mirror, key: String) -> Any? {
        mirror.children.first(where: { $0.label == key })?.value
    }

    private static func unwrap(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value as Any
    }

    private static func readDate(from mirror: Mirror, key: String) -> Date? {
        guard let value = readValue(from: mirror, key: key) else { return nil }
        let unwrapped = unwrap(value)
        if let date = unwrapped as? Date {
            return date
        }
        if let string = unwrapped as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return BusinessInsightsDateParsers.iso8601WithFractional.date(from: trimmed)
                ?? BusinessInsightsDateParsers.iso8601Plain.date(from: trimmed)
        }
        return nil
    }

    private static func readInt(from mirror: Mirror, key: String) -> Int? {
        guard let value = readValue(from: mirror, key: key) else { return nil }
        let unwrapped = unwrap(value)
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
}

private enum BusinessInsightsDateParsers {
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
