//
//  ContractTemplateEngine.swift
//  SmallBiz Workspace
//
//  Created by Javon Freeman on 1/12/26.
//

import Foundation

struct ContractContext {
    let business: BusinessProfile?
    let client: Client?
    let invoice: Invoice?

    /// Extra fields you want to ask the user for during generation
    /// Example: ["Event.Date": "Jan 22, 2026", "Shoot.Location": "Augusta, GA"]
    let extras: [String: String]

    init(
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?,
        extras: [String: String] = [:]
    ) {
        self.business = business
        self.client = client
        self.invoice = invoice
        self.extras = extras
    }
}

enum ContractTemplateEngine {
    /// Replace {{Token}} placeholders with values from the context.
    static func render(template: String, context: ContractContext) -> String {
        var output = template

        // Basic Business
        output = replace(output, "Business.Name", context.business?.name)
        output = replace(output, "Business.Email", context.business?.email)
        output = replace(output, "Business.Phone", context.business?.phone)
        output = replace(output, "Business.Address", context.business?.address)

        // Client
        output = replace(output, "Client.Name", context.client?.name)
        output = replace(output, "Client.Email", context.client?.email)
        output = replace(output, "Client.Phone", context.client?.phone)
        output = replace(output, "Client.Address", context.client?.address)

        // Invoice
        output = replace(output, "Invoice.Number", context.invoice?.invoiceNumber)
        output = replace(output, "Invoice.IssueDate", context.invoice?.issueDate.formatted(date: .abbreviated, time: .omitted))
        output = replace(output, "Invoice.DueDate", context.invoice?.dueDate.formatted(date: .abbreviated, time: .omitted))

        if let invoice = context.invoice {
            output = replace(output, "Invoice.Subtotal", currency(invoice.subtotal))
            output = replace(output, "Invoice.Discount", currency(invoice.discountAmount))
            output = replace(output, "Invoice.TaxRate", percent(invoice.taxRate))
            output = replace(output, "Invoice.TaxAmount", currency(invoice.taxAmount))
            output = replace(output, "Invoice.Total", currency(invoice.total))

            // Line items as a bullet list
            let itemsText = (invoice.items ?? [])
                .map { "• \($0.itemDescription) — \(cleanQty($0.quantity)) × \(currency($0.unitPrice)) = \(currency($0.lineTotal))" }
                .joined(separator: "\n")
            output = replace(output, "Invoice.Items", itemsText.isEmpty ? nil : itemsText)
        } else {
            output = replace(output, "Invoice.Subtotal", nil)
            output = replace(output, "Invoice.Total", nil)
            output = replace(output, "Invoice.Items", nil)
        }

        // Common dynamic tokens
        output = replace(output, "Today", Date().formatted(date: .abbreviated, time: .omitted))

        // Extras (user-provided fields)
        for (k, v) in context.extras {
            output = replace(output, k, v)
        }

        // Clean up any unreplaced tokens (optional)
        output = stripUnreplacedTokens(output)

        return output
    }

    private static func replace(_ text: String, _ token: String, _ value: String?) -> String {
        let placeholder = "{{\(token)}}"
        return text.replacingOccurrences(of: placeholder, with: value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }

    private static func stripUnreplacedTokens(_ text: String) -> String {
        // Removes remaining {{...}} patterns so users don’t see raw tokens.
        // Lightweight approach without regex dependencies.
        var out = text
        while let start = out.range(of: "{{"),
              let end = out.range(of: "}}", range: start.upperBound..<out.endIndex) {
            out.replaceSubrange(start.lowerBound...end.upperBound, with: "")
        }
        return out
    }

    private static func currency(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = Locale.current.currency?.identifier ?? "USD"
        return f.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }

    private static func percent(_ value: Double) -> String {
        // Your taxRate appears to be 0.07 style; show as 7%
        let pct = value * 100
        return String(format: "%.2f%%", pct)
    }

    private static func cleanQty(_ value: Double) -> String {
        // Avoid showing 1.0 if it’s whole
        if value.rounded() == value { return String(Int(value)) }
        return String(value)
    }
}

