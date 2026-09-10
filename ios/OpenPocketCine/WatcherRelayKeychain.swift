import Foundation
import Security

enum WatcherRelayKeychain {
    private static let service = "com.opencapture.openpocketcine.watcher-relay"
    private static let passcodeAccount = "host-passcode"
    private static let installAccount = "install-id"

    static var hostPasscode: String {
        get { read(account: passcodeAccount) ?? "" }
        set { write(account: passcodeAccount, value: newValue) }
    }

    static var installID: String {
        if let existing = read(account: installAccount), !existing.isEmpty { return existing }
        let id = UUID().uuidString
        write(account: installAccount, value: id)
        return id
    }

    static func rememberedPasscode(forHost name: String) -> String {
        read(account: "code.\(name)") ?? ""
    }

    static func rememberPasscode(_ code: String, forHost name: String) {
        write(account: "code.\(name)", value: code)
    }

    private static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
            let data = out as? Data, let s = String(data: data, encoding: .utf8)
        else { return nil }
        return s
    }

    private static func write(account: String, value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
