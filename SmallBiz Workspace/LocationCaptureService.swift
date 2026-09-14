import Foundation
import CoreLocation

/// One-shot "capture where I am right now" for a job site — not continuous
/// tracking, no background updates. A classic delegate shim wrapped in a
/// continuation rather than the iOS 17 `CLLocationUpdate.liveUpdates()`
/// async stream, since a single reading is all a job-location pin needs.
@MainActor
final class LocationCaptureService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    enum CaptureError: LocalizedError {
        case authorizationDenied
        case noLocationReturned

        var errorDescription: String? {
            switch self {
            case .authorizationDenied:
                return "Location access is off for SmallBiz Workspace. Enable it in Settings to pin the job site."
            case .noLocationReturned:
                return "Couldn't get a location just now. Try again in a moment."
            }
        }
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    // This project's default actor isolation is MainActor, which makes the
    // compiler synthesize an isolated deinit for classes like this one —
    // and back-deploying that synthesis has a known heap-corruption bug
    // (swiftlang/swift#87316, see the fix already applied to PortalService)
    // when an instance is deallocated synchronously outside a Task. Opt out
    // up front rather than wait to hit it again.
    nonisolated deinit {}

    /// Requests when-in-use authorization if needed, then returns a single
    /// current location.
    func captureCurrentLocation() async throws -> CLLocation {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                authContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        }

        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else {
            throw CaptureError.authorizationDenied
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard let authContinuation else { return }
            self.authContinuation = nil
            authContinuation.resume()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let continuation else { return }
            self.continuation = nil
            if let location = locations.last {
                continuation.resume(returning: location)
            } else {
                continuation.resume(throwing: CaptureError.noLocationReturned)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(throwing: error)
        }
    }
}
