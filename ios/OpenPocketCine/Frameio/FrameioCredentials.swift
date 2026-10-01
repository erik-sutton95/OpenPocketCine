import Foundation
import OpenCineFrameIO
import os

let frameioLogger = Logger(subsystem: "OpenPocketCine", category: "frameio")

/// Reads the Frame.io OAuth configuration from Info.plist. Register an OAuth Native App credential
/// in the Adobe Developer Console (Frame.io API on the project) and set `FrameioClientID` +
/// `FrameioRedirectURI` via Frameio.local.xcconfig.
enum FrameioConfig {
    static var configuration: FrameioConfiguration? {
        guard
            let clientID = info("FrameioClientID"), !clientID.isEmpty,
            let redirect = info("FrameioRedirectURI"), !redirect.isEmpty
        else { return nil }
        return FrameioConfiguration(clientID: clientID, redirectURI: redirect)
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}

/// Keychain-backed store for the Frame.io token in OpenPocketCine's own namespace. The service
/// and account are unchanged from before OpenCineFrameIO, so saved sign-ins keep working. Never
/// logs token values.
struct FrameioTokenStore: FrameioTokenStorage {
    static let service = "OpenPocketCine.frameio"
    static let account = "oauth-token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
        ]
    }

    func save(_ stored: StoredFrameioToken) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    func load() -> StoredFrameioToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data,
            let stored = try? JSONDecoder().decode(StoredFrameioToken.self, from: data)
        else { return nil }
        return stored
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var isConnected: Bool { FrameioTokenStore().load() != nil }
}

extension FrameioClient {
    /// OpenPocketCine's client: Pocket's keychain namespace over a URLSession transport.
    /// API calls use the short-timeout interactive session; the post-sign-in code exchange
    /// passes `.shared` (default timeout), as before.
    static func pocket(
        _ config: FrameioConfiguration,
        transport: FrameioURLSessionTransport = .interactive
    ) -> FrameioClient {
        FrameioClient(config: config, transport: transport, tokens: FrameioTokenStore())
    }
}
