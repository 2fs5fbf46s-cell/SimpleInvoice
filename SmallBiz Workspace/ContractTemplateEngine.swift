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

    /// Cancellation tiers, balance deadline and governing state — the
    /// business's defaults unless this one contract was given its own.
    let terms: ContractTerms

    /// Extra fields you want to ask the user for during generation
    /// Example: ["Event.Date": "Jan 22, 2026", "Shoot.Location": "Augusta, GA"]
    let extras: [String: String]

    init(
        business: BusinessProfile?,
        client: Client?,
        invoice: Invoice?,
        job: Job? = nil,
        depositAmountCents: Int? = nil,
        terms: ContractTerms? = nil,
        extras: [String: String] = [:]
    ) {
        self.business = business
        self.client = client
        self.invoice = invoice
        self.job = job
        self.depositAmountCents = depositAmountCents
        self.terms = (terms ?? ContractTerms(profile: business)).normalized
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
        output = replace(output, "Business.NameWithContact", nameWithContact(
            name: context.business?.name, email: context.business?.email, phone: context.business?.phone
        ))

        // Client
        output = replace(output, "Client.Name", context.client?.name)
        output = replace(output, "Client.Email", context.client?.email)
        output = replace(output, "Client.Phone", context.client?.phone)
        output = replace(output, "Client.Address", context.client?.address)
        output = replace(output, "Client.ContactLine", contactLine(
            email: context.client?.email, phone: context.client?.phone
        ))
        output = replace(output, "Client.NameWithContact", nameWithContact(
            name: context.client?.name, email: context.client?.email, phone: context.client?.phone
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
        output = replace(output, "Job.Day", jobDay(context.job).map(longDate) ?? blank("event date"))
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
            output = replace(output, "Invoice.TotalWords", "\(amountInWords(invoice.totalCents)) (\(currency(invoice.total)))")
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
            output = replace(output, "Invoice.TotalWords", blank("total"))
            output = replace(output, "Invoice.Items", blank("what the work includes"))
            output = replace(output, "Invoice.PaymentTerms", blank("payment terms"))
            output = replace(output, "Invoice.Deposit", blank("deposit"))
            output = replace(output, "Invoice.DepositDueDate", "")
            output = replace(output, "Invoice.Balance", blank("balance"))
            output = replace(output, "Invoice.BalanceDueDate", blank("due date"))
        }

        output = renderTerms(output, context: context)

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

    /// The tokens the Voorhees-style templates (v3) are written with: the
    /// fee, deposit and balance as sentences, and the cancellation tiers
    /// with the money each one comes to.
    private static func renderTerms(_ text: String, context: ContractContext) -> String {
        var output = text
        let t = context.terms
        let job = context.job
        let totalCents = context.invoice?.totalCents
        let depositCents = context.depositAmountCents.flatMap { $0 > 0 ? $0 : nil }
        let money = { (cents: Int) in currency(dollars(cents)) }

        output = replace(output, "Contract.Subtitle", [
            nonBlank(context.client?.name),
            jobDay(job).map(longDate),
            nonBlank(job?.locationName)
        ].compactMap { $0 }.joined(separator: " · "))

        // Deposit
        let depositLine: String
        let depositClause: String
        switch (totalCents, depositCents) {
        case (nil, _):
            depositLine = blank("deposit")
            depositClause = blank("deposit")
        case let (total?, deposit?):
            let pct = total > 0 ? Int((Double(deposit) / Double(total) * 100).rounded()) : 0
            depositLine = "\(money(deposit)) (\(pct)%) — due upon signing"
            depositClause = "A booking deposit of \(money(deposit)) (\(pct)% of the Total Fee) is due upon Client’s signing of this Agreement. The scheduled date is not reserved until Provider has received both the signed Agreement and the deposit. The deposit is credited in full toward the Total Fee, and its refund is governed only by the cancellation terms of this Agreement."
        case (_?, nil):
            depositLine = "None required"
            depositClause = "No booking deposit is required. The scheduled date is reserved once both Parties have signed this Agreement."
        }
        output = replace(output, "Terms.DepositLine", depositLine)
        output = replace(output, "Terms.DepositClause", depositClause)

        // Final balance, `balanceDueHours` before the start
        let hoursText = t.balanceDueHours == 0 ? nil : "\(spelled(t.balanceDueHours)) (\(t.balanceDueHours)) hours"
        let deadline = jobDay(job).map { $0.addingTimeInterval(-Double(t.balanceDueHours) * 3600) }
        let whenShort = t.balanceDueHours == 0 ? "before work begins" : "\(t.balanceDueHours) hours before start"
        if let total = totalCents {
            let balance = max(total - (depositCents ?? 0), 0)
            let what = depositCents == nil
                ? "The full Total Fee of \(money(balance))"
                : "The remaining balance of \(money(balance))"
            var clause = hoursText.map { "\(what) is due no later than \($0) before the scheduled start time." }
                ?? "\(what) is due on the scheduled date, before work begins."
            if let start = jobDay(job), let deadline, t.balanceDueHours > 0 {
                clause += " With a start on \(longDate(start)), the payment deadline is the same local time on \(longDate(deadline))."
            }
            output = replace(output, "Terms.BalanceLine", "\(money(balance)) — due \(whenShort)")
            output = replace(output, "Terms.BalanceClause", clause)
        } else {
            output = replace(output, "Terms.BalanceLine", blank("balance"))
            output = replace(output, "Terms.BalanceClause", blank("balance"))
        }
        output = replace(output, "Terms.BalanceDeadline", deadline.map {
            "\(longDate($0)), at ________ (\(whenShort))"
        } ?? capitalized(whenShort))

        // Cancellation tiers
        let refund14 = "within fourteen (14) calendar days after cancellation"
        func feeAmount(_ pct: Int) -> String {
            guard let total = totalCents else { return "\(pct)% of the Total Fee" }
            return "\(money(Int((Double(total) * Double(pct) / 100).rounded()))) (\(pct)% of the Total Fee)"
        }
        let earlyFee: String
        if let deposit = depositCents {
            earlyFee = "the cancellation fee is the \(money(deposit)) deposit, which Provider shall retain. Any amount paid beyond the deposit shall be refunded \(refund14)."
        } else {
            earlyFee = "no cancellation fee applies, and any payments received shall be refunded \(refund14)."
        }
        func tierFee(_ pct: Int) -> String {
            if pct >= 100 {
                return "the cancellation fee is \(feeAmount(pct)). No refund shall be issued, and any unpaid balance shall be paid by Client \(refund14)."
            }
            return "the cancellation fee is \(feeAmount(pct)). Provider shall retain payments received up to that amount; any amount paid beyond it shall be refunded, and any unpaid portion of the fee shall be paid by Client, \(refund14)."
        }
        output = replace(output, "Terms.CancelEarlyDays", "\(spelled(t.cancelEarlyDays)) (\(t.cancelEarlyDays))")
        output = replace(output, "Terms.CancelMidRange", "\(capitalized(spelled(t.cancelLateDays + 1))) (\(t.cancelLateDays + 1)) to \(spelled(t.cancelEarlyDays)) (\(t.cancelEarlyDays))")
        output = replace(output, "Terms.CancelLateDays", "\(capitalized(spelled(t.cancelLateDays))) (\(t.cancelLateDays))")
        output = replace(output, "Terms.CancelEarlyFee", earlyFee)
        output = replace(output, "Terms.CancelMidFee", tierFee(t.cancelMidPercent))
        output = replace(output, "Terms.CancelLateFee", tierFee(t.cancelLatePercent))
        output = replace(output, "Terms.CancellationSummary", t.summary(hasDeposit: depositCents != nil))

        // Governing law
        if t.governingState.isEmpty {
            output = replace(output, "Terms.GoverningLaw", "the laws of the state in which Provider principally operates")
            output = replace(output, "Terms.DisputeVenue", "a court of competent jurisdiction in that state")
        } else {
            output = replace(output, "Terms.GoverningLaw", "the laws of the State of \(t.governingState)")
            output = replace(output, "Terms.DisputeVenue", "a court of competent jurisdiction located in the State of \(t.governingState)")
        }
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

    /// "Name · email · phone" with only the parts that exist.
    private static func nameWithContact(name: String?, email: String?, phone: String?) -> String {
        [nonBlank(name), nonBlank(email), nonBlank(phone)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// The job's real start, nil while it still needs scheduling.
    private static func jobDay(_ job: Job?) -> Date? {
        guard let job, !job.needsScheduling else { return nil }
        return job.startDate
    }

    /// "Sunday, November 8, 2026"
    private static func longDate(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "EEEE, MMMM d, yyyy"
        return df.string(from: date)
    }

    /// 30 → "thirty", 48 → "forty-eight": contracts write a number in
    /// words and figures, "thirty (30) days".
    private static func spelled(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .spellOut
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }

    private static func capitalized(_ s: String) -> String {
        s.prefix(1).uppercased() + s.dropFirst()
    }

    /// 800000 → "Eight Thousand Dollars", 1250 → "Twelve Dollars and 50/100".
    private static func amountInWords(_ cents: Int) -> String {
        let whole = cents / 100
        let words = spelled(whole)
            .split(separator: " ")
            .map { $0.split(separator: "-").map { capitalized(String($0)) }.joined(separator: "-") }
            .joined(separator: " ")
        let unit = whole == 1 ? "Dollar" : "Dollars"
        let rest = cents % 100
        return rest == 0 ? "\(words) \(unit)" : "\(words) \(unit) and \(String(format: "%02d", rest))/100"
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

