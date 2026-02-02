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

// MARK: - Backend client

final class PortalBackend {
    static let shared = PortalBackend()

    private let baseURL = PortalConfig.shared.baseURL
    private init() {}

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

        let body: [String: Any] = [
            "businessId": invoice.businessID.uuidString,
            "clientId": clientId.uuidString,
            "scope": "invoice",
            "mode": mode,
            "invoiceId": invoice.id.uuidString,
            "invoiceNumber": invoice.invoiceNumber,
            "amountCents": Int((invoice.total * 100).rounded()),
            "currency": "usd",
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
            "contractId": contract.id.uuidString,
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
        portalContractURL(contractId: contract.id.uuidString, token: token, mode: mode)
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

        let body: [String: Any] = [
            "businessId": invoice.businessID.uuidString,
            "clientId": client.id.uuidString,
            "scope": "invoice",
            "mode": "live",
            "invoiceId": invoice.id.uuidString,
            "invoiceNumber": invoice.invoiceNumber,
            "amountCents": Int((invoice.total * 100).rounded()),
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
            "contractId": contract.id.uuidString,
            "contractTitle": contract.title,
            "status": contract.statusRaw,
            "title": contract.title,
            "updatedAtMs": updatedAtMs,
            "contractBody": contract.renderedBody,
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
}
