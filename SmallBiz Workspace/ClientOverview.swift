//
//  ClientOverview.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData

/// What the client screen and the Clients list say about one client: what
/// they owe, what to do next, and their work, worked out from the records
/// in one place so both agree and the rules can be tested without a view.
@MainActor
struct ClientOverview {
    let client: Client
    let invoices: [Invoice]
    let jobs: [Job]
    let contracts: [Contract]
    let now: Date

    init(client: Client, invoices: [Invoice], jobs: [Job], contracts: [Contract], now: Date = .now) {
        self.client = client
        self.invoices = invoices.filter { $0.client?.id == client.id || $0.clientID == client.id }
        self.jobs = jobs.filter { $0.clientID == client.id }
        self.contracts = contracts.filter { ClientContractSummaryLogic.belongsToClient($0, clientID: client.id) }
        self.now = now
    }

    // MARK: Money

    private var billed: [Invoice] { invoices.filter { $0.documentType != "estimate" } }

    /// Sent and unpaid. Drafts aren't owed yet: the client hasn't seen them.
    var openInvoices: [Invoice] {
        billed.filter { $0.wasSent && !$0.isPaid && $0.balanceDueCents > 0 }
    }

    var owedCents: Int { openInvoices.reduce(0) { $0 + $1.balanceDueCents } }

    var overdueInvoices: [Invoice] {
        openInvoices.filter(\.isOverdue).sorted { $0.dueDate < $1.dueDate }
    }

    var overdueCents: Int { overdueInvoices.reduce(0) { $0 + $1.balanceDueCents } }

    /// Money received this calendar year. Recorded payments count on the day
    /// they were paid; an invoice marked paid the old way, with no payment
    /// rows, counts on its issue date.
    var paidThisYearCents: Int {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: now)
        return billed.reduce(0) { total, invoice in
            let payments = invoice.payments ?? []
            if payments.isEmpty {
                guard invoice.isPaid, calendar.component(.year, from: invoice.issueDate) == year else { return total }
                return total + invoice.paidCents
            }
            let thisYear = payments
                .filter { calendar.component(.year, from: $0.paidAt) == year }
                .reduce(0) { $0 + max(0, $1.amountCents) }
            return total + thisYear
        }
    }

    var hasBillingHistory: Bool { !billed.isEmpty }

    /// When they became a client: the recorded date, or for older clients the
    /// first thing done for them.
    var clientSince: Date? {
        if let created = client.createdAt { return created }
        let dates = invoices.map(\.issueDate) + jobs.map(\.startDate) + contracts.map(\.createdAt)
        return dates.min()
    }

    var lastActivity: Date? {
        let dates = invoices.map(\.issueDate) + jobs.map(\.startDate) + contracts.map(\.updatedAt)
        return dates.max()
    }

    // MARK: Next step

    enum NextStep {
        case overdue(Invoice)
        case invoiceFinishedJob(Job)
        case scheduleJob(Job)
        case finishDraft(Invoice)
        case awaitingEstimate(Invoice)
        case awaitingPayment(Invoice)
        case upcomingJob(Job)
        case addContact
        case startWork
    }

    /// The one thing most worth doing for this client, most urgent first:
    /// money that's late, finished work not yet billed, work to schedule,
    /// paperwork to send, then things waiting on the client.
    var nextStep: NextStep {
        if let late = overdueInvoices.first { return .overdue(late) }

        let activeJobs = jobs.filter { job in
            let status = JobDisplayStatus(job)
            return status != .canceled
        }
        if let done = activeJobs
            .filter({ JobDisplayStatus($0) == .completed && !hasFinalInvoice($0) })
            .sorted(by: { ($0.completedAt ?? $0.startDate) > ($1.completedAt ?? $1.startDate) })
            .first {
            return .invoiceFinishedJob(done)
        }
        if let unscheduled = activeJobs.first(where: { JobDisplayStatus($0) == .needsScheduling }) {
            return .scheduleJob(unscheduled)
        }

        if let draft = invoices
            .filter({ $0.documentType == "estimate" ? $0.isUnsentEstimate : !$0.wasSent })
            .sorted(by: { $0.issueDate > $1.issueDate })
            .first {
            return .finishDraft(draft)
        }
        if let waiting = invoices
            .filter({ $0.documentType == "estimate" && $0.estimateStatus.lowercased() == "sent" })
            .sorted(by: { $0.issueDate < $1.issueDate })
            .first {
            return .awaitingEstimate(waiting)
        }
        if let due = openInvoices.sorted(by: { $0.dueDate < $1.dueDate }).first {
            return .awaitingPayment(due)
        }
        if let next = activeJobs
            .filter({ [.inProgress, .scheduled].contains(JobDisplayStatus($0)) })
            .sorted(by: { $0.startDate < $1.startDate })
            .first {
            return .upcomingJob(next)
        }

        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = client.phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if email.isEmpty && phone.isEmpty { return .addContact }
        return .startWork
    }

    /// A real invoice for the work, not the deposit invoice.
    private func hasFinalInvoice(_ job: Job) -> Bool {
        invoices.contains {
            $0.job?.id == job.id
                && $0.documentType != "estimate"
                && $0.id.uuidString != job.depositInvoiceId
        }
    }

    // MARK: Work

    var workItems: [ClientWorkItem] {
        let items = invoices.map(ClientWorkItem.init(document:))
            + jobs.map(ClientWorkItem.init(job:))
            + contracts.map(ClientWorkItem.init(contract:))
        return items.sorted { lhs, rhs in
            if lhs.isOpen != rhs.isOpen { return lhs.isOpen }
            return lhs.date > rhs.date
        }
    }
}

/// One estimate, invoice, job or contract on the client screen.
struct ClientWorkItem: Identifiable {
    enum Kind: String, CaseIterable {
        case estimate = "Estimates"
        case invoice = "Invoices"
        case job = "Jobs"
        case contract = "Contracts"

        var systemImage: String {
            switch self {
            case .estimate: return "doc.text.magnifyingglass"
            case .invoice: return "doc.plaintext"
            case .job: return "wrench.and.screwdriver"
            case .contract: return "signature"
            }
        }
    }

    enum Target {
        case document(Invoice)
        case job(Job)
        case contract(Contract)
    }

    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let status: String
    let statusColor: Color
    let date: Date
    /// Still needs something from someone: not paid, decided, done or signed.
    let isOpen: Bool
    let target: Target

    @MainActor
    init(document: Invoice) {
        id = "doc-\(document.id.uuidString)"
        target = .document(document)
        date = document.issueDate
        let amount = InvoicePaymentService.currency(document.totalCents)
        if document.documentType == "estimate" {
            kind = .estimate
            title = Self.documentName(document)
            detail = amount
            switch document.estimateStatus.lowercased() {
            case "sent":
                status = "Sent"; statusColor = SBWTheme.brandBlue; isOpen = true
            case "accepted":
                status = "Accepted"; statusColor = SBWTheme.brandGreen; isOpen = false
            case "declined":
                status = "Declined"; statusColor = .red; isOpen = false
            default:
                status = "Draft"; statusColor = .secondary; isOpen = true
            }
        } else {
            kind = .invoice
            title = Self.documentName(document)
            let recorded = (document.payments ?? []).reduce(0) { $0 + $1.amountCents }
            if document.isPaid || (document.wasSent && document.totalCents > 0 && document.balanceDueCents == 0) {
                status = "Paid"; statusColor = SBWTheme.brandGreen; isOpen = false
                detail = amount
            } else if !document.wasSent {
                status = "Draft"; statusColor = .secondary; isOpen = true
                detail = amount
            } else if document.isOverdue {
                status = "Overdue"; statusColor = .red; isOpen = true
                detail = "\(InvoicePaymentService.currency(document.balanceDueCents)) due"
            } else if recorded > 0 {
                status = "Part paid"; statusColor = .orange; isOpen = true
                detail = "\(InvoicePaymentService.currency(document.balanceDueCents)) left"
            } else {
                status = "Sent"; statusColor = SBWTheme.brandBlue; isOpen = true
                detail = "\(amount) · due \(document.dueDate.formatted(date: .abbreviated, time: .omitted))"
            }
        }
    }

    /// "Estimate 1042", or the name as given when it already says what it
    /// is ("TF Estimate", not "Estimate TF Estimate").
    static func documentName(_ document: Invoice, lowercased: Bool = false) -> String {
        let noun = document.documentType == "estimate" ? "Estimate" : "Invoice"
        let number = document.invoiceNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if number.localizedCaseInsensitiveContains(noun) { return number }
        let word = lowercased ? noun.lowercased() : noun
        return number.isEmpty ? word : "\(word) \(number)"
    }

    init(job: Job) {
        id = "job-\(job.id.uuidString)"
        kind = .job
        target = .job(job)
        date = job.startDate
        let trimmed = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Job" : trimmed
        let display = JobDisplayStatus(job)
        status = display.label
        statusColor = display.foreground
        isOpen = display != .completed && display != .canceled
        detail = display == .needsScheduling
            ? "Not on the calendar yet"
            : job.startDate.formatted(date: .abbreviated, time: .shortened)
    }

    init(contract: Contract) {
        id = "contract-\(contract.id.uuidString)"
        kind = .contract
        target = .contract(contract)
        date = contract.updatedAt
        let trimmed = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
        title = trimmed.isEmpty ? "Contract" : trimmed
        detail = contract.updatedAt.formatted(date: .abbreviated, time: .omitted)
        switch contract.status {
        case .draft: status = "Draft"; statusColor = .secondary; isOpen = true
        case .sent: status = "Sent"; statusColor = SBWTheme.brandBlue; isOpen = true
        case .signed: status = "Signed"; statusColor = SBWTheme.brandGreen; isOpen = false
        case .cancelled: status = "Canceled"; statusColor = .red; isOpen = false
        }
    }
}

extension Client {
    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Client" : trimmed
    }

    /// Up to two letters for the avatar: first and last word.
    var initials: String {
        let words = name.split(whereSeparator: { $0.isWhitespace }).filter { $0.first?.isLetter == true }
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let last = words.last?.first else { return String(first).uppercased() }
        return (String(first) + String(last)).uppercased()
    }
}

/// Call, text, email and directions for a client, from the client screen and
/// the list's swipe actions.
enum ClientContact {
    static func phoneURL(_ client: Client, scheme: String) -> URL? {
        let digits = client.phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "\(scheme):\(digits)")
    }

    static func emailURL(_ client: Client) -> URL? {
        let email = client.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@") else { return nil }
        return URL(string: "mailto:\(email)")
    }

    static func directionsURL(_ client: Client) -> URL? {
        let address = client.address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty,
              let query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "http://maps.apple.com/?daddr=\(query)")
    }
}

/// Delete and archive, shared by the client screen and the list.
@MainActor
enum ClientRecords {
    /// Every invoice and contract keeps its own copy of who it was for, so
    /// deleting the client doesn't blank them. Take one last snapshot for
    /// anything that somehow missed it.
    static func delete(_ clients: [Client], context: ModelContext) throws {
        for client in clients {
            for invoice in client.invoices ?? [] {
                invoice.captureClientSnapshotIfNeeded()
            }
            for contract in client.contracts ?? [] {
                contract.captureClientSnapshotIfNeeded()
            }
            context.delete(client)
        }
        try context.save()
    }

    static func setArchived(_ archived: Bool, for client: Client, context: ModelContext) {
        client.archivedAt = archived ? .now : nil
        try? context.save()
    }
}

/// Which contracts are a client's: linked directly, or through an invoice,
/// estimate or job made for them.
enum ClientContractSummaryLogic {
    static func visibleContracts(in contracts: [Contract], businessID: UUID, clientID: UUID) -> [Contract] {
        contracts.filter { isContract($0, scopedTo: businessID, clientID: clientID) }
    }

    static func isContract(_ contract: Contract, scopedTo businessID: UUID, clientID: UUID) -> Bool {
        contract.businessID == businessID && belongsToClient(contract, clientID: clientID)
    }

    static func belongsToClient(_ contract: Contract, clientID: UUID) -> Bool {
        if contract.client?.id == clientID { return true }
        if contract.invoice?.client?.id == clientID || contract.invoice?.clientID == clientID { return true }
        if contract.estimate?.client?.id == clientID || contract.estimate?.clientID == clientID { return true }
        if contract.job?.clientID == clientID { return true }
        return false
    }
}
