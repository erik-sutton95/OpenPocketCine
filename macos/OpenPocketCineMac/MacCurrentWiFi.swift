import CoreLocation
import CoreWLAN
import Foundation

/// The Wi-Fi this Mac is already using. macOS withholds the name until Location is allowed.
@MainActor
final class MacCurrentWiFi: NSObject, CLLocationManagerDelegate {
    private let location = CLLocationManager()
    private(set) var ssid: String?
    var onChange: (@MainActor () -> Void)?

    var denied: Bool {
        location.authorizationStatus == .denied || location.authorizationStatus == .restricted
    }

    func refresh() {
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            location.startUpdatingLocation()
            read()
        default:
            read()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.location.authorizationStatus != .notDetermined else { return }
            if self.location.authorizationStatus == .authorized
                || self.location.authorizationStatus == .authorizedAlways
            {
                self.location.startUpdatingLocation()
            }
            self.read()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.read()
            self.location.stopUpdatingLocation()
        }
    }

    private func read() {
        let name = CWWiFiClient.shared().interface()?.ssid()?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ssid = (name?.isEmpty == false) ? name : nil
        onChange?()
    }
}
