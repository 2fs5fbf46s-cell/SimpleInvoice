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
    let job: Job?

    /// Half up front, half on completion, per the founder's standard split
    /// (`ContractCreation.defaultDepositCents`) — nil only when there's no
    /// invoice to split, or the caller explicitly wants no deposit called out.
    let depositAmountCents: Int?

    /// Extra fields you want to ask the user for during generation
    /// Example: ["Event.Date": "Jan 22, 2026", "Shoot.Location": "Augusta, GA"]
    let extras: [String: String]

    init(
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?,
        job: Job? = nil,
        depositAmountCents: Int? = nil,
        extras: [String: String] = [:]
    ) {
        self.business = business
        self.client = client
        self.invoice = invoice
        self.job = job
        self.depositAmountCents = depositAmountCents
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
        // One line, only the parts that exist — the old per-field tokens left
        // a dangling "Phone: | " when a business or client had no phone.
        output = replace(output, "Business.ContactLine", contactLine(
            email: context.business?.email, phone: context.business?.phone
        ))

        // Client
        output = replace(output, "Client.Name", context.client?.name)
        output = replace(output, "Client.Email", context.client?.email)
        output = replace(output, "Client.Phone", context.client?.phone)
        output = replace(output, "Client.Address", context.client?.address)
        output = replace(output, "Client.ContactLine", contactLine(
            email: context.client?.email, phone: context.client?.phone
        ))

        // Job — the site and schedule, never available in a contract before.
        // A job may genuinely not exist yet (a contract bundled with an
        // estimate is drafted before the estimate is accepted, and the job
        // isn't created until then), so these degrade the same way invoice
        // tokens do with no invoice: a visible "[add …]" rather than a blank
        // that's easy to send without noticing.
        output = replace(output, "Job.Title", nonBlank(context.job?.title) ?? blank("job description"))
        output = replace(output, "Job.Location", nonBlank(context.job?.locationName) ?? blank("job site address"))
        output = replace(output, "Job.Date", jobDateText(context.job))
        // Optional, so no blank marker: notes/measurements are extra detail,
        // not something every job has.
        output = replace(output, "Job.Notes", context.job?.notes ?? "")
        output = replace(output, "Job.Measurements", jobMeasurementsText(context.job))

        // Invoice
        // With no invoice these used to come out empty ("Total:", "Due:"),
        // easy to send for signature without noticing. Mark each so it's
        // plain what to fill in; the contract won't send until they're gone.
        output = replace(output, "Invoice.Number", context.invoice?.invoiceNumber ?? blank("invoice number"))
        output = replace(output, "Invoice.IssueDate", context.invoice?.issueDate.formatted(date: .abbreviated, time: .omitted))
        output = replace(output, "Invoice.DueDate", context.invoice?.dueDate.formatted(date: .abbreviated, time: .omitted) ?? blank("due date"))

        if let invoice = context.invoice {
            output = replace(output, "Invoice.Subtotal", currency(invoice.subtotal))
            output = replace(output, "Invoice.Discount", currency(invoice.discountAmount))
            output = replace(output, "Invoice.TaxRate", percent(invoice.taxRate))
            output = replace(output, "Invoice.TaxAmount", currency(invoice.taxAmount))
            output = replace(output, "Invoice.Total", currency(invoice.total))
            output = replace(output, "Invoice.PaymentTerms", nonBlank(invoice.paymentTerms) ?? "Due upon completion")

            // Line items as a bullet list
            let itemsText = (invoice.items ?? [])
                .map { "• \($0.itemDescription) — \(cleanQty($0.quantity)) × \(currency($0.unitPrice)) = \(currency($0.lineTotal))" }
                .joined(separator: "\n")
            output = replace(output, "Invoice.Items", itemsText.isEmpty ? blank("what the work includes") : itemsText)

            // Deposit / balance — the split the app already tracks per
            // contract (ContractCreation.depositAmountCents) but never
            // printed anywhere. No deposit configured: the full total is
            // due on completion, plainly stated rather than left out.
            if let depositCents = context.depositAmountCents, depositCents > 0 {
                let balanceCents = max(invoice.totalCents - depositCents, 0)
                output = replace(output, "Invoice.Deposit", currency(dollars(depositCents)))
                output = replace(output, "Invoice.DepositDueDate", "due at signing")
                output = replace(output, "Invoice.Balance", currency(dollars(balanceCents)))
                output = replace(output, "Invoice.BalanceDueDate", "due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
            } else {
                output = replace(output, "Invoice.Deposit", "No deposit required")
                output = replace(output, "Invoice.DepositDueDate", "")
                output = replace(output, "Invoice.Balance", currency(invoice.total))
                output = replace(output, "Invoice.BalanceDueDate", "due \(invoice.dueDate.formatted(date: .abbreviated, time: .omitted))")
            }
        } else {
            output = replace(output, "Invoice.Subtotal", blank("subtotal"))
            output = replace(output, "Invoice.Total", blank("total"))
            output = replace(output, "Invoice.Items", blank("what the work includes"))
            output = replace(output, "Invoice.PaymentTerms", blank("payment terms"))
            output = replace(output, "Invoice.Deposit", blank("deposit"))
            output = replace(output, "Invoice.DepositDueDate", "")
            output = replace(output, "Invoice.Balance", blank("balance"))
            output = replace(output, "Invoice.BalanceDueDate", blank("due date"))
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

    static let blankPrefix = "[add "

    /// A spot the owner still has to fill in, e.g. "[add total]".
    static func blank(_ what: String) -> String { "\(blankPrefix)\(what)]" }

    /// The "[add …]" spots left in a contract's text, e.g. ["total", "due date"].
    static func blanks(in text: String) -> [String] {
        var found: [String] = []
        var rest = text[...]
        while let start = rest.range(of: blankPrefix),
              let end = rest.range(of: "]", range: start.upperBound..<rest.endIndex) {
            let what = String(rest[start.upperBound..<end.lowerBound])
            if !found.contains(what) { found.append(what) }
            rest = rest[end.upperBound...]
        }
        return found
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

    private static func dollars(_ cents: Int) -> Double {
        Double(cents) / 100.0
    }

    /// The trimmed string, or nil if it's empty/whitespace-only.
    private static func nonBlank(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// "email | phone", "email", "phone", or "" — never a dangling separator
    /// when one side is missing.
    private static func contactLine(email: String?, phone: String?) -> String {
        [nonBlank(email), nonBlank(phone)]
            .compactMap { $0 }
            .joined(separator: " | ")
    }

    /// "Tue, Oct 6, 2026 at 9:00 AM", plus an end time on the same calendar
    /// day when the job runs more than a few minutes ("...–5:00 PM").
    private static func jobDateText(_ job: Job?) -> String {
        // needsScheduling: startDate/endDate are still placeholders, not a
        // real date — nothing should read them while this is true (Job.swift).
        guard let job, !job.needsScheduling else { return blank("scheduled date") }

        let start = job.startDate
        let end = job.endDate
        let df = DateFormatter()
        df.dateFormat = "EEE, MMM d, yyyy"
        let startDay = df.string(from: start)

        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        let startTime = tf.string(from: start)

        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        let hasDuration = end.timeIntervalSince(start) > 60

        if sameDay && hasDuration {
            return "\(startDay) at \(startTime)–\(tf.string(from: end))"
        }
        return "\(startDay) at \(startTime)"
    }

    /// "• Fence length: 200 ft\n• Gate width: 4 ft", or "" with no job or no
    /// measurements taken — this is extra detail, never a required field.
    private static func jobMeasurementsText(_ job: Job?) -> String {
        guard let job, !job.measurements.isEmpty else { return "" }
        return job.measurements
            .map { "• \($0.label): \(cleanQty($0.value)) \($0.unit)" }
            .joined(separator: "\n")
    }
}

