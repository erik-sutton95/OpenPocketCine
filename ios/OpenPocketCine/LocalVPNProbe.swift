import Foundation
import OpenPocketViewCore

/// Best-effort local-VPN probe for the iOS shell. Android uses
/// `TRANSPORT_VPN`, which is authoritative. CFNetwork `__SCOPED__` tunnel
/// names also fire for iCloud Private Relay (`utun`), so the wizard only
/// shows [LocalVPNFilter.wizardBanner] when a tunnel is present, and the
/// live-well hint still waits [LocalVPNFilter.liveHintDelaySeconds].
enum LocalVPNProbe {
    private static var loggedActive = false

    static func isActive() -> Bool {
        scopedInterfaceNames().contains { LocalVPNFilter.isTunnelInterface($0) }
    }

    static func noteIfActive() {
        guard isActive(), !loggedActive else { return }
        loggedActive = true
        DiagnosticCenter.shared.event(
            level: .notice,
            category: .session,
            code: "vpn",
            message: "vpn: local VPN or ad blocker active — can drop UDP live view")
    }

    static func scopedInterfaceNames() -> [String] {
        guard
            let cf = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any],
            let scoped = cf["__SCOPED__"] as? [String: Any]
        else { return [] }
        return Array(scoped.keys)
    }
}
