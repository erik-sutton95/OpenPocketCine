import Foundation
import Network
import OpenPocketViewCore

/// iOS Local Network privacy (TN3179). There is no API to read or request it: the
/// first local-network operation shows the system prompt, and a denial surfaces only
/// as Network.framework `.waiting(kDNSServiceErr_PolicyDenied)` or a path whose
/// `unsatisfiedReason` is `.localNetworkDenied`. Denied, the camera datalink never
/// opens (TCP 7001 and UDP sit in `.waiting` until they time out).
@MainActor
enum LocalNetworkAccess {
    enum Status: String { case unknown, allowed, denied }

    private(set) static var status: Status = .unknown
    private static var probe: NWBrowser?

    /// `kDNSServiceErr_PolicyDenied`.
    nonisolated static let policyDenied: Int32 = -65570

    nonisolated static func isDenied(_ error: NWError?, path: NWPath? = nil) -> Bool {
        if path?.unsatisfiedReason == .localNetworkDenied { return true }
        if case .dns(let code) = error, code == policyDenied { return true }
        return false
    }

    /// Browse our own Bonjour type (listed in `NSBonjourServices`) while pairing, so the
    /// system prompt appears while the operator approves on the camera instead of while
    /// the datalink handshake is already timing out.
    static func requestEarly() {
        guard status != .allowed, probe == nil else { return }
        if status == .denied { status = .unknown }  // Settings may have changed; re-learn.
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(
            for: .bonjour(type: WatcherRelayProtocol.serviceType, domain: nil),
            using: parameters)
        browser.stateUpdateHandler = { state in
            guard case .waiting(let error) = state, isDenied(error) else { return }
            Task { @MainActor in note(.denied, source: "probe \(error)") }
        }
        probe = browser
        browser.start(queue: .main)
        ControlLiveLog.line("localNetwork: probe started")
        // ponytail: a fixed 30 s probe; the prompt outlives it, the datalink re-detects.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(30))
            probe?.cancel()
            probe = nil
        }
    }

    static func note(_ next: Status, source: String) {
        guard next != status else { return }
        status = next
        ControlLiveLog.line("localNetwork: \(next.rawValue) (\(source))")
    }
}
