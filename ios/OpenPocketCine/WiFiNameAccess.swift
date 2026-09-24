import CoreLocation

/// iOS names the current Wi-Fi to an app only with precise location permission (and the
/// Access WiFi Information entitlement). Asked in context, from Add setup › Wi-Fi, never
/// at launch. Location itself is never read.
@MainActor final class WiFiNameAccess: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiNameAccess()
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<Void, Never>] = []

    override private init() {
        super.init()
        manager.delegate = self
    }

    var undecided: Bool { manager.authorizationStatus == .notDetermined }
    var denied: Bool {
        manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted
    }
    /// Allowed, but Precise Location is off: iOS still withholds the Wi-Fi name.
    var approximateOnly: Bool {
        !undecided && !denied && manager.accuracyAuthorization == .reducedAccuracy
    }

    /// Returns once the operator has answered, or at once if they already did.
    func request() async {
        guard undecided else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard !self.undecided else { return }
            let waiting = self.waiters
            self.waiters.removeAll()
            for waiter in waiting { waiter.resume() }
        }
    }
}
