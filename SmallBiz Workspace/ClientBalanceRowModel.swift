import Foundation

enum OutstandingMode: Hashable {
    case outstandingAll
    case overdueOnly

    var isOverdueOnly: Bool {
        self == .overdueOnly
    }
}

struct ClientBalanceRowModel: Identifiable {
    let client: Client?
    let clientID: UUID
    let totalCents: Int
    let invoiceCount: Int

    var id: UUID { clientID }
}

struct OutstandingClientRoute: Hashable {
    let businessID: UUID
    let clientID: UUID
    let mode: OutstandingMode
}

struct OutstandingInvoiceRowModel: Identifiable {
    let invoice: Invoice
    let amountCents: Int
    let isOverdue: Bool
    let overdueDays: Int

    var id: UUID { invoice.id }
}

enum OutstandingAggregation {
    static func clientRows(invoices: [Invoice], mode: OutstandingMode, now: Date = Date()) -> [ClientBalanceRowModel] {
        var buckets: [UUID: (client: Client?, totalCents: Int, invoiceCount: Int)] = [:]

        for invoice in invoices where shouldInclude(invoice: invoice, mode: mode, now: now) {
            guard let clientID = invoice.client?.id else { continue }
            let remaining = max(0, invoice.remainingDueCents)

            if var bucket = buckets[clientID] {
                bucket.totalCents += remaining
                bucket.invoiceCount += 1
                if bucket.client == nil { bucket.client = invoice.client }
                buckets[clientID] = bucket
            } else {
                buckets[clientID] = (client: invoice.client, totalCents: remaining, invoiceCount: 1)
            }
        }

        return buckets.map {
            ClientBalanceRowModel(
                client: $0.value.client,
                clientID: $0.key,
                totalCents: $0.value.totalCents,
                invoiceCount: $0.value.invoiceCount
            )
        }
        .sorted { lhs, rhs in
            if lhs.totalCents == rhs.totalCents {
                let lhsName = lhs.client?.name ?? ""
                let rhsName = rhs.client?.name ?? ""
                return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
            }
            return lhs.totalCents > rhs.totalCents
        }
    }

    static func invoiceRows(
        invoices: [Invoice],
        businessID: UUID,
        clientID: UUID,
        mode: OutstandingMode,
        now: Date = Date()
    ) -> [OutstandingInvoiceRowModel] {
        invoices
            .filter { $0.businessID == businessID }
            .filter { $0.client?.id == clientID }
            .filter { shouldInclude(invoice: $0, mode: mode, now: now) }
            .map {
                let overdueDays = $0.dueDate < now ? max(1, Calendar.autoupdatingCurrent.dateComponents([.day], from: $0.dueDate, to: now).day ?? 1) : 0
                return OutstandingInvoiceRowModel(
                    invoice: $0,
                    amountCents: max(0, $0.remainingDueCents),
                    isOverdue: $0.dueDate < now,
                    overdueDays: overdueDays
                )
            }
            .sorted { lhs, rhs in
                lhs.invoice.dueDate < rhs.invoice.dueDate
            }
    }

    static func summary(for rows: [OutstandingInvoiceRowModel]) -> (totalCents: Int, count: Int) {
        let total = rows.reduce(0) { $0 + $1.amountCents }
        return (total, rows.count)
    }

    private static func shouldInclude(invoice: Invoice, mode: OutstandingMode, now: Date) -> Bool {
        let type = invoice.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard type != "estimate" else { return false }
        guard !invoice.isPaid else { return false }
        guard !((invoice.items ?? []).isEmpty) else { return false }
        guard max(0, invoice.remainingDueCents) > 0 else { return false }

        if mode.isOverdueOnly {
            return invoice.dueDate < now
        }
        return true
    }
}

enum InsightsCurrency {
    static func normalizedCode(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 3 else { return nil }
        return trimmed.uppercased()
    }

    static func string(cents: Int, code: String) -> String {
        let amount = Double(max(0, cents)) / 100.0
        return amount.formatted(.currency(code: code))
    }
}
