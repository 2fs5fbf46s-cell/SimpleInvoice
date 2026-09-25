//
//  MoneyMath.swift
//  SmallBiz Workspace
//

import Foundation

/// Every money number in the app, worked out one way.
///
/// Money, Insights, Today and each client used to count differently:
/// Insights called any unpaid invoice with line items "outstanding" (drafts
/// the client never saw included) and ignored part payments; "Paid this
/// week" was dated by the invoice's issue date, found by reflection on
/// fields the invoice doesn't have; Today added booking deposits Insights
/// left out. The rules now:
///
/// - Owed: sent, not paid, what's still due.
/// - Overdue: owed and past the due date (from the start of today).
/// - Money in: each payment on the day it was paid; an invoice marked paid
///   with no payment recorded, on the day it was sent; a paid booking
///   deposit on the day it was paid, unless the owner marked it refunded.
enum MoneyMath {
    struct Received: Equatable, Identifiable {
        let date: Date
        let amountCents: Int
        let clientName: String
        let source: Source
        enum Source: Equatable { case payment, markedPaid, bookingDeposit }
        var id: String { "\(date.timeIntervalSince1970)-\(amountCents)-\(clientName)" }
    }

    struct Tally: Equatable {
        var cents = 0
        var count = 0
        static let zero = Tally()
    }

    // MARK: Owed

    static func billed(_ invoices: [Invoice]) -> [Invoice] {
        invoices.filter { $0.documentType != "estimate" }
    }

    static func open(_ invoices: [Invoice]) -> [Invoice] {
        billed(invoices).filter { $0.wasSent && !$0.isPaid && $0.balanceDueCents > 0 }
    }

    static func owed(_ invoices: [Invoice]) -> Tally {
        tally(open(invoices))
    }

    static func overdue(_ invoices: [Invoice]) -> Tally {
        tally(open(invoices).filter(\.isOverdue))
    }

    private static func tally(_ invoices: [Invoice]) -> Tally {
        Tally(cents: invoices.reduce(0) { $0 + $1.balanceDueCents }, count: invoices.count)
    }

    // MARK: Money in

    static func received(invoices: [Invoice], jobs: [Job]) -> [Received] {
        var out: [Received] = []
        for invoice in billed(invoices) {
            let payments = invoice.payments ?? []
            if payments.isEmpty {
                guard invoice.isPaid, invoice.totalCents > 0 else { continue }
                out.append(Received(
                    date: invoice.sentAt ?? invoice.issueDate,
                    amountCents: invoice.totalCents,
                    clientName: invoice.displayClientName,
                    source: .markedPaid
                ))
            } else {
                for payment in payments where payment.amountCents > 0 {
                    out.append(Received(
                        date: payment.paidAt,
                        amountCents: payment.amountCents,
                        clientName: invoice.displayClientName,
                        source: .payment
                    ))
                }
            }
        }
        // Booking deposits are paid on the booking page, not against an
        // invoice on this phone; the booking's job carries them. (Estimate
        // deposits have their own invoice, counted above.)
        for job in jobs where job.sourceBookingRequestId != nil && job.depositRefundedAt == nil {
            guard let ms = job.depositPaidAtMs, ms > 0, let cents = job.depositAmountCents, cents > 0 else { continue }
            out.append(Received(
                date: Date(timeIntervalSince1970: TimeInterval(ms) / 1000),
                amountCents: cents,
                clientName: job.title,
                source: .bookingDeposit
            ))
        }
        return out.sorted { $0.date > $1.date }
    }

    static func tally(_ received: [Received], in interval: DateInterval) -> Tally {
        let hits = received.filter { interval.contains($0.date) }
        return Tally(cents: hits.reduce(0) { $0 + $1.amountCents }, count: hits.count)
    }

    static func thisMonth(_ now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: now, duration: 0)
    }

    /// The last `days` days up to now, today included.
    static func lastDays(_ days: Int, now: Date = .now, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now)) ?? now
        return DateInterval(start: start, end: max(start, now))
    }

    /// Money in per week, oldest first, the current week last.
    static func weekly(_ received: [Received], weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [(start: Date, cents: Int)] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return (0..<weeks).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek.start),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            let cents = tally(received, in: DateInterval(start: start, end: end)).cents
            return (start, cents)
        }
    }

    // MARK: Who owes you

    struct ClientBalance: Equatable, Identifiable {
        /// Nil for invoices with no client.
        let clientID: UUID?
        let name: String
        let owedCents: Int
        let invoiceCount: Int
        let overdueCount: Int
        var id: String { clientID?.uuidString ?? "no-client" }
    }

    static func byClient(_ invoices: [Invoice]) -> [ClientBalance] {
        let groups = Dictionary(grouping: open(invoices)) { $0.client?.id ?? $0.clientID }
        return groups.map { id, list in
            ClientBalance(
                clientID: id,
                name: id == nil ? "No client" : (list.first?.displayClientName ?? "Client"),
                owedCents: list.reduce(0) { $0 + $1.balanceDueCents },
                invoiceCount: list.count,
                overdueCount: list.filter(\.isOverdue).count
            )
        }
        .sorted { $0.owedCents > $1.owedCents }
    }

    // MARK: Expenses

    static func spent(_ expenses: [Expense], in interval: DateInterval) -> Tally {
        let hits = expenses.filter { interval.contains($0.date) }
        return Tally(cents: hits.reduce(0) { $0 + $1.amountCents }, count: hits.count)
    }

    static func deductible(_ expenses: [Expense], in interval: DateInterval) -> Int {
        expenses.filter { $0.isTaxDeductible && interval.contains($0.date) }.reduce(0) { $0 + $1.amountCents }
    }
}
