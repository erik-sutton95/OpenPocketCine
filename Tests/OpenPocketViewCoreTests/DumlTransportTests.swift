import Testing

@testable import OpenPocketViewCore

@Suite struct DumlTransportTests {
    // The worked example from Osmosis: a command packet wrapping enter-playback.
    // transport: session 0x3A7C, seq 0xB890, pktType 0x05, payload 29 bytes (12 routing + 17 DUML).
    @Test func transportHeaderWorkedExample() {
        let hdr = DumlTransport.transportHeader(
            pktType: 0x05, payloadLen: 29, sessionId: 0x3A7C, seq: 0xB890)
        #expect(hdr == [0x25, 0x80, 0x7C, 0x3A, 0x90, 0xB8, 0x05, 0xCE])
    }

    @Test func routingHeaderWorkedExample() {
        let rt = DumlTransport.routingHeader(seq: 0xB890, cmdCounter: 0x06)
        #expect(rt == [0x88, 0xB8, 0x90, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x06, 0x01, 0x00, 0x00])
    }

    @Test func transportSeqReadsBytes4And5() {
        let hdr = DumlTransport.transportHeader(
            pktType: 0x02, payloadLen: 100, sessionId: 0x0992, seq: 0xA8B0)
        #expect(DumlTransport.transportSeq(hdr) == 0xA8B0)
        #expect(DumlTransport.PktType(rawValue: hdr[6]) == .video)
    }

    @Test func transportHeaderXorIsSelfChecking() {
        let hdr = DumlTransport.transportHeader(
            pktType: 0x00, payloadLen: 40, sessionId: 0x1234, seq: 0x5678)
        #expect(hdr.count == 8)
        #expect(hdr.reduce(0, ^) == 0)  // XOR of all 8 bytes (incl. the trailing xor) is 0
    }

    @Test func handshakePayloadStampsBaseSeq() {
        let p = DumlTransport.handshakePayload(baseSeq: 0xB887)
        #expect(p.count == 40)
        #expect(p[0] == 0x87 && p[1] == 0xB8)
        #expect(Array(p[2..<8]) == [0x64, 0x00, 0x64, 0x00, 0xC0, 0x05])  // template survives
    }

    @Test func handshakeDatagramIsPktType00() {
        let hdr = DumlTransport.transportHeader(
            pktType: 0x00, payloadLen: 40, sessionId: 0x1234, seq: 0)
        #expect(DumlTransport.isHandshake(hdr))
        #expect(
            !DumlTransport.isHandshake(
                DumlTransport.transportHeader(
                    pktType: 0x04, payloadLen: 26, sessionId: 0x1234, seq: 0)))
    }

    /// Wire bytes for the 48-byte pktType-0x00 open (8-byte header + 40-byte payload).
    /// Matches the Osmosis / DumlTransportTests baseSeq stamp (0xB887).
    @Test func handshakeDatagramMatchesKnownGood() {
        let pkt = DumlTransport.handshakeDatagram(sessionId: 0x1234, seq: 0, baseSeq: 0xB887)
        #expect(pkt.count == 48)
        #expect(Array(pkt[0..<8]) == [0x30, 0x80, 0x34, 0x12, 0x00, 0x00, 0x00, 0x96])
        #expect(pkt[6] == 0x00)
        #expect(Array(pkt[8..<14]) == [0x87, 0xB8, 0x64, 0x00, 0x64, 0x00])
        #expect(DumlTransport.isHandshake(pkt))
        #expect(CameraSoftAP.isHandshakeAck(pkt))
    }

    @Test func ackPayloadLayout() {
        let p = DumlTransport.ackPayload(peerCursor: 0x1234, baseSeq: 0x5678)
        #expect(p.count == 26)  // 34-byte packet with the 8-byte header
        #expect(Array(p[0..<8]) == [0x34, 0x12, 0x34, 0x12, 0, 0, 0, 0])  // grp(peerCursor)
        #expect(Array(p[8..<16]) == [0x78, 0x56, 0x78, 0x56, 0, 0, 0, 0])  // grp(baseSeq)
        #expect(Array(p[16..<24]) == [0x78, 0x56, 0x78, 0x56, 0, 0, 0, 0])  // grp(baseSeq) again
        #expect(Array(p.suffix(2)) == [0, 0])
    }

    // scanFrames must find the DUML frame buried under the transport + routing wrapper.
    @Test func scanFindsWrappedFrame() {
        let packet: [UInt8] = [
            0x25, 0x80, 0x7C, 0x3A, 0x90, 0xB8, 0x05, 0xCE,  // transport
            0x88, 0xB8, 0x90, 0xB8, 0x00, 0x00, 0x00, 0x00, 0x06, 0x01, 0x00, 0x00,  // routing
            0x55, 0x11, 0x04, 0x92, 0x02, 0x01, 0x00, 0xA0, 0x40, 0x02, 0x0C, 0x01, 0x01, 0x00,
            0x01, 0xB6, 0x3B,  // DUML
        ]
        let frames = DumlTransport.scanFrames(packet)
        #expect(frames.count == 1)
        #expect(frames.first?.cmdSet == 0x02 && frames.first?.cmdId == 0x0C)
        #expect(frames.first?.payload == [0x01, 0x01, 0x00, 0x01])
    }
}
