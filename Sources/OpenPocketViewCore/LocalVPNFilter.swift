import Foundation

/// Local VPN / ad-blocker filters (AdGuard, Blokada, RethinkDNS) capture the
/// camera UDP datalink. `bindProcessToNetwork` cannot bypass a `VpnService`
/// that did not call `allowBypass()`. Official camera apps have the same limit
/// (#239). Shells detect the tunnel; this type owns copy and when to hint.
public enum LocalVPNFilter: Sendable {
    /// First picture can take a few seconds (enable at +3 s; Pocket 3 format
    /// poke is later). Hint only after the well has sat black this long.
    public static let liveHintDelaySeconds: TimeInterval = 8

    /// Connection-setup banner when a local VPN is already on.
    public static let wizardBanner =
        "Pause VPNs and ad blockers, or exclude this app. They can block the camera live feed."

    /// WAITING FOR LIVE VIEW subtitle after [liveHintDelaySeconds] with no picture.
    public static let liveHint =
        "A VPN or ad blocker may be blocking the live feed. Pause it, or exclude this app, then try again."

    /// Join-Wi-Fi phone instruction. Same voice as the other wizard bullets.
    public static let joinWifiPhoneStep =
        "Pause VPNs and ad blockers, or exclude this app"

    public static func shouldHintOnLiveWait(
        vpnActive: Bool,
        hadVideo: Bool,
        secondsWithoutVideo: TimeInterval
    ) -> Bool {
        vpnActive && !hadVideo && secondsWithoutVideo >= liveHintDelaySeconds
    }

    /// CFNetwork `__SCOPED__` / ifaddrs names that mean a tunnel. `utun` is
    /// also used by iCloud Private Relay — shells should not warn on name
    /// alone before the live well has stalled.
    public static func isTunnelInterface(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("tap") || lower.contains("tun") || lower.contains("ppp")
            || lower.contains("ipsec")
    }
}
