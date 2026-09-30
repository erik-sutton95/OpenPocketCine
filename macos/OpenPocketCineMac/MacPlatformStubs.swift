import Foundation
import Network
import OpenPocketCineMacCore
import OpenPocketViewCore
import os

/// Symbols the unmodified iOS I/O files call. This target does not compile the iOS Wi-Fi joiner.
enum StartupConnectionCopy {
    static let localNetworkDenied =
        "OpenPocketCine needs Local Network access to reach the camera. Allow it for this app, then try again."
    static let bluetoothDenied =
        "OpenPocketCine needs Bluetooth access to find the camera. Allow it for this app, then try again."
    static let bluetoothOff =
        "Bluetooth is off. Turn it on, then try again."
    static let bluetoothNotReady = "Bluetooth is not ready yet. Try again in a moment."
}

enum ControlLiveLog {
    private static let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "session")
    nonisolated static func line(_ text: String) {
        log.info("\(text, privacy: .public)")
    }
}

enum SharedWiFiPath {
    static func validAddress(_ value: String) -> Bool {
        MacLanPath.validAddress(value)
    }

    static func address(hotspot: Bool = false) -> String? {
        guard !hotspot else { return nil }
        return MacLanPath.current()?.ipv4
    }

    static func netmask(hotspot: Bool = false) -> String? {
        guard !hotspot else { return nil }
        return MacLanPath.current()?.netmask
    }
}

enum WiFiJoiner {
    static func isCameraPathReady() -> Bool { false }

    static func waitUntilCameraPathReady(timeout: TimeInterval = 15) async throws {
        _ = timeout
        throw MacPlatformError.softAPPathUnused
    }

    static func cameraLocalIPv4() -> String? { nil }

    static func interfaceAddresses() -> [CameraSoftAP.InterfaceAddress] { [] }

    static func resolveCameraInterface(timeout: TimeInterval = 2) async -> NWInterface? {
        _ = timeout
        return nil
    }
}

enum MacPlatformError: Error {
    case softAPPathUnused
}

enum LocalNetworkAccess {
    enum Status { case unknown, allowed, denied }

    static func note(_ next: Status, source: String) {
        _ = (next, source)
    }

    nonisolated static func isDenied(_ error: NWError?, path: NWPath? = nil) -> Bool {
        if path?.unsatisfiedReason == .localNetworkDenied { return true }
        if case .dns(let code) = error, code == -65570 { return true }
        return false
    }
}

enum FeedStressAutomation {
    static func noteSourceObserved(videoPackets: Int, accessUnits: Int) {
        _ = (videoPackets, accessUnits)
    }

    static func noteSourceDelivered(videoPackets: Int, accessUnits: Int) {
        _ = (videoPackets, accessUnits)
    }

    static func shouldDropPacket(seq: UInt64) -> Bool {
        _ = seq
        return false
    }
}

/// Nested name `MultiviewProvisioner` already uses. The iOS session class stays out of this target.
enum MultiviewSession {
    enum Failure: LocalizedError {
        case timeout, unavailable, rejected, network, pairingDeferred

        var errorDescription: String? {
            switch self {
            case .timeout: "Camera did not respond. Close other camera apps and try again."
            case .unavailable: "Camera is not nearby. Check that it is powered on."
            case .rejected:
                "Camera could not complete this step. Check the Wi-Fi details and try again."
            case .network: "Join the shared Wi-Fi network on this Mac first."
            case .pairingDeferred: "Camera is not ready to pair again. Please try again."
            }
        }
    }
}
