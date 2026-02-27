import Foundation

struct ClientBalanceRowModel: Identifiable {
    let client: Client
    let totalCents: Int
    let invoiceCount: Int

    var id: UUID { client.id }
}

enum ClientBalanceScope {
    case outstanding
    case overdue
}

enum ClientBalanceAggregation {
    static func rows(invoices: [Invoice], scope: ClientBalanceScope, now: Date = Date()) -> [ClientBalanceRowModel] {
        var buckets: [UUID: (client: Client, totalCents: Int, invoiceCount: Int)] = [:]

        for invoice in invoices {
            guard shouldInclude(invoice: invoice, scope: scope, now: now) else { continue }
            guard let client = invoice.client else { continue }

            let remaining = max(0, invoice.remainingDueCents)
            guard remaining > 0 else { continue }

            let key = client.id
            if var bucket = buckets[key] {
                bucket.totalCents += remaining
                bucket.invoiceCount += 1
                buckets[key] = bucket
            } else {
                buckets[key] = (client: client, totalCents: remaining, invoiceCount: 1)
            }
        }

        return buckets.values
            .map {
                ClientBalanceRowModel(
                    client: $0.client,
                    totalCents: $0.totalCents,
                    invoiceCount: $0.invoiceCount
                )
            }
            .sorted { lhs, rhs in
                if lhs.totalCents == rhs.totalCents {
                    return lhs.client.name.localizedCaseInsensitiveCompare(rhs.client.name) == .orderedAscending
                }
                return lhs.totalCents > rhs.totalCents
            }
    }

    private static func shouldInclude(invoice: Invoice, scope: ClientBalanceScope, now: Date) -> Bool {
        let type = invoice.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard type != "estimate" else { return false }
        guard !invoice.isPaid else { return false }

        // Sent/unpaid invoice heuristic used across the app: unpaid and contains line items.
        guard !((invoice.items ?? []).isEmpty) else { return false }

        switch scope {
        case .outstanding:
            return true
        case .overdue:
            return invoice.dueDate < now
        }
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
