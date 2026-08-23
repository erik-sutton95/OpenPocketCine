import Foundation

/// Where the connection is in the BLE -> WiFi -> datalink handshake. Drives the status UI and
/// makes "it stalled" legible about *where* it stalled. Pure value type, shared by app + tests.
public enum ConnectionPhase: Equatable, Sendable {
    case idle
    case scanning
    case connectingGatt  // GATT connect + notifications + arm pairing
    case pairing  // SetPairingPIN sent
    case awaitingApproval  // camera showed a prompt — user must tap it
    case readingWifiCreds  // asking the camera for its SSID + passphrase
    case joiningWifi  // NEHotspotConfiguration
    case openingDatalink  // UDP handshake + register + subscribe
    case live  // registered; status pushes flowing
    case failed(String)

    public var label: String {
        switch self {
        case .idle: "Idle"
        case .scanning: "Scanning for camera…"
        case .connectingGatt: "Connecting (Bluetooth)…"
        case .pairing: "Pairing…"
        case .awaitingApproval: "Approve on the camera screen"
        case .readingWifiCreds: "Reading Wi-Fi credentials…"
        case .joiningWifi: "Joining camera Wi-Fi…"
        case .openingDatalink: "Opening datalink…"
        case .live: "Connected"
        case .failed(let why): "Failed: \(why)"
        }
    }

    public var isTerminalFailure: Bool { if case .failed = self { true } else { false } }
}
