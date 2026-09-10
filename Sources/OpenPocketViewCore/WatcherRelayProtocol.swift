import Foundation

/// Bonjour second-screen contract. Sockets and VideoToolbox stay in the iOS shell.
public enum WatcherRelayProtocol: Sendable {
    /// Must also appear in `NSBonjourServices`. 14-character limit.
    public static let serviceType = "_opc-mon._tcp"
    public static let version = 1
    public static let maximumPayloadBytes = 8 * 1024 * 1024
    public static let txtCamera = "c"
    public static let txtWatchable = "w"
    public static let hevcCodec = 1

    public enum Kind: UInt8, Sendable {
        case hello = 0x01
        case state = 0x02
        case frame = 0x03
        case controlToken = 0x04
        case joinDenied = 0x05
        case requestControl = 0x10
        case releaseControl = 0x11
        case command = 0x12
    }
}
