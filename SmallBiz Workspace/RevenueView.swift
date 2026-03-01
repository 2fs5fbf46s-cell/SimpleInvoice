import SwiftUI
import SwiftData

struct RevenueView: View {
    @EnvironmentObject private var activeBiz: ActiveBusinessStore

    private let businessID: UUID?

    @Query private var invoices: [Invoice]
    @Query private var businesses: [Business]

    @State private var invoiceListDestination: InvoiceListFilter? = nil

    init(businessID: UUID? = nil) {
        self.businessID = businessID

        if let businessID {
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
        } else {
            _invoices = Query(sort: [SortDescriptor(\Invoice.issueDate, order: .reverse)])
            _businesses = Query()
        }
    }

    private var effectiveBusinessID: UUID? {
        businessID ?? activeBiz.activeBusinessID
    }

    private var scopedInvoices: [Invoice] {
        guard let bizID = effectiveBusinessID else { return [] }
        return invoices.filter { $0.businessID == bizID }
    }

    private var currentBusiness: Business? {
        guard let bizID = effectiveBusinessID else { return nil }
        return businesses.first(where: { $0.id == bizID })
    }

    private var displayCurrencyCode: String {
        if let businessCode = Self.normalizedCurrencyCode(currentBusiness?.currencyCode) {
            return businessCode
        }
        if let invoiceCode = scopedInvoices.compactMap({ Self.invoiceCurrencyCode(for: $0) }).first {
            return invoiceCode
        }
        return "USD"
    }

    private var snapshot: RevenueSnapshot {
        RevenueSnapshot.make(from: scopedInvoices, now: Date())
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            SBWTheme.headerWash()

            if effectiveBusinessID == nil {
                ContentUnavailableView(
                    "No Business Selected",
                    systemImage: "building.2",
                    description: Text("Select a business to view revenue totals.")
                )
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        cashInCard
                        outstandingCard
                        pipelineCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle("Revenue")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $invoiceListDestination) { filter in
            InvoiceListView(businessID: effectiveBusinessID, initialFilter: filter)
        }
    }

    private var cashInCard: some View {
        let stats = snapshot
        return SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Cash In")
                    .font(.headline)

                valueRow(
                    label: "Paid this week",
                    value: Self.currencyString(fromCents: stats.paidWeekCents, currencyCode: displayCurrencyCode)
                )

                Divider().opacity(0.35)

                valueRow(
                    label: "Paid this month",
                    value: Self.currencyString(fromCents: stats.paidMonthCents, currencyCode: displayCurrencyCode)
                )
            }
        }
    }

    private var outstandingCard: some View {
        let stats = snapshot
        return SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Outstanding")
                    .font(.headline)

                tappableValueRow(
                    label: "Outstanding total",
                    value: Self.currencyString(fromCents: stats.outstandingCents, currencyCode: displayCurrencyCode)
                ) {
                    invoiceListDestination = .unpaid
                }

                Divider().opacity(0.35)

                tappableValueRow(
                    label: "Overdue total",
                    value: Self.currencyString(fromCents: stats.overdueCents, currencyCode: displayCurrencyCode)
                ) {
                    invoiceListDestination = .overdue
                }
            }
        }
    }

    private var pipelineCard: some View {
        let stats = snapshot
        return SBWCardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Pipeline")
                    .font(.headline)

                valueRow(label: "Draft invoices", value: "\(stats.draftCount)")

                Divider().opacity(0.35)

                valueRow(label: "Sent/unpaid invoices", value: "\(stats.sentUnpaidCount)")

                Divider().opacity(0.35)

                valueRow(label: "Estimates", value: "\(stats.estimateCount)")
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

    private func tappableValueRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
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
        .buttonStyle(.plain)
    }

    private static func normalizedCurrencyCode(_ code: String?) -> String? {
        guard let code else { return nil }
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 3 else { return nil }
        return trimmed.uppercased()
    }

    private static func invoiceCurrencyCode(for invoice: Invoice) -> String? {
        let mirror = Mirror(reflecting: invoice)
        for key in ["currencyCode", "currency", "invoiceCurrencyCode"] {
            guard let value = readValue(from: mirror, key: key) else { continue }
            if let code = normalizedCurrencyCode(value) {
                return code
            }
        }
        return nil
    }

    private static func readValue(from mirror: Mirror, key: String) -> String? {
        guard let value = mirror.children.first(where: { $0.label == key })?.value else { return nil }
        let reflected = Mirror(reflecting: value)
        if reflected.displayStyle == .optional {
            if let unwrapped = reflected.children.first?.value as? String {
                return unwrapped
            }
            return nil
        }
        return value as? String
    }

    private static func currencyString(fromCents cents: Int, currencyCode: String) -> String {
        let amount = Double(max(0, cents)) / 100.0
        return amount.formatted(.currency(code: currencyCode))
    }
}

private struct RevenueSnapshot {
    let paidWeekCents: Int
    let paidMonthCents: Int
    let outstandingCents: Int
    let overdueCents: Int
    let draftCount: Int
    let sentUnpaidCount: Int
    let estimateCount: Int

    static func make(from invoices: [Invoice], now: Date) -> RevenueSnapshot {
        let nonEstimates = invoices.filter { $0.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "estimate" }
        let estimates = invoices.filter { $0.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "estimate" }

        let sentUnpaid = nonEstimates.filter {
            !$0.isPaid && !($0.items ?? []).isEmpty
        }
        let draftUnpaid = nonEstimates.filter {
            !$0.isPaid && ($0.items ?? []).isEmpty
        }
        let overdue = sentUnpaid.filter { $0.dueDate < now }

        let weekInterval = RevenueDateSupport.calendar.dateInterval(of: .weekOfYear, for: now)
        let monthInterval = RevenueDateSupport.calendar.dateInterval(of: .month, for: now)

        var paidWeekCents = 0
        var paidMonthCents = 0

        for invoice in nonEstimates where invoice.isPaid {
            guard let paidDate = RevenueDateSupport.resolvedPaidDate(for: invoice) else { continue }
            let amountCents = max(0, invoice.totalCents)

            if let weekInterval, weekInterval.contains(paidDate) {
                paidWeekCents += amountCents
            }
            if let monthInterval, monthInterval.contains(paidDate) {
                paidMonthCents += amountCents
            }
        }

        let outstandingCents = sentUnpaid.reduce(0) { $0 + max(0, $1.remainingDueCents) }
        let overdueCents = overdue.reduce(0) { $0 + max(0, $1.remainingDueCents) }

        return RevenueSnapshot(
            paidWeekCents: paidWeekCents,
            paidMonthCents: paidMonthCents,
            outstandingCents: outstandingCents,
            overdueCents: overdueCents,
            draftCount: draftUnpaid.count,
            sentUnpaidCount: sentUnpaid.count,
            estimateCount: estimates.count
        )
    }
}

private enum RevenueDateSupport {
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
            return RevenueDateParsers.iso8601WithFractional.date(from: trimmed)
                ?? RevenueDateParsers.iso8601Plain.date(from: trimmed)
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

private enum RevenueDateParsers {
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

