import Foundation
import Combine
import UIKit

struct NotificationRoutePayload: Equatable {
    let notificationId: String?
    let event: String
    let businessId: String
    let invoiceId: String?
    let contractId: String?
    let bookingRequestId: String?
    let deepLink: String?
    let portalURL: URL?

    init?(
        notificationId: String? = nil,
        event: String,
        businessId: String,
        invoiceId: String? = nil,
        contractId: String? = nil,
        bookingRequestId: String? = nil,
        deepLink: String? = nil,
        portalURL: URL? = nil
    ) {
        let normalizedEvent = event.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedBusinessId = businessId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEvent.isEmpty, !normalizedBusinessId.isEmpty else { return nil }

        self.notificationId = Self.normalizedString(notificationId)
        self.event = normalizedEvent
        self.businessId = normalizedBusinessId
        self.invoiceId = Self.normalizedString(invoiceId)
        self.contractId = Self.normalizedString(contractId)
        self.bookingRequestId = Self.normalizedString(bookingRequestId)
        self.deepLink = Self.normalizedString(deepLink)
        self.portalURL = portalURL
    }

    init?(userInfo: [AnyHashable: Any]) {
        func readString(_ key: String) -> String? {
            if let value = userInfo[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            if let value = userInfo[key] {
                let str = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                return str.isEmpty ? nil : str
            }
            return nil
        }

        let notificationId = readString("notificationId") ?? readString("id")
        let event = readString("event") ?? readString("eventType")
        let businessId = readString("businessId")
        let invoiceId = readString("invoiceId")
        let contractId = readString("contractId")
        let bookingRequestId = readString("bookingRequestId")
        let deepLink = readString("deepLink") ?? readString("deeplink")
        let urlString = readString("portalUrl") ?? readString("portalURL") ?? readString("url")

        guard let event, let businessId else { return nil }

        self.init(
            notificationId: notificationId,
            event: event,
            businessId: businessId,
            invoiceId: invoiceId,
            contractId: contractId,
            bookingRequestId: bookingRequestId,
            deepLink: deepLink,
            portalURL: urlString.flatMap(URL.init(string:))
        )
    }

    private static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

@MainActor
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()

    @Published private(set) var pendingPayload: NotificationRoutePayload?
    @Published var toastMessage: String?

    private init() {}

    func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let payload = NotificationRoutePayload(userInfo: userInfo) else {
            showToast("Notification opened.")
            return
        }
        pendingPayload = payload
    }

    func handleIncomingURL(_ url: URL) {
        guard let payload = Self.payload(fromDeepLink: url) else {
            return
        }
        pendingPayload = payload
    }

    func consumePendingPayload() {
        pendingPayload = nil
    }

    func openFallbackIfPossible(_ payload: NotificationRoutePayload) -> Bool {
        guard let url = payload.portalURL else { return false }
        UIApplication.shared.open(url)
        return true
    }

    func showToast(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        toastMessage = trimmed.isEmpty ? nil : trimmed
    }

    private static func payload(fromDeepLink url: URL) -> NotificationRoutePayload? {
        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        guard (comps.scheme ?? "").lowercased() == "sbw" else { return nil }

        let host = (comps.host ?? "").lowercased()
        let pathParts = comps.path.split(separator: "/").map(String.init)
        let primary = host.isEmpty ? (pathParts.first?.lowercased() ?? "") : host
        let idFromPath = host.isEmpty ? (pathParts.dropFirst().first ?? pathParts.first) : pathParts.first
        let queryBusinessId = comps.queryItems?.first(where: { $0.name.lowercased() == "businessid" })?.value
        let businessId = queryBusinessId ?? UserDefaults.standard.string(forKey: "activeBusinessID") ?? ""

        switch primary {
        case "invoice":
            return NotificationRoutePayload(event: "invoice_deeplink", businessId: businessId, invoiceId: idFromPath, deepLink: url.absoluteString)
        case "contract":
            return NotificationRoutePayload(event: "contract_deeplink", businessId: businessId, contractId: idFromPath, deepLink: url.absoluteString)
        case "booking", "booking-request":
            return NotificationRoutePayload(event: "booking_deeplink", businessId: businessId, bookingRequestId: idFromPath, deepLink: url.absoluteString)
        default:
            return NotificationRoutePayload(event: "deeplink", businessId: businessId, deepLink: url.absoluteString)
        }
    }
}
