//
//  TapToPayAPI.swift
//  SmallBiz Workspace
//

import Foundation

/// The backend half of Tap to Pay on iPhone: everything Stripe Terminal
/// needs minted on the business's own connected account. All business
/// routes, signed in with the business token like the rest of payments.
enum TapToPayAPI {
    struct ServerError: LocalizedError {
        let code: String
        var errorDescription: String? { TapToPayAPI.message(for: code) }
    }

    struct PaymentStart: Decodable {
        let paymentIntentId: String
        let clientSecret: String
        let amountCents: Int
        let tipCents: Int
    }

    struct PaymentResult: Decodable {
        let status: String
        let recorded: Bool
        let brand: String?
        let last4: String?
        let receiptUrl: String?
    }

    static func connectionToken() async throws -> String {
        struct Response: Decodable { let secret: String }
        let response: Response = try await post("/api/payments/stripe/terminal/connection-token", body: [:])
        return response.secret
    }

    /// The location this business's readers register to, if it has one yet.
    static func existingLocationID() async throws -> String? {
        struct Response: Decodable { let locationId: String? }
        let response: Response = try await send("/api/payments/stripe/terminal/location", method: "GET", body: nil)
        return response.locationId
    }

    static func saveLocation(displayName: String, address: TapToPayAddress) async throws -> String {
        struct Response: Decodable { let locationId: String }
        let response: Response = try await post("/api/payments/stripe/terminal/location", body: [
            "displayName": displayName,
            "address": [
                "line1": address.line1,
                "line2": address.line2,
                "city": address.city,
                "state": address.state,
                "postalCode": address.postalCode,
                "country": address.country,
            ],
        ])
        return response.locationId
    }

    static func startPayment(
        invoiceID: UUID,
        invoiceNumber: String,
        currencyCode: String,
        amountCents: Int,
        tipCents: Int,
        balanceDueCents: Int
    ) async throws -> PaymentStart {
        try await post("/api/payments/stripe/terminal/payment-intent", body: [
            "invoiceId": invoiceID.uuidString,
            "invoiceNumber": invoiceNumber,
            "currency": currencyCode.lowercased(),
            "amountCents": amountCents,
            "tipCents": tipCents,
            "balanceDueCents": balanceDueCents,
        ])
    }

    static func completePayment(paymentIntentID: String) async throws -> PaymentResult {
        try await post("/api/payments/stripe/terminal/payment-intent/complete", body: ["paymentIntentId": paymentIntentID])
    }

    // MARK: - Transport

    private struct Failure: Decodable { let error: String? }

    private static func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        try await send(path, method: "POST", body: body)
    }

    private static func send<T: Decodable>(_ path: String, method: String, body: [String: Any]?) async throws -> T {
        var request = URLRequest(url: PortalConfig.shared.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let token = PortalBackend.activeBusinessToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "x-sbw-business-token")
        }

        let (data, response) = try await PortalBackend.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(status) else {
            let code = (try? JSONDecoder().decode(Failure.self, from: data))?.error ?? "HTTP_\(status)"
            throw ServerError(code: code)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PortalBackendError.decode(body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// The server's error codes, said the way an owner can act on.
    static func message(for code: String) -> String {
        switch code {
        case "STRIPE_NOT_CONNECTED":
            return "Finish setting up Stripe in Payment Methods to take card payments."
        case "ADDRESS_REQUIRED":
            return "Add your business's street address, city, state and ZIP."
        case "ALREADY_PAID":
            return "This invoice is already paid."
        case "AMOUNT_EXCEEDS_BALANCE":
            return "That's more than what's still owed. The client may have paid part of it online."
        case "TIP_NOT_ALLOWED":
            return "A tip can only be added to the payment that pays the invoice in full."
        case "TIPS_NOT_ENABLED":
            return "Tips are turned off. Turn them on in Payment Methods."
        case "INVALID_AMOUNT", "INVALID_TIP":
            return "Check the amount and try again."
        case "UNAUTHORIZED", "HTTP_401":
            return "This iPhone isn't signed in for this business. Reopen the app and try again."
        default:
            return "Couldn't reach the payment service. Check your connection and try again."
        }
    }
}
