import Foundation

struct PayPalStatus: Equatable {
    let connected: Bool
    let merchantIdLast4: String?
    let merchantIdFull: String?
}

final class PortalPaymentsAPI {
    static let shared = PortalPaymentsAPI()

    private let baseURL = PortalConfig.shared.baseURL
    private init() {}

    private struct PayPalStatusResponseDTO: Decodable {
        let connected: Bool
        let paypalMerchantIdInPayPal: String?
    }

    private struct CreatePayPalReferralResponseDTO: Decodable {
        let actionUrl: String
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    func fetchPayPalStatus(businessId: UUID) async throws -> PayPalStatus {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/business/paypal-status"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [
            URLQueryItem(name: "businessId", value: businessId.uuidString)
        ]

        guard let url = comps?.url else { throw PortalBackendError.badURL }

        let (data, resp) = try await URLSession.shared.data(from: url)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        do {
            let dto = try decoder().decode(PayPalStatusResponseDTO.self, from: data)
            let last4 = dto.paypalMerchantIdInPayPal.flatMap { String($0.suffix(4)) }
            return PayPalStatus(
                connected: dto.connected,
                merchantIdLast4: last4,
                merchantIdFull: dto.paypalMerchantIdInPayPal
            )
        } catch {
            throw PortalBackendError.decode(body: raw)
        }
    }

    func createPayPalReferral(businessId: UUID) async throws -> URL {
        do {
            return try await createPayPalReferralPOST(businessId: businessId)
        } catch {
            if case PortalBackendError.http(let code, _) = error, code == 405 {
                return try await createPayPalReferralGET(businessId: businessId)
            }
            throw error
        }
    }

    private func createPayPalReferralPOST(businessId: UUID) async throws -> URL {
        let url = baseURL.appendingPathComponent("/api/paypal/onboard/create-referral")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = ["businessId": businessId.uuidString]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        return try decodeReferralURL(from: data, raw: raw)
    }

    private func createPayPalReferralGET(businessId: UUID) async throws -> URL {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/paypal/onboard/create-referral"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [
            URLQueryItem(name: "businessId", value: businessId.uuidString)
        ]

        guard let url = comps?.url else { throw PortalBackendError.badURL }

        let (data, resp) = try await URLSession.shared.data(from: url)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        return try decodeReferralURL(from: data, raw: raw)
    }

    private func decodeReferralURL(from data: Data, raw: String) throws -> URL {
        do {
            let dto = try decoder().decode(CreatePayPalReferralResponseDTO.self, from: data)
            guard let actionURL = URL(string: dto.actionUrl) else {
                throw PortalBackendError.decode(body: raw)
            }
            return actionURL
        } catch {
            throw PortalBackendError.decode(body: raw)
        }
    }
}
