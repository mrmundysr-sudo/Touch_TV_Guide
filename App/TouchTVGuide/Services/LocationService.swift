import CoreLocation
import Foundation

enum LocationOutcome: Equatable { case found(Double, Double), denied, unavailable }

/// One-shot approximate location. Permission is requested only when `requestOnce()` is called, which the UI does
/// only after explaining why. Nothing is stored or sent.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<LocationOutcome, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func requestOnce() async -> LocationOutcome {
        guard continuation == nil else { return .unavailable }
        return await withCheckedContinuation { (c: CheckedContinuation<LocationOutcome, Never>) in
            continuation = c
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .denied, .restricted: finish(.denied)
            default: manager.requestLocation()
            }
        }
    }

    private func finish(_ o: LocationOutcome) { continuation?.resume(returning: o); continuation = nil }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
            case .denied, .restricted: self.finish(.denied)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let l = locations.last
        Task { @MainActor in
            if let l { self.finish(.found(l.coordinate.latitude, l.coordinate.longitude)) } else { self.finish(.unavailable) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(.unavailable) }
    }
}
