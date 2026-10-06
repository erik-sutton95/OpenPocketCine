import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenPocketViewCore
import SwiftUI
import OpenCineDJIApple

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
    static var text: Color { LiveHDRDisplay.app.chromeColor(red: 1, green: 1, blue: 1) }
    static var muted: Color { LiveHDRDisplay.app.chromeColor(hex: 0x8D9293) }
    static var faint: Color { LiveHDRDisplay.app.chromeColor(hex: 0x5E6262) }
    static var accent: Color { LiveHDRDisplay.app.chromeColor(hex: 0x00A3E0) }
    static let accentDim = MonitorTheme.accent.opacity(0.16)
    static var amber: Color { LiveHDRDisplay.app.chromeColor(red: 0.914, green: 0.674, blue: 0.208) }
    static var good: Color { LiveHDRDisplay.app.chromeColor(red: 0.18, green: 0.78, blue: 0.42) }
    /// AE lock yellow: the focus box, its `AE-L` tag and the unlock key.
    static var aeLock: Color { LiveHDRDisplay.app.chromeColor(hex: 0xF5D052) }
    static var rec: Color { LiveHDRDisplay.app.chromeColor(hex: 0xD13034) }
    static var info: Color { accent }
    static let cornerRadius = MonitorTheme.radius
    static let controlHeight: CGFloat = 58
}

/// The shared live chrome reads this app's palette.
extension LiveDesign: LiveChromePalette {
    /// Ink on the accent stays this app's white text.
    static var onAccent: Color { text }
    static var destructive: Color { StartupColors.destructive }

    static func chromeColor(red: CGFloat, green: CGFloat, blue: CGFloat) -> Color {
        LiveHDRDisplay.app.chromeColor(red: red, green: green, blue: blue)
    }
}

typealias CloseButton = LiveCloseButton<LiveDesign>

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

    /// Why a Bluetooth scan cannot run (`DjiAppleBluetoothLink.unavailableReason`).
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

extension AppModel {
    /// The pair wizard in OpenPocketCine's words: the four Pocket and Nano pages, the pre-check (or
    /// the still-looking hint once a scan turns up nothing), the session's live label, a Bluetooth
    /// failure, the camera Wi-Fi joined and a local VPN.
    func pairingWizard() -> PairingWizard {
        PairingWizard(
            bodies: [
                "Turn the camera on and keep the phone nearby. Pocket and Nano both appear. Choose the one you want.",
                "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
                "We read the camera's network over Bluetooth, then join its Wi-Fi for you.",
                "Exposure, LUTs and scopes go live as soon as the video link is up.",
            ],
            approveLines: ["Look for an Approve / pairing prompt", "Tap it on the camera screen"],
            joinLines: [
                "Leave the camera on. It brings up its own Wi-Fi",
                "On 5.8 GHz that can take about a minute; we keep trying",
            ],
            choosing: session.scanLooksEmpty && cameras.nearby.isEmpty
                ? .init(
                    title: StartupConnectionCopy.scanEmptyTitle, icon: .camera,
                    lines: [StartupConnectionCopy.scanEmptyHint])
                : .init(
                    title: StartupConnectionCopy.preCheckTitle, icon: .phone, lines: [StartupConnectionCopy.preCheck]),
            label: liveLabel,
            discoveryFailure: discoveryFailure, joinedNetwork: session.joinedSSID,
            vpnActive: LocalVPNProbe.isActive())
    }

    /// Main's live label: the scan while choosing, then the session's phase (a connect starts at
    /// the Bluetooth link; the simulator review's scripted camera never moves the session).
    private var liveLabel: String {
        typealias Phase = OpenPocketViewCore.ConnectionPhase
        if cameras.attempts.isEmpty { return Phase.scanning.label }
        return session.phase == .idle ? Phase.connectingGatt.label : session.phase.label
    }

    /// Why Bluetooth discovery is not running, in this app's copy, with Open Settings where only
    /// Settings fixes it.
    var discoveryFailure: ConnectionFailure? {
        guard cameras.attempts.isEmpty, case .failed(let why) = session.phase,
            StartupConnectionCopy.bluetoothProblems.contains(why)
        else { return nil }
        let (reason, code) = CameraSession.reason(nil, why)
        var failure = CameraSession.failure(reason, code, StartupConnectionCopy.friendly(why))
        if StartupConnectionCopy.opensSettings(why) { failure.actions = [.openSettings, .retry] }
        return failure
    }
}
