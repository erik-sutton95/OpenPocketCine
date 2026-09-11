import Foundation

/// Wire protocol shared by the iPhone relay and the watchOS companion.
///
/// The iPhone owns the camera radio (BLE → SoftAP → DUML). It forwards a downscaled
/// preview plus a small state snapshot to the Watch; the Watch relays Record / shutter
/// back. Payloads are `Codable` + `Sendable`. Messages travel over
/// `WCSession.sendMessageData` framed by ``WatchRelayEnvelope``.
public enum WatchRelayProtocol {
    /// Wire framing: a one-byte kind tag followed by the JSON-encoded payload.
    public enum Kind: UInt8, Sendable {
        /// Phone → watch: a ``WatchRelayState`` snapshot.
        case state = 0x01
        /// Phone → watch: a throttled ``WatchRelayFrame`` preview image.
        case frame = 0x02
        /// Watch → phone: a ``WatchRelayCommand``.
        case command = 0x10
        /// Phone → watch: a ``WatchCommandResult`` reply to a command.
        case result = 0x11
    }
}

/// Connection state the watch shows in placeholders.
public enum WatchConnectionState: String, Codable, Equatable, Sendable {
    /// The iPhone relay is not reachable (app backgrounded, unpaired, or out of range).
    case disconnected
    /// The iPhone is in ``ConnectionPhase/live``.
    case connected
    /// The iPhone is reachable but not live.
    case noCamera
}

/// Operator-facing watch copy. No sister-app names, no opcodes.
public enum WatchRelayCopy: Sendable {
    public static let openOnIPhone = "Open OpenPocketCine on iPhone"
    public static let noCamera = "No camera connected"
    public static let waitingLive = "Waiting for live view"
    public static let connectFirst = "Connect the camera first."
    public static let switchToVideo = "Switch to video first."
    public static let switchToPhoto = "Switch to photo first."
    public static let busy = "Camera is busy."
}

/// `WCSession.updateApplicationContext` key. Plist-safe so rec/tally still
/// land when `sendMessageData` is not reachable (wrist down / Always On).
public enum WatchRelayContext: Sendable {
    public static let stateKey = "state"
}

/// Wrist placeholder. Wrist-down must not cover a live tally with "open iPhone".
public enum WatchMonitorPlaceholder: Equatable, Sendable {
    case none
    case openOnIPhone
    case noCamera
    case waitingLive

    public var copy: String? {
        switch self {
        case .none: nil
        case .openOnIPhone: WatchRelayCopy.openOnIPhone
        case .noCamera: WatchRelayCopy.noCamera
        case .waitingLive: WatchRelayCopy.waitingLive
        }
    }

    /// Last picture and chrome stay up when WatchConnectivity drops.
    public static func resolve(
        isReachable: Bool, state: WatchRelayState?, hasFeed: Bool
    ) -> WatchMonitorPlaceholder {
        if let state {
            if state.connection == .noCamera { return .noCamera }
            if !state.feedLive, !hasFeed { return .waitingLive }
            return .none
        }
        if !isReachable { return .openOnIPhone }
        return .none
    }
}

/// Storage slot on the wrist. Same formula as the phone HUD default
/// (`N GB · P%`), with remaining minutes when the body has no totals.
public enum WatchRelayMedia: Sendable {
    public static func label(
        storageFreeMb: Int,
        storageTotalMb: Int,
        sdFreeMb: Int,
        sdTotalMb: Int,
        recordRemainingSec: Int
    ) -> String {
        let free = storageFreeMb > 0 ? storageFreeMb : sdFreeMb
        let total = storageTotalMb > 0 ? storageTotalMb : sdTotalMb
        if total > 0 {
            let gb = max(0, free) / 1024
            let pct = Int((Double(max(0, free)) / Double(total) * 100).rounded())
            return "\(gb) GB · \(pct)%"
        }
        if recordRemainingSec > 0 {
            return "\(recordRemainingSec / 60) Min"
        }
        if free > 0 {
            return "\(free / 1024) GB"
        }
        return "—"
    }
}

/// Phone → watch state snapshot. Only what the wrist monitor renders.
public struct WatchRelayState: Codable, Equatable, Sendable {
    public init(
        isRecording: Bool,
        timecode: String,
        media: String,
        cameraBatteryPercent: Int,
        cameraName: String,
        connection: WatchConnectionState,
        feedLive: Bool,
        isPhotography: Bool = false,
        feedAspectRatio: Double = 16.0 / 9.0
    ) {
        self.isRecording = isRecording
        self.timecode = timecode
        self.media = media
        self.cameraBatteryPercent = cameraBatteryPercent
        self.cameraName = cameraName
        self.connection = connection
        self.feedLive = feedLive
        self.isPhotography = isPhotography
        self.feedAspectRatio = feedAspectRatio > 0 ? feedAspectRatio : 16.0 / 9.0
    }

    public let isRecording: Bool
    public let timecode: String
    public let media: String
    public let cameraBatteryPercent: Int
    public let cameraName: String
    public let connection: WatchConnectionState
    public let feedLive: Bool
    public let isPhotography: Bool
    public let feedAspectRatio: Double

    /// True when nothing the wrist renders as state differs from `other`.
    /// Timecode ticks with the frame stream; including it would put a state
    /// message on the link beside every preview frame.
    public func matchesIgnoringLiveReadouts(_ other: WatchRelayState) -> Bool {
        isRecording == other.isRecording
            && media == other.media
            && cameraBatteryPercent == other.cameraBatteryPercent
            && cameraName == other.cameraName
            && connection == other.connection
            && feedLive == other.feedLive
            && isPhotography == other.isPhotography
            && feedAspectRatio == other.feedAspectRatio
    }

    public func replacing(isRecording: Bool) -> WatchRelayState {
        WatchRelayState(
            isRecording: isRecording,
            timecode: timecode,
            media: media,
            cameraBatteryPercent: cameraBatteryPercent,
            cameraName: cameraName,
            connection: connection,
            feedLive: feedLive,
            isPhotography: isPhotography,
            feedAspectRatio: feedAspectRatio)
    }

    /// Snapshot from live telemetry. `feedLive` is whether a picture has presented.
    public static func snapshot(
        status: CameraStatus,
        phase: ConnectionPhase,
        cameraName: String,
        feedLive: Bool
    ) -> WatchRelayState {
        let live = {
            if case .live = phase { return true }
            return false
        }()
        let photography: Bool = {
            guard (0...255).contains(status.shootingMode) else { return false }
            return ShootingMode(rawValue: UInt8(status.shootingMode))?.isPhoto == true
        }()
        return WatchRelayState(
            isRecording: status.isRecording,
            timecode: status.timecodeClock,
            media: WatchRelayMedia.label(
                storageFreeMb: status.storageFreeMb,
                storageTotalMb: status.storageTotalMb,
                sdFreeMb: status.sdFreeMb,
                sdTotalMb: status.sdTotalMb,
                recordRemainingSec: status.recordRemainingSec),
            cameraBatteryPercent: status.batteryPercent,
            cameraName: cameraName,
            connection: live ? .connected : .noCamera,
            feedLive: live && feedLive,
            isPhotography: photography,
            feedAspectRatio: 16.0 / 9.0)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isRecording = try container.decode(Bool.self, forKey: .isRecording)
        timecode = try container.decode(String.self, forKey: .timecode)
        media = try container.decode(String.self, forKey: .media)
        cameraBatteryPercent = try container.decode(Int.self, forKey: .cameraBatteryPercent)
        cameraName = try container.decode(String.self, forKey: .cameraName)
        connection = try container.decode(WatchConnectionState.self, forKey: .connection)
        feedLive = try container.decode(Bool.self, forKey: .feedLive)
        isPhotography = try container.decodeIfPresent(Bool.self, forKey: .isPhotography) ?? false
        let ratio = try container.decodeIfPresent(Double.self, forKey: .feedAspectRatio)
        feedAspectRatio = (ratio ?? 0) > 0 ? (ratio ?? 0) : 16.0 / 9.0
    }
}

/// Phone → watch preview frame. Throttled and drop-stale (only the latest matters).
public struct WatchRelayFrame: Codable, Equatable, Sendable {
    public init(jpeg: Data, timecode: String, isRecording: Bool) {
        self.jpeg = jpeg
        self.timecode = timecode
        self.isRecording = isRecording
    }

    /// Image bytes: HEIC preferred, JPEG fallback. Watch hands them to `UIImage`.
    public let jpeg: Data
    public let timecode: String
    public let isRecording: Bool
}

/// Watch → phone command.
public enum WatchRelayCommand: String, Codable, Equatable, Sendable {
    /// Toggle recording (start if stopped, stop if recording).
    case toggleRecord
    /// The watch came back to the foreground: resend a snapshot and restart the frame pump.
    case resume
    /// Release the shutter. Photo / SuperNight only.
    case capture
}

/// Phone → watch reply acknowledging a ``WatchRelayCommand``.
public struct WatchCommandResult: Codable, Equatable, Sendable {
    public init(accepted: Bool, isRecording: Bool, error: String?) {
        self.accepted = accepted
        self.isRecording = isRecording
        self.error = error
    }

    public let accepted: Bool
    public let isRecording: Bool
    public let error: String?
}

public enum WatchRelayEnvelopeError: Error, Equatable, Sendable {
    case empty
    case unknownKind(UInt8)
}

/// One-byte-tagged JSON framing over `WCSession.sendMessageData`.
public enum WatchRelayEnvelope {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode<Payload: Encodable>(
        kind: WatchRelayProtocol.Kind,
        payload: Payload
    ) throws -> Data {
        var data = Data([kind.rawValue])
        data.append(try encoder.encode(payload))
        return data
    }

    public static func kind(of envelope: Data) throws -> WatchRelayProtocol.Kind {
        guard let first = envelope.first else { throw WatchRelayEnvelopeError.empty }
        guard let kind = WatchRelayProtocol.Kind(rawValue: first) else {
            throw WatchRelayEnvelopeError.unknownKind(first)
        }
        return kind
    }

    public static func decode<Payload: Decodable>(
        _ type: Payload.Type,
        from envelope: Data
    ) throws -> Payload {
        guard !envelope.isEmpty else { throw WatchRelayEnvelopeError.empty }
        return try decoder.decode(type, from: envelope.dropFirst())
    }
}
