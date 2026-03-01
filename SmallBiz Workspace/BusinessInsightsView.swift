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
    @State private var hasAnyInvoices = false
    @State private var showAboutInsights = false
    @State private var showCreateInvoice = false
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
                        if !isLoadingInsights && !hasAnyInvoices {
                            emptyInsightsCard(businessID: bizID)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAboutInsights = true
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .accessibilityLabel("About Insights")
            }
        }
        .sheet(isPresented: $showAboutInsights) {
            AboutInsightsSheet()
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showCreateInvoice) {
            NewInvoiceView(businessID: effectiveBusinessID)
        }
        .task(id: effectiveBusinessID?.uuidString ?? "none") {
            guard let bizID = effectiveBusinessID else {
                resetInsightsState()
                return
            }
            await loadInsights(businessID: bizID)
        }
    }

    private func emptyInsightsCard(businessID: UUID) -> some View {
        SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("No insights yet")
                    .font(.headline)

                Text("Create your first invoice to start tracking revenue and outstanding balances.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Button {
                    Haptics.lightTap()
                    showCreateInvoice = true
                } label: {
                    Label("Create Invoice", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(SBWTheme.brandBlue)
            }
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
                    value: currencyOrPlaceholder(cashInWeekCents),
                    isLoading: isLoadingInsights
                )

                Divider().opacity(0.35)

                valueRow(
                    label: "Paid this month",
                    value: currencyOrPlaceholder(cashInMonthCents),
                    isLoading: isLoadingInsights
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
                        value: currencyOrPlaceholder(outstandingTotalCents),
                        isLoading: isLoadingInsights
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
                        value: currencyOrPlaceholder(overdueTotalCents),
                        isLoading: isLoadingInsights
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

                valueRow(label: "Draft invoices", value: countOrPlaceholder(draftCount), isLoading: isLoadingInsights)

                Divider().opacity(0.35)

                valueRow(label: "Sent/unpaid invoices", value: countOrPlaceholder(sentUnpaidCount), isLoading: isLoadingInsights)

                Divider().opacity(0.35)

                valueRow(label: "Estimates", value: countOrPlaceholder(estimateCount), isLoading: isLoadingInsights)
            }
        }
    }

    private func valueRow(label: String, value: String, isLoading: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if isLoading {
                InsightsSkeletonBar(width: 84)
            } else {
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .frame(minHeight: 28)
    }

    private func navigationValueRow(label: String, value: String, isLoading: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                if isLoading {
                    InsightsSkeletonBar(width: 84)
                } else {
                    Text(value)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
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

            let now = Date()
            let snapshots: [BusinessInsightsInvoiceSnapshot] = fetchedInvoices.map { invoice in
                let type = invoice.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let hasItems = !((invoice.items ?? []).isEmpty)
                let paidDate = BusinessInsightsDateSupport.resolvedPaidDate(for: invoice)
                return BusinessInsightsInvoiceSnapshot(
                    documentType: type,
                    isPaid: invoice.isPaid,
                    hasItems: hasItems,
                    dueDate: invoice.dueDate,
                    totalCents: max(0, invoice.totalCents),
                    remainingDueCents: max(0, invoice.remainingDueCents),
                    paidDate: paidDate
                )
            }

            let summary = BusinessInsightsSummary.compute(from: snapshots, now: now)

            guard loadGeneration == generation else { return }

            hasAnyInvoices = !fetchedInvoices.isEmpty
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
        hasAnyInvoices = false
        isLoadingInsights = false
    }
}

private struct BusinessInsightsInvoiceSnapshot: Sendable {
    let documentType: String
    let isPaid: Bool
    let hasItems: Bool
    let dueDate: Date
    let totalCents: Int
    let remainingDueCents: Int
    let paidDate: Date?
}

private struct BusinessInsightsSummary {
    let paidWeekCents: Int
    let paidMonthCents: Int
    let outstandingCents: Int
    let overdueCents: Int
    let draftCount: Int
    let sentUnpaidCount: Int
    let estimateCount: Int

    nonisolated static func compute(from invoices: [BusinessInsightsInvoiceSnapshot], now: Date) -> BusinessInsightsSummary {
        let nonEstimates = invoices.filter { $0.documentType != "estimate" }
        let estimates = invoices.filter { $0.documentType == "estimate" }

        let sentUnpaid = nonEstimates.filter {
            !$0.isPaid && $0.hasItems
        }
        let draftUnpaid = nonEstimates.filter {
            !$0.isPaid && !$0.hasItems
        }
        let overdue = sentUnpaid.filter { $0.dueDate < now }

        let cal = Calendar(identifier: .gregorian)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now

        var paidWeekCents = 0
        var paidMonthCents = 0

        for invoice in nonEstimates where invoice.isPaid {
            guard let paidDate = invoice.paidDate else { continue }
            let amountCents = invoice.totalCents

            if paidDate >= weekStart && paidDate <= now {
                paidWeekCents += amountCents
            }
            if paidDate >= monthStart && paidDate <= now {
                paidMonthCents += amountCents
            }
        }

        return BusinessInsightsSummary(
            paidWeekCents: paidWeekCents,
            paidMonthCents: paidMonthCents,
            outstandingCents: sentUnpaid.reduce(0) { $0 + $1.remainingDueCents },
            overdueCents: overdue.reduce(0) { $0 + $1.remainingDueCents },
            draftCount: draftUnpaid.count,
            sentUnpaidCount: sentUnpaid.count,
            estimateCount: estimates.count
        )
    }
}

private enum BusinessInsightsDateSupport {
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

private struct InsightsSkeletonBar: View {
    let width: CGFloat
    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(pulse ? 0.15 : 0.08))
            .frame(width: width, height: 14)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse.toggle()
                }
            }
    }
}

private struct AboutInsightsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                SBWCardContainer {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How Insights Works")
                            .font(.headline)

                        bullet("Cash In shows paid invoice totals for this week and this month.")
                        bullet("Outstanding includes unpaid, sent invoices with remaining balances.")
                        bullet("Overdue is the unpaid subset with due dates before today.")
                        bullet("Pipeline tracks draft invoices, sent/unpaid invoices, and estimates.")
                        bullet("Totals are calculated from invoice status, due dates, and business scope.")
                    }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle("About Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
