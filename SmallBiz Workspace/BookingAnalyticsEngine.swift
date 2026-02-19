import Foundation

enum BookingAnalyticsEngine {
    static func buildSnapshot(
        bookingRequests: [BookingRequestItem],
        invoices: [Invoice],
        jobs: [Job],
        businessId: UUID,
        timeRange: BookingAnalyticsRange,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> BookingAnalyticsSnapshot {
        _ = jobs // Reserved for future job-derived metrics.

        let start = timeRange.periodStart(now: now, calendar: calendar)
        let inRangeBookings = bookingRequests
            .filter { normalizedBusinessId($0.businessId) == businessId }
            .filter { bookingDate($0) >= start && bookingDate($0) <= now }

        let totalRequests = inRangeBookings.count
        let pendingCount = inRangeBookings.filter { normalizedStatus($0.status) == "pending" }.count
        let approvedCount = inRangeBookings.filter { normalizedStatus($0.status) == "approved" }.count
        let declinedCount = inRangeBookings.filter { normalizedStatus($0.status) == "declined" }.count
        let depositRequestedCount = inRangeBookings.filter { hasDepositRequested($0) }.count
        let depositsPaidCount = inRangeBookings.filter { hasDepositPaid($0) }.count

        let depositRevenueCents = inRangeBookings.reduce(0) { partial, booking in
            guard hasDepositPaid(booking) else { return partial }
            return partial + max(0, booking.depositAmountCents ?? 0)
        }

        let paidInvoiceRevenueCents = invoices
            .filter { $0.businessID == businessId }
            .filter { $0.documentType == "invoice" }
            .filter {
                let source = ($0.sourceBookingRequestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !source.isEmpty
            }
            .filter { $0.isPaid }
            .filter { $0.issueDate >= start && $0.issueDate <= now }
            .reduce(0) { partial, invoice in
                partial + Int((invoice.total * 100.0).rounded())
            }

        let totalRevenueCents = max(0, depositRevenueCents) + max(0, paidInvoiceRevenueCents)

        let conversionRate = safeRate(numerator: approvedCount, denominator: totalRequests)
        let depositConversionRate = safeRate(numerator: depositsPaidCount, denominator: depositRequestedCount)

        let trend = buildTrend(
            bookings: inRangeBookings,
            timeRange: timeRange,
            start: start,
            end: now,
            calendar: calendar
        )

        let funnel = buildFunnel(
            totalRequests: totalRequests,
            depositRequestedCount: depositRequestedCount,
            depositsPaidCount: depositsPaidCount,
            approvedCount: approvedCount
        )

        let topServices = buildTopServices(bookings: inRangeBookings)
        let recentActivity = inRangeBookings
            .sorted { bookingDate($0) > bookingDate($1) }
            .prefix(8)
            .map { $0 }

        let delta = buildDelta(
            bookingRequests: bookingRequests,
            invoices: invoices,
            businessId: businessId,
            timeRange: timeRange,
            now: now,
            calendar: calendar
        )

        return BookingAnalyticsSnapshot(
            range: timeRange,
            generatedAt: now,
            totalRequests: totalRequests,
            pendingCount: pendingCount,
            approvedCount: approvedCount,
            declinedCount: declinedCount,
            depositRequestedCount: depositRequestedCount,
            depositsPaidCount: depositsPaidCount,
            conversionRate: conversionRate,
            depositConversionRate: depositConversionRate,
            depositRevenueCents: max(0, depositRevenueCents),
            paidInvoiceRevenueCents: max(0, paidInvoiceRevenueCents),
            totalRevenueCents: max(0, totalRevenueCents),
            trend: trend,
            funnel: funnel,
            topServices: topServices,
            recentActivity: recentActivity,
            inRangeBookings: inRangeBookings,
            delta: delta
        )
    }

    static func normalizedStatus(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func bookingDate(_ booking: BookingRequestItem) -> Date {
        if let ms = booking.createdAtMs, ms > 0 {
            let seconds = ms > 10_000_000_000 ? Double(ms) / 1000.0 : Double(ms)
            return Date(timeIntervalSince1970: seconds)
        }
        if let requestedStart = booking.requestedStart?.trimmingCharacters(in: .whitespacesAndNewlines),
           !requestedStart.isEmpty {
            if let withFractional = isoWithFractional.date(from: requestedStart) {
                return withFractional
            }
            if let plain = isoPlain.date(from: requestedStart) {
                return plain
            }
            if let raw = Double(requestedStart) {
                let normalized = raw > 10_000_000_000 ? raw / 1000.0 : raw
                return Date(timeIntervalSince1970: normalized)
            }
        }
        return .distantPast
    }

    static func hasDepositRequested(_ booking: BookingRequestItem) -> Bool {
        let status = normalizedStatus(booking.status)
        if status == "deposit_requested" || status == "deposit_paid" { return true }
        if let invoiceId = booking.depositInvoiceId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !invoiceId.isEmpty { return true }
        return (booking.depositAmountCents ?? 0) > 0
    }

    static func hasDepositPaid(_ booking: BookingRequestItem) -> Bool {
        if booking.depositPaidAtMs != nil { return true }
        let status = normalizedStatus(booking.status)
        return status == "deposit_paid"
    }

    static func matchesFilter(_ booking: BookingRequestItem, filter: BookingAnalyticsDetailFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .pending:
            return normalizedStatus(booking.status) == "pending"
        case .approved:
            return normalizedStatus(booking.status) == "approved"
        case .declined:
            return normalizedStatus(booking.status) == "declined"
        case .depositRequested:
            return hasDepositRequested(booking)
        case .depositPaid:
            return hasDepositPaid(booking)
        case .serviceType(let raw):
            let lhs = normalizeServiceName(booking.serviceType)
            let rhs = normalizeServiceName(raw)
            return lhs == rhs
        }
    }

    private static func buildDelta(
        bookingRequests: [BookingRequestItem],
        invoices: [Invoice],
        businessId: UUID,
        timeRange: BookingAnalyticsRange,
        now: Date,
        calendar: Calendar
    ) -> BookingAnalyticsDelta? {
        let currentStart = timeRange.periodStart(now: now, calendar: calendar)
        let previousEnd = currentStart
        let interval = now.timeIntervalSince(currentStart)
        guard interval > 0 else { return nil }
        let previousStart = previousEnd.addingTimeInterval(-interval)

        let previousBookings = bookingRequests
            .filter { normalizedBusinessId($0.businessId) == businessId }
            .filter {
                let d = bookingDate($0)
                return d >= previousStart && d < previousEnd
            }

        let prevRequests = previousBookings.count
        let prevApproved = previousBookings.filter { normalizedStatus($0.status) == "approved" }.count
        let prevDeclined = previousBookings.filter { normalizedStatus($0.status) == "declined" }.count
        let prevDepositRequested = previousBookings.filter { hasDepositRequested($0) }.count
        let prevDepositsPaid = previousBookings.filter { hasDepositPaid($0) }.count
        let prevDepositRevenue = previousBookings.reduce(0) { partial, booking in
            guard hasDepositPaid(booking) else { return partial }
            return partial + max(0, booking.depositAmountCents ?? 0)
        }
        let prevInvoiceRevenue = invoices
            .filter { $0.businessID == businessId }
            .filter { $0.documentType == "invoice" }
            .filter {
                let source = ($0.sourceBookingRequestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !source.isEmpty
            }
            .filter { $0.isPaid }
            .filter { $0.issueDate >= previousStart && $0.issueDate < previousEnd }
            .reduce(0) { partial, invoice in
                partial + Int((invoice.total * 100.0).rounded())
            }

        let current = buildSnapshotCore(
            bookings: bookingRequests.filter { normalizedBusinessId($0.businessId) == businessId }
                .filter {
                    let d = bookingDate($0)
                    return d >= currentStart && d <= now
                },
            invoices: invoices,
            businessId: businessId,
            start: currentStart,
            end: now
        )

        return BookingAnalyticsDelta(
            requests: current.totalRequests - prevRequests,
            approved: current.approvedCount - prevApproved,
            declined: current.declinedCount - prevDeclined,
            depositRequested: current.depositRequestedCount - prevDepositRequested,
            depositsPaid: current.depositsPaidCount - prevDepositsPaid,
            revenueCents: current.totalRevenueCents - (prevDepositRevenue + prevInvoiceRevenue)
        )
    }

    private struct SnapshotCore {
        let totalRequests: Int
        let approvedCount: Int
        let declinedCount: Int
        let depositRequestedCount: Int
        let depositsPaidCount: Int
        let totalRevenueCents: Int
    }

    private static func buildSnapshotCore(
        bookings: [BookingRequestItem],
        invoices: [Invoice],
        businessId: UUID,
        start: Date,
        end: Date
    ) -> SnapshotCore {
        let totalRequests = bookings.count
        let approvedCount = bookings.filter { normalizedStatus($0.status) == "approved" }.count
        let declinedCount = bookings.filter { normalizedStatus($0.status) == "declined" }.count
        let depositRequestedCount = bookings.filter { hasDepositRequested($0) }.count
        let depositsPaidCount = bookings.filter { hasDepositPaid($0) }.count
        let depositRevenue = bookings.reduce(0) { partial, booking in
            guard hasDepositPaid(booking) else { return partial }
            return partial + max(0, booking.depositAmountCents ?? 0)
        }
        let invoiceRevenue = invoices
            .filter { $0.businessID == businessId }
            .filter { $0.documentType == "invoice" }
            .filter {
                let source = ($0.sourceBookingRequestId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return !source.isEmpty
            }
            .filter { $0.isPaid }
            .filter { $0.issueDate >= start && $0.issueDate <= end }
            .reduce(0) { partial, invoice in
                partial + Int((invoice.total * 100.0).rounded())
            }

        return SnapshotCore(
            totalRequests: totalRequests,
            approvedCount: approvedCount,
            declinedCount: declinedCount,
            depositRequestedCount: depositRequestedCount,
            depositsPaidCount: depositsPaidCount,
            totalRevenueCents: depositRevenue + invoiceRevenue
        )
    }

    private static func buildTrend(
        bookings: [BookingRequestItem],
        timeRange: BookingAnalyticsRange,
        start: Date,
        end: Date,
        calendar: Calendar
    ) -> [BookingTrendPoint] {
        var buckets: [Date: (requests: Int, approved: Int)] = [:]
        for booking in bookings {
            let date = bookingDate(booking)
            let bucket = bucketDate(for: date, weekly: timeRange.usesWeeklyBuckets, calendar: calendar)
            var value = buckets[bucket] ?? (0, 0)
            value.requests += 1
            if normalizedStatus(booking.status) == "approved" {
                value.approved += 1
            }
            buckets[bucket] = value
        }

        var points: [BookingTrendPoint] = []
        var cursor = bucketDate(for: start, weekly: timeRange.usesWeeklyBuckets, calendar: calendar)
        let endBucket = bucketDate(for: end, weekly: timeRange.usesWeeklyBuckets, calendar: calendar)
        while cursor <= endBucket {
            let value = buckets[cursor] ?? (0, 0)
            points.append(BookingTrendPoint(date: cursor, requests: value.requests, approved: value.approved))
            cursor = nextBucket(from: cursor, weekly: timeRange.usesWeeklyBuckets, calendar: calendar)
        }
        return points
    }

    private static func buildFunnel(
        totalRequests: Int,
        depositRequestedCount: Int,
        depositsPaidCount: Int,
        approvedCount: Int
    ) -> [BookingFunnelRow] {
        [
            BookingFunnelRow(id: "requests", title: "Requests", count: totalRequests, ratio: 1),
            BookingFunnelRow(
                id: "deposit_requested",
                title: "Deposit Requested",
                count: depositRequestedCount,
                ratio: safeRate(numerator: depositRequestedCount, denominator: totalRequests)
            ),
            BookingFunnelRow(
                id: "deposits_paid",
                title: "Deposits Paid",
                count: depositsPaidCount,
                ratio: safeRate(numerator: depositsPaidCount, denominator: totalRequests)
            ),
            BookingFunnelRow(
                id: "approved",
                title: "Approved",
                count: approvedCount,
                ratio: safeRate(numerator: approvedCount, denominator: totalRequests)
            ),
        ]
    }

    private static func buildTopServices(bookings: [BookingRequestItem]) -> [BookingServiceStat] {
        let total = max(1, bookings.count)
        var counts: [String: Int] = [:]
        for booking in bookings {
            let name = normalizeServiceName(booking.serviceType)
            counts[name, default: 0] += 1
        }
        return counts
            .map { (name, count) in
                BookingServiceStat(id: name, name: name, count: count, ratio: safeRate(numerator: count, denominator: total))
            }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
            .prefix(5)
            .map { $0 }
    }

    private static func normalizeServiceName(_ raw: String?) -> String {
        let trimmed = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unspecified" : trimmed
    }

    private static func normalizedBusinessId(_ raw: String) -> UUID? {
        UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func safeRate(numerator: Int, denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }

    private static func bucketDate(for date: Date, weekly: Bool, calendar: Calendar) -> Date {
        if weekly {
            return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        }
        return calendar.startOfDay(for: date)
    }

    private static func nextBucket(from date: Date, weekly: Bool, calendar: Calendar) -> Date {
        calendar.date(byAdding: weekly ? .weekOfYear : .day, value: 1, to: date) ?? date
    }

    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
