import Foundation

struct PaymentServiceResponseError: LocalizedError {
    let message: String
    let details: String

    var errorDescription: String? { message }
}

struct PayPalStatus: Equatable {
    let connected: Bool
    let merchantIdLast4: String?
    let merchantIdFull: String?
}

struct StripeConnectStatus: Equatable {
    let stripeAccountId: String?
    let chargesEnabled: Bool
    let payoutsEnabled: Bool
    let onboardingStatus: String
}

struct PayPalPlatformStatus: Equatable {
    let enabled: Bool
    let env: String?
}

struct PayPalStatusResponse: Decodable {
    let ok: Bool
    let enabled: Bool
    let env: String?
}

struct ManualPaymentReportDTO: Decodable, Identifiable, Equatable {
    let id: String
    let businessId: String
    let invoiceId: String
    let method: String
    let amountCents: Int
    let payerName: String?
    let payerEmail: String?
    let reference: String?
    let status: String
    let createdAtMs: Int64
    let resolvedAtMs: Int64?
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

    private struct StripeConnectStartResponseDTO: Decodable {
        let ok: Bool?
        let url: String?
        let stripeAccountId: String?
    }

    private struct StripeConnectStatusResponseDTO: Decodable {
        let ok: Bool?
        let stripeAccountId: String?
        let chargesEnabled: Bool?
        let payoutsEnabled: Bool?
        let onboardingStatus: String?
    }

    private struct ManualReportsResponseDTO: Decodable {
        let reports: [ManualPaymentReportDTO]?
    }

    private func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func adminKey() throws -> String {
        guard let key = PortalSecrets.portalAdminKey(), !key.isEmpty else {
            throw PortalBackendError.missingAdminKey
        }
        return key
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
            if case PortalBackendError.http(let code, _, _) = error, code == 405 {
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

    func startStripeConnect(businessId: UUID, returnURL: URL) async throws -> URL {
        let adminKey = try adminKey()
        let url = baseURL.appendingPathComponent("/api/payments/stripe/connect/start")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let payload: [String: Any] = [
            "businessId": businessId.uuidString,
            "returnUrl": returnURL.absoluteString
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: "/api/payments/stripe/connect/start")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw, path: "/api/payments/stripe/connect/start")
        }

        let dto = try decoder().decode(StripeConnectStartResponseDTO.self, from: data)
        guard let urlString = dto.url, let onboardingURL = URL(string: urlString) else {
            throw PortalBackendError.decode(body: raw)
        }
        return onboardingURL
    }

    func fetchStripeConnectStatus(businessId: UUID) async throws -> StripeConnectStatus {
        let adminKey = try adminKey()
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/payments/stripe/connect/status"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "businessId", value: businessId.uuidString)]
        guard let url = comps?.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: "/api/payments/stripe/connect/status")
        }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw, path: "/api/payments/stripe/connect/status")
        }

        let dto = try decoder().decode(StripeConnectStatusResponseDTO.self, from: data)
        return StripeConnectStatus(
            stripeAccountId: dto.stripeAccountId,
            chargesEnabled: dto.chargesEnabled ?? false,
            payoutsEnabled: dto.payoutsEnabled ?? false,
            onboardingStatus: dto.onboardingStatus ?? "not_connected"
        )
    }

    func fetchPayPalPlatformStatus() async throws -> PayPalPlatformStatus {
        let url = baseURL.appendingPathComponent("/api/payments/paypal/status")
        let (data, resp) = try await URLSession.shared.data(from: url)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else {
            throw PaymentServiceResponseError(
                message: "Payment service is unavailable (unexpected response). Please try again.",
                details: raw
            )
        }
        guard http.statusCode == 200 else {
            throw PaymentServiceResponseError(
                message: "Unable to check PayPal status right now. Please try again.",
                details: raw
            )
        }
        do {
            let dto = try decoder().decode(PayPalStatusResponse.self, from: data)
            return PayPalPlatformStatus(enabled: dto.enabled, env: dto.env)
        } catch {
            throw PaymentServiceResponseError(
                message: "Payment service is unavailable (unexpected response). Please try again.",
                details: raw
            )
        }
    }

    func fetchManualPaymentReports(businessId: UUID) async throws -> [ManualPaymentReportDTO] {
        let adminKey = try adminKey()
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("/api/payments/manual/list"),
            resolvingAgainstBaseURL: false
        )
        comps?.queryItems = [URLQueryItem(name: "businessId", value: businessId.uuidString)]
        guard let url = comps?.url else { throw PortalBackendError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }

        let dto = try decoder().decode(ManualReportsResponseDTO.self, from: data)
        return dto.reports ?? []
    }

    func resolveManualPaymentReport(reportId: String, action: String) async throws {
        let adminKey = try adminKey()
        let url = baseURL.appendingPathComponent("/api/payments/manual/resolve")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "reportId": reportId,
            "action": action
        ], options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        guard let http = resp as? HTTPURLResponse else { throw PortalBackendError.http(-1, body: raw) }
        guard (200...299).contains(http.statusCode) else {
            throw PortalBackendError.http(http.statusCode, body: raw)
        }
    }
}
