//
//  ContractTokenRenderer.swift
//  SmallBiz Workspace
//

import Foundation

enum ContractTokenRenderer {

    /// Replaces tokens like:
    /// {{Business.Name}}, {{Client.Name}}, {{Invoice.Number}}, {{Invoice.Total}}, {{Today}}, etc.
    static func render(
        templateBody: String,
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?
    ) -> String {

        let today = formattedDate(.now)

        let map: [String: String] = [
            // Business
            "Business.Name": business?.name.trimmed ?? "",
            "Business.Email": business?.email.trimmed ?? "",
            "Business.Phone": business?.phone.trimmed ?? "",
            "Business.Address": business?.address.trimmed ?? "",
            "Business.ThankYou": business?.defaultThankYou.trimmed ?? "",
            "Business.Terms": business?.defaultTerms.trimmed ?? "",

            // Client
            "Client.Name": client?.name.trimmed ?? "",
            "Client.Email": client?.email.trimmed ?? "",
            "Client.Phone": client?.phone.trimmed ?? "",
            "Client.Address": client?.address.trimmed ?? "",

            // Invoice
            "Invoice.Number": invoice?.invoiceNumber.trimmed ?? "",
            "Invoice.IssueDate": invoice.map { formattedDate($0.issueDate) } ?? "",
            "Invoice.DueDate": invoice.map { formattedDate($0.dueDate) } ?? "",
            "Invoice.Subtotal": invoice.map { currency($0.subtotal) } ?? "",
            "Invoice.Tax": invoice.map { currency($0.taxAmount) } ?? "",
            "Invoice.Discount": invoice.map { currency($0.discountAmount) } ?? "",
            "Invoice.Total": invoice.map { currency($0.total) } ?? "",

            // Misc
            "Today": today
        ]

        // Regex for {{ token }}
        let pattern = #"\{\{\s*([A-Za-z0-9\.\_]+)\s*\}\}"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return templateBody
        }

        let ns = templateBody as NSString
        let matches = regex.matches(in: templateBody, options: [], range: NSRange(location: 0, length: ns.length))

        // Build from end -> start so ranges stay valid
        var output = templateBody as NSString
        for m in matches.reversed() {
            guard m.numberOfRanges >= 2 else { continue }
            let tokenRange = m.range(at: 1)
            let rawToken = ns.substring(with: tokenRange)
            let replacement = map[rawToken] ?? ""   // unknown tokens become blank
            output = output.replacingCharacters(in: m.range(at: 0), with: replacement) as NSString
        }

        return output as String
    }

    private static func formattedDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: d)
    }

    private static func currency(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return nf.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
