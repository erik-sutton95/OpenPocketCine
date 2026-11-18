import OpenCineApple

/// Last shared network, stored only in this device's Keychain. The saved-network rules live in
/// OpenCine's `SharedNetworkStore`; this keeps this app's Keychain service name.
enum MultiviewNetworkStore {
    private static let store = SharedNetworkStore(
        storage: KeychainSharedNetworkStorage(
            service: "com.opencapture.openpocketcine.multiview-network"))

    static func savedNetworks() -> [SharedNetworkStore.Network] { store.savedNetworks() }

    static func load(ssid: String, hotspot: Bool) -> SharedNetworkStore.Network? {
        store.load(ssid: ssid, hotspot: hotspot)
    }

    static func save(ssid: String, password: String, hotspot: Bool) {
        store.save(ssid: ssid, password: password, hotspot: hotspot)
    }
}
