import Foundation

/// Bounded RTMP chunk and AMF0 parsing for the experimental local camera receiver.
public enum RTMPIngest {
    public struct Message: Sendable {
        public let type: UInt8
        public let stream: UInt32
        public let timestamp: UInt32
        public let payload: [UInt8]
        public init(type: UInt8, stream: UInt32 = 0, timestamp: UInt32 = 0, payload: [UInt8]) {
            self.type = type
            self.stream = stream
            self.timestamp = timestamp
            self.payload = payload
        }
    }
    public enum Failure: Error { case malformed, limit }
    public struct Parser {
        private struct Channel {
            var length = 0
            var type: UInt8 = 0
            var stream: UInt32 = 0
            var timestamp: UInt32 = 0
            var delta: UInt32 = 0
            var extended = false
            var absolute = true
            var payload: [UInt8] = []
        }
        private var channels: [Int: Channel] = [:]
        private var buffer: [UInt8] = []
        public private(set) var chunkSize = 128
        public init() {}
        public mutating func append(_ bytes: [UInt8]) throws -> [Message] {
            guard buffer.count + bytes.count <= 8_388_608 else { throw Failure.limit }
            buffer += bytes
            var offset = 0
            var messages: [Message] = []
            while offset < buffer.count {
                let start = offset
                var cursor = start + 1
                let format = Int(buffer[start] >> 6)
                var id = Int(buffer[start] & 63)
                if id == 0 {
                    guard cursor < buffer.count else { break }
                    id = 64 + Int(buffer[cursor])
                    cursor += 1
                } else if id == 1 {
                    guard cursor + 2 <= buffer.count else { break }
                    id = 64 + Int(buffer[cursor]) + Int(buffer[cursor + 1]) * 256
                    cursor += 2
                }
                guard channels.count < 64 || channels[id] != nil else { throw Failure.limit }
                guard format == 0 || channels[id] != nil else { throw Failure.malformed }
                var channel = channels[id] ?? Channel()
                let fresh = channel.payload.isEmpty
                let headerLength = [11, 7, 3, 0][format]
                guard cursor + headerLength <= buffer.count else { break }
                if format < 3 {
                    guard fresh else { throw Failure.malformed }
                    let stamp = read24(buffer, cursor)
                    channel.extended = stamp == 0xffffff
                    channel.absolute = format == 0
                    if format == 0 {
                        channel.timestamp = stamp
                        channel.delta = 0
                    } else {
                        channel.delta = stamp
                    }
                    if format <= 1 {
                        channel.length = Int(read24(buffer, cursor + 3))
                        channel.type = buffer[cursor + 6]
                        guard channel.length <= 4_194_304 else { throw Failure.limit }
                    }
                    if format == 0 {
                        channel.stream =
                            UInt32(buffer[cursor + 7]) | UInt32(buffer[cursor + 8]) << 8
                            | UInt32(buffer[cursor + 9]) << 16 | UInt32(buffer[cursor + 10]) << 24
                    }
                }
                cursor += headerLength
                if channel.extended {
                    guard cursor + 4 <= buffer.count else { break }
                    let stamp = read32(buffer, cursor)
                    cursor += 4
                    if format < 3 {
                        if channel.absolute {
                            channel.timestamp = stamp
                        } else {
                            channel.delta = stamp
                        }
                    }
                }
                if fresh && format != 0 { channel.timestamp &+= channel.delta }
                let take = min(chunkSize, channel.length - channel.payload.count)
                guard take >= 0, cursor + take <= buffer.count else { break }
                channel.payload += buffer[cursor..<cursor + take]
                cursor += take
                if channel.payload.count == channel.length {
                    let message = Message(
                        type: channel.type, stream: channel.stream,
                        timestamp: channel.timestamp, payload: channel.payload)
                    if message.type == 1 {
                        guard message.payload.count == 4 else { throw Failure.malformed }
                        let next = Int(read32(message.payload, 0))
                        guard (1...65_536).contains(next) else { throw Failure.limit }
                        chunkSize = next
                    }
                    messages.append(message)
                    channel.payload.removeAll(keepingCapacity: true)
                }
                channels[id] = channel
                offset = cursor
            }
            if offset > 0 { buffer.removeFirst(offset) }
            return messages
        }
    }

    public static func read24(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) << 16 | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2])
    }
    public static func read32(_ b: [UInt8], _ i: Int) -> UInt32 {
        read24(b, i) << 8 | UInt32(b[i + 3])
    }
    public static func big32(_ n: UInt32) -> [UInt8] {
        [
            UInt8(truncatingIfNeeded: n >> 24), UInt8(truncatingIfNeeded: n >> 16),
            UInt8(truncatingIfNeeded: n >> 8), UInt8(truncatingIfNeeded: n),
        ]
    }
    public static func encode(_ message: Message) -> [UInt8] {
        let size = message.payload.count
        var result: [UInt8] = [
            3, 0, 0, 0, UInt8((size >> 16) & 255), UInt8((size >> 8) & 255), UInt8(size & 255),
            message.type,
        ]
        result += (0..<4).map { UInt8(truncatingIfNeeded: message.stream >> ($0 * 8)) }
        for index in stride(from: 0, to: size, by: 128) {
            if index > 0 { result.append(0xc3) }
            result += message.payload[index..<min(index + 128, size)]
        }
        return result
    }

    public indirect enum Value: Sendable {
        case string(String), number(Double), bool(Bool), null, object([String: Value])
        public var string: String? {
            if case .string(let s) = self { return s }
            return nil
        }
        public var number: Double? {
            if case .number(let n) = self { return n }
            return nil
        }
    }
    public static func amf(_ values: [Value]) -> [UInt8] {
        values.flatMap { value -> [UInt8] in
            switch value {
            case .null: return [5]
            case .bool(let b): return [1, b ? 1 : 0]
            case .number(let n):
                return [0]
                    + (0..<8).reversed().map { UInt8(truncatingIfNeeded: n.bitPattern >> ($0 * 8)) }
            case .string(let s):
                let b = Array(s.utf8)
                return [2, UInt8((b.count >> 8) & 255), UInt8(b.count & 255)] + b
            case .object(let object):
                var b: [UInt8] = [3]
                for key in object.keys.sorted() {
                    let k = Array(key.utf8)
                    b +=
                        [UInt8((k.count >> 8) & 255), UInt8(k.count & 255)] + k
                        + amf([object[key]!])
                }
                return b + [0, 0, 9]
            }
        }
    }
    public static func values(_ data: [UInt8]) throws -> [Value] {
        var i = 0
        func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, i + count <= data.count else { throw Failure.malformed }
            defer { i += count }
            return Array(data[i..<i + count])
        }
        func string() throws -> String {
            let n = try take(2)
            return String(decoding: try take(Int(n[0]) * 256 + Int(n[1])), as: UTF8.self)
        }
        func value(_ depth: Int) throws -> Value {
            guard depth < 12 else { throw Failure.limit }
            switch try take(1)[0] {
            case 0:
                let bits = try take(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                return .number(Double(bitPattern: bits))
            case 1: return .bool(try take(1)[0] != 0)
            case 2: return .string(try string())
            case 5, 6: return .null
            case 3, 8:
                if data[i - 1] == 8 { _ = try take(4) }
                var object: [String: Value] = [:]
                while true {
                    let key = try string()
                    if key.isEmpty, i < data.count, data[i] == 9 {
                        i += 1
                        break
                    }
                    guard object.count < 128 else { throw Failure.limit }
                    object[key] = try value(depth + 1)
                }
                return .object(object)
            default: throw Failure.malformed
            }
        }
        var result: [Value] = []
        while i < data.count { result.append(try value(0)) }
        return result
    }
}
