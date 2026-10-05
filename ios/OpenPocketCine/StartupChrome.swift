import MonitorUI
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

enum StartupColors {
    static let background = MonitorTheme.background
    static let surface = MonitorTheme.surface
    static let tile = MonitorTheme.raised
    static let control = MonitorTheme.faint
    static let ink = MonitorTheme.text
    static let muted = MonitorTheme.muted
    static let dim = MonitorTheme.faint
    static let border = Color.white
    static let card = MonitorTheme.surface
    static let accent = MonitorTheme.accent
    static let ready = Color(red: 0.247, green: 0.710, blue: 0.416)
    static let destructive = MonitorTheme.recording
    static let darkText = MonitorTheme.canvas
    static var backdrop: some View { MonitorTheme.background }
}

enum LiveDesign {
    static let background = MonitorTheme.canvas
    static let surface = MonitorTheme.surface
    static let glass = MonitorTheme.surface
    static let glassOpaque = MonitorTheme.surface
    static let chromePlate = MonitorTheme.surface
    static let chromeTint = MonitorTheme.surface
    static let glassBright = MonitorTheme.raised
    static let hairline = MonitorTheme.border
    static let hairlineStrong = MonitorTheme.faint.opacity(0.5)
    static var text: Color { LiveHDRDisplay.chromeColor(red: 1, green: 1, blue: 1) }
    static var muted: Color { LiveHDRDisplay.chromeColor(hex: 0x8D9293) }
    static var faint: Color { LiveHDRDisplay.chromeColor(hex: 0x5E6262) }
    static var accent: Color { LiveHDRDisplay.chromeColor(hex: 0x00A3E0) }
    static let accentDim = MonitorTheme.accent.opacity(0.16)
    static var amber: Color { LiveHDRDisplay.chromeColor(red: 0.914, green: 0.674, blue: 0.208) }
    static var good: Color { LiveHDRDisplay.chromeColor(red: 0.18, green: 0.78, blue: 0.42) }
    /// AE lock yellow: the focus box, its `AE-L` tag and the unlock key.
    static var aeLock: Color { LiveHDRDisplay.chromeColor(hex: 0xF5D052) }
    static var rec: Color { LiveHDRDisplay.chromeColor(hex: 0xD13034) }
    static var info: Color { accent }
    static let cornerRadius = MonitorTheme.radius
    static let controlHeight: CGFloat = 58
}

extension View {
    /// Compositor-owned Field Monitor material; no application-side frame copy.
    func liveChromeGlass(in shape: some Shape, interactive: Bool = false) -> some View {
        monitorGlass(in: shape)
            .environment(\.colorScheme, .dark)
    }
    func liveChromeCapsule(interactive: Bool = false) -> some View {
        liveChromeGlass(in: Capsule(), interactive: interactive)
    }
    func liveChromeCircle(interactive: Bool = false) -> some View {
        liveChromeGlass(in: Circle(), interactive: interactive)
    }
}

enum StartupConnectionCopy {
    static let openSettings = "Open Settings"
    static let localNetworkDenied =
        "OpenPocketCine needs Local Network access to reach the camera. Open Settings, turn on Local Network for OpenPocketCine, then try again."
    static let bluetoothDenied =
        "OpenPocketCine needs Bluetooth access to find the camera. Open Settings, turn on Bluetooth for OpenPocketCine, then try again."
    static let bluetoothOff =
        "Bluetooth is off. Turn it on in Control Center or Settings, then try again."
    static let bluetoothNotReady = "Bluetooth is not ready yet. Try again in a moment."
    static let personalHotspotOn =
        "Turn off Personal Hotspot, then try again. While it is on, this iPhone cannot join the camera Wi-Fi."
    /// DJI Frame Tap or a running DJI Mimo holds the camera and blocks pairing and the
    /// video link. `preCheck` and `scanEmptyHint` match Android word for word.
    static let preCheckTitle = "Check first"
    static let preCheck = "Before pairing, turn off DJI Frame Tap and force quit DJI Mimo."
    static let scanEmptyTitle = "Still looking"
    static let scanEmptyHint =
        "Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera. Make sure the camera is on and activated, then move closer."
    static let pairingDeferred =
        "The camera is not ready to pair again yet. Force quit DJI Mimo on every phone near the camera, wait a few seconds, then try again."
    /// Datalink never answered: another phone holds the camera, or a VPN eats the UDP.
    static let datalinkSilent =
        "The camera did not answer over its Wi-Fi. Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera, pause any VPN or ad blocker, then try again."
    static let bluetoothTimedOut =
        "The camera didn't respond in time. Check Bluetooth, turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera, then try again."
    static let bluetoothEnded =
        "The camera ended the connection. Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera, then try again."

    /// Why a Bluetooth scan cannot run (`BleLink.unavailableReason`).
    static let bluetoothProblems: Set<String> = [bluetoothDenied, bluetoothOff, bluetoothNotReady]

    /// Failures the operator can only fix in iOS Settings get an Open Settings action.
    static func opensSettings(_ raw: String) -> Bool {
        raw == localNetworkDenied || raw == bluetoothDenied
    }

    static func friendly(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        let lower = trimmed.lowercased()
        if lower.contains("datalink handshake") || lower.contains("not ready for the datalink") {
            return datalinkSilent
        }
        if lower.contains("timed out") || lower.contains("timeout") {
            return bluetoothTimedOut
        }
        if lower.contains("disconnected") || lower.contains("camera disappeared") {
            return bluetoothEnded
        }
        if lower.contains("approve") {
            return trimmed
        }
        return trimmed
    }
}

struct StartupFilledButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(LiveType.ui(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(StartupColors.darkText)
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(
                    StartupColors.accent.opacity(configuration.isPressed ? 0.80 : 1),
                    in: RoundedRectangle(cornerRadius: MonitorTheme.radius)
                )
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// The DJI entry's pairing slot (SHELL-02): why Bluetooth discovery is not running (with Open
/// Settings where only Settings fixes it), the vendor-app check before pairing, or after 20 s
/// without a camera the still-looking tip, and the VPN banner when a filter may block the link.
struct PocketPairingTips: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if case .failed(let reason) = model.session.phase, StartupConnectionCopy.bluetoothProblems.contains(reason) {
                tip("Bluetooth", reason, settings: StartupConnectionCopy.opensSettings(reason))
            } else if model.session.scanLooksEmpty, model.cameras.nearby.isEmpty {
                tip(StartupConnectionCopy.scanEmptyTitle, StartupConnectionCopy.scanEmptyHint)
            } else {
                tip(StartupConnectionCopy.preCheckTitle, StartupConnectionCopy.preCheck)
            }
            if LocalVPNProbe.isActive() { tip("Check the connection", LocalVPNFilter.wizardBanner) }
        }
    }

    /// The shared pair page's instruction card, with an optional Open Settings.
    private func tip(_ title: String, _ text: String, settings: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased()).font(MonitorTheme.font(9, weight: .bold)).tracking(1.4)
            Text(text).font(MonitorTheme.font(12.5)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if settings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button(StartupConnectionCopy.openSettings) { openURL(url) }
                    .font(MonitorTheme.font(12.5, weight: .semibold)).foregroundStyle(MonitorTheme.accent)
            }
        }
        .foregroundStyle(MonitorTheme.secondary).frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
}
