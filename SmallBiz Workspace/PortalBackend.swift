//
//  PortalBackend.swift
//  SmallBiz Workspace
//

import Foundation

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
            print("🔐 PortalSecrets.plist not found or unreadable.")
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

extension PortalBackendError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAdminKey: return "Missing PORTAL_ADMIN_KEY (PortalSecrets.plist)."
        case .badURL: return "Invalid portal backend URL."
        case .http(let code, let body, let path):
            let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedPath.isEmpty {
                return "Portal backend HTTP \(code). \(body)"
            }
            return "Portal backend HTTP \(code) at \(trimmedPath). \(body)"
        case .decode(let body): return "Portal backend decode failed. \(body)"
        }
    }
}

// MARK: - DTOs (match seed route)

struct PortalSeedResponseDTO: Decodable {
    let token: String
    let expiresAt: String?
    let session: PortalSessionDTO?
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

    private func contractIdString(_ contract: Contract) -> String {
        // Contract.id is SwiftData PersistentIdentifier in this project.
        String(describing: contract.id)
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
            let discountCents = toCents(invoice.discountAmount)
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
        toCents(invoice.taxAmount)
    }

    private func portalTotalCents(invoice: Invoice) -> Int {
        toCents(invoice.total)
    }

    // MARK: - Shared

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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        do { return try decoder().decode(PortalSeedResponseDTO.self, from: data) }
        catch { throw PortalBackendError.decode(body: raw) }
    }

    // MARK: - Token builders

    func createInvoicePortalToken(invoice: Invoice, businessName: String? = nil, mode: String = "live") async throws -> String {
        guard let clientId = invoice.client?.id else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invoice must be linked to a client to create a portal link."])
        }
        
        let lineItems = buildPortalLineItems(invoice: invoice)
        let subtotalCents = portalSubtotalCents(from: lineItems)
        let taxCents = portalTaxCents(invoice: invoice)
        let totalCents = portalTotalCents(invoice: invoice)

        let body: [String: Any] = [
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
            "clientPortalEnabled": invoice.client?.portalEnabled ?? true
        ]

        return try await seedToken(payload: body).token
    }

    func createContractPortalToken(contract: Contract, businessName: String? = nil, mode: String = "live") async throws -> String {
        guard let client = contract.client else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Contract must be linked to a client to open in portal."])
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = body

        let (bodyData, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

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

        let (bodyData, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let body = PublicSiteDomainUpsertBody(
            domain: normalizedDomain,
            businessId: businessId,
            handle: normalizedHandle,
            includeWww: includeWww
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (bodyData, resp) = try await URLSession.shared.data(for: req)
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
            let (data, _) = try await URLSession.shared.data(for: req)
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
    func indexInvoiceForPortalDirectory(invoice: Invoice, pdfUrl: String? = nil) async throws {
        guard let client = invoice.client else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invoice is not linked to a client."])
        }
        guard client.portalEnabled else { return }
        
        let lineItems = buildPortalLineItems(invoice: invoice)
        let subtotalCents = portalSubtotalCents(from: lineItems)
        let taxCents = portalTaxCents(invoice: invoice)
        let totalCents = portalTotalCents(invoice: invoice)

        let body: [String: Any] = [
            "businessId": invoice.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "invoice",
            "mode": "live",
            "documentType": "invoice",
            "invoiceId": invoiceIdString(invoice),
            "invoiceNumber": invoice.invoiceNumber,
            "issueDateMs": Int((invoice.issueDate.timeIntervalSince1970 * 1000).rounded()),
            "dueDateMs": Int((invoice.dueDate.timeIntervalSince1970 * 1000).rounded()),
            "clientName": client.name,
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
            "pdfUrl": (pdfUrl ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ]

        _ = try await seedToken(payload: body)
    }

    /// IMPORTANT: scope=directory so directory tokens pass and it shows in the directory list.
    @MainActor
    func indexContractForPortalDirectory(contract: Contract) async throws {
        guard let client = contract.client else {
            throw NSError(domain: "Portal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Contract is not linked to a client."])
        }
        guard client.portalEnabled else { return }

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

        _ = try await seedToken(payload: body)
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

        let amountCents = Int((estimate.total * 100).rounded())
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
        print("⬆️ Portal binary upload", "path:", endpointPath, "bytes:", pdfData.count)

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
                print("↩️ Falling back to legacy JSON upload", "path:", endpointPath, "status:", code)
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
        print("⬆️ Portal binary upload", "path:", endpointPath, "bytes:", pdfData.count)

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
                print("↩️ Falling back to legacy JSON upload", "path:", endpointPath, "status:", code)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = pdfData

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: endpointPath)
        }
        guard (200...299).contains(http.statusCode) else {
            print("⚠️ Portal upload failed", "path:", endpointPath, "status:", http.statusCode)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

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

        let (data, resp) = try await URLSession.shared.data(for: req)
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

        let (data, resp) = try await URLSession.shared.data(from: url)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

        let trimmedBrand = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOwner = ownerEmail.trimmingCharacters(in: .whitespacesAndNewlines)

        let payload: [String: Any] = [
            "businessId": businessId.uuidString,
            "slug": slug,
            "brandName": trimmedBrand,
            "ownerEmail": trimmedOwner
        ]
        #if DEBUG
        print("[bookinglink] upsert request", payload)
        #endif
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            #if DEBUG
            print("[bookinglink] upsert response error", raw)
            #endif
            throw PortalBackendError.http(-1, body: raw)
        }
        guard (200...299).contains(http.statusCode) else {
            #if DEBUG
            print("[bookinglink] upsert response error", http.statusCode, raw)
            #endif
            throw PortalBackendError.http(http.statusCode, body: raw)
        }
    }

    func fetchBookingRequests(businessId: UUID) async throws -> [BookingRequestDTO] {
        let adminKey = try requireAdminKey()

        print("📥 Fetch booking requests", "businessId:", businessId.uuidString)

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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

        let (data, resp) = try await URLSession.shared.data(for: req)
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

        print("📥 Fetch booking requests",
              "businessId:", businessId,
              "status:", status)

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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        print("📥 BookingSettings fetch: businessId=\(businessId)")
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            // Backward compatibility route.
            return try await fetchBookingSettingsLegacy(businessId: businessId, adminKey: adminKey)
        }

        #if DEBUG
        print("✅ BookingSettings fetch response: \(raw)")
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

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
            "allow_same_day": settings.allowSameDay ?? false
        ]

        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])

        #if DEBUG
        if let payloadJSONString = String(data: payloadData, encoding: .utf8) {
            print("⬆️ BookingSettings upsert payload: \(payloadJSONString)")
        } else {
            print("⬆️ BookingSettings upsert payload: <non-utf8 payload>")
        }
        #endif

        req.httpBody = payloadData

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            // Backward compatibility route.
            return try await upsertBookingSettingsLegacy(businessId: businessId, settings: settings, adminKey: adminKey)
        }

        #if DEBUG
        print("✅ BookingSettings upsert response: \(raw)")
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        #if DEBUG
        print("✅ BookingSettings fetch response (legacy): \(raw)")
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")

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
        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        #if DEBUG
        print("✅ BookingSettings upsert response (legacy): \(raw)")
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

        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/notifications"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "businessId", value: businessId.uuidString)
        ]
        guard let url = comps.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "businessId": businessId.uuidString,
                "notificationId": notificationId
            ],
            options: []
        )

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "businessId": businessId.uuidString
            ],
            options: []
        )

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let payload: [String: Any] = [
            "businessId": businessId,
            "deviceToken": deviceToken,
            "platform": "ios",
            "environment": environment
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

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

        let (respData, resp) = try await URLSession.shared.data(for: req)
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")
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

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
        do {
            return try decoder().decode(BookingDepositResponseDTO.self, from: data)
        } catch {
            throw PortalBackendError.decode(body: raw)
        }
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")
        let payload: [String: Any] = [
            "businessId": businessId,
            "requestId": requestId,
            "totalAmountCents": max(1, totalAmountCents),
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
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
        req.setValue(adminKey, forHTTPHeaderField: "x-admin-key")
        let payload: [String: Any] = [
            "businessId": businessId,
            "requestId": requestId
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }
    }
}
