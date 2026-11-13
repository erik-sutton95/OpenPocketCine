import Foundation
import OpenCineAppKit
import OpenCineMulticam
import Security

/// This app's existing four-camera qualification. Stage validation and admission share it.
enum MultiviewQualificationPolicy {
    static let budget = ResourceBudget(qualifiedEntries: 4)
    static var tileCount: Int {
        guard let count = budget.qualifiedEntries else {
            preconditionFailure("Multiview requires a finite app qualification budget")
        }
        return count
    }
}

extension MultiviewStageJournal.Stage {
    /// The stage when it is safe to restore with this app's tile count.
    var validated: Self? { validated(tileCount: MultiviewQualificationPolicy.tileCount) }
}

/// Device-only stage metadata. Network credentials stay in MultiviewNetworkStore. The values and
/// rules are OpenCine's `MultiviewStageJournal`; this keeps the Keychain and this app's tile count.
enum MultiviewStageStore {
    typealias Camera = MultiviewStageJournal.Camera
    typealias Stage = MultiviewStageJournal.Stage

    static func cleanupTargets(_ pending: [Camera], including cameras: [Camera]) -> [Camera] {
        MultiviewStageJournal.cleanupTargets(pending, including: cameras)
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
    @discardableResult static func save(_ stage: Stage?) -> Bool {
        guard let stage else {
            let deleted = SecItemDelete(query as CFDictionary)
            return deleted == errSecSuccess || deleted == errSecItemNotFound
        }
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
