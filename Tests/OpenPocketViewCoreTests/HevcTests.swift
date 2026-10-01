import Testing

@testable import OpenPocketViewCore

private func hex(_ s: String) -> [UInt8] {
    var out = [UInt8]()
    var i = s.startIndex
    while i < s.endIndex {
        let j = s.index(i, offsetBy: 2)
        out.append(UInt8(s[i..<j], radix: 16)!)
        i = j
    }
    return out
}

// Generic HEVC/AVC NAL math is tested in OpenCineCore (OpenCineMediaTests). These cover DJI framing.
@Suite struct HevcTests {
    @Test func stripsDjiFrameMarker() {
        let marker: [UInt8] = [0, 0, 1, 0xff] + [UInt8](repeating: 0, count: 13)  // NAL type 63
        let slice: [UInt8] = [0, 0, 1, 0x02, 0xAA, 0xBB]  // TRAIL_R (type 1)
        #expect(Hevc.stripDjiMarker(marker + slice) == slice)
    }

    // The enable command, byte-checked against the captured frame.
    @Test func liveViewEnableFrame() throws {
        let bytes = Duml.encode(Commands.liveViewEnable(seq: 0xE06E))
        let f = try #require(DumlTransport.scanFrames(bytes).first)
        #expect(f.receiver == 0x08 && f.cmdSet == 0x09 && f.cmdId == 0xA8)
        #expect(f.payload == [0x00, 0x04, 0x02, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func liveViewPrepareIsTapFocusHint() throws {
        let prepare = Commands.liveViewPrepare()
        let hint = Commands.tapFocusLiveHint()
        #expect(prepare.cmdSet == 0x02 && prepare.cmdId == 0x68)
        #expect(prepare.payload == [0x08])
        #expect(prepare.receiver == hint.receiver)
        #expect(prepare.payload == hint.payload)
        #expect(CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: false))
        #expect(!CameraSoftAP.shouldSendLiveViewPrepare(usesNanoLiveViewGate: true))
    }

    @Test func nanoLiveViewEnableUsesCapturedReceiver() throws {
        let f = Commands.liveViewEnable(seq: 0, receiver: Commands.liveViewEnableReceiverNano)
        #expect(f.receiver == 0x41)
        #expect(f.cmdSet == 0x09 && f.cmdId == 0xA8)
        #expect(f.payload == [0x00, 0x04, 0x02, 0, 0, 0, 0, 0, 0, 0])
        let start = Commands.nanoLiveViewGate(start: true)
        #expect(start.receiver == Duml.rxCamera)
        #expect(start.cmdSet == 0x02 && start.cmdId == 0x09)
        #expect(start.payload == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x03])
        #expect(Commands.nanoLiveViewGate(start: false).payload.last == 0x04)
        let nano = CameraModel.resolve(modelId: 0x19, name: nil)
        #expect(nano.liveViewEnableReceiver == 0x41)
        #expect(nano.usesNanoLiveViewGate)
        #expect(CameraModel.resolve(modelId: 0x22, name: nil).liveViewEnableReceiver == 0x08)
        #expect(!CameraModel.resolve(modelId: 0x22, name: nil).usesNanoLiveViewGate)
    }
}

@Suite struct AvcLiveViewTests {
    // Real Nano SPS/PPS from mimo-nano-live-20260818 (H.264 High 1280×720).
    private let nanoSPS = hex("6764001facb402802dd3501040106d0a1350")

    @Test func stripDjiMarkerKeepsAvcSps() {
        let marker: [UInt8] = [0, 0, 1, 0xff] + [UInt8](repeating: 0, count: 13)
        // 4-byte Annex-B start collapses to 3-byte — same as `Hevc.nalUnits`.
        let annex: [UInt8] = [0, 0, 0, 1] + nanoSPS
        #expect(Hevc.stripDjiMarker(marker + annex) == [0, 0, 1] + nanoSPS)
    }
}

@Suite struct HevcDepacketizerTests {
    // pos = byte18*2 + byte17>>7, so byte18 = pos/2 and byte17 high bit = pos&1.
    private func videoPacket(frame: UInt8, pos: Int, _ body: [UInt8]) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 20)
        p[6] = 0x02  // pktType = video
        p[16] = frame  // frame counter
        p[18] = UInt8(pos / 2)  // fragment pair index
        p[17] = UInt8((pos & 1) << 7)  // even/odd half
        return p + body
    }

    private let marker: [UInt8] = [0, 0, 1, 0xff] + [UInt8](repeating: 0, count: 13)
    private let slice: [UInt8] = [0, 0, 1, 0x02, 0xAA, 0xBB]

    @Test func groupsFragmentsAndEmitsStrippedAccessUnit() {
        var dp = HevcDepacketizer()
        let frame = marker + slice
        // Frame 0x10 split across two in-order fragments — nothing emitted yet.
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 0, Array(frame[0..<10]))) == nil)
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 1, Array(frame[10...]))) == nil)
        // First fragment of frame 0x11 completes frame 0x10.
        let au = dp.feed(videoPacket(frame: 0x11, pos: 0, marker))
        #expect(au == slice)  // reassembled and DJI marker stripped
    }

    @Test func dropsFrameWithMissingFragment() {
        var dp = HevcDepacketizer()
        _ = dp.feed(videoPacket(frame: 0x20, pos: 0, marker))  // ok
        _ = dp.feed(videoPacket(frame: 0x20, pos: 2, slice))  // pos 1 lost -> corrupt
        let au = dp.feed(videoPacket(frame: 0x21, pos: 0, marker))  // completes frame 0x20
        #expect(au == nil)  // dropped rather than fed to the decoder broken
        #expect(dp.droppedIncomplete == 1)
    }

    /// Capture: 108/1856 frames start at pos 128/192/320, not 0. Relative contiguity still holds.
    @Test func acceptsFrameThatDoesNotStartAtPositionZero() {
        var dp = HevcDepacketizer()
        let frame = marker + slice
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 128, Array(frame[0..<10]))) == nil)
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 129, Array(frame[10...]))) == nil)
        let au = dp.feed(videoPacket(frame: 0x11, pos: 0, marker))
        #expect(au == slice)
        #expect(dp.droppedIncomplete == 0)
    }

    @Test func frameCounterWrapDoesNotDropAContiguousFrame() {
        var dp = HevcDepacketizer()
        let frame = marker + slice
        #expect(dp.feed(videoPacket(frame: 0xFF, pos: 0, Array(frame[0..<10]))) == nil)
        #expect(dp.feed(videoPacket(frame: 0xFF, pos: 1, Array(frame[10...]))) == nil)
        let au = dp.feed(videoPacket(frame: 0x00, pos: 0, marker))
        #expect(au == slice)
        #expect(dp.droppedIncomplete == 0)
    }

    @Test func ignoresNonVideoPackets() {
        var dp = HevcDepacketizer()
        var cmd = [UInt8](repeating: 0, count: 30)
        cmd[6] = 0x05  // a command packet
        #expect(dp.feed(cmd) == nil)
    }

    @Test func reusedFrameNumberStartsANewAccessUnit() {
        var dp = HevcDepacketizer()
        let frame = marker + slice
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 0, Array(frame[0..<10]))) == nil)
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 1, Array(frame[10...]))) == nil)
        // GOP restart reuses frame 0x10 at pos 0 — close the previous AU.
        let au = dp.feed(videoPacket(frame: 0x10, pos: 0, marker + slice))
        #expect(au == slice)
        #expect(dp.droppedIncomplete == 0)
    }

    @Test func duplicateFragmentDoesNotCorruptTheAU() {
        var dp = HevcDepacketizer()
        let frame = marker + slice
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 0, Array(frame[0..<10]))) == nil)
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 0, Array(frame[0..<10]))) == nil)
        #expect(dp.feed(videoPacket(frame: 0x10, pos: 1, Array(frame[10...]))) == nil)
        let au = dp.feed(videoPacket(frame: 0x11, pos: 0, marker))
        #expect(au == slice)
        #expect(dp.droppedIncomplete == 0)
    }
}
