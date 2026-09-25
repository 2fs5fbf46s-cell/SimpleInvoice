import Foundation
import SwiftData

/// What a Needs You row points at, so a tap or its button resolves to the
/// exact record.
enum AttentionKind: Equatable {
    case overdueInvoice(invoiceID: UUID)
    case bookingRequests(count: Int, first: BookingRequestItem?)
    case manualPayment(invoiceID: UUID)
    case finishedJob(jobID: UUID)
    case scheduleJob(jobID: UUID)
    case contractWaiting(contractID: UUID)
    case recurringWentOut(count: Int)
}

/// The row's button: the obvious next step, done right there.
enum AttentionAction: Equatable {
    case remind, answer, confirm, bill, schedule, remindContract, gotIt

    var title: String {
        switch self {
        case .remind, .remindContract: return "Remind"
        case .answer: return "Answer"
        case .confirm: return "Confirm"
        case .bill: return "Bill"
        case .schedule: return "Schedule"
        case .gotIt: return "Got It"
        }
    }
}

struct AttentionItem: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case critical, warning, info
        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    let severity: Severity
    let title: String
    let subtitle: String
    let kind: AttentionKind
    let action: AttentionAction
}

/// What only the server knows, fetched by Today and passed in.
struct TodayRemoteState: Equatable {
    var pendingBookings: [BookingRequestItem] = []
    var manualReports: [ManualPaymentReportDTO] = []
}

/// What needs the owner today, most urgent first:
///
/// 1. Overdue invoices (critical).
/// 2. Things only the owner can move: booking requests to answer, payments a
///    client says they sent, finished jobs not billed, accepted work with
///    no date.
/// 3. Things waiting on someone else long enough to nudge: contracts out 4+
///    days, and recurring invoices that went out on their own.
///
/// It used to call unsent drafts "overdue" (at the invoice's full total, from
/// the middle of the due date), list every contract the moment it was sent,
/// tell the owner to "review before sending" recurring invoices that had
/// already gone out, and end with a setup step that never went away (setup
/// is the Business sheet's Next step card now).
enum AttentionFeedService {
    static let contractNudgeDays = 4

    @MainActor
    static func attentionItems(
        businessID: UUID?,
        context: ModelContext,
        remote: TodayRemoteState,
        now: Date = .now
    ) -> [AttentionItem] {
        guard let businessID else { return [] }
        let invoices = (try? context.fetch(FetchDescriptor<Invoice>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
        let jobs = (try? context.fetch(FetchDescriptor<Job>(predicate: #Predicate { $0.businessID == businessID }))) ?? []
        let contracts = (try? context.fetch(FetchDescriptor<Contract>(predicate: #Predicate { $0.businessID == businessID }))) ?? []

        var items: [AttentionItem] = []
        items += overdue(invoices, now: now)
        items += bookings(remote.pendingBookings)
        items += manualPayments(remote.manualReports, invoices: invoices)
        items += finishedJobs(jobs, invoices: invoices)
        items += unscheduledJobs(jobs)
        items += waitingContracts(contracts, now: now)
        items += recurring(invoices)
        return items.enumerated()
            .sorted { ($0.element.severity, $0.offset) < ($1.element.severity, $1.offset) }
            .map(\.element)
    }

    // MARK: - Items

    private static func overdue(_ invoices: [Invoice], now: Date) -> [AttentionItem] {
        let calendar = Calendar.current
        return MoneyMath.open(invoices)
            .filter(\.isOverdue)
            .sorted { $0.dueDate < $1.dueDate }
            .map { invoice in
                let days = max(1, calendar.dateComponents([.day], from: calendar.startOfDay(for: invoice.dueDate), to: calendar.startOfDay(for: now)).day ?? 1)
                return AttentionItem(
                    id: "overdue-\(invoice.id.uuidString)",
                    severity: .critical,
                    title: "\(invoice.displayClientName) is \(days) day\(days == 1 ? "" : "s") late",
                    subtitle: "\(ClientWorkItem.documentName(invoice)) · \(InvoicePaymentService.currency(invoice.balanceDueCents))",
                    kind: .overdueInvoice(invoiceID: invoice.id),
                    action: .remind
                )
            }
    }

    private static func bookings(_ pending: [BookingRequestItem]) -> [AttentionItem] {
        guard let first = pending.sorted(by: { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }).first else { return [] }
        let count = pending.count
        return [AttentionItem(
            id: "bookings",
            severity: .warning,
            title: count == 1 ? "\(first.customerName) wants to book" : "\(count) booking requests",
            subtitle: "\(first.serviceName) · \(first.whenText)",
            kind: .bookingRequests(count: count, first: count == 1 ? first : nil),
            action: .answer
        )]
    }

    private static func manualPayments(_ reports: [ManualPaymentReportDTO], invoices: [Invoice]) -> [AttentionItem] {
        reports.filter { $0.status == "pending" }.compactMap { report in
            guard let id = UUID(uuidString: report.invoiceId), let invoice = invoices.first(where: { $0.id == id }) else { return nil }
            let who = (report.payerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return AttentionItem(
                id: "manual-\(report.id)",
                severity: .warning,
                title: "\(who.isEmpty ? invoice.displayClientName : who) says they paid by \(methodName(report.method))",
                subtitle: "\(InvoicePaymentService.currency(report.amountCents)) · check it arrived",
                kind: .manualPayment(invoiceID: invoice.id),
                action: .confirm
            )
        }
    }

    private static func finishedJobs(_ jobs: [Job], invoices: [Invoice]) -> [AttentionItem] {
        jobs.filter { job in
            JobDisplayStatus(job) == .completed
                && !invoices.contains { $0.job?.id == job.id && $0.documentType != "estimate" && $0.id.uuidString != job.depositInvoiceId }
        }
        .sorted { ($0.completedAt ?? $0.startDate) > ($1.completedAt ?? $1.startDate) }
        .map { job in
            AttentionItem(
                id: "bill-\(job.id.uuidString)",
                severity: .warning,
                title: "\(jobName(job)) is done",
                subtitle: "Not billed yet",
                kind: .finishedJob(jobID: job.id),
                action: .bill
            )
        }
    }

    private static func unscheduledJobs(_ jobs: [Job]) -> [AttentionItem] {
        jobs.filter { JobDisplayStatus($0) == .needsScheduling }.map { job in
            AttentionItem(
                id: "schedule-\(job.id.uuidString)",
                severity: .warning,
                title: "\(jobName(job)) needs a date",
                subtitle: job.quotedTotalCents.map { "\(InvoicePaymentService.currency($0)) · accepted" } ?? "Accepted",
                kind: .scheduleJob(jobID: job.id),
                action: .schedule
            )
        }
    }

    private static func waitingContracts(_ contracts: [Contract], now: Date) -> [AttentionItem] {
        let calendar = Calendar.current
        return contracts
            .filter { $0.status == .sent }
            .compactMap { contract -> (Contract, Int)? in
                // Waiting since the last nudge: a reminder restarts the clock.
                guard let since = contract.lastReminderAt ?? contract.sentAt else { return nil }
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: since), to: calendar.startOfDay(for: now)).day ?? 0
                return days >= contractNudgeDays ? (contract, days) : nil
            }
            .sorted { $0.1 > $1.1 }
            .map { contract, days in
                let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return AttentionItem(
                    id: "contract-\(contract.id.uuidString)",
                    severity: .info,
                    title: "\(contract.displayClientName) hasn't signed yet",
                    subtitle: "\(title.isEmpty ? "Contract" : title) · \(days) days",
                    kind: .contractWaiting(contractID: contract.id),
                    action: .remindContract
                )
            }
    }

    private static func recurring(_ invoices: [Invoice]) -> [AttentionItem] {
        let count = invoices.filter { $0.isRecurringGenerated && $0.recurringReviewedAt == nil }.count
        guard count > 0 else { return [] }
        return [AttentionItem(
            id: "recurring",
            severity: .info,
            title: count == 1 ? "A recurring invoice went out" : "\(count) recurring invoices went out",
            subtitle: "Already in your clients' portals",
            kind: .recurringWentOut(count: count),
            action: .gotIt
        )]
    }

    // MARK: - Helpers

    static func jobName(_ job: Job) -> String {
        let title = job.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "A job" : title
    }

    static func methodName(_ method: String) -> String {
        switch method {
        case "cashapp": return "Cash App"
        case "venmo": return "Venmo"
        case "square": return "Square"
        case "ach": return "bank transfer"
        case "paypal_fallback": return "PayPal"
        default: return method.capitalized
        }
    }
}
