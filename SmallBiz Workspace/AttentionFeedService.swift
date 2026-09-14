import Foundation
import SwiftData

/// What Today points at, so a tap can resolve to the exact record without a
/// second lookup — and so the ranking logic stays plain data, testable the
/// same way `QuickStartChecklist` already is.
enum AttentionKind: Equatable {
    case overdueInvoice(invoiceID: UUID)
    case unsignedContract(contractID: UUID)
    case pendingBookings(count: Int)
    case setupStep(QuickStartChecklist.Step)
}

struct AttentionItem: Identifiable, Equatable {
    /// Ordinal, not a UI color — Today ranks by this before anything else, the
    /// way the report's mockup put an overdue invoice ahead of a booking
    /// waiting on you, ahead of a contract waiting on the client.
    enum Severity: Int, Comparable {
        case critical
        case warning
        case info

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    let id: String
    let severity: Severity
    let title: String
    let subtitle: String
    let amountText: String?
    let kind: AttentionKind
}

/// Scans the business's own data for what actually needs a decision today —
/// the mechanism Today's whole pitch depends on. Deliberately synchronous and
/// SwiftData-only: bookings live server-side (`PortalBackend`), so their
/// count is folded in by the caller (`TodayView`, via `DashboardMetricsVM`,
/// which already fetches and caches them) rather than duplicating a network
/// fetch here just to keep this half testable without mocking a server.
enum AttentionFeedService {
    private static let currencyCode = Locale.current.currency?.identifier ?? "USD"

    @MainActor
    static func attentionItems(
        businessID: UUID?,
        context: ModelContext,
        checklist: QuickStartChecklist,
        pendingApprovalBookingCount: Int,
        now: Date = .now
    ) -> [AttentionItem] {
        guard let businessID else { return [] }

        var items: [AttentionItem] = []
        items.append(contentsOf: overdueInvoiceItems(businessID: businessID, context: context, now: now))
        items.append(contentsOf: unsignedContractItems(businessID: businessID, context: context))

        if pendingApprovalBookingCount > 0 {
            items.append(AttentionItem(
                id: "bookings-pending",
                severity: .warning,
                title: "Booking\(pendingApprovalBookingCount == 1 ? "" : "s") need\(pendingApprovalBookingCount == 1 ? "s" : "") approval",
                subtitle: "\(pendingApprovalBookingCount) waiting on you",
                amountText: nil,
                kind: .pendingBookings(count: pendingApprovalBookingCount)
            ))
        }

        if let nextStep = checklist.nextStep {
            items.append(AttentionItem(
                id: "setup-\(nextStep.rawValue)",
                severity: .info,
                title: nextStep.title,
                subtitle: nextStep.detail,
                amountText: nil,
                kind: .setupStep(nextStep)
            ))
        }

        // A plain sort on severity alone, relying on Swift's sort being stable:
        // each severity group was already appended in its own meaningful order
        // (most-overdue-first for invoices, oldest-sent-first for contracts), and
        // a stable sort preserves that instead of re-shuffling it alphabetically
        // by id the way a severity/id tiebreak would.
        return items.sorted { $0.severity < $1.severity }
    }

    @MainActor
    private static func overdueInvoiceItems(businessID: UUID, context: ModelContext, now: Date) -> [AttentionItem] {
        let descriptor = FetchDescriptor<Invoice>(
            predicate: #Predicate<Invoice> { invoice in
                invoice.businessID == businessID
            }
        )
        let invoices = (try? context.fetch(descriptor)) ?? []
        let calendar = Calendar.current

        let overdue = invoices.filter { invoice in
            invoice.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "estimate"
                && !invoice.isPaid
                && invoice.dueDate < now
                && !(invoice.items ?? []).isEmpty
        }

        return overdue
            .sorted { $0.dueDate < $1.dueDate }
            .map { invoice in
                let days = max(0, calendar.dateComponents([.day], from: invoice.dueDate, to: now).day ?? 0)
                let amount = invoice.total.formatted(.currency(code: currencyCode))
                return AttentionItem(
                    id: "invoice-overdue-\(invoice.id.uuidString)",
                    severity: .critical,
                    title: "Overdue \u{2022} \(invoice.displayClientName)",
                    subtitle: days == 0 ? "Due today" : "\(days) day\(days == 1 ? "" : "s") late",
                    amountText: amount,
                    kind: .overdueInvoice(invoiceID: invoice.id)
                )
            }
    }

    @MainActor
    private static func unsignedContractItems(businessID: UUID, context: ModelContext) -> [AttentionItem] {
        let descriptor = FetchDescriptor<Contract>(
            predicate: #Predicate<Contract> { contract in
                contract.businessID == businessID
            }
        )
        let contracts = (try? context.fetch(descriptor)) ?? []

        let awaitingSignature = contracts.filter { $0.statusRaw == ContractStatus.sent.rawValue }

        return awaitingSignature
            .sorted { $0.updatedAt < $1.updatedAt }
            .map { contract in
                let name = contract.resolvedClient?.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let clientText = (name?.isEmpty ?? true) ? "No client" : name!
                let title = contract.title.trimmingCharacters(in: .whitespacesAndNewlines)
                return AttentionItem(
                    id: "contract-awaiting-\(contract.id.uuidString)",
                    severity: .warning,
                    title: "Awaiting signature",
                    subtitle: title.isEmpty ? clientText : "\(title) \u{2022} \(clientText)",
                    amountText: nil,
                    kind: .unsignedContract(contractID: contract.id)
                )
            }
    }
}
