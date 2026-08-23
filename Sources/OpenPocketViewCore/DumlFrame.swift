import Foundation

/// DUML wire framing for DJI Osmo cameras, ported from the Osmosis
/// reverse-engineering (see docs/protocol-notes.md). Plaintext, no crypto.
///
/// Frame layout (total = 13 + payload.count):
///   55 | len_lo | (ver<<2)|len_hi | crc8(bytes[0..2]) |
///   sender | receiver | seq:u16le | flags | cmdSet | cmdId | payload | crc16:u16le
public enum Duml {
    /// The app is always the sender: id 0, type 2 -> (0<<5)|2.
    public static let senderApp: UInt8 = 0x02

    /// Receivers, packed as (id<<5)|type. See Osmosis OsmoCommands / DumlTransport.
    public static let rxCamera: UInt8 = 0x01  // id 0, type 1
    public static let rxWifi: UInt8 = 0x07  // id 0, type 7
    public static let rxSession: UInt8 = 0xF0  // id 7, type 0x10 — session/heartbeat (0x00/0x2b)
    public static let rx1C: UInt8 = 0x1C  // id 0, type 0x1C — wake (0x53/0x10)

    /// Command flags (byte 8): request / response / unsolicited notify.
    public static let flagRequest: UInt8 = 0x40
    public static let flagResponse: UInt8 = 0xC0
    public static let flagNotify: UInt8 = 0x00
    /// Gimbal / cmdType-4 ACK (not the usual 0x02/* `0xC0`).
    public static let flagAck80: UInt8 = 0x80

    /// Opcode waiter key: `cmdSet << 8 | cmdId`. Not a human label.
    public static func opcodeKey(set: UInt8, cmd: UInt8) -> UInt16 {
        UInt16(set) << 8 | UInt16(cmd)
    }

    /// Camera/gimbal command ACK. `0xC0` is the 0x02/* reply; `0x80` is gimbal / cmdType 4.
    /// Do not require an exact payload — `CameraReply.parse` decides success after the match.
    public static func isCommandReply(_ flags: UInt8) -> Bool {
        flags == flagResponse || flags == flagAck80
    }

    /// In-session `0x02/*` writes that wait for an ACK (includes zoom `0xB8`).
    public static func isLiveCameraControl(set: UInt8, cmd: UInt8) -> Bool {
        guard set == 0x02 else { return false }
        switch cmd {
        case 0x01, 0x02, 0x0C, 0x1E, 0x18, 0x22, 0x24, 0x28, 0x2A, 0x2C, 0x2E,
            0x30, 0x32, 0x42, 0x68, 0x8E, 0x9F, 0xA0, 0xA5, 0xA6, 0xB8, 0xBF, 0xE1:
            return true
        default:
            return false
        }
    }

    /// Pairing / Wi-Fi / live-control replies that can land before the waiter.
    public static func shouldHoldReply(set: UInt8, cmd: UInt8) -> Bool {
        switch (set, cmd) {
        case (0x07, 0x45), (0x07, 0x46), (0x07, 0x07), (0x07, 0x0E), (0x53, 0x10):
            return true
        default:
            return isLiveCameraControl(set: set, cmd: cmd)
        }
    }

    public static func hex(_ bytes: [UInt8], limit: Int = 24) -> String {
        if bytes.isEmpty { return "-" }
        let head = bytes.prefix(limit).map { String(format: "%02X", $0) }.joined(separator: " ")
        return bytes.count > limit ? head + "…" : head
    }

    public struct Frame: Equatable {
        public var sender: UInt8
        public var receiver: UInt8
        public var seq: UInt16
        public var flags: UInt8
        public var cmdSet: UInt8
        public var cmdId: UInt8
        public var payload: [UInt8]

        public init(
            sender: UInt8, receiver: UInt8, seq: UInt16, flags: UInt8,
            cmdSet: UInt8, cmdId: UInt8, payload: [UInt8]
        ) {
            self.sender = sender
            self.receiver = receiver
            self.seq = seq
            self.flags = flags
            self.cmdSet = cmdSet
            self.cmdId = cmdId
            self.payload = payload
        }
    }

    public static func encode(_ f: Frame) -> [UInt8] {
        let total = 13 + f.payload.count
        var b: [UInt8] = []
        b.reserveCapacity(total)
        b.append(0x55)
        b.append(UInt8(total & 0xFF))
        b.append(UInt8((1 << 2) | ((total >> 8) & 0x03)))  // ver 1 + high length bits
        b.append(crc8(Array(b[0..<3])))
        b.append(f.sender)
        b.append(f.receiver)
        b.append(UInt8(f.seq & 0xFF))
        b.append(UInt8((f.seq >> 8) & 0xFF))
        b.append(f.flags)
        b.append(f.cmdSet)
        b.append(f.cmdId)
        b.append(contentsOf: f.payload)
        let c = crc16(b)
        b.append(UInt8(c & 0xFF))
        b.append(UInt8((c >> 8) & 0xFF))
        return b
    }

    /// Decode one frame at the start of `data`. Returns the frame and bytes
    /// consumed, or nil if `data` doesn't begin with a CRC-valid DUML frame.
    public static func decode(_ data: [UInt8]) -> (frame: Frame, consumed: Int)? {
        guard data.count >= 13, data[0] == 0x55 else { return nil }
        let total = Int(data[1]) | ((Int(data[2]) & 0x03) << 8)
        guard data[2] >> 2 == 1, total >= 13, data.count >= total else { return nil }
        let f = Array(data[0..<total])
        guard crc8(Array(f[0..<3])) == f[3] else { return nil }
        let got = UInt16(f[total - 2]) | (UInt16(f[total - 1]) << 8)
        guard crc16(Array(f[0..<(total - 2)])) == got else { return nil }
        return (
            Frame(
                sender: f[4], receiver: f[5],
                seq: UInt16(f[6]) | (UInt16(f[7]) << 8),
                flags: f[8], cmdSet: f[9], cmdId: f[10],
                payload: Array(f[11..<(total - 2)])), total
        )
    }

    /// `[len:u8][utf8]` — how the WiFi subsystem packs strings (SSID, pass, PIN).
    public static func packString(_ s: String) -> [UInt8] {
        let bytes = Array(s.utf8)
        return [UInt8(bytes.count)] + bytes
    }

    /// A WiFi-subsystem reply is `[status:1][len:1][utf8…]`. Empty if truncated.
    public static func unpackStatusString(_ p: [UInt8]) -> String {
        guard p.count >= 2 else { return "" }
        let end = min(2 + Int(p[1]), p.count)
        return String(decoding: p[2..<end], as: UTF8.self)
    }

    // Reflected CRC-8, init 0x77, poly 0x8C, over the 3 header bytes -> byte 3.
    public static func crc8(_ data: [UInt8]) -> UInt8 {
        var c: UInt8 = 0x77
        for byte in data {
            c ^= byte
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0x8C : c >> 1 }
        }
        return c
    }

    // Reflected CRC-16, init 0x3692, poly 0x8408, over the whole frame minus the trailing CRC.
    public static func crc16(_ data: [UInt8]) -> UInt16 {
        var c: UInt16 = 0x3692
        for byte in data {
            c ^= UInt16(byte)
            for _ in 0..<8 { c = (c & 1) != 0 ? (c >> 1) ^ 0x8408 : c >> 1 }
        }
        return c
    }
}
