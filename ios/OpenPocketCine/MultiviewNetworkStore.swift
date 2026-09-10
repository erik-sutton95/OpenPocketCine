import Foundation
import Security

/// Last shared network, stored only in this device's Keychain.
enum MultiviewNetworkStore {
    struct Network: Codable {
        var ssid: String
        var password: String
        var hotspot: Bool?
    }
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.opencapture.openpocketcine.multiview-network",
            kSecAttrAccount as String: "last-network",
        ]
    }
    static func load() -> Network? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
            let data = value as? Data
        else { return nil }
        return try? JSONDecoder().decode(Network.self, from: data)
    }
    static func savedNetworks() -> [Network] {
        var request = query
        request[kSecAttrAccount as String] = "saved-networks"
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &value) == errSecSuccess,
            let data = value as? Data,
            let profiles = try? JSONDecoder().decode([Network].self, from: data)
        {
            return profiles
        }
        return load().map { [$0] } ?? []
    }
    static func load(ssid: String, hotspot: Bool) -> Network? {
        savedNetworks().first { $0.ssid == ssid && ($0.hotspot ?? false) == hotspot }
    }
    static func save(ssid: String, password: String, hotspot: Bool) {
        var profiles = savedNetworks().filter {
            !($0.ssid == ssid && ($0.hotspot ?? false) == hotspot)
        }
        guard
            let data = try? JSONEncoder().encode(
                Network(ssid: ssid, password: password, hotspot: hotspot))
        else {
            return
        }
        SecItemDelete(query as CFDictionary)
        var request = query
        request[kSecValueData as String] = data
        request[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(request as CFDictionary, nil)
        profiles.append(Network(ssid: ssid, password: password, hotspot: hotspot))
        guard let profileData = try? JSONEncoder().encode(profiles) else { return }
        var profileQuery = query
        profileQuery[kSecAttrAccount as String] = "saved-networks"
        SecItemDelete(profileQuery as CFDictionary)
        profileQuery[kSecValueData as String] = profileData
        profileQuery[kSecAttrAccessible as String] =
            kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(profileQuery as CFDictionary, nil)
    }
}
