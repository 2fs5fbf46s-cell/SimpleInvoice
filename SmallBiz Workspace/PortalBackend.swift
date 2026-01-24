import Foundation

struct PortalSeedResponse: Decodable {
    struct Session: Decodable {
        struct Allowed: Decodable {
            let invoiceId: String
            let invoiceNumber: String
            let amountCents: Int
            let currency: String
        }

        let businessId: String
        let createdAt: String
        let expiresAt: String
        let allowed: Allowed
    }

    let token: String
    let session: Session
}

enum PortalBackendError: Error {
    case http(Int)
    case decode
}

struct PaymentStatusResponse: Decodable {
    let paid: Bool
    let receipt: Receipt?

    struct Receipt: Decodable {
        let status: String?
        let invoiceId: String?
        let businessId: String?
        let sessionId: String?
        let amountTotal: Int?
        let currency: String?
        let paidAt: String?
    }
}


final class PortalBackend {
    static let shared = PortalBackend()

    private let baseURL = URL(string: "https://smallbizworkspace-portal-backend.vercel.app")!

    func createInvoicePortalToken(
        invoice: Invoice
    ) async throws -> PortalSeedResponse {

        let url = baseURL.appendingPathComponent("/api/portal-session/seed")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "businessId": invoice.businessID.uuidString,
            "invoiceId": invoice.id.uuidString,
            "invoiceNumber": invoice.invoiceNumber,
            "amountCents": Int((invoice.total * 100).rounded()),
            "currency": "usd"
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1) }
        guard (200..<300).contains(http.statusCode) else {
            let bodyText = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            print("Seed failed:", http.statusCode, "body:", bodyText)
            throw PortalBackendError.http(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(PortalSeedResponse.self, from: data) else {
            throw PortalBackendError.decode
        }

        return decoded
    }

    func portalInvoiceURL(invoiceId: String, token: String) -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/portal/invoice/\(invoiceId)"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [URLQueryItem(name: "t", value: token)]
        return comps.url!
    }
    func fetchPaymentStatus(businessId: String, invoiceId: String) async throws -> PaymentStatusResponse {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/payment-status"),
            resolvingAgainstBaseURL: false
        )!
        comps.queryItems = [
            URLQueryItem(name: "invoiceId", value: invoiceId),
            URLQueryItem(name: "businessId", value: businessId)
        ]

        let url = comps.url!
        let (data, resp) = try await URLSession.shared.data(from: url)

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw PortalBackendError.http(http.statusCode) }

        guard let decoded = try? JSONDecoder().decode(PaymentStatusResponse.self, from: data) else {
            throw PortalBackendError.decode
        }
        return decoded
    }
}
