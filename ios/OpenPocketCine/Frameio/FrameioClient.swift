import Foundation
import os

private let frameioLogger = Logger(subsystem: "OpenPocketCine", category: "frameio")

/// Reads the Frame.io OAuth configuration from Info.plist. Register an OAuth Single Page App in the
/// Adobe Developer Console (Frame.io API on the project) and set `FrameioClientID` + `FrameioRedirectURI`.
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

/// A persisted token plus its wall-clock receipt time, so access-token expiry can be computed.
struct StoredFrameioToken: Codable, Equatable {
    var token: FrameioToken
    var receivedAt: Date

    var accessExpiry: Date { receivedAt.addingTimeInterval(TimeInterval(token.expiresIn)) }
    /// True within 60s of expiry — refresh early so a token can't expire mid-request.
    var needsRefresh: Bool { Date() >= accessExpiry.addingTimeInterval(-60) }
}

/// Keychain-backed store for the Frame.io token. Never logs token values.
enum FrameioTokenStore {
    private static let service = "OpenPocketCine.frameio"
    private static let account = "oauth-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func save(_ stored: StoredFrameioToken) {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> StoredFrameioToken? {
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

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    static var isConnected: Bool { load() != nil }
}

/// Errors from the Frame.io API client.
enum FrameioError: LocalizedError {
    case notConfigured
    case notConnected
    case http(Int, String)
    case decode(String)
    case noUploadURL
    case noProject
    case unsupportedOS
    case uploadIncomplete
    case unexpectedFileSize
    case unsafeMediaFilename

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Frame.io isn't configured (add FrameioClientID / FrameioRedirectURI via Frameio.local.xcconfig)."
        case .notConnected: "Connect Frame.io from the share options first."
        case .http(let code, let detail):
            "Frame.io request failed (HTTP \(code))\(detail.isEmpty ? "" : ": \(detail)")."
        case .decode(let detail): detail
        case .noUploadURL: "Frame.io didn't return an upload URL."
        case .noProject: "Pick a Frame.io project to upload into."
        case .unsupportedOS: "Frame.io sign-in requires iOS 17.4 or later."
        case .uploadIncomplete: "Frame.io didn't confirm the upload finished."
        case .unexpectedFileSize: "Local file size doesn't match the upload plan."
        case .unsafeMediaFilename: "The camera supplied an unsafe media filename."
        }
    }
}

/// `URLSession` client for the Frame.io Platform API v4: token refresh, account/project listing, and clip
/// upload. Endpoint paths beyond the documented shapes are `[verify-with-credentials]`.
@MainActor
final class FrameioService {
    private let config: FrameioConfiguration

    /// Short-timeout session for API + token calls: they're interactive (popup rows, upload
    /// kickoff), and on the camera AP there is no internet route — the default 60s request
    /// timeout showed up as minute-long hangs and launch-log IMS timeout spam. Uploads keep
    /// their own longer resource window via the same session's per-chunk requests.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 12
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    init(config: FrameioConfiguration) { self.config = config }

    // MARK: - Auth

    /// A valid access token, refreshing via the refresh token when near expiry.
    private func accessToken() async throws -> String {
        guard var stored = FrameioTokenStore.load() else { throw FrameioError.notConnected }
        if stored.needsRefresh, let refresh = stored.token.refreshToken {
            let refreshed = try await exchangeToken(
                FrameioOAuth.refreshRequest(config: config, refreshToken: refresh))
            stored = StoredFrameioToken(token: refreshed, receivedAt: Date())
            FrameioTokenStore.save(stored)
        }
        return stored.token.accessToken
    }

    private func exchangeToken(_ request: URLRequest) async throws -> FrameioToken {
        let (data, response) = try await Self.session.data(for: request)
        try Self.checkStatus(response, data)
        return try JSONDecoder().decode(FrameioToken.self, from: data)
    }

    // MARK: - API

    func currentUser() async throws -> FrameioUser {
        try await get("/me", as: FrameioOne<FrameioUser>.self).data
    }

    func accounts() async throws -> [FrameioAccount] {
        try await get("/accounts", as: FrameioList<FrameioAccount>.self).data
    }

    func workspaces(accountID: String) async throws -> [FrameioWorkspace] {
        try await get("/accounts/\(accountID)/workspaces", as: FrameioList<FrameioWorkspace>.self)
            .data
    }

    func projects(accountID: String, workspaceID: String) async throws -> [FrameioProject] {
        try await get(
            "/accounts/\(accountID)/workspaces/\(workspaceID)/projects",
            as: FrameioList<FrameioProject>.self
        ).data
    }

    /// Creates a blank project in the given workspace and returns the new project (including root folder).
    func createProject(accountID: String, workspaceID: String, name: String) async throws
        -> FrameioProject
    {
        let body = FrameioCreateProjectRequest(name: name)
        let created: FrameioOne<FrameioProject> = try await post(
            "/accounts/\(accountID)/workspaces/\(workspaceID)/projects",
            body: body)
        return created.data
    }

    /// Uploads a local file: Create File (local upload) → `PUT` each chunk to its pre-signed S3 URL
    /// → poll until Frame.io marks the upload complete. Returns the new file id.
    func upload(
        fileURL: URL, name: String, mediaType: String, fileSize: Int,
        accountID: String, folderID: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> String {
        progress(0.05)
        let createBody = FrameioCreateFileRequest(name: name, fileSize: fileSize)
        let created: FrameioCreateFileResponse = try await post(
            "/accounts/\(accountID)/folders/\(folderID)/files/local_upload", body: createBody)
        let parts = created.uploadParts
        guard !parts.isEmpty else { throw FrameioError.noUploadURL }

        let partBytes = parts.reduce(0) { $0 + $1.size }
        guard partBytes == fileSize else { throw FrameioError.unexpectedFileSize }

        let contentType = created.mediaType ?? mediaType
        progress(0.1)

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var bytesSent = 0
        for (index, part) in parts.enumerated() {
            guard let uploadURL = part.uploadURL else { throw FrameioError.noUploadURL }
            let chunk = try readExactBytes(count: part.size, from: fileHandle)
            try await putChunk(chunk, to: uploadURL, contentType: contentType)
            bytesSent += part.size
            let fraction = 0.1 + 0.75 * Double(bytesSent) / Double(fileSize)
            progress(min(fraction, 0.85))
            #if DEBUG
                frameioLogger.debug(
                    "uploaded part \(index + 1)/\(parts.count) for \(name, privacy: .private(mask: .hash))"
                )
            #endif
        }

        try await waitForUploadComplete(
            accountID: accountID, fileID: created.fileID, progress: progress)
        progress(1.0)
        frameioLogger.info(
            "uploaded \(name, privacy: .private(mask: .hash)) → file \(created.fileID, privacy: .private(mask: .hash))"
        )
        return created.fileID
    }

    private func putChunk(_ chunk: Data, to uploadURL: URL, contentType: String) async throws {
        var put = URLRequest(url: uploadURL)
        put.httpMethod = "PUT"
        put.setValue("private", forHTTPHeaderField: "x-amz-acl")
        put.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await Self.session.upload(for: put, from: chunk)
        try Self.checkStatus(response, data)
    }

    private func readExactBytes(count: Int, from handle: FileHandle) throws -> Data {
        var remaining = count
        var data = Data()
        data.reserveCapacity(count)
        while remaining > 0 {
            guard let chunk = try handle.read(upToCount: remaining), !chunk.isEmpty else {
                throw FrameioError.unexpectedFileSize
            }
            data.append(chunk)
            remaining -= chunk.count
        }
        return data
    }

    /// Polls `GET /files/{id}/status` until `upload_complete` is true (Frame.io assembles parts async).
    private func waitForUploadComplete(
        accountID: String, fileID: String,
        progress: @escaping @MainActor (Double) -> Void
    ) async throws {
        let maxAttempts = 45
        for attempt in 0..<maxAttempts {
            let status: FrameioFileUploadStatus = try await get(
                "/accounts/\(accountID)/files/\(fileID)/status",
                as: FrameioFileUploadStatus.self)
            if status.uploadComplete {
                progress(0.95)
                return
            }
            progress(0.85 + 0.1 * Double(attempt) / Double(maxAttempts))
            try await Task.sleep(for: .seconds(2))
        }
        throw FrameioError.uploadIncomplete
    }

    // MARK: - HTTP helpers

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send(try await authedRequest(path, method: "GET"))
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = try await authedRequest(path, method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await Self.session.data(for: request)
        try Self.checkStatus(response, data)
        do {
            return try FrameioJSON.decode(T.self, from: data)
        } catch let error as FrameioDecodingError {
            throw FrameioError.decode(error.errorDescription ?? error.localizedDescription)
        }
    }

    private func authedRequest(_ path: String, method: String) async throws -> URLRequest {
        let token = try await accessToken()
        guard let url = URL(string: config.apiBaseURL.absoluteString + path) else {
            throw FrameioError.http(-1, "bad path")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private static func checkStatus(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw FrameioError.http(
                http.statusCode, String(decoding: data.prefix(500), as: UTF8.self))
        }
    }
}
