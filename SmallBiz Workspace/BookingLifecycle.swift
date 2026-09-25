//
//  BookingLifecycle.swift
//  SmallBiz Workspace
//

import SwiftUI
import SwiftData
import EventKit

/// A booking request as the app shows it: the server's record, with its
/// times parsed. Bookings live on the server; the app never stores them.
struct BookingRequestItem: Identifiable, Hashable {
    let requestId: String
    let businessId: String
    let slug: String?
    let clientName: String?
    let clientEmail: String?
    let clientPhone: String?
    let requestedStart: String?
    let requestedEnd: String?
    let serviceType: String?
    let notes: String?
    let status: String
    let createdAtMs: Int?
    let bookingTotalAmountCents: Int?
    let depositAmountCents: Int?
    let depositInvoiceId: String?
    let depositPaidAtMs: Int?
    let finalInvoiceId: String?
    var approvedAtMs: Int? = nil
    var declinedAtMs: Int? = nil
    var depositRequestedAtMs: Int? = nil
    var depositWaivedAtMs: Int? = nil
    var cancelledAtMs: Int? = nil

    var id: String { requestId }

    init(
        requestId: String, businessId: String, slug: String?, clientName: String?, clientEmail: String?,
        clientPhone: String?, requestedStart: String?, requestedEnd: String?, serviceType: String?,
        notes: String?, status: String, createdAtMs: Int?, bookingTotalAmountCents: Int?,
        depositAmountCents: Int?, depositInvoiceId: String?, depositPaidAtMs: Int?, finalInvoiceId: String?
    ) {
        self.requestId = requestId
        self.businessId = businessId
        self.slug = slug
        self.clientName = clientName
        self.clientEmail = clientEmail
        self.clientPhone = clientPhone
        self.requestedStart = requestedStart
        self.requestedEnd = requestedEnd
        self.serviceType = serviceType
        self.notes = notes
        self.status = status
        self.createdAtMs = createdAtMs
        self.bookingTotalAmountCents = bookingTotalAmountCents
        self.depositAmountCents = depositAmountCents
        self.depositInvoiceId = depositInvoiceId
        self.depositPaidAtMs = depositPaidAtMs
        self.finalInvoiceId = finalInvoiceId
    }

    /// Every screen built this by hand, and each dropped a different field.
    init(dto: BookingRequestDTO) {
        self.init(
            requestId: dto.requestId, businessId: dto.businessId, slug: dto.slug,
            clientName: dto.clientName, clientEmail: dto.clientEmail, clientPhone: dto.clientPhone,
            requestedStart: dto.requestedStart, requestedEnd: dto.requestedEnd,
            serviceType: dto.serviceType, notes: dto.notes, status: dto.status,
            createdAtMs: dto.createdAtMs, bookingTotalAmountCents: dto.bookingTotalAmountCents,
            depositAmountCents: dto.depositAmountCents, depositInvoiceId: dto.depositInvoiceId,
            depositPaidAtMs: dto.depositPaidAtMs, finalInvoiceId: dto.finalInvoiceId
        )
        approvedAtMs = dto.approvedAtMs
        declinedAtMs = dto.declinedAtMs
        depositRequestedAtMs = dto.depositRequestedAtMs
        depositWaivedAtMs = dto.depositWaivedAtMs
        cancelledAtMs = dto.cancelledAtMs
    }

    var start: Date? { BookingDates.parse(requestedStart) }
    var end: Date? { BookingDates.parse(requestedEnd) }
    var stage: BookingStage { BookingStage(self) }

    var customerName: String {
        for candidate in [clientName, clientEmail, clientPhone] {
            let trimmed = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return "Customer"
    }

    var serviceName: String {
        let trimmed = (serviceType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Booking" : trimmed
    }

    /// Past once it has ended (or started, when there's no end).
    func isPast(now: Date = .now) -> Bool {
        guard let reference = end ?? start else { return false }
        return reference < now
    }

    var depositPaid: Bool { (depositPaidAtMs ?? 0) > 0 }

    /// "Sat, Oct 4 · 2:00–3:00 PM", in this device's time zone.
    var whenText: String {
        guard let start else { return "No time requested" }
        let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let from = start.formatted(date: .omitted, time: .shortened)
        guard let end else { return "\(day) · \(from)" }
        // Word joiners keep "10:00–10:30" on one line when the text wraps.
        return "\(day) · \(from)\u{2060}–\u{2060}\(end.formatted(date: .omitted, time: .shortened))"
    }
}

enum BookingDates {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        return fractional.date(from: raw) ?? plain.date(from: raw)
    }

    static func string(_ date: Date) -> String { fractional.string(from: date) }
}

/// One set of names for booking states. The app had three mappings ("Deny"
/// here, "Declined" there, Deposit Requested blue in one place and yellow in
/// another).
enum BookingStage: Equatable {
    case needsAnswer
    case awaitingDeposit
    case confirmed
    case declined
    case canceled

    init(_ booking: BookingRequestItem) {
        switch booking.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "deposit_requested": self = .awaitingDeposit
        case "approved", "deposit_paid": self = .confirmed
        case "declined": self = .declined
        case "cancelled", "canceled": self = .canceled
        default: self = .needsAnswer
        }
    }

    var label: String {
        switch self {
        case .needsAnswer: return "New"
        case .awaitingDeposit: return "Deposit"
        case .confirmed: return "Confirmed"
        case .declined: return "Declined"
        case .canceled: return "Canceled"
        }
    }

    var foreground: Color {
        switch self {
        case .needsAnswer: return .orange
        case .awaitingDeposit: return SBWTheme.brandBlue
        case .confirmed: return SBWTheme.brandGreen
        case .declined, .canceled: return .red
        }
    }
}

/// The owner's answers to a booking, each returning the updated booking.
@MainActor
enum BookingActions {
    enum ActionError: LocalizedError {
        case server(code: String)

        var errorDescription: String? {
            switch self {
            case .server(let code):
                switch code {
                case "BOOKING_DECLINED": return "This booking was declined, so it can't be changed."
                case "BOOKING_CANCELLED": return "This booking was canceled, so it can't be changed."
                case "BOOKING_ALREADY_CONFIRMED": return "This booking is already confirmed."
                case "DEPOSIT_ALREADY_PAID": return "The deposit for this booking is already paid."
                case "END_BEFORE_START": return "The end time has to be after the start."
                default: return "This booking changed since you opened it. Pull to refresh and try again."
                }
            }
        }
    }

    private static func run(_ path: String, _ payload: [String: Any]) async throws -> BookingRequestItem? {
        do {
            let response = try await PortalBackend.shared.postBookingAction(path: path, payload: payload)
            return response.request.map(BookingRequestItem.init(dto:))
        } catch let PortalBackendError.http(code, body, _) where code == 409 {
            if PortalBackendError.actionableMessage(fromBody: body) != nil {
                throw PortalBackendError.http(code, body: body)
            }
            let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
            throw ActionError.server(code: json?["error"] as? String ?? "")
        } catch let PortalBackendError.http(code, body, _) where code == 400 {
            let json = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any]
            if let error = json?["error"] as? String, error == "END_BEFORE_START" {
                throw ActionError.server(code: error)
            }
            throw PortalBackendError.http(code, body: body)
        }
    }

    static func confirm(_ booking: BookingRequestItem, waiveDeposit: Bool = false) async throws -> BookingRequestItem? {
        try await run("/api/booking/admin/approve", ["requestId": booking.requestId, "waiveDeposit": waiveDeposit])
    }

    static func decline(_ booking: BookingRequestItem, message: String?) async throws -> BookingRequestItem? {
        var payload: [String: Any] = ["requestId": booking.requestId]
        if let message, !message.isEmpty { payload["message"] = message }
        return try await run("/api/booking/admin/decline", payload)
    }

    static func cancel(_ booking: BookingRequestItem, message: String?) async throws -> BookingRequestItem? {
        var payload: [String: Any] = ["requestId": booking.requestId]
        if let message, !message.isEmpty { payload["message"] = message }
        return try await run("/api/booking/admin/cancel", payload)
    }

    static func reschedule(_ booking: BookingRequestItem, start: Date, end: Date) async throws -> BookingRequestItem? {
        try await run("/api/booking/admin/reschedule", [
            "requestId": booking.requestId,
            "requestedStart": BookingDates.string(start),
            "requestedEnd": BookingDates.string(end),
        ])
    }

    static func markDepositPaid(_ booking: BookingRequestItem) async throws -> BookingRequestItem? {
        try await run("/api/booking/admin/request/deposit/mark-paid", ["requestId": booking.requestId])
    }
}

/// The client and job behind a confirmed booking, made once.
///
/// Opening the Bookings list used to create a client, a job and a $0 "final"
/// invoice for every confirmed booking with a deposit, on every load; deleted
/// ones came back, each using up an invoice number. Now a confirmed booking
/// gets one client and one scheduled job, the first time the app sees it
/// confirmed, and never again — deleting the job is respected.
@MainActor
enum BookingWorkSetup {
    private static func madeKey(_ requestId: String) -> String { "sbw.booking.jobMade.\(requestId)" }

    static func job(for booking: BookingRequestItem, in context: ModelContext) -> Job? {
        let requestId = booking.requestId
        return try? context.fetch(
            FetchDescriptor<Job>(predicate: #Predicate { $0.sourceBookingRequestId == requestId })
        ).first
    }

    /// The existing client with the same email or phone. Not by name alone:
    /// that merged different people who share a name.
    static func matchingClient(for booking: BookingRequestItem, businessID: UUID, in context: ModelContext) -> Client? {
        let clients = (try? context.fetch(
            FetchDescriptor<Client>(predicate: #Predicate { $0.businessID == businessID })
        )) ?? []
        let email = (booking.clientEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !email.isEmpty, let match = clients.first(where: { $0.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == email }) {
            return match
        }
        let digits = (booking.clientPhone ?? "").filter(\.isNumber)
        if digits.count >= 7, let match = clients.first(where: { $0.phone.filter(\.isNumber).hasSuffix(digits.suffix(10)) }) {
            return match
        }
        return nil
    }

    /// Makes the client (if new) and the job, links the calendar, and records
    /// that it was done. Returns the job; nil if it was made before and since
    /// deleted, or the booking isn't confirmed.
    @discardableResult
    static func ensureJob(
        for booking: BookingRequestItem,
        businessID: UUID,
        context: ModelContext,
        addToCalendar: Bool = true
    ) async -> Job? {
        guard booking.stage == .confirmed else { return nil }
        if let existing = job(for: booking, in: context) {
            sync(existing, with: booking)
            try? context.save()
            return existing
        }
        guard !UserDefaults.standard.bool(forKey: madeKey(booking.requestId)) else { return nil }

        let client = matchingClient(for: booking, businessID: businessID, in: context) ?? {
            let client = Client(
                businessID: businessID,
                name: booking.customerName,
                email: (booking.clientEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                phone: (booking.clientPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            )
            context.insert(client)
            return client
        }()

        let start = booking.start ?? .now
        let job = Job(
            businessID: businessID,
            clientID: client.id,
            title: "\(booking.serviceName) — \(booking.customerName)",
            notes: (booking.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            startDate: start,
            endDate: booking.end ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start,
            locationName: client.address,
            status: "scheduled",
            sourceBookingRequestId: booking.requestId
        )
        job.stage = .booked
        sync(job, with: booking)
        context.insert(job)
        try? context.save()
        UserDefaults.standard.set(true, forKey: madeKey(booking.requestId))
        _ = try? WorkspaceProvisioningService.ensureJobWorkspace(job: job, context: context)
        if addToCalendar {
            await self.addToCalendar(job, client: client, context: context)
        }
        return job
    }

    /// On push, launch and foreground: a booking confirmed on the server
    /// (its deposit paid online) gets its client and job without the owner
    /// opening Bookings. Upcoming ones only; once each.
    static func syncConfirmed(context: ModelContext, businessID: UUID?) async {
        guard let businessID,
              let dtos = try? await PortalBackend.shared.fetchBookingRequests(businessId: businessID)
        else { return }
        for booking in dtos.map(BookingRequestItem.init(dto:)) where booking.stage == .confirmed && !booking.isPast() {
            await ensureJob(for: booking, businessID: businessID, context: context)
        }
    }

    /// Price and deposit, so "Bill for it" on the job asks for the rest.
    static func sync(_ job: Job, with booking: BookingRequestItem) {
        if let total = booking.bookingTotalAmountCents, total > 0 { job.quotedTotalCents = total }
        if let deposit = booking.depositAmountCents, deposit > 0, booking.depositPaid {
            job.depositAmountCents = deposit
            job.depositPaidAtMs = Int64(booking.depositPaidAtMs ?? 0)
        }
    }

    /// Moves the job and its calendar event to the booking's new time.
    static func reschedule(_ job: Job, to booking: BookingRequestItem, context: ModelContext) async {
        guard let start = booking.start else { return }
        job.startDate = start
        job.endDate = booking.end ?? Calendar.current.date(byAdding: .hour, value: 1, to: start) ?? start
        try? context.save()
        if job.calendarEventId != nil {
            let clientID = job.clientID
            let client = clientID.flatMap { id in
                try? context.fetch(FetchDescriptor<Client>(predicate: #Predicate { $0.id == id })).first
            }
            await addToCalendar(job, client: client, context: context)
        }
    }

    static func addToCalendar(_ job: Job, client: Client?, context: ModelContext) async {
        let businessID = job.businessID
        let businessName = (try? context.fetch(
            FetchDescriptor<BusinessProfile>(predicate: #Predicate { $0.businessID == businessID })
        ).first)?.name
        guard let event = try? await CalendarEventService.shared.createOrUpdateEvent(
            for: job,
            businessName: businessName,
            clientName: client?.name,
            clientEmail: client?.email,
            clientPhone: client?.phone
        ) else { return }
        job.calendarEventId = event.eventIdentifier
        try? context.save()
    }
}
