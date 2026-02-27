import Foundation
import Combine

enum AppRoute {
    case clientsRoot
    case invoicesRoot
    case moreRoot
    case paymentsSetup
    case openAppSettings
}

final class AppRouteCenter {
    static let shared = AppRouteCenter()

    private let subject = PassthroughSubject<AppRoute, Never>()

    var publisher: AnyPublisher<AppRoute, Never> {
        subject.eraseToAnyPublisher()
    }

    func route(_ route: AppRoute) {
        subject.send(route)
    }
}
