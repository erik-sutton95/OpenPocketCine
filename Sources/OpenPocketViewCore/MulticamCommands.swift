import Foundation

/// Experimental Pocket 4 Pro station-Wi-Fi and livestream provisioning.
/// Network role and shooting mode are separate commands, observed on hardware.
public enum MulticamCommands {
    public enum Failure: Error { case invalidInput }

    public static func wifiWorkMode(seq: UInt16) -> Duml.Frame {
        command(7, 7, 0x39, [0], seq)
    }

    /// Separate network role; does not select livestream shooting mode.
    public static func stationMode(_ enabled: Bool, seq: UInt16) -> Duml.Frame {
        command(7, 7, 0x48, [enabled ? 1 : 0], seq)
    }

    /// BLE shooting-mode route observed on Pocket 4 Pro. Select before joining Wi-Fi.
    public static func videoMode(seq: UInt16) -> Duml.Frame {
        command(8, 2, 0xe1, [1], seq)
    }

    /// A short handshake reply is not the camera's initial command window.
    public static func controlSequence(fromInitialWindow bytes: [UInt8]) -> UInt16? {
        guard bytes.count == 34, bytes[6] == DumlTransport.PktType.telemetry.rawValue else {
            return nil
        }
        return (UInt16(bytes[8]) | UInt16(bytes[9]) << 8) &+ 8
    }

    public static func join(ssid: String, password: String, seq: UInt16) throws -> Duml.Frame {
        guard !ssid.isEmpty, ssid.utf8.count <= 32, password.utf8.count <= 63 else {
            throw Failure.invalidInput
        }
        return command(7, 7, 0x47, Duml.packString(ssid) + Duml.packString(password), seq)
    }

    public static func prepare(seq: UInt16) -> Duml.Frame {
        command(8, 2, 0xe1, [0x1a], seq)
    }

    public static func configuration(url: String, seq: UInt16) throws -> Duml.Frame {
        guard let address = URL(string: url), address.scheme == "rtmp", address.host != nil,
            url.utf8.count < 256
        else { throw Failure.invalidInput }
        let json: [String: Any] = [
            "codec": "HEVC", "EnhancedRTMP": false, "supportStopLive": false,
            "watermark": 0, "rtmpAddress": url, "orientation": "landscape",
        ]
        let bytes = [UInt8](
            try JSONSerialization.data(
                withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes]))
        let count = UInt16(bytes.count)
        let body = count + 11
        // Version, body size, captured encoder preset, JSON size, JSON document.
        let prefix: [UInt8] = [
            1, UInt8(body & 255), UInt8(body >> 8), 10, 0x70, 0x17,
            2, 1, 2, 0, 0, 0, UInt8(count & 255), UInt8(count >> 8),
        ]
        return command(8, 8, 0x78, prefix + bytes, seq)
    }

    public static func streaming(_ enabled: Bool, seq: UInt16) -> Duml.Frame {
        command(8, 2, 0x8e, [1, 1, 0x1a, 0, 1, enabled ? 1 : 2], seq)
    }

    private static func command(
        _ receiver: UInt8, _ set: UInt8, _ id: UInt8, _ payload: [UInt8], _ seq: UInt16
    ) -> Duml.Frame {
        Duml.Frame(
            sender: 2, receiver: receiver, seq: seq, flags: 0x40, cmdSet: set, cmdId: id,
            payload: payload)
    }
}

/// Bounded retry for the Wi-Fi transition observed in Mimo: 01 ff, then 00 00.
/// Other rejections are not assumed transient.
public enum MulticamJoinPolicy {
    public static let maximumAttempts = 3
    public static let prepareSettleSeconds = 10
    public static let replyTimeoutSeconds: TimeInterval = 45
    public static let retryDelaySeconds = 5
    public enum Decision: Equatable { case connected, retry, rejected }
    public static func decision(reply: [UInt8], attempt: Int) -> Decision {
        // Both success shapes observed on Pocket 4 Pro; do not accept arbitrary suffixes.
        if reply == [0, 0] || reply == [0, 0, 0] { return .connected }
        if reply == [1, 0xff], attempt < maximumAttempts { return .retry }
        return .rejected
    }
}

/// Exact, captured response shapes; an unavailable getter is not a join result.
public enum MulticamStationPolicy {
    public enum Decision: Equatable {
        case alreadyStation, setAndVerify, setWithoutReadback, reject
    }
    public static func decision(reply: [UInt8], allowMissingQuery: Bool) -> Decision {
        if reply == [0, 1] { return .alreadyStation }
        if reply == [0, 0] { return .setAndVerify }
        if reply == [0xe0], allowMissingQuery { return .setWithoutReadback }
        return .reject
    }
    public static func acceptsSetter(_ reply: [UInt8], missingQuery: Bool) -> Bool {
        reply == [0, 0] || (missingQuery && reply == [0])
    }
}
