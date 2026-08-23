import Foundation

/// The DUML-over-UDP datalink framing: the 8-byte transport header, the 12-byte
/// command routing header, and the fixed handshake / ACK payloads. Pure byte math,
/// ported from Osmosis `net/DumlTransport.kt` and asserted against its captures.
///
/// Per packet the wire is `[8B transport hdr][12B routing hdr][DUML frame]`. The
/// stateful socket + sequence counters live in the app's DatalinkDriver; only the
/// pure layout lives here (which is exactly the part two Osmosis regressions got
/// wrong, and exactly the part a test can pin without a socket).
public enum DumlTransport {
    public enum PktType: UInt8 {
        case handshake = 0x00  // session open
        case telemetry = 0x01  // peer status push
        case video = 0x02  // HEVC live-view fragments (best-effort; not in Osmosis)
        case ackedData = 0x03
        case ack = 0x04  // window acknowledgement
        case command = 0x05  // carries a routing header + DUML frame
    }

    /// Transport sequence (bytes 4–5). Mimo echoes the latest video packet's seq as the ACK cursor.
    public static func transportSeq(_ datagram: [UInt8]) -> UInt16? {
        guard datagram.count >= 6 else { return nil }
        return UInt16(datagram[4]) | (UInt16(datagram[5]) << 8)
    }

    /// Session-open reply. Byte 6 is pktType; do not require our session/seq —
    /// the camera's 0x00 is the ACK even when those fields differ.
    public static func isHandshake(_ datagram: [UInt8]) -> Bool {
        datagram.count >= 8 && datagram[6] == PktType.handshake.rawValue
    }

    /// 8-byte transport header: `[u16le 0x8000|total][u16le session][u16le seq][u8 pktType][u8 xor]`,
    /// where the trailing byte is the XOR of the other seven and `total = 8 + payloadLen`.
    public static func transportHeader(
        pktType: UInt8, payloadLen: Int, sessionId: UInt16, seq: UInt16
    ) -> [UInt8] {
        let total = 8 + payloadLen
        let w0 = 0x8000 | (total & 0x3FFF)
        var b: [UInt8] = [
            UInt8(w0 & 0xFF), UInt8((w0 >> 8) & 0xFF),
            UInt8(sessionId & 0xFF), UInt8((sessionId >> 8) & 0xFF),
            UInt8(seq & 0xFF), UInt8((seq >> 8) & 0xFF),
            pktType,
        ]
        b.append(b.reduce(0, ^))
        return b
    }

    /// 12-byte routing header (pkt `0x05`): `[u16le ack=seq-8][u16le seq][00 00 00 00][u8 counter][01][drone?60:00][00]`.
    /// Both seq fields are in OUR OWN command-seq space (r2-3 = this seq, r0-1 = previous). Getting this
    /// wrong silently drops writes while reads keep flowing — see the Osmosis notes.
    public static func routingHeader(seq: UInt16, cmdCounter: UInt8, drone: Bool = false) -> [UInt8]
    {
        let ack = seq &- 8
        return [
            UInt8(ack & 0xFF), UInt8((ack >> 8) & 0xFF),
            UInt8(seq & 0xFF), UInt8((seq >> 8) & 0xFF),
            0, 0, 0, 0, cmdCounter, 0x01,
            drone ? 0x60 : 0x00, 0x00,
        ]
    }

    /// Full 48-byte session-open datagram: transport header + `handshakePayload`.
    public static func handshakeDatagram(sessionId: UInt16, seq: UInt16, baseSeq: UInt16) -> [UInt8]
    {
        let payload = handshakePayload(baseSeq: baseSeq)
        return transportHeader(
            pktType: PktType.handshake.rawValue, payloadLen: payload.count,
            sessionId: sessionId, seq: seq
        ) + payload
    }

    /// The 40-byte handshake payload (sent as pktType 0x00). First two bytes are `baseSeq` LE — a fresh
    /// random 8-aligned value per connect (a fixed base can wedge the peer). The rest is a fixed template
    /// (proposed window 100, MTU 1472).
    public static func handshakePayload(baseSeq: UInt16) -> [UInt8] {
        var p: [UInt8] = [
            0x00, 0x00, 0x64, 0x00, 0x64, 0x00, 0xC0, 0x05, 0x14, 0x00, 0x00, 0x64, 0x00, 0x00,
            0x01, 0x90,
            0x01, 0xC0, 0x05, 0x14, 0x00, 0x00, 0x64, 0x00, 0x14, 0x00, 0x64, 0x00, 0xC0, 0x05,
            0x14, 0x00,
            0x00, 0x64, 0x00, 0x01, 0x01, 0x04, 0x01, 0x02,
        ]
        p[0] = UInt8(baseSeq & 0xFF)
        p[1] = UInt8((baseSeq >> 8) & 0xFF)
        return p
    }

    /// The 26-byte pktType-0x04 ACK payload: `grp(peerCursor) + grp(baseSeq) + grp(baseSeq) + [0,0]`,
    /// where `grp(v) = [v_lo, v_hi, v_lo, v_hi, 0,0,0,0]`. With the 8-byte transport header the whole
    /// packet is 34 bytes. The peer holds its downlink until it sees its own cursor echoed here.
    public static func ackPayload(peerCursor: UInt16, baseSeq: UInt16) -> [UInt8] {
        func grp(_ v: UInt16) -> [UInt8] {
            [
                UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), 0,
                0, 0, 0,
            ]
        }
        return grp(peerCursor) + grp(baseSeq) + grp(baseSeq) + [0, 0]
    }

    /// Every CRC-valid DUML frame in `raw`, scanning byte-at-a-time so it finds frames inside the
    /// transport/routing wrapper (and any tunnelled frames), and tolerates multiple frames per datagram.
    /// Ported from Osmosis `scanFrames`; validating both CRCs is what makes byte-at-a-time safe.
    public static func scanFrames(_ raw: [UInt8]) -> [Duml.Frame] {
        var out: [Duml.Frame] = []
        var i = 0
        let n = raw.count
        while i + 13 <= n {
            guard raw[i] == 0x55 else {
                i += 1
                continue
            }
            let total = Int(raw[i + 1]) | ((Int(raw[i + 2]) & 0x03) << 8)
            guard raw[i + 2] >> 2 == 1, total >= 13, i + total <= n else {
                i += 1
                continue
            }
            let f = Array(raw[i..<(i + total)])
            guard Duml.crc8(Array(f[0..<3])) == f[3] else {
                i += 1
                continue
            }
            let got = UInt16(f[total - 2]) | (UInt16(f[total - 1]) << 8)
            guard Duml.crc16(Array(f[0..<(total - 2)])) == got else {
                i += 1
                continue
            }
            out.append(
                Duml.Frame(
                    sender: f[4], receiver: f[5],
                    seq: UInt16(f[6]) | (UInt16(f[7]) << 8),
                    flags: f[8], cmdSet: f[9], cmdId: f[10],
                    payload: Array(f[11..<(total - 2)])))
            i += 1
        }
        return out
    }
}
