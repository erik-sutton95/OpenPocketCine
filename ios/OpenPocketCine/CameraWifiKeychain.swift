import Foundation
import OpenPocketViewCore
import Security

/// SoftAP SSID + password on this phone only. GetSSID after a Mimo session often
/// returns a 1-byte `0xE4`, so reconnect cannot rely on BLE for the key.
enum CameraWifiKeychain {
    struct Creds: Equatable {
        var ssid: String
        var password: String
    }

    private static let service = "com.opencapture.openpocketcine.wifi"

    static func save(cameraId: UUID, advertisedName: String, ssid: String, password: String) {
        let creds = Creds(ssid: ssid, password: password)
        write(creds, account: account(id: cameraId))
        if !advertisedName.isEmpty { write(creds, account: account(name: advertisedName)) }
        if !ssid.isEmpty { write(creds, account: account(ssid: ssid)) }
    }

    static func load(cameraId: UUID?, advertisedName: String?, lastSSID: String?) -> Creds? {
        if let cameraId, let creds = read(account(id: cameraId)) { return creds }
        // A nameless first advert is "DJI camera" on every body — do not share that key.
        if let advertisedName, !advertisedName.isEmpty,
            !FoundCameraIdentity.isGenericName(advertisedName),
            let creds = read(account(name: advertisedName))
        {
            return creds
        }
        if let lastSSID, !lastSSID.isEmpty, let creds = read(account(ssid: lastSSID)) {
            return creds
        }
        return nil
    }

    static func delete(cameraId: UUID, advertisedName: String?, lastSSID: String?) {
        remove(account(id: cameraId))
        if let advertisedName, !advertisedName.isEmpty { remove(account(name: advertisedName)) }
        if let lastSSID, !lastSSID.isEmpty { remove(account(ssid: lastSSID)) }
    }

    // ---- Keychain I/O ----------------------------------------------------------------------------

    private static func account(id: UUID) -> String { "id.\(id.uuidString)" }
    private static func account(name: String) -> String { "name.\(name)" }
    private static func account(ssid: String) -> String { "ssid.\(ssid)" }

    private static func write(_ creds: Creds, account: String) {
        let payload = ["ssid": creds.ssid, "password": creds.password]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func read(_ account: String) -> Creds? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
            let data = out as? Data,
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String],
            let ssid = obj["ssid"], !ssid.isEmpty,
            let password = obj["password"], !password.isEmpty
        else { return nil }
        return Creds(ssid: ssid, password: password)
    }

    private static func remove(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
