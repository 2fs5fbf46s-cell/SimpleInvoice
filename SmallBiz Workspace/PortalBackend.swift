//
//  PortalBackend.swift
//  SmallBiz Workspace
//

import Foundation

// MARK: - Config

final class PortalConfig {
    static let shared = PortalConfig()
    let baseURL = URL(string: "https://smallbizworkspace-portal-backend.vercel.app")!
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
    case http(Int, body: String)
    case decode(body: String)
}

extension PortalBackendError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAdminKey: return "Missing PORTAL_ADMIN_KEY (PortalSecrets.plist)."
        case .badURL: return "Invalid portal backend URL."
        case .http(let code, let body): return "Portal backend HTTP \(code). \(body)"
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
        case createdAt
        case approvedAt
        case declinedAt
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

        self.isHandled = false
    }
}

struct BookingRequestsResponseDTO: Decodable {
    let requests: [BookingRequestDTO]
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
                "quantity": qty,
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
                "quantity": 1,
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
    func indexInvoiceForPortalDirectory(invoice: Invoice) async throws {
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
            "invoiceId": invoiceIdString(invoice),
            "invoiceNumber": invoice.invoiceNumber,
            "amountCents": totalCents,
            "subtotalCents": subtotalCents,
            "taxCents": taxCents,
            "lineItems": lineItems,
            "currency": "usd",
            "status": invoice.isPaid ? "paid" : "unpaid",
            "title": "Invoice \(invoice.invoiceNumber)",
            "updatedAtMs": Int(Date().timeIntervalSince1970 * 1000),
            "clientPortalEnabled": client.portalEnabled
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
    func indexEstimateForDirectory(estimate: Invoice) async throws {
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
            "amountCents": amountCents,
            "subtotalCents": subtotalCents,
            "taxCents": taxCents,
            "lineItems": lineItems,
            "currency": "usd",
            "status": normalizedStatus,
            "title": "Estimate \(estimate.invoiceNumber)",
            "updatedAtMs": Int(Date().timeIntervalSince1970 * 1000),
            "clientPortalEnabled": client.portalEnabled
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

        print("⬆️ Uploading invoice PDF",
              "businessId:", businessId,
              "invoiceId:", invoiceId,
              "fileName:", fileName,
              "bytes:", pdfData.count)

        let endpoint = baseURL.appendingPathComponent("/api/portal/invoice/pdf-upload")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let payload: [String: Any] = [
            "businessId": businessId,
            "invoiceId": invoiceId,
            "fileName": fileName,
            "pdfBase64": pdfData.base64EncodedString()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        let decoded = try decoder().decode(PDFUploadResponseDTO.self, from: data)
        if let err = decoded.error, !err.isEmpty { throw PortalBackendError.http(http.statusCode, body: err) }
        guard let url = decoded.url, !url.isEmpty else { throw PortalBackendError.decode(body: raw) }

        print("✅ Uploaded invoice PDF:", url)

        return (url: url, fileName: decoded.fileName ?? fileName)
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

        print("⬆️ Uploading contract PDF",
              "businessId:", businessId,
              "contractId:", contractId,
              "fileName:", fileName,
              "bytes:", pdfData.count)

        let endpoint = baseURL.appendingPathComponent("/api/portal/contract/pdf-upload")
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let payload: [String: Any] = [
            "businessId": businessId,
            "contractId": contractId,
            "fileName": fileName,
            "pdfBase64": pdfData.base64EncodedString()
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode, body: raw) }

        let decoded = try decoder().decode(PDFUploadResponseDTO.self, from: data)
        if let err = decoded.error, !err.isEmpty { throw PortalBackendError.http(http.statusCode, body: err) }
        guard let url = decoded.url, !url.isEmpty else { throw PortalBackendError.decode(body: raw) }

        print("✅ Uploaded contract PDF:", decoded.url ?? "nil")

        return (url: url, fileName: decoded.fileName ?? fileName)
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
