import Foundation

struct PaymentServiceResponseError: LocalizedError {
    let message: String
    let details: String

    var errorDescription: String? { message }
}

struct AdminBackendDiagnosticResult: Equatable {
    let status: String
    let details: String?
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
    let actionRequired: Bool
    let detailsSubmitted: Bool?
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

    private struct APIErrorResponseDTO: Decodable {
        let ok: Bool?
        let error: String?
        let errorCode: String?
    }

    private struct StripeConnectStatusResponseDTO: Decodable {
        let ok: Bool?
        let stripeAccountId: String?
        let chargesEnabled: Bool?
        let payoutsEnabled: Bool?
        let onboardingStatus: String?
        let actionRequired: Bool?
        let detailsSubmitted: Bool?
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

    private func attachAdminHeaders(_ request: inout URLRequest, adminKey: String) {
        request.setValue(adminKey, forHTTPHeaderField: "x-portal-admin")
        request.setValue(adminKey, forHTTPHeaderField: "x-admin-key")
    }

    private func stripeServiceErrorMessage(from data: Data) -> String? {
        guard let dto = try? decoder().decode(APIErrorResponseDTO.self, from: data) else { return nil }
        let error = (dto.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let code = (dto.errorCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if error.isEmpty && code.isEmpty { return nil }
        if error.isEmpty { return code }
        if code.isEmpty { return error }
        return "\(error) [\(code)]"
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
        attachAdminHeaders(&req, adminKey: adminKey)

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
            if let message = stripeServiceErrorMessage(from: data) {
                throw PaymentServiceResponseError(message: message, details: raw)
            }
            throw PortalBackendError.http(http.statusCode, body: raw, path: "/api/payments/stripe/connect/start")
        }

        let dto = try decoder().decode(StripeConnectStartResponseDTO.self, from: data)
        guard let urlString = dto.url, let onboardingURL = URL(string: urlString) else {
            throw PortalBackendError.decode(body: raw)
        }
        return onboardingURL
    }

    func resumeStripeConnect(businessId: UUID, returnURL: URL) async throws -> URL {
        let adminKey = try adminKey()
        let url = baseURL.appendingPathComponent("/api/payments/stripe/connect/resume")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        attachAdminHeaders(&req, adminKey: adminKey)

        let payload: [String: Any] = [
            "businessId": businessId.uuidString,
            "returnURL": returnURL.absoluteString
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: "/api/payments/stripe/connect/resume")
        }
        if http.statusCode == 405 {
            throw PaymentServiceResponseError(
                message: "Stripe setup service misconfigured (method not allowed).",
                details: raw
            )
        }
        guard (200...299).contains(http.statusCode) else {
            if appearsToBeHTML(raw) {
                throw PaymentServiceResponseError(
                    message: "Stripe service unavailable. Try again.",
                    details: raw
                )
            }
            if let message = stripeServiceErrorMessage(from: data) {
                throw PaymentServiceResponseError(message: message, details: raw)
            }
            throw PortalBackendError.http(http.statusCode, body: raw, path: "/api/payments/stripe/connect/resume")
        }

        do {
            let dto = try decoder().decode(StripeConnectStartResponseDTO.self, from: data)
            guard dto.ok == true else {
                throw PaymentServiceResponseError(
                    message: "Stripe service unavailable. Try again.",
                    details: raw
                )
            }
            guard let urlString = dto.url, let onboardingURL = URL(string: urlString) else {
                throw PortalBackendError.decode(body: raw)
            }
            return onboardingURL
        } catch {
            if appearsToBeHTML(raw) {
                throw PaymentServiceResponseError(
                    message: "Stripe service unavailable. Try again.",
                    details: raw
                )
            }
            if let serviceError = error as? PaymentServiceResponseError {
                throw serviceError
            }
            throw PortalBackendError.decode(body: raw)
        }
    }

    private func appearsToBeHTML(_ body: String) -> Bool {
        let lower = body.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("<!doctype html") || lower.hasPrefix("<html")
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
        attachAdminHeaders(&req, adminKey: adminKey)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"

        guard let http = resp as? HTTPURLResponse else {
            throw PortalBackendError.http(-1, body: raw, path: "/api/payments/stripe/connect/status")
        }
        guard (200...299).contains(http.statusCode) else {
            if let message = stripeServiceErrorMessage(from: data) {
                throw PaymentServiceResponseError(message: message, details: raw)
            }
            throw PortalBackendError.http(http.statusCode, body: raw, path: "/api/payments/stripe/connect/status")
        }

        let dto = try decoder().decode(StripeConnectStatusResponseDTO.self, from: data)
        return StripeConnectStatus(
            stripeAccountId: dto.stripeAccountId,
            chargesEnabled: dto.chargesEnabled ?? false,
            payoutsEnabled: dto.payoutsEnabled ?? false,
            onboardingStatus: dto.onboardingStatus ?? "not_connected",
            actionRequired: dto.actionRequired ?? false,
            detailsSubmitted: dto.detailsSubmitted
        )
    }

    func fetchPayPalPlatformStatus() async throws -> PayPalPlatformStatus {
        let url = baseURL.appendingPathComponent("/api/payments/paypal/status")
        let (data, resp) = try await URLSession.shared.data(from: url)
        let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
        let friendly = "PayPal status unavailable. Please verify backend deployment and environment variables."
        guard let http = resp as? HTTPURLResponse else {
            throw PaymentServiceResponseError(
                message: friendly,
                details: raw
            )
        }
        guard http.statusCode == 200 else {
            throw PaymentServiceResponseError(
                message: friendly,
                details: raw
            )
        }
        do {
            let dto = try decoder().decode(PayPalStatusResponse.self, from: data)
            return PayPalPlatformStatus(enabled: dto.enabled, env: dto.env)
        } catch {
            throw PaymentServiceResponseError(
                message: friendly,
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
        attachAdminHeaders(&req, adminKey: adminKey)

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
        attachAdminHeaders(&req, adminKey: adminKey)
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

    func testAdminBackendAuth() async -> AdminBackendDiagnosticResult {
        let key: String
        do {
            key = try adminKey()
        } catch {
            return AdminBackendDiagnosticResult(status: "Unauthorized", details: error.localizedDescription)
        }

        let url = baseURL.appendingPathComponent("/api/health/admin")
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        attachAdminHeaders(&req, adminKey: key)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            let raw = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            guard let http = resp as? HTTPURLResponse else {
                return AdminBackendDiagnosticResult(status: "Server Error", details: raw)
            }
            switch http.statusCode {
            case 200:
                return AdminBackendDiagnosticResult(status: "OK", details: raw)
            case 401:
                return AdminBackendDiagnosticResult(status: "Unauthorized", details: raw)
            case 404:
                return AdminBackendDiagnosticResult(status: "Not Found", details: raw)
            default:
                return AdminBackendDiagnosticResult(status: "Server Error", details: raw)
            }
        } catch {
            return AdminBackendDiagnosticResult(
                status: "Server Error",
                details: (error as NSError).localizedDescription
            )
        }
    }
}
