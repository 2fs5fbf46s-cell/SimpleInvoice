import Foundation
import Combine

@MainActor
final class DashboardMetricsVM: ObservableObject {
    @Published private(set) var weeklyPaidCents: Int = 0
    @Published private(set) var monthlyPaidCents: Int = 0
    @Published private(set) var upcomingJobCount: Int = 0

    private struct BookingCacheEntry {
        let requests: [BookingRequestDTO]
        let fetchedAt: Date
    }

    private var bookingRequestsCacheByBusiness: [UUID: BookingCacheEntry] = [:]
    private var inFlightFetchByBusiness: [UUID: Task<[BookingRequestDTO], Error>] = [:]
    private var lastBusinessID: UUID?
    private let cacheTTLSeconds: TimeInterval = 60

    func refresh(
        invoices: [Invoice],
        jobs: [Job],
        businessID: UUID?,
        forceRemote: Bool,
        now: Date = Date()
    ) async {
        guard let businessID else {
            lastBusinessID = nil
            weeklyPaidCents = 0
            monthlyPaidCents = 0
            upcomingJobCount = 0
            return
        }

        let businessChanged = (lastBusinessID != businessID)
        lastBusinessID = businessID

        let cachedEntry = bookingRequestsCacheByBusiness[businessID]
        let cacheExpired = cachedEntry.map { now.timeIntervalSince($0.fetchedAt) > cacheTTLSeconds } ?? true
        let shouldFetchRemote = forceRemote || businessChanged || cacheExpired

        var bookingRequests = cachedEntry?.requests ?? []

        if shouldFetchRemote {
            if let inFlight = inFlightFetchByBusiness[businessID] {
                if let fetched = try? await inFlight.value {
                    bookingRequests = fetched
                }
            } else {
                let task = Task { try await PortalBackend.shared.fetchBookingRequests(businessId: businessID) }
                inFlightFetchByBusiness[businessID] = task
                defer { inFlightFetchByBusiness[businessID] = nil }

                do {
                    let fetched = try await task.value
                    bookingRequests = fetched
                    bookingRequestsCacheByBusiness[businessID] = BookingCacheEntry(
                        requests: fetched,
                        fetchedAt: now
                    )
                } catch {
                    // Keep cached data when remote fetch fails.
                }
            }
        }

        let metrics = DashboardMetricsService.compute(
            invoices: invoices,
            jobs: jobs,
            bookingRequests: bookingRequests,
            businessID: businessID,
            now: now
        )
        weeklyPaidCents = metrics.weeklyPaidCents
        monthlyPaidCents = metrics.monthlyPaidCents
        upcomingJobCount = metrics.upcomingJobCount
    }
}

private struct DashboardMetrics {
    let weeklyPaidCents: Int
    let monthlyPaidCents: Int
    let upcomingJobCount: Int
}

private enum DashboardMetricsService {
    static func compute(
        invoices: [Invoice],
        jobs: [Job],
        bookingRequests: [BookingRequestDTO],
        businessID: UUID,
        now: Date
    ) -> DashboardMetrics {
        let calendar = Calendar.current
        let weeklyStart = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let monthInterval = calendar.dateInterval(of: .month, for: now)
        let businessIDString = businessID.uuidString.lowercased()

        var weeklyInvoicePaidCents = 0
        var monthlyInvoicePaidCents = 0

        for invoice in invoices where invoice.businessID == businessID {
            guard invoice.isPaid else { continue }
            if invoice.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "estimate" {
                continue
            }

            guard let paidDate = resolvedPaidDate(for: invoice) else { continue }
            let amountCents = max(0, Int((invoice.total * 100).rounded()))

            if paidDate >= weeklyStart && paidDate <= now {
                weeklyInvoicePaidCents += amountCents
            }
            if let monthInterval, monthInterval.contains(paidDate) {
                monthlyInvoicePaidCents += amountCents
            }
        }

        var weeklyDepositsCents = 0
        var monthlyDepositsCents = 0

        for request in bookingRequests {
            if request.businessId.lowercased() != businessIDString { continue }
            guard let depositAmountCents = request.depositAmountCents, depositAmountCents > 0 else { continue }
            guard let depositPaidAtMs = request.depositPaidAtMs else { continue }

            let paidDate = Date(timeIntervalSince1970: TimeInterval(depositPaidAtMs) / 1000.0)
            if paidDate >= weeklyStart && paidDate <= now {
                weeklyDepositsCents += depositAmountCents
            }
            if let monthInterval, monthInterval.contains(paidDate) {
                monthlyDepositsCents += depositAmountCents
            }
        }

        let upcomingJobCount = jobs
            .filter { $0.businessID == businessID }
            .filter { $0.startDate >= now }
            .filter { !isCompleted($0) }
            .count

        return DashboardMetrics(
            weeklyPaidCents: weeklyInvoicePaidCents + weeklyDepositsCents,
            monthlyPaidCents: monthlyInvoicePaidCents + monthlyDepositsCents,
            upcomingJobCount: upcomingJobCount
        )
    }

    private static func isCompleted(_ job: Job) -> Bool {
        let normalizedStatus = job.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedStatus == "completed" {
            return true
        }

        if let stage = JobStage(rawValue: job.stageRaw), stage == .completed {
            return true
        }
        return false
    }

    private static func resolvedPaidDate(for invoice: Invoice) -> Date? {
        guard invoice.isPaid else { return nil }

        let mirror = Mirror(reflecting: invoice)
        if let date = readDate(from: mirror, key: "paidAt") {
            return date
        }
        if let date = readDate(from: mirror, key: "paidDate") {
            return date
        }
        if let paidAtMs = readInt(from: mirror, key: "paidAtMs"), paidAtMs > 0 {
            return Date(timeIntervalSince1970: TimeInterval(paidAtMs) / 1000.0)
        }

        // Safe analytics-only fallback when no paid date field exists.
        return invoice.issueDate
    }

    private static func readValue(from mirror: Mirror, key: String) -> Any? {
        mirror.children.first(where: { $0.label == key })?.value
    }

    private static func unwrap(_ value: Any) -> Any {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value as Any
    }

    private static func readDate(from mirror: Mirror, key: String) -> Date? {
        guard let value = readValue(from: mirror, key: key) else { return nil }
        let unwrapped = unwrap(value)
        if let date = unwrapped as? Date {
            return date
        }
        if let string = unwrapped as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return ISO8601DateFormatter().date(from: trimmed)
        }
        return nil
    }

    private static func readInt(from mirror: Mirror, key: String) -> Int? {
        guard let value = readValue(from: mirror, key: key) else { return nil }
        let unwrapped = unwrap(value)
        if let intValue = unwrapped as? Int {
            return intValue
        }
        if let int64Value = unwrapped as? Int64 {
            return Int(int64Value)
        }
        if let doubleValue = unwrapped as? Double {
            return Int(doubleValue)
        }
        if let string = unwrapped as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed) {
                return intValue
            }
            if let doubleValue = Double(trimmed) {
                return Int(doubleValue)
            }
        }
        return nil
    }
}
