import AuthenticationServices
import Foundation
import OpenCineFrameIO
import UIKit

/// Drives the Adobe IMS OAuth (PKCE) sign-in via `ASWebAuthenticationSession`, exchanges the
/// authorization code for a token, and persists it to the Keychain. `@MainActor` — it presents UI.
@MainActor
final class FrameioAuthCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let config: FrameioConfiguration
    private var session: ASWebAuthenticationSession?

    init(config: FrameioConfiguration) { self.config = config }

    /// Presents the Frame.io login, exchanges the returned code (PKCE), and stores the token.
    func signIn() async throws -> FrameioToken {
        guard let redirect = URL(string: config.redirectURI) else {
            throw FrameioError.notConfigured
        }
        let pkce = PKCE.generate()
        let state = UUID().uuidString
        let authorizeURL = FrameioOAuth.authorizeURL(config: config, pkce: pkce, state: state)

        let callbackURL = try await present(authorizeURL, redirect: redirect)
        let code = try FrameioOAuth.parseRedirect(callbackURL, expectedState: state)
        // The default-timeout shared session, as before: this runs once, right after sign-in.
        return try await FrameioClient.pocket(
            config, transport: FrameioURLSessionTransport(session: .shared)
        ).completeSignIn(code: code, verifier: pkce.verifier)
    }

    func signOut() {
        FrameioTokenStore().clear()
    }

    /// Captures the OAuth redirect in-session. Adobe **Native App** credentials use a custom scheme
    /// (`adobe+{unique}://adobeid/{clientId}`); `ASWebAuthenticationSession.Callback.customScheme`
    /// receives the scheme from `URL.scheme` (including the `+`). HTTPS redirects use the iOS 17.4
    /// `.https` callback when `webcredentials` + AASA are configured on the host.
    private func present(_ url: URL, redirect: URL) async throws -> URL {
        guard #available(iOS 17.4, *) else { throw FrameioError.unsupportedOS }
        return try await withCheckedThrowingContinuation { continuation in
            let completion: (URL?, Error?) -> Void = { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? FrameioError.notConnected)
                }
            }

            let session: ASWebAuthenticationSession
            if redirect.scheme == "https" || redirect.scheme == "http" {
                guard let host = redirect.host else {
                    continuation.resume(throwing: FrameioError.notConfigured)
                    return
                }
                let path = redirect.path.isEmpty ? "/" : redirect.path
                session = ASWebAuthenticationSession(
                    url: url, callback: .https(host: host, path: path),
                    completionHandler: completion)
            } else if let scheme = redirect.scheme {
                session = ASWebAuthenticationSession(
                    url: url, callback: .customScheme(scheme), completionHandler: completion)
            } else {
                continuation.resume(throwing: FrameioError.notConfigured)
                return
            }

            session.presentationContextProvider = self
            self.session = session
            if !session.start() {
                continuation.resume(throwing: FrameioError.notConfigured)
            }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession)
        -> ASPresentationAnchor
    {
        MainActor.assumeIsolated {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
            return window ?? ASPresentationAnchor()
        }
    }
}
