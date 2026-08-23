import Testing

@testable import OpenPocketViewCore

@Suite struct DumlFrameTests {
    // CRC-8 vectors from the Osmosis unit tests.
    @Test func crc8Vectors() {
        #expect(Duml.crc8([0x55, 0x11, 0x04]) == 0x92)
        #expect(Duml.crc8([0x55, 0x33, 0x04]) == 0xC2)
    }

    // Enter-playback (0x02/0x0C), App -> Camera, seq 0xA000 — a real Osmosis frame, byte for byte.
    @Test func encodeEnterPlayback() {
        let frame = Duml.encode(
            .init(
                sender: Duml.senderApp, receiver: Duml.rxCamera, seq: 0xA000,
                flags: Duml.flagRequest, cmdSet: 0x02, cmdId: 0x0C,
                payload: [0x01, 0x01, 0x00, 0x01]))
        #expect(
            frame == [
                0x55, 0x11, 0x04, 0x92, 0x02, 0x01, 0x00, 0xA0,
                0x40, 0x02, 0x0C, 0x01, 0x01, 0x00, 0x01, 0xB6, 0x3B,
            ])
    }

    // SetPairingPIN (0x07/0x45), App -> WiFi, id 0x8092 — 51-byte frame, verified end + length.
    @Test func encodePairing() {
        let pin = Duml.packString("284ae5b8d76b3375a04a6417ad71bea3") + Duml.packString("osmo")
        let frame = Duml.encode(
            .init(
                sender: Duml.senderApp, receiver: Duml.rxWifi, seq: 0x8092,
                flags: Duml.flagRequest, cmdSet: 0x07, cmdId: 0x45, payload: pin))
        #expect(frame.count == 51)
        #expect(frame[3] == 0xC2)
        #expect(Array(frame.suffix(2)) == [0xA0, 0xB4])
        #expect(
            Array(frame.prefix(11)) == [
                0x55, 0x33, 0x04, 0xC2, 0x02, 0x07, 0x92, 0x80, 0x40, 0x07, 0x45,
            ])
    }

    @Test func roundTrip() throws {
        let original = Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: 0xA000,
            flags: Duml.flagRequest, cmdSet: 0x02, cmdId: 0x0C, payload: [0x01, 0x01, 0x00, 0x01])
        let bytes = Duml.encode(original)
        let decoded = try #require(Duml.decode(bytes))
        #expect(decoded.consumed == bytes.count)
        #expect(decoded.frame == original)
    }

    @Test func unpackStatusString() {
        // Osmosis example: `00 12 "XtraEdgePro-2DCA16"`
        let ssid = Array("XtraEdgePro-2DCA16".utf8)
        #expect(Duml.unpackStatusString([0x00, UInt8(ssid.count)] + ssid) == "XtraEdgePro-2DCA16")
        #expect(Duml.unpackStatusString([0xE0]) == "")  // Pocket 3 wake-error, no string
        #expect(Duml.unpackStatusString([0x00, 0x00]) == "")  // AP not up yet
        #expect(Duml.unpackStatusString([]) == "")
    }

    @Test func decodeRejectsBadCrc() {
        var bytes = Duml.encode(
            .init(
                sender: Duml.senderApp, receiver: Duml.rxCamera, seq: 0xA000,
                flags: Duml.flagRequest, cmdSet: 0x02, cmdId: 0x0C, payload: [0x01]))
        bytes[bytes.count - 1] ^= 0xFF  // corrupt the CRC16
        #expect(Duml.decode(bytes) == nil)
    }
}
