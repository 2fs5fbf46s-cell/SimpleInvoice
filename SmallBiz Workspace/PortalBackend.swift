//
//  PortalBackend.swift
//  SmallBiz Workspace
//

import Foundation
import OSLog

// MARK: - Config

final class PortalConfig {
    static let shared = PortalConfig()
    let baseURL = URL(string: "https://portal.smallbizworkspace.com")!
    private init() {}
}

// MARK: - Secrets loader (PortalSecrets.plist)

enum PortalSecrets {
    static func portalAdminKey() -> String? {
        guard
            let url = Bundle.main.url(forResource: "PortalSecrets", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            SBWLog.portal.note("🔐 PortalSecrets.plist not found or unreadable.")
            return nil
        }

        let raw = dict["PORTAL_ADMIN_KEY"]
        let trimmed: String?

        if let s = raw as? String {
            trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let raw {
            trimmed = String(describing: raw).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            trimmed = nil
        }

        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

// MARK: - Errors

enum PortalBackendError: Error {
    case missingAdminKey
    case badURL
    case http(Int, body: String, path: String = "")
    case decode(body: String)
}

extension PortalBackendError {

    /// Errors the server can explain better than a status code can.
    ///
    /// Most failures are transient and the generic copy is right: try again. These
    /// are not. A deposit above the booking total, or an edit to a contract
    /// somebody signed, will fail identically forever — and the status-code copy
    /// ("try again shortly", "someone else changed this first") sends the user to
    /// wait for something that is never going to happen.
    ///
    /// Deliberately an allowlist rather than "show whatever `message` arrives".
    /// These strings are written for the person reading them; a server message
    /// from anywhere else has made no such promise.
    static let actionableServerErrors: Set<String> = [
        "DEPOSIT_EXCEEDS_TOTAL",
        "TOTAL_BELOW_PAID_DEPOSIT",
        "DEPOSIT_PAYMENT_REQUIRED",
        "CONTRACT_SIGNED_BODY_LOCKED",
        "CONTRACT_SIGNED_TITLE_LOCKED",
    ]

    /// The server's own explanation, when it sent one worth showing.
    static func actionableMessage(fromBody body: String) -> String? {
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        guard let code = json["error"] as? String,
              actionableServerErrors.contains(code)
        else { return nil }

        guard let message = (json["message"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else { return nil }

        return message
    }
}

extension PortalBackendError: LocalizedError {
    /// What the customer reads.
    ///
    /// This used to interpolate the raw response body and the internal route path,
    /// so a business owner would see "Portal backend HTTP 500 at
    /// /api/portal/invoice. {…}". Say what happened and what to do; the detail
    /// belongs in `diagnosticDescription`, which goes to the log.
    var errorDescription: String? {
        switch self {
        case .missingAdminKey:
            return "This device isn't set up to sync yet. Reopen the app, and contact support if it keeps happening."
        case .badURL:
            return "Couldn't reach the sync service. Check your connection and try again."
        case .http(let code, let body, _):
            // A specific, actionable explanation beats the status-code copy, which
            // would otherwise tell the user to retry something that cannot succeed.
            if let message = Self.actionableMessage(fromBody: body) {
                return message
            }

            switch code {
            case 401, 403:
                return "This device is no longer signed in for this business. Reopen the app to sign in again."
            case 404:
                return "That item isn't on the server yet. Try syncing again in a moment."
            case 409:
                return "Someone else changed this first. Reopen it to see the latest version."
            case 413:
                return "That file is too large to upload. Try a smaller one."
            case 429:
                return "Too many requests just now. Wait a moment and try again."
            case 500...599:
                return "The sync service is having trouble. Your work is saved on this device — try again shortly."
            default:
                return "Couldn't complete that just now. Your work is saved on this device — try again shortly."
            }
        case .decode:
            return "Got an unexpected response from the sync service. Try again shortly."
        }
    }

    /// Full detail, for logs and bug reports. Never shown in the UI.
    var diagnosticDescription: String {
        switch self {
        case .missingAdminKey:
            return "PortalBackendError.missingAdminKey (PortalSecrets.plist)"
        case .badURL:
            return "PortalBackendError.badURL"
        case .http(let code, let body, let path):
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            let where_ = trimmedPath.isEmpty ? "" : " at \(trimmedPath)"
            return "PortalBackendError.http \(code)\(where_): \(body)"
        case .decode(let body):
            return "PortalBackendError.decode: \(body)"
        }
    }
}

// MARK: - DTOs (match seed route)

struct PortalSeedResponseDTO: Decodable {
    let token: String
    let expiresAt: String?
    let session: PortalSessionDTO?
}

struct PullRecurringResponseDTO: Decodable {
    let ok: Bool?
    let invoices: [GeneratedRecurringInvoiceDTO]
}

struct PullEstimateDecisionsResponseDTO: Decodable {
    let ok: Bool?
    let decisions: [EstimateDecisionDTO]
}

struct EstimateDecisionDTO: Decodable {
    let estimateId: String
    let businessId: String
    let clientId: String
    /// "accepted" or "declined".
    let status: String
    let decidedAtMs: Double
    let updatedAtMs: Double
}

struct GeneratedRecurringInvoiceDTO: Decodable {
    let invoiceId: String
    let invoiceNumber: String
    let clientId: String
    let amountCents: Int
    let taxCents: Int
    let discountAmountCents: Int
    let taxRate: Double
    let currency: String
    let dueAtMs: Double
    let updatedAtMs: Double
    let lineItems: [GeneratedLineItemDTO]
}

struct GeneratedLineItemDTO: Decodable {
    let description: String
    let quantity: Double
    let unitPrice: Double
}

struct PortalSessionDTO: Decodable {
    let businessId: String?
    let brand: PortalBrandDTO?
    let allowed: PortalAllowedDTO?
    let mode: String?
    let exp: Double?
}

struct PortalBrandDTO: Decodable {
    let name: String?
    let logoUrl: String?
}

/// allowed can be invoice/contract/directory now
struct PortalAllowedDTO: Decodable {
    let scope: String?
    let clientId: String?

    // invoice
    let invoiceId: String?
    let invoiceNumber: String?
    let amountCents: Int?
    let currency: String?

    // contract
    let contractId: String?
    let contractTitle: String?

    // gate
    let clientPortalEnabled: Bool?
}

// MARK: - Payment Status

struct PaymentStatusResponse: Decodable {
    let paid: Bool
    let receipt: ReceiptDTO?

    struct ReceiptDTO: Decodable {
        let status: String?
        let invoiceId: String?
        let businessId: String?
        let sessionId: String?
        let amountTotal: Int?
        let currency: String?
        let paidAt: String?
    }
}

struct EstimateStatusResponseDTO: Decodable {
    let status: String?
    let decidedAt: String?
    let acceptedAt: String?
    let declinedAt: String?
    let updatedAt: String?
}

struct PublicSiteUpsertPayload: Encodable {
    struct TeamMemberV2Payload: Encodable {
        let id: String
        let name: String
        let title: String
        let photoUrl: String?
    }

    let appName: String
    let heroUrl: String?
    let aboutUrl: String?
    let services: [String]
    let aboutUs: String
    let team: [String]
    let teamV2: [TeamMemberV2Payload]?
    let galleryUrls: [String]
    let updatedAtMs: Int
}

struct DomainVerifyDTO: Decodable {
    let ok: Bool
    let mapped: Bool
    let status: String
    let handle: String?
    let businessId: String?
    let canonicalUrl: String?
    let error: String?
}

struct PushRegistrationResponseDTO: Decodable {
    let ok: Bool?
    let error: String?
}

struct SendTestPushResponseDTO: Decodable {
    let ok: Bool?
    let error: String?
}

struct AppNotificationDTO: Decodable, Identifiable {
    let notificationId: String
    let businessId: String
    let title: String
    let body: String
    let eventType: String
    let deepLink: String?
    let createdAtMs: Int
    let readAtMs: Int?
    let rawDataJson: String?

    var id: String { notificationId }

    private enum CodingKeys: String, CodingKey {
        case notificationId
        case id
        case businessId
        case businessID
        case title
        case body
        case message
        case eventType
        case event
        case deepLink
        case deeplink
        case createdAtMs
        case createdAt
        case readAtMs
        case readAt
        case rawDataJson
        case rawData
        case data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func decodeString(_ key: CodingKeys) -> String? {
            if let v = try? c.decodeIfPresent(String.self, forKey: key) {
                let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return String(v) }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return String(v) }
            return nil
        }

        func decodeFirstString(_ keys: [CodingKeys], fallback: String = "") -> String {
            for key in keys {
                if let value = decodeString(key) { return value }
            }
            return fallback
        }

        func decodeInt(_ key: CodingKeys) -> Int? {
            if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
            if let v = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(v) }
            if let v = decodeString(key), let intVal = Int(v) { return intVal }
            if let v = decodeString(key), let dblVal = Double(v) { return Int(dblVal) }
            return nil
        }

        func decodeFirstInt(_ keys: [CodingKeys], fallback: Int = 0) -> Int {
            for key in keys {
                if let value = decodeInt(key) { return value }
            }
            return fallback
        }

        let generatedId = UUID().uuidString
        self.notificationId = decodeFirstString([.notificationId, .id], fallback: generatedId)
        self.businessId = decodeFirstString([.businessId, .businessID])
        self.title = decodeFirstString([.title], fallback: "Notification")
        self.body = decodeFirstString([.body, .message])
        self.eventType = decodeFirstString([.eventType, .event], fallback: "generic")
        let deepLinkValue = decodeFirstString([.deepLink, .deeplink])
        self.deepLink = deepLinkValue.isEmpty ? nil : deepLinkValue
        self.createdAtMs = decodeFirstInt([.createdAtMs, .createdAt], fallback: Int(Date().timeIntervalSince1970 * 1000))
        let read = decodeFirstInt([.readAtMs, .readAt], fallback: 0)
        self.readAtMs = read > 0 ? read : nil

        if let raw = decodeString(.rawDataJson) {
            self.rawDataJson = raw
        } else if let raw = decodeString(.rawData) {
            self.rawDataJson = raw
        } else if let dataObj = try? c.decodeIfPresent([String: String].self, forKey: .data),
                  let encoded = try? JSONEncoder().encode(dataObj),
                  let json = String(data: encoded, encoding: .utf8) {
            self.rawDataJson = json
        } else {
            self.rawDataJson = nil
        }
    }
}

struct FetchNotificationsResponseDTO: Decodable {
    let items: [AppNotificationDTO]
    let unreadCount: Int

    private enum CodingKeys: String, CodingKey {
        case items
        case notifications
        case unreadCount
        case unread
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let direct = try? c.decode([AppNotificationDTO].self, forKey: .items) {
            items = direct
        } else if let alt = try? c.decode([AppNotificationDTO].self, forKey: .notifications) {
            items = alt
        } else {
            items = []
        }
        unreadCount = (try? c.decodeIfPresent(Int.self, forKey: .unreadCount))
            ?? (try? c.decodeIfPresent(Int.self, forKey: .unread))
            ?? 0
    }
}

// MARK: - Booking Admin DTOs

struct BookingRequestDTO: Decodable, Identifiable, Equatable {
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
    var status: String

    let createdAtMs: Int?
    let approvedAtMs: Int?
    let declinedAtMs: Int?
    let bookingTotalAmountCents: Int?
    let depositAmountCents: Int?
    let depositInvoiceId: String?
    let depositPaidAtMs: Int?
    let finalInvoiceId: String?
    let depositRequestedAtMs: Int?
    let depositWaivedAtMs: Int?
    let cancelledAtMs: Int?
    let rescheduledAtMs: Int?

    // Local-only for future workflow; not encoded/decoded.
    var isHandled: Bool = false

    var id: String { requestId }

    private enum CodingKeys: String, CodingKey {
        case requestId
        case id
        case bookingRequestId

        case businessId
        case businessID

        case slug
        case clientName
        case clientEmail
        case clientPhone
        case customerName
        case customerEmail
        case customerPhone

        case requestedStart
        case requestedEnd
        case requestedStartAt
        case requestedEndAt
        case startAt
        case endAt

        case serviceType
        case serviceName
        case notes
        case message
        case status

        case createdAtMs
        case approvedAtMs
        case declinedAtMs
        case bookingTotalAmountCents
        case depositAmountCents
        case depositInvoiceId
        case depositPaidAtMs
        case finalInvoiceId
        case createdAt
        case approvedAt
        case declinedAt
        case bookingTotalAmount
        case depositAmount
        case depositInvoiceID
        case depositPaidAt
        case finalInvoiceID
        case depositRequestedAtMs
        case depositWaivedAtMs
        case cancelledAtMs
        case rescheduledAtMs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        func decodeString(_ key: CodingKeys) -> String? {
            if let val = try? c.decodeIfPresent(String.self, forKey: key) { return val }
            if let val = try? c.decodeIfPresent(Int.self, forKey: key) { return String(val) }
            if let val = try? c.decodeIfPresent(Double.self, forKey: key) { return String(val) }
            return nil
        }

        func decodeInt(_ key: CodingKeys) -> Int? {
            if let val = try? c.decodeIfPresent(Int.self, forKey: key) { return val }
            if let val = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(val) }
            if let val = (try? c.decodeIfPresent(String.self, forKey: key)) ?? nil {
                let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
                if let intVal = Int(trimmed) { return intVal }
                if let dblVal = Double(trimmed) { return Int(dblVal) }
            }
            return nil
        }

        func decodeFirst(_ keys: [CodingKeys]) -> String? {
            for key in keys {
                if let val = decodeString(key), !val.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return val
                }
            }
            return nil
        }

        func decodeFirstInt(_ keys: [CodingKeys]) -> Int? {
            for key in keys {
                if let val = decodeInt(key) {
                    return val
                }
            }
            return nil
        }

        guard let requestId = decodeFirst([.requestId, .id, .bookingRequestId]) else {
            throw DecodingError.keyNotFound(
                CodingKeys.requestId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing requestId/id")
            )
        }
        guard let businessId = decodeFirst([.businessId, .businessID]) else {
            throw DecodingError.keyNotFound(
                CodingKeys.businessId,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing businessId")
            )
        }

        self.requestId = requestId
        self.businessId = businessId
        self.slug = decodeFirst([.slug])

        self.clientName = decodeFirst([.clientName, .customerName])
        self.clientEmail = decodeFirst([.clientEmail, .customerEmail])
        self.clientPhone = decodeFirst([.clientPhone, .customerPhone])

        self.requestedStart = decodeFirst([.requestedStart, .requestedStartAt, .startAt])
        self.requestedEnd = decodeFirst([.requestedEnd, .requestedEndAt, .endAt])

        self.serviceType = decodeFirst([.serviceType, .serviceName])
        self.notes = decodeFirst([.notes, .message])
        self.status = decodeFirst([.status]) ?? "pending"

        self.createdAtMs = decodeFirstInt([.createdAtMs, .createdAt])
        self.approvedAtMs = decodeFirstInt([.approvedAtMs, .approvedAt])
        self.declinedAtMs = decodeFirstInt([.declinedAtMs, .declinedAt])
        self.bookingTotalAmountCents = decodeFirstInt([.bookingTotalAmountCents, .bookingTotalAmount])
        self.depositAmountCents = decodeFirstInt([.depositAmountCents, .depositAmount])
        self.depositInvoiceId = decodeFirst([.depositInvoiceId, .depositInvoiceID])
        self.depositPaidAtMs = decodeFirstInt([.depositPaidAtMs, .depositPaidAt])
        self.finalInvoiceId = decodeFirst([.finalInvoiceId, .finalInvoiceID])
        self.depositRequestedAtMs = decodeFirstInt([.depositRequestedAtMs])
        self.depositWaivedAtMs = decodeFirstInt([.depositWaivedAtMs])
        self.cancelledAtMs = decodeFirstInt([.cancelledAtMs])
        self.rescheduledAtMs = decodeFirstInt([.rescheduledAtMs])

        self.isHandled = false
    }
}

struct BookingRequestsResponseDTO: Decodable {
    let requests: [BookingRequestDTO]
}

struct BookingDepositResponseDTO: Decodable {
    let ok: Bool?
    let portalUrl: String?
    let depositInvoiceId: String?
    let status: String?
    let token: String?
    let warnings: [String]?
    let error: String?
}

struct BookingAnalyticsDTO: Decodable, Equatable {
    let windowDays: Int
    let totalRequests: Int
    let pendingCount: Int
    let depositRequestedCount: Int
    let depositPaidCount: Int
    let approvedCount: Int
    let declinedCount: Int
    let depositsTotalCents: Int
    let totalsTotalCents: Int
    let remainingTotalCents: Int
    let conversionRates: BookingConversionRatesDTO
}

struct BookingConversionRatesDTO: Decodable, Equatable {
    let approved: Double
    let declined: Double
    let depositRequested: Double
    let depositPaid: Double
}

private struct BookingAnalyticsEnvelopeDTO: Decodable {
    let analytics: BookingAnalyticsDTO?
}

private struct BookingSettingsEnvelopeDTO: Decodable {
    let settings: BookingSettingsDTO?
    let data: BookingSettingsDTO?
}

struct BookingSettingsDTO: Decodable, Encodable {
    let businessId: String?
    let slug: String?
    let brandName: String?
    let ownerEmail: String?
    let services: [BookingServiceOption]?
    let businessHours: [String: [String: String?]]?
    let hoursJson: String?
    let slotMinutes: Int?
    let bookingSlotMinutes: Int?
    let minBookingMinutes: Int?
    let maxBookingMinutes: Int?
    let allowSameDay: Bool?

    init(
        businessId: String? = nil,
        slug: String? = nil,
        brandName: String? = nil,
        ownerEmail: String? = nil,
        services: [BookingServiceOption]? = nil,
        businessHours: [String: [String: String?]]? = nil,
        hoursJson: String? = nil,
        slotMinutes: Int? = nil,
        bookingSlotMinutes: Int? = nil,
        minBookingMinutes: Int? = nil,
        maxBookingMinutes: Int? = nil,
        allowSameDay: Bool? = nil
    ) {
        self.businessId = businessId
        self.slug = slug
        self.brandName = brandName
        self.ownerEmail = ownerEmail
        self.services = services
        self.businessHours = businessHours
        self.hoursJson = hoursJson
        self.slotMinutes = slotMinutes
        self.bookingSlotMinutes = bookingSlotMinutes
        self.minBookingMinutes = minBookingMinutes
        self.maxBookingMinutes = maxBookingMinutes
        self.allowSameDay = allowSameDay
    }

    private enum CodingKeys: String, CodingKey {
        case businessId
        case slug
        case brandName
        case ownerEmail
        case services
        case businessHours
        case hoursJson
        case slotMinutes
        case bookingSlotMinutes
        case minBookingMinutes
        case maxBookingMinutes
        case allowSameDay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        businessId = try c.decodeIfPresent(String.self, forKey: .businessId)
        slug = try c.decodeIfPresent(String.self, forKey: .slug)
        brandName = try c.decodeIfPresent(String.self, forKey: .brandName)
        ownerEmail = try c.decodeIfPresent(String.self, forKey: .ownerEmail)
        businessHours = try c.decodeIfPresent([String: [String: String?]].self, forKey: .businessHours)
        hoursJson = try c.decodeIfPresent(String.self, forKey: .hoursJson)
        minBookingMinutes = try c.decodeIfPresent(Int.self, forKey: .minBookingMinutes)
        maxBookingMinutes = try c.decodeIfPresent(Int.self, forKey: .maxBookingMinutes)
        allowSameDay = try c.decodeIfPresent(Bool.self, forKey: .allowSameDay)

        if let opts = try c.decodeIfPresent([BookingServiceOption].self, forKey: .services) {
            services = opts
        } else if let names = try c.decodeIfPresent([String].self, forKey: .services) {
            services = names.map { BookingServiceOption(name: $0, durationMinutes: 30) }
        } else {
            services = nil
        }

        let slot = try c.decodeIfPresent(Int.self, forKey: .slotMinutes)
        let bookingSlot = try c.decodeIfPresent(Int.self, forKey: .bookingSlotMinutes)
        slotMinutes = slot
        bookingSlotMinutes = bookingSlot
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(businessId, forKey: .businessId)
        try c.encodeIfPresent(slug, forKey: .slug)
        try c.encodeIfPresent(brandName, forKey: .brandName)
        try c.encodeIfPresent(ownerEmail, forKey: .ownerEmail)
        try c.encodeIfPresent(services, forKey: .services)
        try c.encodeIfPresent(businessHours, forKey: .businessHours)
        try c.encodeIfPresent(hoursJson, forKey: .hoursJson)
        try c.encodeIfPresent(slotMinutes, forKey: .slotMinutes)
        try c.encodeIfPresent(bookingSlotMinutes, forKey: .bookingSlotMinutes)
        try c.encodeIfPresent(minBookingMinutes, forKey: .minBookingMinutes)
        try c.encodeIfPresent(maxBookingMinutes, forKey: .maxBookingMinutes)
        try c.encodeIfPresent(allowSameDay, forKey: .allowSameDay)
    }
}

// MARK: - Backend client

final class PortalBackend {
    static let shared = PortalBackend()

    private let baseURL = PortalConfig.shared.baseURL
    private init() {}

    // MARK: - ID helpers (SwiftData PersistentIdentifier safe)

    private func invoiceIdString(_ invoice: Invoice) -> String {
        // Invoice.id is SwiftData PersistentIdentifier in this project.
        // String(describing:) provides a stable identifier string for backend routing.
        String(describing: invoice.id)
    }

    /// The id the portal keys a contract by (its UUID string).
    func contractIdString(_ contract: Contract) -> String {
        contract.id.uuidString
    }
    // MARK: - Invoice line items -> portal payload

    /// Builds the `lineItems` array that the portal backend stores in KV.
    ///
    /// Uses Invoice.items: [LineItem]? with fields:
    /// - id (String), name (String), description (String), quantity (Double), unitAmountCents (Int), amountCents (Int)
    private func buildPortalLineItems(invoice: Invoice) -> [[String: Any]] {
        var out: [[String: Any]] = []

        for li in (invoice.items ?? []) {
            let qty = li.quantity // Double (supports fractional)
            let unitCents = toCents(li.unitPrice)
            let amountCents = toCents(li.lineTotal)

            out.append([
                "id": li.id.uuidString,
                "name": li.itemDescription.isEmpty ? "Item" : li.itemDescription,
                "description": "",
                "qty": qty,
                "quantity": qty, // Back-compat for older portal renderers
                "unitAmountCents": unitCents,
                "amountCents": amountCents
            ])
        }

        // Represent discount as its own negative line item so the subtotal matches the visible list.
        if invoice.discountAmount > 0 {
            let discountCents = invoice.discountCents
            out.append([
                "id": "discount",
                "name": "Discount",
                "description": "",
                "qty": 1,
                "quantity": 1, // Back-compat for older portal renderers
                "unitAmountCents": -discountCents,
                "amountCents": -discountCents
            ])
        }

        return out
    }
    // MARK: - Invoice totals (cents)

    private func toCents(_ dollars: Double) -> Int {
        Int((dollars * 100).rounded())
    }

    private func portalSubtotalCents(from lineItems: [[String: Any]]) -> Int {
        lineItems.reduce(0) { partial, dict in
            partial + (dict["amountCents"] as? Int ?? 0)
        }
    }

    private func portalTaxCents(invoice: Invoice) -> Int {
        invoice.taxCents
    }

    private func portalTotalCents(invoice: Invoice) -> Int {
        invoice.totalCents
    }

    // MARK: - Shared

    // MARK: - Networking

    /// The session every portal call goes through.
    ///
    /// `URLSession.shared` defaults to a 60-second request timeout, so one stalled
    /// call could block a sync pass for a full minute with nothing shown to the
    /// user. These are sized for a mobile connection: long enough to ride out a
    /// slow handshake, short enough that a dead network surfaces quickly.
    nonisolated(unsafe) static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        // Uploads carry PDFs, so the whole-resource budget is larger.
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: - Per-business auth

    /// The device token for the business the app is currently acting as.
    ///
    /// Set when the active business changes. The backend derives the businessId
    /// from this token, so a request without it can no longer name a business.
    nonisolated(unsafe) static var activeBusinessToken: String?

    /// Attach the caller's identity to a request.
    ///
    /// The business token is what authorizes business-scoped routes. The admin key
    /// is still sent because a few genuinely platform-level routes accept it, but
    /// it no longer grants access to anyone else's data.
    fileprivate func applyAuthHeaders(_ req: inout URLRequest, adminKey: String) {
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        if let token = PortalBackend.activeBusinessToken, !token.isEmpty {
            req.setValue(token, forHTTPHeaderField: "x-sbw-business-token")
        }
    }

    fileprivate func requireAdminKey() throws -> String {
        guard let k = PortalSecrets.portalAdminKey(), !k.isEmpty else {
            throw PortalBackendError.missingAdminKey
        }
        return k
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    // MARK: - Seed

    /// Calls /api/portal-session/seed (this also indexes invoice/contract metadata now).
    func seedToken(payload: [String: Any]) async throws -> PortalSeedResponseDTO {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/portal-session/seed")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        do { return try decoder().decode(PortalSeedResponseDTO.self, from: data) }
        catch { throw PortalBackendError.decode(body: raw) }
    }

    // MARK: - Token builders

    func createInvoicePortalToken(
        invoice: Invoice,
        business: Business? = nil,
        businessName: String? = nil,
        mode: String = "live"
    ) async throws -> String {
        guard let clientId = invoice.client?.id else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invoice must be linked to a client to create a portal link."])
        }
        
        // This seed also files the document in the client's portal, so a
        // draft estimate must never get here.
        if invoice.isUnsentDocument {
            let noun = invoice.documentType == "estimate" ? "estimate" : "invoice"
            throw NSError(domain: "Portal", code: 409, userInfo: [NSLocalizedDescriptionKey: "Send this \(noun) before opening it in the client portal."])
        }

        let lineItems = buildPortalLineItems(invoice: invoice)
        let subtotalCents = portalSubtotalCents(from: lineItems)
        let taxCents = portalTaxCents(invoice: invoice)
        let totalCents = portalTotalCents(invoice: invoice)

        var body: [String: Any] = [
            "businessId": invoice.businessID.uuidString,
            "clientId": clientId.uuidString,
            "scope": "invoice",
            "mode": mode,
            "invoiceId": invoiceIdString(invoice),
            "invoiceNumber": invoice.invoiceNumber,
            "amountCents": totalCents,
            "currency": "usd",
            "subtotalCents": subtotalCents,
            "taxCents": taxCents,
            "lineItems": lineItems,
            "status": invoice.isPaid ? "paid" : "unpaid",
            "title": "Invoice \(invoice.invoiceNumber)",
            "updatedAtMs": Int(Date().timeIntervalSince1970 * 1000),
            "brandName": (businessName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "clientPortalEnabled": invoice.client?.portalEnabled ?? true,
            "paymentMethods": paymentMethodsPayload(for: business)
        ]

        // Without these the backend guessed the type from an "EST-" number
        // prefix, so a named estimate ("TF Estimate") was filed as an unpaid
        // invoice — listed under Invoices, and its estimate link unavailable.
        if invoice.documentType != "estimate" {
            body.merge(Self.invoiceBalanceFields(invoice)) { _, new in new }
        }
        if invoice.documentType == "estimate" {
            let status = invoice.estimateStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            body["documentType"] = "estimate"
            body["estimateStatus"] = status
            body["status"] = status
            body["title"] = "Estimate \(invoice.invoiceNumber)"
        }

        return try await seedToken(payload: body).token
    }

    func createContractPortalToken(contract: Contract, businessName: String? = nil, mode: String = "live") async throws -> String {
        guard let client = contract.resolvedClient else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Choose a client for this contract first."])
        }
        // Minting a token lists the contract in the client's portal, so a
        // draft opened "in the portal" used to leak there, signable.
        guard contract.status != .draft else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Send the contract before opening it in the client portal."])
        }

        let body: [String: Any] = [
            "businessId": client.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "contract",
            "mode": mode,
            "contractId": contractIdString(contract),
            "contractTitle": contract.title,
            "status": contract.statusRaw,
            "title": contract.title,
            "updatedAtMs": Int(contract.updatedAt.timeIntervalSince1970 * 1000),
            "brandName": (businessName ?? "SmallBiz Workspace").trimmingCharacters(in: .whitespacesAndNewlines),
            "clientPortalEnabled": client.portalEnabled
        ]

        return try await seedToken(payload: body).token
    }

    func createClientDirectoryPortalToken(client: Client, businessName: String? = nil, mode: String = "live") async throws -> String {
        let body: [String: Any] = [
            "businessId": client.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "directory",
            "mode": mode,
            "brandName": (businessName ?? "SmallBiz Workspace").trimmingCharacters(in: .whitespacesAndNewlines),
            "clientPortalEnabled": client.portalEnabled
        ]

        return try await seedToken(payload: body).token
    }

    // MARK: - URL builders

    /// Compatibility overload (some call sites pass Any?)
    func portalInvoiceURL(invoiceId: String, token: String, mode: Any? = nil) -> URL {
        let m = (mode as? String) ?? "live"
        return portalInvoiceURL(invoiceId: invoiceId, token: token, mode: m)
    }

    func portalInvoiceURL(invoiceId: String, token: String, mode: String = "live") -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/portal/invoice/\(invoiceId)"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "mode", value: mode)
        ]
        return comps.url!
    }

    func portalEstimateURL(estimateId: String, token: String, mode: String = "live") -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/portal/estimate/\(estimateId)"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "mode", value: mode)
        ]
        return comps.url!
    }

    func portalContractURL(contractId: String, token: String, mode: String = "live") -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/portal/contract/\(contractId)"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "mode", value: mode)
        ]
        return comps.url!
    }

    func portalClientDirectoryURL(clientId: String, token: String, mode: String = "live") -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/portal/client/\(clientId)"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "t", value: token),
            URLQueryItem(name: "mode", value: mode)
        ]
        return comps.url!
    }

    func publicSiteURL(handle: String) -> URL {
        publicSiteURL(handle: handle, customDomain: nil)
    }

    func publicSiteURL(handle: String, customDomain: String?) -> URL {
        let normalizedDomain = PublishedBusinessSite.normalizePublicSiteDomain(customDomain ?? "")
        if !normalizedDomain.isEmpty {
            var comps = URLComponents(string: "https://\(normalizedDomain)")!
            comps.path = "/"
            return comps.url!
        }

        let normalized = PublishedBusinessSite.normalizeHandle(handle)
        let safeHandle = normalized.isEmpty ? handle : normalized
        var comps = URLComponents(string: "https://biz.smallbizworkspace.com")!
        comps.path = "/\(safeHandle)"
        return comps.url!
    }

    // MARK: - Public Site Admin

    private struct PublicSiteAssetUploadResponseDTO: Decodable {
        let ok: Bool?
        let url: String?
        let error: String?
    }

    private struct PublicSiteUpsertResponseDTO: Decodable {
        let ok: Bool?
        let error: String?
    }

    private struct PublicSiteDomainUpsertBody: Encodable {
        let domain: String
        let businessId: String
        let handle: String
        let includeWww: Bool
    }

    func uploadPublicSiteAssetToBlob(
        businessId: String,
        handle: String,
        kind: String,
        fileName: String,
        data: Data
    ) async throws -> String {
        let adminKey = try requireAdminKey()

        let endpoint = baseURL.appendingPathComponent("/api/public-site/asset-upload")
        let boundary = "Boundary-\(UUID().uuidString)"

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField("businessId", businessId)
        appendField("handle", PublishedBusinessSite.normalizeHandle(handle))
        appendField("kind", kind)
        appendField("fileName", fileName)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = body

        let (bodyData, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: bodyData, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: "/api/public-site/asset-upload")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw, path: "/api/public-site/asset-upload")
        }

        let decoded = try decoder().decode(PublicSiteAssetUploadResponseDTO.self, from: bodyData)
        if let err = decoded.error, !err.isEmpty {
            throw PortalBackendError.http(http.statusCode, body: err, path: "/api/public-site/asset-upload")
        }
        guard decoded.ok == true, let url = decoded.url, !url.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }
        return url
    }

    func uploadSiteAssetToBlob(
        businessId: String,
        handle: String,
        kind: String,
        fileName: String,
        data: Data
    ) async throws -> String {
        try await uploadPublicSiteAssetToBlob(
            businessId: businessId,
            handle: handle,
            kind: kind,
            fileName: fileName,
            data: data
        )
    }

    func upsertPublicSite(
        businessId: String,
        handle: String,
        payload: PublicSiteUpsertPayload
    ) async throws -> Bool {
        let adminKey = try requireAdminKey()

        let endpoint = baseURL.appendingPathComponent("/api/public-site/upsert")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let normalizedHandle = PublishedBusinessSite.normalizeHandle(handle)
        let body: [String: Any] = [
            "businessId": businessId,
            "handle": normalizedHandle,
            "appName": payload.appName,
            "heroUrl": payload.heroUrl ?? NSNull(),
            "aboutUrl": payload.aboutUrl ?? NSNull(),
            "services": payload.services,
            "aboutUs": payload.aboutUs,
            "team": payload.team,
            "teamV2": payload.teamV2?.map { member -> [String: Any] in
                [
                    "id": member.id,
                    "name": member.name,
                    "title": member.title,
                    "photoUrl": member.photoUrl ?? NSNull()
                ]
            } ?? [],
            "galleryUrls": payload.galleryUrls,
            "updatedAtMs": payload.updatedAtMs
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (bodyData, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: bodyData, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        if let decoded = try? decoder().decode(PublicSiteUpsertResponseDTO.self, from: bodyData) {
            if let err = decoded.error, !err.isEmpty { throw PortalBackendError.http(http.statusCode, body: err) }
            return decoded.ok ?? true
        }

        return true
    }

    func upsertPublicSiteDomainMapping(
        domain: String,
        businessId: String,
        handle: String,
        includeWww: Bool
    ) async throws {
        let adminKey = try requireAdminKey()
        let normalizedDomain = PublishedBusinessSite.normalizePublicSiteDomain(domain)
        let normalizedHandle = PublishedBusinessSite.normalizeHandle(handle)

        guard !normalizedDomain.isEmpty else {
            throw PortalBackendError.decode(body: "Domain is required.")
        }
        guard !normalizedHandle.isEmpty else {
            throw PortalBackendError.decode(body: "Handle is required.")
        }

        let endpointPath = "/api/public-site/domain/upsert"
        let endpoint = baseURL.appendingPathComponent(endpointPath)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let body = PublicSiteDomainUpsertBody(
            domain: normalizedDomain,
            businessId: businessId,
            handle: normalizedHandle,
            includeWww: includeWww
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (bodyData, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: bodyData, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: endpointPath)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw, path: endpointPath)
        }

        if bodyData.isEmpty { return }
        if let decoded = try? decoder().decode(PublicSiteUpsertResponseDTO.self, from: bodyData) {
            if let err = decoded.error, !err.isEmpty {
                throw PortalBackendError.http(http.statusCode, body: err, path: endpointPath)
            }
            if decoded.ok == false {
                throw PortalBackendError.http(http.statusCode, body: raw, path: endpointPath)
            }
        }
    }

    func verifyPublicSiteDomain(domain: String) async -> DomainVerifyDTO {
        let normalizedDomain = PublishedBusinessSite.normalizePublicSiteDomain(domain)
        guard !normalizedDomain.isEmpty else {
            return DomainVerifyDTO(
                ok: false,
                mapped: false,
                status: "unmapped",
                handle: nil,
                businessId: nil,
                canonicalUrl: nil,
                error: "INVALID_DOMAIN"
            )
        }

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/public-site/domain/verify"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "domain", value: normalizedDomain)]
        guard let url = comps.url else {
            return DomainVerifyDTO(
                ok: false,
                mapped: false,
                status: "unmapped",
                handle: nil,
                businessId: nil,
                canonicalUrl: nil,
                error: "INVALID_URL"
            )
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"

        do {
            let (data, _) = try await PortalBackend.session.data(for: req)
            if let decoded = try? decoder().decode(DomainVerifyDTO.self, from: data) {
                return decoded
            }
            return DomainVerifyDTO(
                ok: false,
                mapped: false,
                status: "unmapped",
                handle: nil,
                businessId: nil,
                canonicalUrl: nil,
                error: "INVALID_RESPONSE"
            )
        } catch {
            return DomainVerifyDTO(
                ok: false,
                mapped: false,
                status: "unmapped",
                handle: nil,
                businessId: nil,
                canonicalUrl: nil,
                error: error.localizedDescription
            )
        }
    }

    // MARK: - Back-compat builders (used by other views)

    func buildClientDirectoryPortalURL(client: Client, token: String, mode: String = "live") -> URL {
        portalClientDirectoryURL(clientId: client.id.uuidString, token: token, mode: mode)
    }

    func buildContractPortalURL(contract: Contract, token: String, mode: String = "live") -> URL {
        portalContractURL(contractId: contractIdString(contract), token: token, mode: mode)
    }

    // MARK: - Index helpers (used by other files)

    func indexInvoiceForDirectory(invoice: Invoice, client: Client) async throws {
        _ = try await createInvoicePortalToken(invoice: invoice, businessName: nil, mode: "live")
    }

    func indexContractForDirectory(contract: Contract, client: Client) async throws {
        _ = try await createContractPortalToken(contract: contract, businessName: nil, mode: "live")
    }

    @MainActor
    func indexInvoiceForPortalDirectory(
        invoice: Invoice,
        business: Business? = nil,
        pdfUrl: String? = nil
    ) async throws {
        guard let client = invoice.client else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invoice is not linked to a client."])
        }
        guard client.portalEnabled else { return }
        
        let lineItems = buildPortalLineItems(invoice: invoice)
        let subtotalCents = portalSubtotalCents(from: lineItems)
        let taxCents = portalTaxCents(invoice: invoice)
        let totalCents = portalTotalCents(invoice: invoice)

        var body: [String: Any] = [
            "businessId": invoice.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "invoice",
            "mode": "live",
            "documentType": "invoice",
            "invoiceId": invoiceIdString(invoice),
            "invoiceNumber": invoice.invoiceNumber,
            "issueDateMs": Int((invoice.issueDate.timeIntervalSince1970 * 1000).rounded()),
            "dueDateMs": Int((invoice.dueDate.timeIntervalSince1970 * 1000).rounded()),
            // The backend's overdue-reminder job reads "dueAtMs" specifically
            // (matching its own cron naming) — "dueDateMs" above was never
            // actually read server-side under that name. Sent alongside it
            // rather than renamed, in case anything else already depends on
            // the old key.
            "dueAtMs": Int((invoice.dueDate.timeIntervalSince1970 * 1000).rounded()),
            "clientName": client.name,
            "clientEmail": client.email.trimmingCharacters(in: .whitespacesAndNewlines),
            "amountCents": totalCents,
            "subtotalCents": subtotalCents,
            "taxCents": taxCents,
            "lineItems": lineItems,
            "currency": "usd",
            "paid": invoice.isPaid,
            "status": invoice.isPaid ? "paid" : "unpaid",
            "title": "Invoice \(invoice.invoiceNumber)",
            "updatedAtMs": Int(Date().timeIntervalSince1970 * 1000),
            "clientPortalEnabled": client.portalEnabled,
            "pdfUrl": (pdfUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "paymentMethods": paymentMethodsPayload(for: business)
        ]
        // Only present when this invoice IS a deposit tied to a bundled
        // Contract — lets the Stripe checkout route trace a paid deposit
        // back to its contract (stripeWebhookHandler.syncDepositContractReady).
        if let sourceContractId = invoice.sourceContractId, !sourceContractId.isEmpty {
            body["sourceContractId"] = sourceContractId
        }
        body.merge(Self.invoiceBalanceFields(invoice)) { _, new in new }

        _ = try await seedToken(payload: body)
    }

    /// What's been paid and what's still owed, so the portal shows the
    /// balance and checkout charges it — not the original total — after a
    /// part payment recorded in the app.
    static func invoiceBalanceFields(_ invoice: Invoice) -> [String: Any] {
        var fields: [String: Any] = [
            "paidCents": invoice.paidCents,
            "balanceDueCents": invoice.balanceDueCents,
        ]
        if invoice.balanceDueCents == 0 {
            fields["paid"] = true
            fields["status"] = "paid"
        }
        if let sentAt = invoice.sentAt {
            fields["sentAtMs"] = Int((sentAt.timeIntervalSince1970 * 1000).rounded())
        }
        return fields
    }

    /// A contract only belongs in the client-facing directory once it's been
    /// activated (sent/signed/cancelled) — a bundled contract sitting in
    /// .draft alongside an unsent estimate must never appear there. Pulled
    /// out as a pure predicate (rather than left inline) so it's directly
    /// testable without a network call.
    static func isContractReadyForDirectory(_ contract: Contract) -> Bool {
        contract.statusRaw != ContractStatus.draft.rawValue
    }

    /// IMPORTANT: scope=directory so directory tokens pass and it shows in the directory list.
    @MainActor
    func indexContractForPortalDirectory(contract: Contract) async throws {
        guard let client = contract.resolvedClient else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Contract is not linked to a client."])
        }
        guard client.portalEnabled else { return }

        // A draft that was in front of the client ("Revise terms", or one an
        // older build published): tell the server, which takes it off their
        // list and stops it being signed until it's sent again. No text goes up.
        if contract.status == .draft {
            guard contract.sentAt != nil || contract.portalLastUploadedAtMs != nil else { return }
            _ = try await seedToken(payload: [
                "businessId": client.businessID.uuidString,
                "clientId": client.id.uuidString,
                "scope": "directory",
                "mode": "live",
                "contractId": contractIdString(contract),
                "contractTitle": contract.title,
                "status": ContractStatus.draft.rawValue,
                "updatedAtMs": Int(Date().timeIntervalSince1970 * 1000),
                "clientPortalEnabled": client.portalEnabled
            ])
            return
        }
        // A contract bundled/drafted alongside an estimate stays in .draft
        // until the estimate is accepted (PortalService.markContractSentAndIndex
        // flips it to .sent as part of activation) — mirrors
        // indexEstimateForDirectory's own status gate below. Without this, a
        // draft contract could reach the client the moment any of the
        // existing eager upload triggers (e.g. tapping "Done" while
        // reviewing it) fires, before the owner ever sent the estimate.
        guard PortalBackend.isContractReadyForDirectory(contract) else { return }

        let updatedAtMs = Int(Date().timeIntervalSince1970 * 1000)

        let body: [String: Any] = [
            "businessId": client.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "directory",
            "mode": "live",
            "contractId": contractIdString(contract),
            "contractTitle": contract.title,
            "status": contract.statusRaw,
            "title": contract.title,
            "updatedAtMs": updatedAtMs,
            "contractBody": contract.renderedBody,
            "clientPortalEnabled": client.portalEnabled
        ]
        var payload = body
        // A paper signature recorded here; the server keeps a portal one.
        if contract.status == .signed {
            payload["signedName"] = contract.signedByName
            if let signedAt = contract.signedAt {
                payload["signedAtMs"] = Int(signedAt.timeIntervalSince1970 * 1000)
            }
        }

        _ = try await seedToken(payload: payload)
    }

    /// Indexes an estimate into the portal directory list.
    @MainActor
    func indexEstimateForDirectory(estimate: Invoice, pdfUrl: String? = nil) async throws {
        guard estimate.documentType == "estimate" else { return }
        guard let client = estimate.client else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Estimate is not linked to a client."])
        }
        guard client.portalEnabled else { return }

        let normalizedStatus = estimate.estimateStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard ["sent", "accepted", "declined"].contains(normalizedStatus) else { return }

        let amountCents = estimate.totalCents
        let lineItems = buildPortalLineItems(invoice: estimate)
        let subtotalCents = portalSubtotalCents(from: lineItems)
        let taxCents = portalTaxCents(invoice: estimate)

        let body: [String: Any] = [
            "businessId": estimate.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "directory",
            "mode": "live",
            "documentType": "estimate",
            "estimateId": estimate.id.uuidString,
            "invoiceId": estimate.id.uuidString,
            "invoiceNumber": estimate.invoiceNumber,
            "issueDateMs": Int((estimate.issueDate.timeIntervalSince1970 * 1000).rounded()),
            "dueDateMs": Int((estimate.dueDate.timeIntervalSince1970 * 1000).rounded()),
            "clientName": client.name,
            "amountCents": amountCents,
            "subtotalCents": subtotalCents,
            "taxCents": taxCents,
            "lineItems": lineItems,
            "currency": "usd",
            "paid": estimate.isPaid,
            "status": normalizedStatus,
            "title": "Estimate \(estimate.invoiceNumber)",
            "updatedAtMs": Int(Date().timeIntervalSince1970 * 1000),
            "clientPortalEnabled": client.portalEnabled,
            "pdfUrl": (pdfUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        _ = try await seedToken(payload: body)
    }
    
    // MARK: - PDF Upload -> Blob + KV

    private struct PDFUploadResponseDTO: Decodable {
        let ok: Bool?
        let url: String?
        let fileName: String?
        let error: String?
    }

    private struct SendLinkResponseDTO: Decodable {
        let ok: Bool?
        let link: String?
        let error: String?
    }

    // MARK: - Invoice PDF Upload

    @MainActor
    func uploadInvoicePDFToBlob(
        businessId: String,
        invoiceId: String,
        fileName: String,
        pdfData: Data
    ) async throws -> (url: String, fileName: String) {
        let adminKey = try requireAdminKey()
        let endpointPath = "/api/portal/invoice/pdf-upload"
        SBWLog.portal.note("⬆️ Portal binary upload path: \(endpointPath) bytes: \(pdfData.count)")

        do {
            return try await uploadPDFBinary(
                endpointPath: endpointPath,
                queryItems: [
                    URLQueryItem(name: "businessId", value: businessId),
                    URLQueryItem(name: "invoiceId", value: invoiceId),
                    URLQueryItem(name: "fileName", value: fileName)
                ],
                adminKey: adminKey,
                pdfData: pdfData,
                fallbackID: fileName
            )
        } catch let error as PortalBackendError {
            if case .http(let code, _, _) = error, code == 400 || code == 415 {
                SBWLog.portal.note("↩️ Falling back to legacy JSON upload path: \(endpointPath) status: \(code)")
                return try await uploadPDFLegacyJSON(
                    endpointPath: endpointPath,
                    payload: [
                        "businessId": businessId,
                        "invoiceId": invoiceId,
                        "fileName": fileName,
                        "pdfBase64": pdfData.base64EncodedString()
                    ],
                    adminKey: adminKey,
                    fallbackID: fileName
                )
            }
            throw error
        }
    }

    // Back-compat convenience (mirrors uploadContractPDF naming)
    @MainActor
    func uploadInvoicePDF(
        businessId: String,
        invoiceId: String,
        fileName: String,
        pdfData: Data
    ) async throws -> (url: String, fileName: String) {
        try await uploadInvoicePDFToBlob(
            businessId: businessId,
            invoiceId: invoiceId,
            fileName: fileName,
            pdfData: pdfData
        )
    }

    // MARK: - Contract PDF Upload

    @MainActor
    func uploadContractPDFToBlob(
        businessId: String,
        contractId: String,
        fileName: String,
        pdfData: Data
    ) async throws -> (url: String, fileName: String) {
        let adminKey = try requireAdminKey()
        let endpointPath = "/api/portal/contract/pdf-upload"
        SBWLog.portal.note("⬆️ Portal binary upload path: \(endpointPath) bytes: \(pdfData.count)")

        do {
            return try await uploadPDFBinary(
                endpointPath: endpointPath,
                queryItems: [
                    URLQueryItem(name: "businessId", value: businessId),
                    URLQueryItem(name: "contractId", value: contractId),
                    URLQueryItem(name: "fileName", value: fileName)
                ],
                adminKey: adminKey,
                pdfData: pdfData,
                fallbackID: fileName
            )
        } catch let error as PortalBackendError {
            if case .http(let code, _, _) = error, code == 400 || code == 415 {
                SBWLog.portal.note("↩️ Falling back to legacy JSON upload path: \(endpointPath) status: \(code)")
                return try await uploadPDFLegacyJSON(
                    endpointPath: endpointPath,
                    payload: [
                        "businessId": businessId,
                        "contractId": contractId,
                        "fileName": fileName,
                        "pdfBase64": pdfData.base64EncodedString()
                    ],
                    adminKey: adminKey,
                    fallbackID: fileName
                )
            }
            throw error
        }
    }

    private func uploadPDFBinary(
        endpointPath: String,
        queryItems: [URLQueryItem],
        adminKey: String,
        pdfData: Data,
        fallbackID: String
    ) async throws -> (url: String, fileName: String) {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(endpointPath), resolvingAgainstBaseURL: false) else {
            throw PortalBackendError.badURL
        }
        comps.queryItems = queryItems
        guard let endpoint = comps.url else {
            throw PortalBackendError.badURL
        }

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/pdf", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = pdfData

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: endpointPath)
        }
        guard (200...299).contains(http.statusCode) else {
            SBWLog.portal.problem("⚠️ Portal upload failed path: \(endpointPath) status: \(http.statusCode)")
            throw PortalBackendError.http(http.statusCode, body: raw, path: endpointPath)
        }

        let decoded = try decoder().decode(PDFUploadResponseDTO.self, from: data)
        if let err = decoded.error, !err.isEmpty {
            throw PortalBackendError.http(http.statusCode, body: err, path: endpointPath)
        }
        guard let url = decoded.url, !url.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }
        return (url: url, fileName: decoded.fileName ?? fallbackID)
    }

    private func uploadPDFLegacyJSON(
        endpointPath: String,
        payload: [String: Any],
        adminKey: String,
        fallbackID: String
    ) async throws -> (url: String, fileName: String) {
        let endpoint = baseURL.appendingPathComponent(endpointPath)
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: endpointPath)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw, path: endpointPath)
        }

        let decoded = try decoder().decode(PDFUploadResponseDTO.self, from: data)
        if let err = decoded.error, !err.isEmpty {
            throw PortalBackendError.http(http.statusCode, body: err, path: endpointPath)
        }
        guard let url = decoded.url, !url.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }
        return (url: url, fileName: decoded.fileName ?? fallbackID)
    }

    // Back-compat (PortalService.swift was calling this name)
    @MainActor
    func uploadContractPDF(
        businessId: String,
        contractId: String,
        fileName: String,
        pdfData: Data
    ) async throws -> (url: String, fileName: String) {
        try await uploadContractPDFToBlob(
            businessId: businessId,
            contractId: contractId,
            fileName: fileName,
            pdfData: pdfData
        )
    }
    
    @MainActor
    func sendPortalLink(
        businessId: String,
        clientId: String,
        clientEmail: String?,
        clientPhone: String?,
        businessName: String?,
        sendEmail: Bool,
        sendSms: Bool,
        ttlDays: Int = 7,
        message: String? = nil
    ) async throws -> String {

        let adminKey = try requireAdminKey()

        let endpoint = baseURL.appendingPathComponent("/api/portal/send-link")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        var payload: [String: Any] = [
            "businessId": businessId,
            "clientId": clientId,
            "sendEmail": sendEmail,
            "sendSms": sendSms,
            "ttlDays": ttlDays
        ]

        if let businessName, !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["businessName"] = businessName
        }
        if let clientEmail, !clientEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["clientEmail"] = clientEmail
        }
        if let clientPhone, !clientPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["clientPhone"] = clientPhone
        }
        if let message, !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["message"] = message
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        let decoded = try decoder().decode(SendLinkResponseDTO.self, from: data)
        if let err = decoded.error, !err.isEmpty {
            throw PortalBackendError.http(http.statusCode, body: err)
        }
        guard let link = decoded.link, !link.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }

        return link
    }

    enum EstimateEmailOutcome {
        case emailed(link: String)
        /// The estimate is in the client's portal but the email didn't go
        /// out; `link` still opens it, to share another way.
        case emailFailed(link: String, reason: String)
    }

    /// Emails the client a link to an estimate that's already published as
    /// "sent" — the server refuses anything else. See EstimateSendService.
    func sendEstimateEmail(
        estimateId: String,
        clientEmail: String,
        businessName: String?
    ) async throws -> EstimateEmailOutcome {
        let adminKey = try requireAdminKey()

        let endpoint = baseURL.appendingPathComponent("/api/portal/estimate/send-email")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        var payload: [String: Any] = [
            "estimateId": estimateId,
            "clientEmail": clientEmail
        ]
        if let businessName, !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["businessName"] = businessName
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }

        let decoded = try? decoder().decode(SendLinkResponseDTO.self, from: data)
        if http.statusCode == 502, let link = decoded?.link, !link.isEmpty {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = (json?["errorCode"] as? String) ?? decoded?.error ?? "email_failed"
            return .emailFailed(link: link, reason: reason)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: decoded?.error ?? raw)
        }
        guard let link = decoded?.link, !link.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }
        return .emailed(link: link)
    }

    // MARK: - Notification settings

    /// Pushes the business's overdue-reminder preference up so the backend
    /// cron job (which has no other way to read on-device settings) can act
    /// on it. Best-effort: a sync failure here just means the backend keeps
    /// using whatever it last had — it never blocks the local save.
    func syncOverdueReminderSettings(enabled: Bool, cadenceDays: Int) async throws {
        let adminKey = try requireAdminKey()

        let endpoint = baseURL.appendingPathComponent("/api/notifications/settings")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let payload: [String: Any] = [
            "settings": [
                "overdueReminders": [
                    "enabled": enabled,
                    "cadenceDays": cadenceDays
                ]
            ]
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Recurring invoice schedules

    /// The backend can't read SwiftData, so a schedule's client email rides
    /// along explicitly rather than being looked up server-side — the caller
    /// already has the `Client` in hand.
    func upsertRecurringSchedule(_ schedule: RecurringInvoiceSchedule, clientEmail: String) async throws {
        let adminKey = try requireAdminKey()

        let endpoint = baseURL.appendingPathComponent("/api/recurring/schedule")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let lineItemsPayload: [[String: Any]] = schedule.lineItems.map { item in
            [
                "description": item.itemDescription,
                "quantity": item.quantity,
                "unitPriceCents": Int((item.unitPrice * 100).rounded())
            ]
        }

        let payload: [String: Any] = [
            "scheduleId": schedule.id.uuidString,
            "clientId": schedule.clientID.uuidString,
            "clientEmail": clientEmail.trimmingCharacters(in: .whitespacesAndNewlines),
            "active": schedule.active,
            "cadence": schedule.cadence.rawValue,
            "nextRunAtMs": Int((schedule.nextRunAt.timeIntervalSince1970 * 1000).rounded()),
            "netDays": schedule.netDays,
            "invoiceNumberPrefix": schedule.invoiceNumberPrefix,
            "taxRatePercent": schedule.taxRatePercent,
            "discountAmountCents": Int((schedule.discountAmount * 100).rounded()),
            "lineItems": lineItemsPayload
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    func deleteRecurringSchedule(scheduleId: UUID) async throws {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/recurring/schedule"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "scheduleId", value: scheduleId.uuidString)]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "DELETE"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: String(data: data, encoding: .utf8) ?? "")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Invoices the generation cron produced since `since` that no device has
    /// materialized yet. See the backend's `/api/recurring/pull` for how a
    /// re-uploaded (reviewed) invoice naturally drops out of this list.
    func pullGeneratedRecurringInvoices(since: Date) async throws -> [GeneratedRecurringInvoiceDTO] {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/recurring/pull"),
            resolvingAgainstBaseURL: false
        )!
        let sinceMs = Int((since.timeIntervalSince1970 * 1000).rounded())
        comps.queryItems = [URLQueryItem(name: "since", value: String(sinceMs))]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        let decoded = try decoder().decode(PullRecurringResponseDTO.self, from: data)
        return decoded.invoices
    }

    /// Estimates accepted or declined since `since`, oldest first. See the
    /// backend's `/api/estimate/decisions/pull` — unlike the recurring-invoice
    /// pull above, nothing here needs generating: the estimate and any bundled
    /// draft contract already exist locally, so this only answers "was
    /// estimate X accepted or declined, and when."
    func pullEstimateDecisions(since: Date) async throws -> [EstimateDecisionDTO] {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/estimate/decisions/pull"),
            resolvingAgainstBaseURL: false
        )!
        let sinceMs = Int((since.timeIntervalSince1970 * 1000).rounded())
        comps.queryItems = [URLQueryItem(name: "since", value: String(sinceMs))]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        let decoded = try decoder().decode(PullEstimateDecisionsResponseDTO.self, from: data)
        return decoded.decisions
    }

    // MARK: - Invoice lifecycle

    /// Emails the client a link to view and pay an invoice that's already
    /// in their portal (kind "send"), or a reminder (kind "reminder"). The
    /// server refuses drafts, paid invoices and estimates.
    func sendInvoiceEmail(
        invoiceId: String,
        clientEmail: String,
        businessName: String?,
        kind: String
    ) async throws -> EstimateEmailOutcome {
        let adminKey = try requireAdminKey()

        var req = URLRequest(url: baseURL.appendingPathComponent("/api/portal/invoice/send-email"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        var payload: [String: Any] = [
            "invoiceId": invoiceId,
            "clientEmail": clientEmail,
            "kind": kind,
            // So the email prints the due date on the owner's calendar day.
            "timeZone": TimeZone.current.identifier
        ]
        if let businessName, !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["businessName"] = businessName
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        let decoded = try? decoder().decode(SendLinkResponseDTO.self, from: data)
        if http.statusCode == 502, let link = decoded?.link, !link.isEmpty {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = (json?["errorCode"] as? String) ?? decoded?.error ?? "email_failed"
            return .emailFailed(link: link, reason: reason)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: decoded?.error ?? raw)
        }
        guard let link = decoded?.link, !link.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }
        return .emailed(link: link)
    }

    /// Emails the client a link to sign (kind "send") or a reminder
    /// ("reminder"). The contract must already be published as sent.
    func sendContractEmail(
        contractId: String,
        clientEmail: String,
        businessName: String?,
        kind: String
    ) async throws -> EstimateEmailOutcome {
        let adminKey = try requireAdminKey()

        var req = URLRequest(url: baseURL.appendingPathComponent("/api/portal/contract/send-email"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        var payload: [String: Any] = [
            "contractId": contractId,
            "clientEmail": clientEmail,
            "kind": kind
        ]
        if let businessName, !businessName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["businessName"] = businessName
        }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        let decoded = try? decoder().decode(SendLinkResponseDTO.self, from: data)
        if http.statusCode == 502, let link = decoded?.link, !link.isEmpty {
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let reason = (json?["errorCode"] as? String) ?? decoded?.error ?? "email_failed"
            return .emailFailed(link: link, reason: reason)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: decoded?.error ?? raw)
        }
        guard let link = decoded?.link, !link.isEmpty else {
            throw PortalBackendError.decode(body: raw)
        }
        return .emailed(link: link)
    }

    struct ContractActivityDTO: Decodable {
        let contractId: String
        let status: String?
        let signedAtMs: Double?
        let signedName: String?
        let signedBodyHash: String?
        let signedPdfUrl: String?
        let signedMethod: String?
        let sentAtMs: Double?
        let lastReminderAtMs: Double?
        let updatedAtMs: Double
    }

    struct ContractActivityPage: Decodable {
        let ok: Bool?
        let items: [ContractActivityDTO]
        let hasMore: Bool?
    }

    /// Signatures and emails the portal saw since `since` — the feed behind
    /// ContractActivityPullService.
    func pullContractActivity(since: Date) async throws -> ContractActivityPage {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/contracts/activity/pull"),
            resolvingAgainstBaseURL: false
        )!
        let sinceMs = Int((since.timeIntervalSince1970 * 1000).rounded())
        comps.queryItems = [URLQueryItem(name: "since", value: String(sinceMs))]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }
        return try decoder().decode(ContractActivityPage.self, from: data)
    }

    struct InvoiceActivityDTO: Decodable {
        let invoiceId: String
        let paid: Bool?
        let paidAtMs: Double?
        let paidOnlineCents: Int?
        let provider: String?
        let viewedAtMs: Double?
        let sentAtMs: Double?
        let lastReminderAtMs: Double?
        let updatedAtMs: Double
    }

    struct InvoiceActivityPage: Decodable {
        let ok: Bool?
        let items: [InvoiceActivityDTO]
        let hasMore: Bool?
    }

    /// Payments and views the portal saw since `since` — the feed behind
    /// InvoiceActivityPullService.
    func pullInvoiceActivity(since: Date) async throws -> InvoiceActivityPage {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/invoices/activity/pull"),
            resolvingAgainstBaseURL: false
        )!
        let sinceMs = Int((since.timeIntervalSince1970 * 1000).rounded())
        comps.queryItems = [URLQueryItem(name: "since", value: String(sinceMs))]

        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }
        return try decoder().decode(InvoiceActivityPage.self, from: data)
    }

    // MARK: - Payment status

    func fetchPaymentStatus(businessId: String, invoiceId: String) async throws -> PaymentStatusResponse {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/payment-status"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId),
            URLQueryItem(name: "invoiceId", value: invoiceId)
        ]

        guard let url = comps.url else { throw PortalBackendError.badURL }

        let (data, resp) = try await PortalBackend.session.data(from: url)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        do { return try decoder().decode(PaymentStatusResponse.self, from: data) }
        catch { throw PortalBackendError.decode(body: raw) }
    }

    // MARK: - Estimate status

    func fetchEstimateStatus(
        businessId: String,
        estimateId: String
    ) async throws -> (status: String, decidedAt: Date?) {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/portal/estimate/status"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId),
            URLQueryItem(name: "estimateId", value: estimateId)
        ]
        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        let decoded: EstimateStatusResponseDTO
        do {
            decoded = try decoder().decode(EstimateStatusResponseDTO.self, from: data)
        } catch {
            throw PortalBackendError.decode(body: raw)
        }

        let normalized = decoded.status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "draft"

        let decidedAt = parsePortalDate(decoded.decidedAt)
            ?? parsePortalDate(decoded.acceptedAt)
            ?? parsePortalDate(decoded.declinedAt)
            ?? parsePortalDate(decoded.updatedAt)

        return (status: normalized, decidedAt: decidedAt)
    }

    private func parsePortalDate(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let value = Double(trimmed) {
            if value > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: value / 1000.0)
            }
            return Date(timeIntervalSince1970: value)
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: trimmed)
    }

    private func paymentMethodsPayload(for business: Business?) -> [String: Any] {
        guard let business else { return [:] }
        return [
            "stripeEnabled": business.stripeChargesEnabled && business.stripePayoutsEnabled,
            "paypalPlatformEnabled": business.paypalEnabled,
            "paypalFallbackUrl": (business.paypalMeFallback ?? business.paypalMeUrl ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "squareEnabled": business.squareEnabled,
            "squareLink": (business.squareLink ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "cashAppEnabled": business.cashAppEnabled,
            "cashAppLink": (business.cashAppHandleOrLink ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "venmoEnabled": business.venmoEnabled,
            "venmoLink": (business.venmoHandleOrLink ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "achEnabled": business.achEnabled,
            "achRecipientName": (business.achRecipientName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "achBankName": (business.achBankName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "achAccountLast4": (business.achAccountLast4 ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "achRoutingLast4": (business.achRoutingLast4 ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "achInstructions": (business.achInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ]
    }

    // MARK: - Booking Admin

    private struct RegisterBookingSlugResponseDTO: Decodable {
        let ok: Bool?
        let brandName: String?
        let ownerEmail: String?
        let error: String?
    }

    func upsertBookingSlug(
        businessId: UUID,
        slug: String,
        brandName: String,
        ownerEmail: String
    ) async throws {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/booking/admin/slug")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let trimmedBrand = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload: [String: Any] = [
            "businessId": businessId.uuidString,
            "slug": slug,
            "brandName": trimmedBrand,
            "ownerEmail": trimmedOwner
        ]
        #if DEBUG
        SBWLog.portal.note("[bookinglink] upsert request \(payload)")
        #endif
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            #if DEBUG
            SBWLog.portal.problem("[bookinglink] upsert response error \(raw)")
            #endif
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            #if DEBUG
            SBWLog.portal.problem("[bookinglink] upsert response error \(http.statusCode) \(raw)")
            #endif
            throw PortalBackendError.http(http.statusCode, body: raw)
        }
    }

    func fetchBookingRequests(businessId: UUID) async throws -> [BookingRequestDTO] {
        let adminKey = try requireAdminKey()

        SBWLog.portal.note("📥 Fetch booking requests businessId: \(businessId.uuidString)")

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/booking/admin/requests"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId.uuidString)
        ]

        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        do {
            return try decoder().decode([BookingRequestDTO].self, from: data)
        } catch {
            do {
                let wrapped = try decoder().decode(BookingRequestsResponseDTO.self, from: data)
                return wrapped.requests
            } catch {
                throw PortalBackendError.decode(body: raw)
            }
        }
    }

    func fetchBookingRequests(
        businessId: String,
        status: String
    ) async throws -> [BookingRequestDTO] {
        let adminKey = try requireAdminKey()

        SBWLog.portal.note("📥 Fetch booking requests businessId: \(businessId) status: \(status)")

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/booking/admin/requests"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId),
            URLQueryItem(name: "status", value: status)
        ]

        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        do {
            return try decoder().decode([BookingRequestDTO].self, from: data)
        } catch {
            do {
                let wrapped = try decoder().decode(BookingRequestsResponseDTO.self, from: data)
                return wrapped.requests
            } catch {
                throw PortalBackendError.decode(body: raw)
            }
        }
    }

    func fetchBookingSettings(businessId: UUID) async throws -> BookingSettingsDTO {
        try await fetchBookingSettings(businessId: businessId.uuidString)
    }

    func fetchBookingSettings(businessId: String) async throws -> BookingSettingsDTO {
        let adminKey = try requireAdminKey()

        #if DEBUG
        SBWLog.portal.note("📥 BookingSettings fetch: businessId=\(businessId)")
        #endif

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/booking/settings"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId)
        ]

        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            // Backward compatibility route.
            return try await fetchBookingSettingsLegacy(businessId: businessId, adminKey: adminKey)
        }

        #if DEBUG
        SBWLog.portal.note("✅ BookingSettings fetch response: \(raw)")
        #endif

        if let dto = try? decoder().decode(BookingSettingsDTO.self, from: data) {
            return dto
        }
        if let wrapped = try? decoder().decode(BookingSettingsEnvelopeDTO.self, from: data),
           let dto = wrapped.settings ?? wrapped.data {
            return dto
        }
        throw PortalBackendError.decode(body: raw)
    }

    func upsertBookingSettings(
        businessId: UUID,
        settings: BookingSettingsDTO
    ) async throws -> BookingSettingsDTO {
        try await upsertBookingSettings(businessId: businessId.uuidString, settings: settings)
    }

    func upsertBookingSettings(
        businessId: String,
        settings: BookingSettingsDTO
    ) async throws -> BookingSettingsDTO {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/booking/settings/upsert")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let normalizedSlug = settings.slug?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBrand = settings.brandName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOwner = settings.ownerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let slotMinutes = settings.slotMinutes ?? settings.bookingSlotMinutes ?? 30
        let bookingSlotMinutes = settings.bookingSlotMinutes ?? settings.slotMinutes ?? slotMinutes

        let normalizedServices = (settings.services ?? [])
            .map {
                BookingServiceOption(
                    name: $0.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    durationMinutes: max(1, $0.durationMinutes)
                )
            }
            .filter { !$0.name.isEmpty }

        let normalizedHoursDict: [String: [String: String?]]
        if let hours = settings.businessHours, !hours.isEmpty {
            normalizedHoursDict = hours
        } else if let hoursJson = settings.hoursJson,
                  let cfg = PortalHoursConfig.fromJSON(hoursJson) {
            normalizedHoursDict = cfg.toBusinessHoursDict()
        } else {
            normalizedHoursDict = PortalHoursConfig.defaultClosed().toBusinessHoursDict()
        }
        let normalizedHoursJSON = PortalHoursConfig.fromBusinessHoursDict(normalizedHoursDict).toJSON() ?? "{}"

        let ownerEmailValue: Any = (normalizedOwner?.isEmpty == false) ? (normalizedOwner ?? "") : NSNull()
        let payload: [String: Any] = [
            "businessId": businessId,
            "slug": normalizedSlug ?? "",
            "brandName": normalizedBrand ?? "",
            "ownerEmail": ownerEmailValue,
            "services": normalizedServices.map { svc in
                [
                    "name": svc.name,
                    "durationMinutes": svc.durationMinutes,
                    "duration_minutes": svc.durationMinutes
                ]
            },
            "businessHours": normalizedHoursDict,
            "business_hours": normalizedHoursDict,
            "hoursJson": normalizedHoursJSON,
            "hours_json": normalizedHoursJSON,
            "slotMinutes": slotMinutes,
            "slot_minutes": slotMinutes,
            "bookingSlotMinutes": bookingSlotMinutes,
            "booking_slot_minutes": bookingSlotMinutes,
            "minBookingMinutes": settings.minBookingMinutes ?? NSNull(),
            "min_booking_minutes": settings.minBookingMinutes ?? NSNull(),
            "maxBookingMinutes": settings.maxBookingMinutes ?? NSNull(),
            "max_booking_minutes": settings.maxBookingMinutes ?? NSNull(),
            "allowSameDay": settings.allowSameDay ?? false,
            "allow_same_day": settings.allowSameDay ?? false,
            // The booking page shows times in this zone; left out, the server
            // used to reset it to New York on every save.
            "timezone": TimeZone.current.identifier
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        #if DEBUG
        if let payloadJSONString = String(data: payloadData, encoding: .utf8) {
            SBWLog.portal.note("⬆️ BookingSettings upsert payload: \(payloadJSONString)")
        } else {
            SBWLog.portal.note("⬆️ BookingSettings upsert payload: <non-utf8 payload>")
        }
        #endif

        req.httpBody = payloadData

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            // Backward compatibility route.
            return try await upsertBookingSettingsLegacy(businessId: businessId, settings: settings, adminKey: adminKey)
        }

        #if DEBUG
        SBWLog.portal.note("✅ BookingSettings upsert response: \(raw)")
        #endif

        if let dto = try? decoder().decode(BookingSettingsDTO.self, from: data) {
            return dto
        }
        if let wrapped = try? decoder().decode(BookingSettingsEnvelopeDTO.self, from: data),
           let dto = wrapped.settings ?? wrapped.data {
            return dto
        }

        return BookingSettingsDTO(
            businessId: businessId,
            slug: normalizedSlug,
            brandName: normalizedBrand,
            ownerEmail: normalizedOwner?.isEmpty == true ? nil : normalizedOwner,
            services: normalizedServices,
            businessHours: normalizedHoursDict,
            hoursJson: normalizedHoursJSON,
            slotMinutes: slotMinutes,
            bookingSlotMinutes: bookingSlotMinutes,
            minBookingMinutes: settings.minBookingMinutes,
            maxBookingMinutes: settings.maxBookingMinutes,
            allowSameDay: settings.allowSameDay
        )
    }

    private func fetchBookingSettingsLegacy(
        businessId: String,
        adminKey: String
    ) async throws -> BookingSettingsDTO {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/booking/admin/settings"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "businessId", value: businessId)]
        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        #if DEBUG
        SBWLog.portal.note("✅ BookingSettings fetch response (legacy): \(raw)")
        #endif
        if let dto = try? decoder().decode(BookingSettingsDTO.self, from: data) {
            return dto
        }
        if let wrapped = try? decoder().decode(BookingSettingsEnvelopeDTO.self, from: data),
           let dto = wrapped.settings ?? wrapped.data {
            return dto
        }
        throw PortalBackendError.decode(body: raw)
    }

    private func upsertBookingSettingsLegacy(
        businessId: String,
        settings: BookingSettingsDTO,
        adminKey: String
    ) async throws -> BookingSettingsDTO {
        let url = baseURL.appendingPathComponent("/api/booking/admin/settings")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        var fallbackSettings = settings
        if fallbackSettings.businessId == nil {
            fallbackSettings = BookingSettingsDTO(
                businessId: businessId,
                slug: settings.slug,
                brandName: settings.brandName,
                ownerEmail: settings.ownerEmail,
                services: settings.services,
                businessHours: settings.businessHours,
                hoursJson: settings.hoursJson,
                slotMinutes: settings.slotMinutes,
                bookingSlotMinutes: settings.bookingSlotMinutes,
                minBookingMinutes: settings.minBookingMinutes,
                maxBookingMinutes: settings.maxBookingMinutes,
                allowSameDay: settings.allowSameDay
            )
        }

        req.httpBody = try JSONEncoder().encode(fallbackSettings)
        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        #if DEBUG
        SBWLog.portal.note("✅ BookingSettings upsert response (legacy): \(raw)")
        #endif

        if let dto = try? decoder().decode(BookingSettingsDTO.self, from: data) {
            return dto
        }
        if let wrapped = try? decoder().decode(BookingSettingsEnvelopeDTO.self, from: data),
           let dto = wrapped.settings ?? wrapped.data {
            return dto
        }
        return fallbackSettings
    }

    // MARK: - Notification Inbox

    func fetchNotifications(businessId: UUID) async throws -> (items: [AppNotificationDTO], unreadCount: Int) {
        let adminKey = try requireAdminKey()

        // The inbox lives at /list. Plain /api/notifications has never existed
        // on the server, so the inbox always came back empty (404).
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/notifications/list"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId.uuidString)
        ]
        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        if let wrapped = try? decoder().decode(FetchNotificationsResponseDTO.self, from: data) {
            return (wrapped.items, wrapped.unreadCount)
        }
        if let array = try? decoder().decode([AppNotificationDTO].self, from: data) {
            return (array, array.filter { $0.readAtMs == nil }.count)
        }
        throw PortalBackendError.decode(body: raw)
    }

    func markNotificationRead(businessId: UUID, notificationId: String) async throws {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/notifications/read")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "businessId": businessId.uuidString,
                "notificationId": notificationId
            ],
            options: []
        )

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
    }

    func markAllNotificationsRead(businessId: UUID) async throws {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/notifications/read-all")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "businessId": businessId.uuidString
            ],
            options: []
        )

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
    }

    // MARK: - Push registration

    func registerPushToken(
        businessId: String,
        deviceToken: String,
        environment: String
    ) async throws {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/push/register")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        let payload: [String: Any] = [
            "businessId": businessId,
            "deviceToken": deviceToken,
            "platform": "ios",
            "environment": environment
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        if data.isEmpty { return }
        if let decoded = try? decoder().decode(PushRegistrationResponseDTO.self, from: data) {
            if let error = decoded.error, !error.isEmpty {
                throw PortalBackendError.http(http.statusCode, body: error)
            }
            if decoded.ok == false {
                throw PortalBackendError.http(http.statusCode, body: raw)
            }
        }
    }

    // MARK: - Push test

    /// Sends a test push notification to all registered devices for a business.
    /// Backend route: POST /api/push/test
    // MARK: - Push test (matches backend /api/push/send)

    /// Sends a test push notification to all registered devices for a business.
    /// Backend route: POST /api/push/send
    @MainActor
    func sendTestPush(
        businessId: String,
        title: String = "Portal test push",
        body: String = "This is a push smoke test.",
        data: [String: Any]? = nil
    ) async throws {

        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent("/api/push/send")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)

        var payload: [String: Any] = [
            "businessId": businessId,
            "title": title,
            "body": body,
            "data": [
                "source": "ios-app",
                "businessId": businessId,
                "sentAtMs": Int(Date().timeIntervalSince1970 * 1000)
            ]
        ]

        // Optional extra custom data
        if let data, !data.isEmpty {
            payload["data"] = data
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (respData, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: respData, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw)
        }

        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        // Some deployments return no JSON
        guard !respData.isEmpty else { return }

        if let decoded = try? decoder().decode(SendTestPushResponseDTO.self, from: respData) {
            if let error = decoded.error, !error.isEmpty {
                throw PortalBackendError.http(http.statusCode, body: error)
            }
            if decoded.ok == false {
                throw PortalBackendError.http(http.statusCode, body: raw)
            }
        }
    }

    // MARK: - Booking Admin (scaffold)

    func approveBookingRequest(businessId: UUID, requestId: String) async throws {
        try await sendBookingAdminDecision(
            endpoint: "/api/booking/admin/approve",
            businessId: businessId.uuidString,
            requestId: requestId
        )
    }

    func declineBookingRequest(businessId: UUID, requestId: String) async throws {
        try await sendBookingAdminDecision(
            endpoint: "/api/booking/admin/decline",
            businessId: businessId.uuidString,
            requestId: requestId
        )
    }

    func approveBookingRequest(businessId: String, requestId: String) async throws {
        try await sendBookingAdminDecision(
            endpoint: "/api/booking/admin/approve",
            businessId: businessId,
            requestId: requestId
        )
    }

    func declineBookingRequest(businessId: String, requestId: String) async throws {
        try await sendBookingAdminDecision(
            endpoint: "/api/booking/admin/decline",
            businessId: businessId,
            requestId: requestId
        )
    }

    func requestBookingDeposit(
        businessId: UUID,
        requestId: String,
        depositAmountCents: Int,
        clientEmail: String?,
        clientPhone: String?,
        businessName: String?,
        sendEmail: Bool,
        sendSms: Bool
    ) async throws -> BookingDepositResponseDTO {
        try await requestBookingDeposit(
            businessId: businessId.uuidString,
            requestId: requestId,
            depositAmountCents: depositAmountCents,
            clientEmail: clientEmail,
            clientPhone: clientPhone,
            businessName: businessName,
            sendEmail: sendEmail,
            sendSms: sendSms
        )
    }

    func requestBookingDeposit(
        businessId: String,
        requestId: String,
        depositAmountCents: Int,
        clientEmail: String?,
        clientPhone: String?,
        businessName: String?,
        sendEmail: Bool,
        sendSms: Bool
    ) async throws -> BookingDepositResponseDTO {
        let adminKey = try requireAdminKey()
        let url = baseURL.appendingPathComponent("/api/booking/admin/request/deposit")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        let payload: [String: Any] = [
            "businessId": businessId,
            "requestId": requestId,
            "depositAmountCents": max(0, depositAmountCents),
            "clientEmail": (clientEmail ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "clientPhone": (clientPhone ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "businessName": (businessName ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            "sendEmail": sendEmail,
            "sendSms": sendSms
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
        do {
            return try decoder().decode(BookingDepositResponseDTO.self, from: data)
        } catch {
            throw PortalBackendError.decode(body: raw)
        }
    }

    func fetchBookingAnalytics(
        businessId: UUID,
        windowDays: Int
    ) async throws -> BookingAnalyticsDTO {
        try await fetchBookingAnalytics(
            businessId: businessId.uuidString,
            windowDays: windowDays
        )
    }

    func fetchBookingAnalytics(
        businessId: String,
        windowDays: Int
    ) async throws -> BookingAnalyticsDTO {
        let adminKey = try requireAdminKey()

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/booking/admin/analytics"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId),
            URLQueryItem(name: "window", value: String(windowDays))
        ]
        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyAuthHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        if let dto = try? decoder().decode(BookingAnalyticsDTO.self, from: data) {
            return dto
        }
        if let wrapped = try? decoder().decode(BookingAnalyticsEnvelopeDTO.self, from: data),
           let analytics = wrapped.analytics {
            return analytics
        }
        throw PortalBackendError.decode(body: raw)
    }

    func setBookingTotal(
        businessId: UUID,
        requestId: String,
        totalAmountCents: Int
    ) async throws {
        try await setBookingTotal(
            businessId: businessId.uuidString,
            requestId: requestId,
            totalAmountCents: totalAmountCents
        )
    }

    func setBookingTotal(
        businessId: String,
        requestId: String,
        totalAmountCents: Int
    ) async throws {
        let adminKey = try requireAdminKey()
        let url = baseURL.appendingPathComponent("/api/booking/admin/request/total")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        let payload: [String: Any] = [
            "businessId": businessId,
            "requestId": requestId,
            "totalAmountCents": max(1, totalAmountCents),
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
    }

    /// Booking actions that answer with the updated booking: confirm,
    /// decline, cancel, reschedule, mark the deposit paid.
    struct BookingActionResponseDTO: Decodable {
        let ok: Bool?
        let request: BookingRequestDTO?
        let emailed: Bool?
        let error: String?
    }

    func postBookingAction(path: String, payload: [String: Any]) async throws -> BookingActionResponseDTO {
        let adminKey = try requireAdminKey()
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw, path: path) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw, path: path) }
        return (try? decoder().decode(BookingActionResponseDTO.self, from: data))
            ?? BookingActionResponseDTO(ok: true, request: nil, emailed: nil, error: nil)
    }

    private func sendBookingAdminDecision(
        endpoint: String,
        businessId: String,
        requestId: String
    ) async throws {
        let adminKey = try requireAdminKey()

        let url = baseURL.appendingPathComponent(endpoint)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(&req, adminKey: adminKey)
        let payload: [String: Any] = [
            "businessId": businessId,
            "requestId": requestId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await PortalBackend.session.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
    }
}
