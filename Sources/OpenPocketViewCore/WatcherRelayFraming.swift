import Foundation

/// `[u32be payload length][u8 kind][payload]`. Length includes the kind byte.
public enum WatcherRelayFraming: Sendable {
    public static let headerBytes = 5

    public static func encode(kind: WatcherRelayProtocol.Kind, payload: Data) -> Data {
        let declared = UInt32(payload.count + 1)
        var out = Data(capacity: headerBytes + payload.count)
        out.append(contentsOf: [
            UInt8(truncatingIfNeeded: declared >> 24),
            UInt8(truncatingIfNeeded: declared >> 16),
            UInt8(truncatingIfNeeded: declared >> 8),
            UInt8(truncatingIfNeeded: declared),
            kind.rawValue,
        ])
        out.append(payload)
        return out
    }

    public struct Decoded: Equatable, Sendable {
        public var kind: WatcherRelayProtocol.Kind
        public var payload: Data
        public var consumedBytes: Int
        public init(kind: WatcherRelayProtocol.Kind, payload: Data, consumedBytes: Int) {
            self.kind = kind
            self.payload = payload
            self.consumedBytes = consumedBytes
        }
    }

    public enum DecodeError: Error, Equatable, Sendable {
        case payloadTooLarge(declared: Int)
        case unknownKind(UInt8)
    }

    public static func decode(from buffer: Data) throws -> Decoded? {
        guard buffer.count >= headerBytes else { return nil }
        let declared =
            Int(buffer[buffer.startIndex]) << 24
            | Int(buffer[buffer.startIndex + 1]) << 16
            | Int(buffer[buffer.startIndex + 2]) << 8
            | Int(buffer[buffer.startIndex + 3])
        guard declared >= 1 else { throw DecodeError.payloadTooLarge(declared: declared) }
        guard declared - 1 <= WatcherRelayProtocol.maximumPayloadBytes else {
            throw DecodeError.payloadTooLarge(declared: declared - 1)
        }
        let total = 4 + declared
        guard buffer.count >= total else { return nil }
        let rawKind = buffer[buffer.startIndex + 4]
        guard let kind = WatcherRelayProtocol.Kind(rawValue: rawKind) else {
            throw DecodeError.unknownKind(rawKind)
        }
        let payloadStart = buffer.startIndex + headerBytes
        let payload = Data(buffer[payloadStart..<(buffer.startIndex + total)])
        return Decoded(kind: kind, payload: payload, consumedBytes: total)
    }
}
