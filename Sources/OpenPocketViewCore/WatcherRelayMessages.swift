import Foundation

public struct WatcherRelayHello: Codable, Equatable, Sendable {
    public var version: Int
    public var hostName: String
    public var cameraName: String?
    public var passcode: String?
    public var watcherID: String?

    public init(
        version: Int = WatcherRelayProtocol.version,
        hostName: String,
        cameraName: String? = nil,
        passcode: String? = nil,
        watcherID: String? = nil
    ) {
        self.version = version
        self.hostName = hostName
        self.cameraName = cameraName
        self.passcode = passcode
        self.watcherID = watcherID
    }
}

public struct WatcherRelayJoinDenied: Codable, Equatable, Error, Sendable {
    public var reason: String
    public var passcodeRequired: Bool

    public init(reason: String, passcodeRequired: Bool) {
        self.reason = reason
        self.passcodeRequired = passcodeRequired
    }
}

public struct WatcherRelayState: Codable, Equatable, Sendable {
    public var isRecording: Bool
    public var format: String
    public var color: String
    public var zoom: String
    public var liveFPS: String
    public var batteryPercent: Int
    public var cameraName: String
    public var iso: String
    public var shutter: String
    public var allowsControlRequests: Bool

    public init(
        isRecording: Bool = false,
        format: String = "",
        color: String = "",
        zoom: String = "",
        liveFPS: String = "",
        batteryPercent: Int = -1,
        cameraName: String = "",
        iso: String = "",
        shutter: String = "",
        allowsControlRequests: Bool = true
    ) {
        self.isRecording = isRecording
        self.format = format
        self.color = color
        self.zoom = zoom
        self.liveFPS = liveFPS
        self.batteryPercent = batteryPercent
        self.cameraName = cameraName
        self.iso = iso
        self.shutter = shutter
        self.allowsControlRequests = allowsControlRequests
    }
}

public struct WatcherRelayFrameMetadata: Codable, Equatable, Sendable {
    public var codec: Int
    public var isKeyframe: Bool
    public var parameterSets: [Data]?
    public var isRecording: Bool
    public var extraMirrored: Bool

    public init(
        codec: Int = WatcherRelayProtocol.hevcCodec,
        isKeyframe: Bool,
        parameterSets: [Data]? = nil,
        isRecording: Bool = false,
        extraMirrored: Bool = false
    ) {
        self.codec = codec
        self.isKeyframe = isKeyframe
        self.parameterSets = parameterSets
        self.isRecording = isRecording
        self.extraMirrored = extraMirrored
    }
}

public enum WatcherRelayCommand: Codable, Equatable, Sendable {
    case toggleRecording
    case tapFocus(cameraX: Int, cameraY: Int, coordinateWidth: Int, coordinateHeight: Int)
    case setISO(Int)
    case setShutterDenom(Int)
    case setWhiteBalance(mode: Int, kelvin: Int, tint: Int)
    case setColor(Int)
    case setZoom(Int)
}

public struct WatcherRelayControlToken: Codable, Equatable, Sendable {
    public var holderName: String
    public var holderIsRecipient: Bool

    public init(holderName: String, holderIsRecipient: Bool) {
        self.holderName = holderName
        self.holderIsRecipient = holderIsRecipient
    }
}

public enum WatcherRelayFrameBlob: Sendable {
    public static func encode(metadata: WatcherRelayFrameMetadata, hevc: Data) throws -> Data {
        let meta = try JSONEncoder().encode(metadata)
        let n = UInt32(meta.count)
        var out = Data(capacity: 4 + meta.count + hevc.count)
        out.append(contentsOf: [
            UInt8(truncatingIfNeeded: n >> 24),
            UInt8(truncatingIfNeeded: n >> 16),
            UInt8(truncatingIfNeeded: n >> 8),
            UInt8(truncatingIfNeeded: n),
        ])
        out.append(meta)
        out.append(hevc)
        return out
    }

    public static func decode(_ payload: Data) throws -> (WatcherRelayFrameMetadata, Data) {
        guard payload.count >= 4 else {
            throw WatcherRelayFraming.DecodeError.payloadTooLarge(declared: payload.count)
        }
        let n =
            Int(payload[payload.startIndex]) << 24
            | Int(payload[payload.startIndex + 1]) << 16
            | Int(payload[payload.startIndex + 2]) << 8
            | Int(payload[payload.startIndex + 3])
        guard n >= 0, 4 + n <= payload.count else {
            throw WatcherRelayFraming.DecodeError.payloadTooLarge(declared: n)
        }
        let meta = try JSONDecoder().decode(
            WatcherRelayFrameMetadata.self,
            from: payload.subdata(in: (payload.startIndex + 4)..<(payload.startIndex + 4 + n)))
        let hevc = payload.subdata(in: (payload.startIndex + 4 + n)..<payload.endIndex)
        return (meta, hevc)
    }
}

public enum WatcherRelayJoin: Sendable {
    public static func hostAccepts(hello: WatcherRelayHello, requiredPasscode: String)
        -> Result<Void, WatcherRelayJoinDenied>
    {
        guard hello.version == WatcherRelayProtocol.version else {
            return .failure(
                WatcherRelayJoinDenied(
                    reason: "This OpenPocketCine build cannot watch that feed.",
                    passcodeRequired: false))
        }
        let need = requiredPasscode.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !need.isEmpty else { return .success(()) }
        if hello.passcode == need { return .success(()) }
        return .failure(
            WatcherRelayJoinDenied(reason: "Wrong passcode.", passcodeRequired: true))
    }
}
