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

// Real parameter sets captured from the Osmo Pocket live view (captures/live1.pcap).
private let VPS = hex("40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540")
private let SPS = hex(
    "42010121600000030000030000030000030096a00280802d17aeedc9ae5d4d404040410000030001000003001908")
private let PPS = hex("4401c17312240890")

@Suite struct HevcTests {
    @Test func nalTypesOfRealParameterSets() {
        #expect(Hevc.nalType(VPS[0]) == Hevc.vps)  // 32
        #expect(Hevc.nalType(SPS[0]) == Hevc.sps)  // 33
        #expect(Hevc.nalType(PPS[0]) == Hevc.pps)  // 34
        #expect(Hevc.isKeyframeNal(Hevc.idr) && Hevc.isKeyframeNal(Hevc.vps))
        #expect(!Hevc.isKeyframeNal(1) && !Hevc.isKeyframeNal(35))
    }

    @Test func splitsRealAnnexBIntoNALs() {
        let sc: [UInt8] = [0, 0, 1]
        let stream = sc + VPS + sc + SPS + sc + PPS
        let nals = Hevc.nalUnits(stream)
        #expect(nals.count == 3)
        #expect(nals[0] == VPS && nals[1] == SPS && nals[2] == PPS)
        #expect(nals.map { Hevc.nalType($0[0]) } == [Hevc.vps, Hevc.sps, Hevc.pps])
    }

    @Test func stripsDjiFrameMarker() {
        let marker: [UInt8] = [0, 0, 1, 0xff] + [UInt8](repeating: 0, count: 13)  // NAL type 63
        let slice: [UInt8] = [0, 0, 1, 0x02, 0xAA, 0xBB]  // TRAIL_R (type 1)
        #expect(Hevc.stripDjiMarker(marker + slice) == slice)
    }

    // The enable command, byte-checked against the captured frame.
    @Test func liveViewEnableFrame() throws {
        let bytes = Duml.encode(Commands.liveViewEnable(seq: 0xE06E))
        let (f, _) = try #require(Duml.decode(bytes))
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
    private let nanoPPS = hex("68ee06f2c0")

    @Test func capturedNanoParameterSets() {
        #expect(Avc.nalType(nanoSPS[0]) == Avc.sps)
        #expect(Avc.nalType(nanoPPS[0]) == Avc.pps)
        #expect(Avc.isKeyframeNal(Avc.idr) && Avc.isKeyframeNal(Avc.sps))
        #expect(!Avc.isKeyframeNal(Avc.nonIdr) && !Avc.isKeyframeNal(Avc.aud))
    }

    @Test func detectsAvcVersusHevc() {
        let sc: [UInt8] = [0, 0, 1]
        let avc = sc + nanoSPS + sc + nanoPPS
        #expect(LiveVideo.detect(annexB: avc) == .avc)
        #expect(LiveVideo.detect(nals: Hevc.nalUnits(avc)) == .avc)
        let hevc =
            sc + hex("40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540")
        #expect(LiveVideo.detect(annexB: hevc) == .hevc)
        #expect(LiveVideo.detect(annexB: sc + [0x02, 0xAA]) == nil)
        #expect(LiveVideo.codec(ofNAL: 0x41) == nil, "AVC P-slice must not latch as HEVC VPS")
        #expect(LiveVideo.codec(ofNAL: 0x40) == .hevc)
        #expect(LiveVideo.codec(ofNAL: 0x67) == .avc)
        #expect(LiveVideo.codec(ofNAL: 0x68) == .avc)
        // Pocket IDR_N_LP first byte is 0x28 — same as AVC PPS with nal_ref_idc=1.
        // Classifying it as AVC made Android MediaCodec.configure(AVC) throw and
        // left WAITING FOR LIVE VIEW up after leftover P-frames.
        #expect(LiveVideo.codec(ofNAL: 0x28) == nil, "HEVC IDR_N_LP must not latch as AVC PPS")
        #expect(LiveVideo.detect(annexB: sc + [0x28, 0x01]) == nil)
        #expect(
            LiveVideo.detect(annexB: sc + [0x02, 0xAA] + sc + [0x46, 0x01] + sc + [0x50, 0x01])
                == nil)
        let idrThenVps =
            sc + [0x28, 0x01] + sc
            + hex("40010c01ffff21600000030000030000030000030096ac0c0000030004000003006540")
        #expect(LiveVideo.detect(annexB: idrThenVps) == .hevc)
    }

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
}
