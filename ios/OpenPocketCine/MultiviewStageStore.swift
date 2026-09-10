import Foundation
import Security

/// Device-only stage metadata. Network credentials stay in MultiviewNetworkStore.
enum MultiviewStageStore {
    struct Camera: Codable, Equatable {
        var slot: Int
        var id: UUID
        var name: String
        var modelId: Int?
        var identity: [UInt8]?
        var address: String
        var experimental: Bool
        var lutEnabled: Bool
    }
    struct Stage: Codable, Equatable {
        var version = 1
        var ssid: String
        var hotspot: Bool
        var layout: String
        var focusedIndex: Int
        var cameras: [Camera]
        var pendingReset: [Camera]?
        var returnedToCameraWiFi: Bool?
        var fill: Bool?

        var validated: Stage? {
            guard version == 1, !ssid.isEmpty, cameras.count <= 4, (pendingReset?.count ?? 0) <= 4,
                (0..<4).contains(focusedIndex),
                Set(cameras.map(\.slot)).count == cameras.count,
                Set(cameras.map(\.id)).count == cameras.count,
                cameras.allSatisfy({ (0..<4).contains($0.slot) && !$0.name.isEmpty })
            else { return nil }
            return self
        }
    }
    private static var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.opencapture.openpocketcine.multiview-stage",
            kSecAttrAccount as String: "stage",
        ]
    }
    static func load() -> Stage? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &value) == errSecSuccess,
            let data = value as? Data
        else { return nil }
        return (try? JSONDecoder().decode(Stage.self, from: data))?.validated
    }
    @discardableResult static func save(_ stage: Stage) -> Bool {
        guard stage.validated != nil, let data = try? JSONEncoder().encode(stage) else {
            return false
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else { return false }
        return SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil)
            == errSecSuccess
    }
}
