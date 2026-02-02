import Foundation
import Combine

@MainActor
final class PortalReturnRouter: ObservableObject {
    static let shared = PortalReturnRouter()

    @Published var didReturnFromPortal: Bool = false
    @Published var lastURL: URL? = nil
    @Published var expiredInvoiceID: UUID? = nil


    func handle(_ url: URL) {
        guard let host = url.host else { return }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch host {
        case "portal-expired":
            if let idStr = comps?.queryItems?.first(where: { $0.name == "invoiceId" })?.value,
               let id = UUID(uuidString: idStr) {
                expiredInvoiceID = id
            }
            didReturnFromPortal = true

        case "payment-success", "payment-cancelled":
            didReturnFromPortal = true

        default:
            break
        }
    }


    func consumeReturnFlag() {
        didReturnFromPortal = false
    }
}
