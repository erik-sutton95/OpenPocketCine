import OpenCineRelayApple

extension WatcherRelayKeychain {
    /// This app's relay secrets. The service name is stored data: never change it.
    static let app = WatcherRelayKeychain(service: "com.opencapture.openpocketcine.watcher-relay")
}
