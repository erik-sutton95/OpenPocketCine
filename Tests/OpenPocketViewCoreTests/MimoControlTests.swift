import Testing
@testable import OpenPocketViewCore

@Suite struct MimoControlTests {
    @Test func shutterPacksU16Denom() {
        #expect(Commands.setShutter(denom: 4).cmdId == 0x28)
        #expect(Commands.setShutter(denom: 4).payload == [0x01, 0x04, 0x80, 0x00, 0x00, 0x00, 0x40])
        #expect(Commands.setShutter(denom: 50).payload == [0x01, 0x32, 0x80, 0x00, 0x00, 0x00, 0x40])
        #expect(Commands.setShutter(denom: 1600).payload == [0x01, 0x40, 0x86, 0x00, 0x00, 0x00, 0x40])
        #expect(Commands.setShutter(denom: 16000).payload == [0x01, 0x80, 0xBE, 0x00, 0x00, 0x00, 0x40])
        #expect(Commands.setShutter(denom: 40).receiver == Duml.rxCamera)
        #expect(Commands.setShutter(denom: 40).flags == Duml.flagRequest)
    }

    @Test func shutterParsesExpoAt2Not16() {
        var expo = [UInt8](repeating: 0, count: 46)
        expo[2] = 0x80; expo[3] = 0xBE     // 1/16000
        expo[16] = 0xC8; expo[17] = 0x00   // ISO 200 sitting where shutter used to be read
        #expect(ExpoParam.shutterDenom(expo) == 16000)
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.shutterDenom == 16000)
        #expect(s.iso == 200)
    }

    @Test func isoIndexPackAndParse() {
        #expect(Commands.setIsoIndex(.auto).cmdId == 0x2A)
        #expect(Commands.setIsoIndex(.auto).payload == [0x00])
        #expect(Commands.setIsoIndex(.iso100).payload == [0x03])
        #expect(Commands.setIsoIndex(.iso25600).payload == [0x0B])
        #expect(IsoIndex.iso1600.isoValue == 1600)

        var expo = [UInt8](repeating: 0, count: 46)
        expo[5] = 0x0B
        expo[13] = 0xC8; expo[14] = 0x00           // 200 at the unlabeled offset
        expo[16] = 0x00; expo[17] = 0x64           // 25600
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.isoIndex == .iso25600)
        #expect(s.iso == 25600)
    }

    @Test func evCompPackAndParse() {
        #expect(Commands.setEv(EvComp.zero).cmdId == 0x2E)
        #expect(Commands.setEv(EvComp.zero).payload == [0x10])
        #expect(Commands.setEv(EvComp(rawValue: 0x11)!).payload == [0x11])
        #expect(Commands.setEv(EvComp(rawValue: 0x12)!).payload == [0x12])
        #expect(Commands.setEv(EvComp(rawValue: 0x0F)!).payload == [0x0F])
        #expect(EvComp(rawValue: 0x00) == nil)
        #expect(EvComp.allCases.count == 19)
        #expect(EvComp.allCases.first?.label == "\(EvComp.minusSign)3.0")
        #expect(EvComp.allCases.last?.label == "+3.0")
        #expect(EvComp(label: "0.0") == EvComp.zero)
        #expect(EvComp(label: "+1.0")?.thirds == 3)
        #expect(EvComp(label: "\(EvComp.minusSign)1.3")?.thirds == -4)

        var expo = [UInt8](repeating: 0, count: 46)
        expo[6] = 0x12
        expo[7] = 0x01
        #expect(ExpoParam.evComp(expo) == EvComp(thirds: 2))
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.evComp?.label == "+0.7")
        #expect(s.expoMode == .auto)
    }

    @Test func isoLimitGetReplyAndColorRanges() {
        #expect(IsoLimit.max800.rawValue == 0x04)
        #expect(IsoLimit.max1600.rawValue == 0x05)
        #expect(IsoLimit.max6400.rawValue == 0x07)
        #expect(IsoLimit.max25600.rawValue == 0x09)
        #expect(IsoLimit.max800.ceiling == 800)
        #expect(IsoLimit.max800.label(base: 400) == "400–800")
        #expect(IsoLimit.range800 == .max800)

        let reply: [UInt8] = [0x00, 0x00, 0x01, 0x0F, 0x00, 0x01, 0x07]
        #expect(CameraParam.parseGetReply(reply)?.pid == CameraParam.isoLimit.rawValue)
        #expect(CameraParam.parseGetReply(reply)?.value == 0x07)
        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: reply),
            to: &s))
        #expect(s.isoLimit == .max6400)

        let reply09: [UInt8] = [0x00, 0x00, 0x01, 0x0F, 0x00, 0x01, 0x09]
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: reply09),
            to: &s))
        #expect(s.isoLimit == .max25600)
    }

    @Test func isoLimitGetOnlyWhenAutoIsOffered() {
        #expect(IsoLimit.shouldGet(colorMode: .normal))
        #expect(IsoLimit.shouldGet(colorMode: .hdr))
        #expect(IsoLimit.shouldGet(colorMode: .dLog))
        #expect(IsoLimit.shouldGet(colorMode: nil), "color unknown — treat as Normal")
        #expect(!IsoLimit.shouldGet(colorMode: .dLog2), "D-Log2 has no Auto ceiling")
    }

    @Test func probeGetTimeoutStaysOffTheHud() {
        #expect(ControlHud.timeoutNote(name: "ISO limit GET", announce: false) == nil)
        #expect(ControlHud.timeoutNote(name: "ISO limit GET", announce: true) == "ISO limit GET timed out")
        #expect(ControlHud.timeoutNote(name: "Audio ch GET", announce: false) == nil)
    }

    @Test func controlNoteToastSitsTopCenterAndFades() {
        #expect(ControlHud.toastHoldSeconds == 2)
        #expect(ControlHud.toastOpacity < 1)
        #expect(ControlHud.toastOpacity > 0.5)
        #expect(ControlHud.toastCenterY(feedMinY: 200) == 222)
    }

    @Test func audioStateRefreshOmitsIsoLimitGet() {
        let frames = Commands.audioStateGets
        #expect(frames.map(\.cmdId) == [0x8E, 0x8E, 0xA0])
        #expect(frames[0].payload == Commands.getAudioChannel().payload)
        #expect(frames[1].payload == Commands.getVocalBoost().payload)
        #expect(frames[2].payload == Commands.audioDspGet().payload)
        #expect(!frames.contains { $0.payload == Commands.getIsoLimit().payload })
    }

    @Test func colorModePackAndParse() {
        #expect(Commands.setColorMode(.normal).cmdId == 0x42)
        #expect(Commands.setColorMode(.normal).payload == [0x3F])
        #expect(Commands.setColorMode(.hdr).payload == [0x3C])
        #expect(Commands.setColorMode(.dLog).payload == [0x17])
        #expect(Commands.setColorMode(.dLog2).payload == [0x41])
        #expect(Commands.setColorMode(.normal10).payload == [0x3D])
        #expect(Commands.setColorMode(.dLogM).payload == [0x00])

        var effect = [UInt8](repeating: 0, count: 16)
        effect[2] = 0x41
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_image_effect", value: effect), to: &s))
        #expect(s.colorMode == .dLog2)
    }

    @Test func focusModePackAndLensState() {
        #expect(Commands.setFocusMode(.single).cmdId == 0x24)
        #expect(Commands.setFocusMode(.single).payload == [0x01])
        #expect(Commands.setFocusMode(.continuous).payload == [0x02])
        #expect(FocusMode.parseLensState([0xB1]) == .single)
        #expect(FocusMode.parseLensState([0xB2]) == .continuous)

        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_lens_state", value: [0xB2]), to: &s))
        #expect(s.focusMode == .continuous)
    }

    @Test func focusTrackIsPid3B() {
        #expect(Commands.getFocusTrack().payload == [0x00, 0x01, 0x3B, 0x00])
        #expect(Commands.setFocusTrack(.default).payload == [0x01, 0x01, 0x3B, 0x00, 0x02, 0x01, 0x00])
        #expect(Commands.setFocusTrack(.productShowcase).payload == [0x01, 0x01, 0x3B, 0x00, 0x02, 0x01, 0x01])
        #expect(Commands.setFocusTrack(.subjectLock).payload == [0x01, 0x01, 0x3B, 0x00, 0x02, 0x01, 0x02])
        #expect(Commands.setFocusTrack(.registeredPriority).payload == [0x01, 0x01, 0x3B, 0x00, 0x02, 0x01, 0x03])

        let reply: [UInt8] = [0x00, 0x00, 0x01, 0x3B, 0x00, 0x02, 0x01, 0x02]
        #expect(FocusTrackMode.parseReply(reply) == .subjectLock)
        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: reply),
            to: &s))
        #expect(s.focusTrack == .subjectLock)
        #expect(
            FocusOption.resolve(mode: .continuous, track: .subjectLock) == .subjectLock)
        #expect(FocusOption.resolve(mode: .single, track: .subjectLock) == .single)
        #expect(FocusOption.resolve(mode: .continuous, track: nil) == .continuousDefault)
        #expect(FocusOption.subjectLock.chip == "Lock")
        #expect(FocusTrackMode.videoGrace == 4)
        #expect(FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 2.2))
        #expect(!FocusTrackMode.shouldHoldWatchdog(secondsSinceSet: 4))
    }

    @Test func whiteBalancePackAndParse() {
        #expect(Commands.setWhiteBalanceAuto().cmdId == 0x2C)
        #expect(Commands.setWhiteBalanceAuto().payload == [0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(Commands.setWhiteBalanceCustom(kelvin: 3000, tint: 0).payload
                == [0x06, 0x1E, 0x00, 0x00, 0x00])
        #expect(Commands.setWhiteBalanceCustom(kelvin: 2000, tint: -5).payload
                == [0x06, 0x14, 0x00, 0xFB, 0xFF])
        #expect(Commands.setWhiteBalanceCustom(kelvin: 10000, tint: 100).payload
                == [0x06, 0x64, 0x00, 0x64, 0x00])
        #expect(Commands.setWhiteBalanceCustom(kelvin: 10000, tint: -100).payload
                == [0x06, 0x64, 0x00, 0x9C, 0xFF])

        var effect = [UInt8](repeating: 0, count: 16)
        effect[2] = 0x3F
        effect[4] = 0x06
        effect[5] = 0x1E; effect[6] = 0x00
        effect[7] = 0xFB; effect[8] = 0xFF
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_image_effect", value: effect), to: &s))
        #expect(s.colorMode == .normal)
        #expect(s.whiteBalance == WhiteBalance.custom(kelvin: 3000, tint: -5))
        #expect(s.whiteBalanceKelvin == 3000)
        #expect(s.whiteBalanceTint == -5)
    }

    @Test func audioChannel8E() {
        #expect(Commands.getAudioChannel().cmdId == 0x8E)
        #expect(Commands.getAudioChannel().payload == [0x00, 0x01, 0x20, 0x00])
        #expect(Commands.setAudioChannel(.stereo).payload == [0x01, 0x01, 0x20, 0x00, 0x01, 0x02])
        #expect(Commands.setAudioChannel(.mono).payload == [0x01, 0x01, 0x20, 0x00, 0x01, 0x01])
        #expect(Commands.setAudioChannel(.spatial).payload == [0x01, 0x01, 0x20, 0x00, 0x01, 0x03])

        let reply: [UInt8] = [0x00, 0x00, 0x01, 0x20, 0x00, 0x01, 0x02]
        #expect(CameraParam.parseGetReply(reply)?.pid == CameraParam.audioChannel.rawValue)
        #expect(CameraParam.parseGetReply(reply)?.value == 0x02)
        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: reply),
            to: &s))
        #expect(s.audioChannel == .stereo)
        #expect(!CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: [0x00]),
            to: &s))
    }

    @Test func glamourIsPid39BlobNot068() throws {
        #expect(Commands.getGlamour().cmdId == 0x8E)
        #expect(Commands.getGlamour().payload == [0x00, 0x01, 0x39, 0x00])
        #expect(CameraParam.glamour.rawValue == 0x0039)
        // /tmp/mimo-glamour-20260818.pcapng pkt#442 GET reply — None / Off.
        let offReply: [UInt8] = [
            0x00, 0x00, 0x01, 0x39, 0x00, 0x3E,
            0x0F, 0x00, 0x00, 0x00, 0x01, 0x00,
            0x01, 0x00, 0x01, 0x14, 0x02, 0x00, 0x01, 0x19, 0x03, 0x00, 0x01, 0x46,
            0x04, 0x00, 0x01, 0x32, 0x05, 0x00, 0x01, 0x32, 0x06, 0x00, 0x01, 0x32,
            0x07, 0x00, 0x01, 0x00, 0x08, 0x00, 0x01, 0x00, 0x09, 0x00, 0x01, 0x00,
            0x0A, 0x00, 0x01, 0x14, 0x0B, 0x00, 0x01, 0x00, 0x0C, 0x00, 0x01, 0x00,
            0x0D, 0x00, 0x01, 0x00, 0x0E, 0x00, 0x01, 0x00,
        ]
        let off = try #require(GlamourEffect.blob(fromGetReply: offReply))
        #expect(off.count == 62)
        #expect(!GlamourEffect.isEnabled(off))
        #expect(GlamourEffect.disabled(off) == off)

        var on = off
        on[GlamourEffect.enableOffset] = 0x01
        #expect(GlamourEffect.isEnabled(on))
        #expect(GlamourEffect.disabled(on) == off)

        let set = Commands.setGlamour(on)
        #expect(set.payload.prefix(5) == [0x01, 0x01, 0x39, 0x00, 0x3E])
        #expect(Array(set.payload.dropFirst(5)) == on)

        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: offReply),
            to: &s))
        #expect(s.glamourEnabled == false)
        #expect(s.glamourBlob == off)
        #expect(CameraParam.parseGetReply(offReply) == nil)
    }

    @Test func vocalBoost8E() {
        #expect(Commands.getVocalBoost().payload == [0x00, 0x01, 0x4C, 0x00])
        #expect(Commands.setVocalBoost(.off).payload == [0x01, 0x01, 0x4C, 0x00, 0x01, 0x00])
        #expect(Commands.setVocalBoost(.on).payload == [0x01, 0x01, 0x4C, 0x00, 0x01, 0x01])

        let reply: [UInt8] = [0x00, 0x00, 0x01, 0x4C, 0x00, 0x01, 0x01]
        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0x8E, payload: reply),
            to: &s))
        #expect(s.vocalBoost == .on)
    }

    @Test func audioDspBlobPatchOnlyByte2() {
        #expect(Commands.audioDspGet().cmdId == 0xA0)
        #expect(Commands.audioDspGet().payload.isEmpty)

        var blob = [UInt8](repeating: 0, count: 26)
        blob[0] = 0xC0; blob[1] = 0x04; blob[2] = 0xDA; blob[3] = 0x05
        let reply = [0x00] + blob
        #expect(AudioDspBlob.blob(fromGetReply: reply) == blob)

        let windOn = AudioDspBlob.patchWind(blob, .on)
        #expect(windOn[2] == 0xDA)
        #expect(windOn[0] == 0xC0)   // do not rewrite @0
        #expect(Array(windOn[3...]) == Array(blob[3...]))
        var windBlob = blob
        windBlob[2] = 0x18
        #expect(AudioDspBlob.patchWind(windBlob, .on)[2] == 0x1A)

        let front = AudioDspBlob.patchDirectional(blob, .front)
        #expect(front[2] == 0x3A)
        #expect(AudioDspBlob.patchDirectional(blob, .frontAndBack)[2] == 0xBA)
        #expect(AudioDspBlob.patchDirectional(blob, .all)[2] == 0xDA)
        #expect(AudioDspBlob.patchWind(blob, .off)[2] == 0x18)

        let set = Commands.audioDspSet(windOn)
        #expect(set.cmdId == 0x9F)
        #expect(set.payload == windOn)

        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0xA0, payload: reply),
            to: &s))
        #expect(s.audioDspBlob == blob)
        #expect(s.audioDspAt2 == .directional(.all))
        #expect(s.windNR == .on)
        #expect(s.directionalAudio == .all)

        var windOnly = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(
                sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x02, cmdId: 0xA0,
                payload: [0x00] + windBlob),
            to: &windOnly))
        #expect(windOnly.windNR == .off)
        #expect(windOnly.directionalAudio == nil)
        #expect(AudioDspBlob.wind(from: 0x3A) == .on)
        #expect(AudioDspBlob.directional(from: 0x1A) == nil)
    }

    @Test func videoFormatPackAndParse() {
        #expect(Commands.setVideoFormat(resolution: .p1080, frameRate: .fps24).cmdId == 0x18)
        #expect(Commands.setVideoFormat(resolution: .p1080, frameRate: .fps24).payload
                == [0x0A, 0x01, 0x00, 0x00, 0x00])
        #expect(Commands.setVideoFormat(resolution: .p1080, frameRate: .fps60).payload
                == [0x0A, 0x06, 0x00, 0x00, 0x00])
        #expect(Commands.setVideoFormat(resolution: .p4K, frameRate: .fps24).payload
                == [0x10, 0x01, 0x00, 0x00, 0x00])
        #expect(Commands.setVideoFormat(resolution: .p4K, frameRate: .fps30).payload
                == [0x10, 0x03, 0x00, 0x00, 0x00])
        #expect(Commands.setVideoFormat(resolution: .p4K, frameRate: .fps60).payload
                == [0x10, 0x06, 0x00, 0x00, 0x00])

        let value: [UInt8] = [0x0A, 0x05, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x11, 0x01]
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_video_param_v2", value: value), to: &s))
        #expect(s.videoResolution == .p1080)
        #expect(s.fps == 50)
        #expect(s.videoFormat == VideoFormat(resolution: .p1080, frameRate: .fps50))
    }

    @Test func recAndColorDrumLabelsMatchCapture() {
        #expect(VideoResolution.allCases.map(\.label) == ["1080p", "4K"])
        #expect(VideoResolution.allCases.map(\.tabTitle) == ["1080", "4K"])
        #expect(VideoFrameRate.allCases.map(\.fps) == [24, 25, 30, 48, 50, 60])
        #expect(VideoFrameRate.allCases.map(\.drumLabel) == ["24p", "25p", "30p", "48p", "50p", "60p"])
        #expect(VideoFrameRate(drumLabel: "48p") == .fps48)
        #expect(VideoFrameRate(drumLabel: "120p") == nil)
        #expect(
            ColorMode.available(for: .pocket).map(\.label)
                == ["Normal", "HDR", "D-Log", "D-Log2"])
        #expect(
            CamCapColorMode.wheel(
                available: [.dLog2, .dLog, .hdr, .normal], family: .pocket
            ).map(\.label) == ["Normal", "HDR", "D-Log", "D-Log2"])
        #expect(
            ColorMode.available(for: .nano).map { $0.label(for: .nano) }
                == ["Normal 8-bit", "Normal 10-bit", "D-Log M 10-bit"])
        #expect(ColorMode(label: "D-Log2") == .dLog2)
        #expect(ColorMode(label: "Normal 8-bit") == .normal)
        #expect(ColorMode(label: "D-Log M 10-bit") == .dLogM)
        #expect(ColorMode(label: "N-Log") == nil)
        #expect(VideoFormat(resolution: .p4K, frameRate: .fps25).chipLabel == "4K · 25p")
        #expect(VideoFormat(resolution: .p1080, frameRate: .fps24).chipLabel == "1080p · 24p")
    }

    @Test func videoFormatOffersOnlyAcceptedPairs() {
        let expected: [(VideoResolution, VideoFrameRate, [UInt8])] = [
            (.p1080, .fps24, [0x0A, 0x01, 0x00, 0x00, 0x00]),
            (.p1080, .fps25, [0x0A, 0x02, 0x00, 0x00, 0x00]),
            (.p1080, .fps30, [0x0A, 0x03, 0x00, 0x00, 0x00]),
            (.p1080, .fps48, [0x0A, 0x04, 0x00, 0x00, 0x00]),
            (.p1080, .fps50, [0x0A, 0x05, 0x00, 0x00, 0x00]),
            (.p1080, .fps60, [0x0A, 0x06, 0x00, 0x00, 0x00]),
            (.p4K, .fps24, [0x10, 0x01, 0x00, 0x00, 0x00]),
            (.p4K, .fps25, [0x10, 0x02, 0x00, 0x00, 0x00]),
            (.p4K, .fps30, [0x10, 0x03, 0x00, 0x00, 0x00]),
            (.p4K, .fps48, [0x10, 0x04, 0x00, 0x00, 0x00]),
            (.p4K, .fps50, [0x10, 0x05, 0x00, 0x00, 0x00]),
            (.p4K, .fps60, [0x10, 0x06, 0x00, 0x00, 0x00]),
        ]
        for (res, rate, payload) in expected {
            #expect(Commands.setVideoFormat(resolution: res, frameRate: rate).payload == payload)
        }
        #expect(VideoResolution.allCases.count == 2)
        #expect(VideoFrameRate.allCases.count == 6)
    }

    @Test func timecodeAt3to6() {
        let value: [UInt8] = [0x00, 0x00, 0x00, 0x05, 0x16, 0x2F, 0x12, 0x00]
        #expect(CameraStatusDecoder.timecodeString(value) == "05:22:47:18")
        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "timecode_info", value: value), to: &s))
        #expect(s.timecode == "05:22:47:18")
        #expect(s.timecodeClock == "05:22:47")
        #expect(CameraStatus.clockDisplay(nil) == "--:--:--")
        #expect(CameraStatus.clockDisplay("01:02:03") == "01:02:03")
    }

    @Test func gimbalBuilders() {
        let flip = Commands.gimbalFlip()
        #expect(flip.cmdSet == 0x04 && flip.cmdId == 0x4C)
        #expect(flip.payload == [0xFE, 0x09])
        #expect(flip.flags == Duml.flagRequest)
        #expect(flip.receiver == (0 << 5) | 0x04)

        #expect(Commands.gimbalFollowFamily().payload == [0x02, 0x08])
        #expect(Commands.gimbalFpv().payload == [0x01, 0x08])

        let stick = Commands.gimbalStick(axis0: GimbalStick.center, axis1: GimbalStick.center)
        #expect(stick.cmdId == 0x01)
        #expect(stick.flags == Duml.flagNotify)
        #expect(stick.payload == [0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x80, 0x22, 0x00])

        #expect(GimbalStick.defaultSensitivity == 4)
        #expect(GimbalStick.sensitivityGain(4) == 1)
        #expect(GimbalStick.sensitivityGain(1) == 0.25)
        #expect(GimbalStick.clampedSensitivity(0) == 1)
        #expect(GimbalStick.clampedSensitivity(9) == 5)
        #expect(GimbalStick.encode(x: 1, y: 0, sensitivity: 4) == GimbalStick.encode(x: 1, y: 0))
        let slow = GimbalStick.encode(x: 1, y: 0, sensitivity: 1)
        #expect(slow.axis0 == GimbalStick.center)
        #expect(slow.axis1 > GimbalStick.center)
        #expect(slow.axis1 < GimbalStick.encode(x: 1, y: 0, sensitivity: 4).axis1)
        let midFour = GimbalStick.axis(0.8, sensitivity: 4)
        let midFive = GimbalStick.axis(0.8, sensitivity: 5)
        #expect(midFive > midFour)
        #expect(GimbalStick.axis(1, sensitivity: 5) == GimbalStick.max)
        #expect(GimbalStick.encode(x: 0, y: 0) == (GimbalStick.center, GimbalStick.center))
        #expect(GimbalStick.encode(x: 0.04, y: -0.04) == (GimbalStick.center, GimbalStick.center))
        #expect(GimbalStick.axis(1) == GimbalStick.max)
        #expect(GimbalStick.axis(-1) == GimbalStick.min)
        let right = GimbalStick.encode(x: 1, y: 0)
        #expect(right.axis0 == GimbalStick.center && right.axis1 == GimbalStick.max)
        let up = GimbalStick.encode(x: 0, y: 1)
        #expect(up.axis0 == GimbalStick.max && up.axis1 == GimbalStick.center)
        let down = GimbalStick.encode(x: 0, y: -1)
        #expect(down.axis0 == GimbalStick.min && down.axis1 == GimbalStick.center)
        let left = GimbalStick.encode(x: -1, y: 0)
        #expect(left.axis0 == GimbalStick.center && left.axis1 == GimbalStick.min)
        let invertedRight = GimbalStick.encode(x: 1, y: 0, invertPan: true)
        #expect(invertedRight.axis0 == GimbalStick.center && invertedRight.axis1 == GimbalStick.min)
        let invertedLeft = GimbalStick.encode(x: -1, y: 0, invertPan: true)
        #expect(invertedLeft.axis0 == GimbalStick.center && invertedLeft.axis1 == GimbalStick.max)
        let invertedUp = GimbalStick.encode(x: 0, y: 1, invertPan: true)
        #expect(invertedUp.axis0 == GimbalStick.max && invertedUp.axis1 == GimbalStick.center)
        let trackingRight = GimbalStick.encode(x: 1, y: 0, invertPan: false)
        #expect(trackingRight == right)
        let full = Commands.gimbalStick(axis0: GimbalStick.max, axis1: GimbalStick.min)
        #expect(full.payload == [0x26, 0x06, 0x00, 0x00, 0xDA, 0x01, 0x00, 0x80, 0x22, 0x00])
        #expect(GimbalStick.streamInterval == 0.04)
        #expect(Commands.gimbalRecenter().cmdSet == 0x04)
        #expect(Commands.gimbalRecenter().cmdId == 0x4C)
        #expect(Commands.gimbalRecenter().payload == [0xFE, 0x08])
        #expect(Commands.gimbalRecenter().receiver == Commands.gimbalFlip().receiver)
        #expect(Commands.gimbalRecenter().flags == Duml.flagRequest)
        #expect(Commands.gimbalInit(seq: 0).cmdSet == 0x03)
        #expect(Commands.gimbalInit(seq: 0).cmdId == 0xDA)
        #expect(GimbalStick.isTap(normalizedMagnitude: 0.05))
        #expect(!GimbalStick.isTap(normalizedMagnitude: 0.4))
        #expect(GimbalStick.isDoubleTap(secondsSincePreviousTap: 0.2))
        #expect(!GimbalStick.isDoubleTap(secondsSincePreviousTap: 0.5))
        #expect(!GimbalStick.isDoubleTap(secondsSincePreviousTap: nil))
        var seq = GimbalStick.TapSequence()
        #expect(seq.tap(at: 0) == .first)
        #expect(seq.tap(at: 0.2) == .second)
        let committed = seq.commitDouble()
        #expect(committed)
        let committedAgain = seq.commitDouble()
        #expect(!committedAgain)
        seq = GimbalStick.TapSequence()
        #expect(seq.tap(at: 0) == .first)
        #expect(seq.tap(at: 0.2) == .second)
        #expect(seq.tap(at: 0.4) == .third)
        let noCommitAfterTriple = seq.commitDouble()
        #expect(!noCommitAfterTriple)
        seq = GimbalStick.TapSequence()
        #expect(seq.tap(at: 0) == .first)
        #expect(seq.tap(at: 0.4) == .first)
        seq = GimbalStick.TapSequence()
        #expect(seq.tap(at: 0) == .first)
        #expect(seq.tap(at: 0.2) == .second)
        #expect(seq.tap(at: 0.56) == .first)
        #expect(!GimbalStick.prefersDarkChrome(luma: 0.2, previous: false))
        #expect(GimbalStick.prefersDarkChrome(luma: 0.7, previous: false))
        #expect(GimbalStick.prefersDarkChrome(luma: 0.5, previous: true))
        #expect(!GimbalStick.prefersDarkChrome(luma: 0.3, previous: true))
        #expect(!GimbalStick.prefersDarkChrome(luma: nil, previous: false))
        let feed = MonitorLayoutRegion(x: 0, y: 100, width: 400, height: 220)
        let onFeed = MonitorLayoutRegion(x: 300, y: 230, width: 88, height: 88)
        let region = GimbalStick.chromeSampleRegion(stick: onFeed, feed: feed)
        #expect(region != nil)
        #expect(abs((region?.maxX ?? 0) - 1) < 0.05)
        let parked = MonitorLayoutRegion(x: 300, y: 340, width: 88, height: 88)
        #expect(GimbalStick.chromeSampleRegion(stick: parked, feed: feed) == nil)

        #expect(Commands.gimbalParamsGet().payload == [0x01, 0x04, 0x05])
        #expect(Commands.setGimbalSpeed(.fast).payload == [0x00, 0x05, 0x01, 0x00])
        #expect(Commands.setGimbalSpeed(.defaultSpeed).payload == [0x00, 0x05, 0x01, 0x01])
        #expect(Commands.setGimbalSpeed(.slow).payload == [0x00, 0x05, 0x01, 0x02])
        #expect(Commands.setGimbalTiltLock(.unlocked).payload == [0x00, 0x04, 0x01, 0x00])
        #expect(Commands.setGimbalTiltLock(.locked).payload == [0x00, 0x04, 0x01, 0x01])

        let reply: [UInt8] = [0x00, 0x01, 0x04, 0x01, 0x01, 0x05, 0x01, 0x01]
        #expect(GimbalParamState.parseGetReply(reply)
                == GimbalParamState(tiltLock: .locked, speed: .defaultSpeed))

        var s = CameraStatus()
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0x00, cmdSet: 0x04, cmdId: 0x27,
                  payload: [0x00, 0x80, 0x40, 0x00, 0x00]), to: &s))
        #expect(s.gimbalFace == .selfie)
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0x00, cmdSet: 0x04, cmdId: 0x27,
                  payload: [0x00, 0x80, 0x00, 0x00, 0x00]), to: &s))
        #expect(s.gimbalFace == .front)
        #expect(CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x04, cmdId: 0x50, payload: reply),
            to: &s))
        #expect(s.gimbalParams?.tiltLock == .locked)
        #expect(s.gimbalParams?.speed == .defaultSpeed)
    }

    @Test func camFovParsesFactorAt0() {
        #expect(Commands.subscriptionKeys.contains("cam_fov"))
        #expect(Commands.subscriptionKeys.contains("cam_audio_status_v2"))

        let atWide: [UInt8] = [
            0x25, 0x09, 0x00, 0x00, 0x25, 0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
            0x3B, 0x3E, 0x00, 0x00, 0x01, 0xE8, 0x12, 0x00, 0x00, 0xAC, 0x0A, 0x00, 0x00,
        ]
        let at12x: [UInt8] = [
            0xFF, 0x2F, 0x00, 0x00, 0x00, 0x1B, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
            0xA8, 0x1B, 0x00, 0x00, 0x01, 0x99, 0x31, 0x00, 0x00, 0x00, 0x1C, 0x00, 0x00,
        ]
        let atDetent: [UInt8] = [
            0x98, 0x24, 0x00, 0x00, 0x95, 0x14, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00,
        ]
        #expect(CamFov.rawAt0(atWide) == 2341)
        #expect(abs((CamFov.factor(atWide) ?? 0) - 12) < 0.01)
        #expect(CamFov.rawAt0(at12x) == CamFov.rawAt1x)
        #expect(abs((CamFov.factor(at12x) ?? 0) - 1) < 0.01)
        #expect(CamFov.displayLabel(raw: CamFov.rawAt1x) == "1×")
        #expect(CamFov.displayLabel(raw: CamFov.rawAt12x) == "12×")
        #expect(abs(CamFov.factor(raw: CamFov.rawAt3x) - 3) < 0.02)
        #expect(CamFov.rawAt0(atDetent) == CamFov.rawAt3x)
        #expect(CamFov.displayLabel(factor: 2.29) == "2.3×")
        #expect(CamFov.displayLabel(factor: 5.3) == "5.3×")
        #expect(CamFov.displayLabel(factor: 5.34) == "5.3×")
        #expect(CamFov.displayLabel(factor: 5.36) == "5.4×")
        #expect(CamFov.displayLabel(factor: 2.89) == "2.9×")
        #expect(CamFov.displayLabel(factor: 2.9) == "2.9×")
        #expect(CamFov.displayLabel(factor: 2.95) == "3×")
        #expect(CamFov.nextJump(from: 2.3) == 3)
        #expect(CamFov.nextJump(from: 3) == 6)
        #expect(CamFov.nextJump(from: 6) == 12)
        #expect(CamFov.nextJump(from: 12) == 1)
        #expect(CamFov.lensPosition(for: 1) == 217)
        #expect(CamFov.lensPosition(for: 3) == 651)
        #expect(CamFov.lensPosition(for: 12) == 2604)
        #expect(CamFov.lensPosition(for: 2.2) == 477)
        #expect(CamFov.lensPosition(for: 6.7) == 1454)
        #expect(Commands.setZoomLens(217).cmdId == 0xB8)
        #expect(Commands.setZoomLens(217).payload == [0x0A, 0x4E, 0xD9, 0x00])
        #expect(Commands.setZoomLens(2604).payload == [0x0A, 0x4E, 0x2C, 0x0A])
        #expect(Commands.setZoomLens(700).payload == [0x0A, 0x4E, 0xBC, 0x02])
        #expect(Commands.setZoom(factor: 1).payload == [0x0A, 0x4E, 0xD9, 0x00])
        #expect(Commands.setZoom(factor: 12).payload == [0x0A, 0x4E, 0x2C, 0x0A])
        #expect(Commands.setZoom(factor: 2.2).payload == [0x0A, 0x4E, 0xDD, 0x01])
        #expect(Commands.setZoom(factor: 6.7).payload == [0x0A, 0x4E, 0xAE, 0x05])
        #expect(Commands.setZoomSlew(100).payload == [0x03, 0x00, 0x64, 0x00])
        #expect(Commands.setZoomSlew(300).payload == [0x03, 0x00, 0x2C, 0x01])
        #expect(Commands.setZoomSlew(CamFov.slewTele).payload == [0x03, 0x00, 0x64, 0x00])
        #expect(Commands.setZoomSlew(CamFov.slewWide).payload == [0x03, 0x00, 0x2C, 0x01])
        #expect(CamFov.slew(forJump: 1) == nil)
        #expect(CamFov.slew(forJump: 3) == nil)
        #expect(CamFov.slew(forJump: 12) == nil)
        #expect(CamFov.chipWrite(forJump: 1) == .lens(CamFov.lens1x))
        #expect(CamFov.chipWrite(forJump: 3) == .lens(CamFov.lens3x))
        #expect(CamFov.chipWrite(forJump: 6) == .lens(CamFov.lens6x))
        #expect(CamFov.chipWrite(forJump: 12) == .lens(CamFov.lens12x))
        #expect(CamFov.usesTelephoto(1) == false)
        #expect(CamFov.usesTelephoto(2.9) == false)
        #expect(CamFov.usesTelephoto(3) == true)
        #expect(CamFov.usesTelephoto(12) == true)
        #expect(CamFov.colorMode(forZoom: 1.1, current: .dLog2) == .dLog)
        #expect(CamFov.colorMode(forZoom: 2.9, current: .dLog2) == .dLog)
        #expect(CamFov.colorMode(forZoom: 3, current: .dLog2) == .dLog)
        #expect(CamFov.colorMode(forZoom: 12, current: .dLog2) == .dLog)
        #expect(CamFov.colorMode(forZoom: 1, current: .dLog2) == nil)
        #expect(CamFov.colorMode(forZoom: 3, current: .dLog) == nil)
        #expect(CamFov.colorMode(forZoom: 3, current: .normal) == nil)
        #expect(CamFov.shouldRestoreDLog2(factor: 1))
        #expect(!CamFov.shouldRestoreDLog2(factor: 2.9))
        #expect(CamFov.nextJump(from: 1) == 3)
        #expect(Commands.setZoomLens(CamFov.lens1x).payload == [0x0A, 0x4E, 0xD9, 0x00])
        #expect(Commands.setZoomSlew(CamFov.slewTele).payload == [0x03, 0x00, 0x64, 0x00])
        #expect(Commands.setZoomSlew(CamFov.slewWide).payload == [0x03, 0x00, 0x2C, 0x01])
        #expect(Commands.setZoomStop().payload == [0xFF, 0x00, 0x00, 0x00])
        #expect(CamFov.lens1x == 217)
        #expect(CamFov.lens3x == 651)
        #expect(CamFov.lens12x == 2604)
        #expect(Commands.setZoom(factor: 3).payload == [0x0A, 0x4E, 0x8B, 0x02])

        var s = CameraStatus()
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_fov", value: at12x), to: &s))
        #expect(s.zoomFactorRaw == 12_287)
        #expect(abs((s.zoomFactor ?? 0) - 1) < 0.01)
        #expect(CamFov.displayLabel(factor: s.zoomFactor ?? 0) == "1×")

        var lensBlob = [UInt8](repeating: 0, count: 16)
        lensBlob[0] = 0xB2
        lensBlob[14] = 0xD9
        lensBlob[15] = 0x00
        #expect(CamFov.lensAt14(lensBlob) == 217)
        #expect(CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_lens_state", value: lensBlob), to: &s))
        #expect(s.zoomLens == 217)
        #expect(abs((s.zoomFactor ?? 0) - 1) < 0.01)
    }

    @Test func camFovHybridReadoutSnapsTeleAndTicksTenths() {
        #expect(abs(CamFov.snapHybrid(2.89) - 2.89) < 0.001)
        #expect(CamFov.snapHybrid(2.9) == 2.9)
        #expect(CamFov.snapHybrid(2.95) == 2.95)
        #expect(CamFov.snapHybrid(3.1) == 3.1)
        #expect(CamFov.displayTenths(2.286) == 2.3)
        #expect(CamFov.displayTenths(2.9) == 2.9)
        #expect(CamFov.displayTenths(2.95) == 3)
        #expect(CamFov.displayTenths(5.34) == 5.3)
        #expect(CamFov.displayTenths(5.36) == 5.4)

        #expect(CamFov.pinchPreview(anchor: 2.3, magnification: 1) == 2.3)
        #expect(CamFov.pinchPreview(anchor: 2.3, magnification: 1.261) == 2.9)
        #expect(CamFov.pinchPreview(anchor: 1, magnification: 2.9) == 2.9)
        #expect(CamFov.pinchPreview(anchor: 1, magnification: 3) == 3)
        #expect(CamFov.pinchPreview(anchor: 2.3, magnification: 2.3) == 5.3)
        #expect(CamFov.pinchPreview(anchor: 2.3, magnification: 2.348) == 5.4)
        #expect(CamFov.pinchPreview(anchor: 3, magnification: 0.967) == 2.9)
        #expect(CamFov.pinchPreview(anchor: 3, magnification: 0.96) == 2.9)

        #expect(CamFov.readout(live: 5.36, preview: nil, fallback: 1) == 5.4)
        #expect(CamFov.readout(live: 2.29, preview: 5.3, fallback: 1) == 5.3)
        #expect(CamFov.readout(live: nil, preview: nil, fallback: 1) == 1)
        #expect(CamFov.displayLabel(factor: CamFov.readout(live: 2.29, preview: nil, fallback: 1)) == "2.3×")

        #expect(CamFov.nextJump(from: 2.89) == 3)
        #expect(CamFov.nextJump(from: 2.9) == 3)
        #expect(CamFov.nextJump(from: 5.4) == 6)
        #expect(CamFov.nextJump(from: 6) == 12)
        #expect(CamFov.chipWrite(forJump: 1) == .lens(CamFov.lens1x))
        #expect(CamFov.chipWrite(forJump: 3) == .lens(CamFov.lens3x))
        #expect(CamFov.chipWrite(forJump: 6) == .lens(CamFov.lens6x))
        #expect(CamFov.chipWrite(forJump: 12) == .lens(CamFov.lens12x))
        #expect(CamFov.lensPosition(for: 6) == 1302)
        #expect(CamFov.isJumpStop(1) && CamFov.isJumpStop(3))
        #expect(CamFov.isJumpStop(6) && CamFov.isJumpStop(12))
        #expect(!CamFov.isJumpStop(2.3) && !CamFov.isJumpStop(5.4))

        #expect(CamFov.pinchLens(for: 2.2) == 477)
        #expect(CamFov.pinchLens(for: 6.7) == 1454)
        #expect(abs(CamFov.pinchFactor(anchor: 2.3, magnification: 1.1) - 2.53) < 0.001)
        #expect(CamFov.pinchPreview(anchor: 2.3, magnification: 1.1) == 2.5)
        #expect(CamFov.pinchLens(for: 2.53) != CamFov.pinchLens(for: 2.5))
        #expect(CamFov.pinchLens(for: 2.15) != CamFov.pinchLens(for: 2.16))
        #expect(Commands.setZoom(factor: 2.2).payload.prefix(2) == [0x0A, 0x4E])
        #expect(Commands.setZoom(factor: 6.7).payload.prefix(2) == [0x0A, 0x4E])
        #expect(CamFov.pinchLens(for: 2.3) != CamFov.pinchLens(for: 6.7))
        #expect(CamFov.pinchLens(for: 2.9) != CamFov.pinchLens(for: 3))
        #expect(CamFov.matches(1, 1))
        #expect(CamFov.matches(12, 12))
        #expect(!CamFov.matches(3, 12))

        #expect(CamFov.pinchCommand(live: 2.3, preview: 3, slewing: nil) == .slider(651))
        #expect(CamFov.pinchCommand(live: 12, preview: 10.5, slewing: nil) == .slider(CamFov.pinchLens(for: 10.5)))
        #expect(CamFov.pinchCommand(live: 9.2, preview: 12, slewing: nil) == .slider(CamFov.lens12x))
        #expect(CamFov.pinchCommand(live: 6.7, preview: 5.3, slewing: nil) == .slider(CamFov.pinchLens(for: 5.3)))

        var lastLens: UInt16?
        for tenth in 10...120 {
            let factor = Double(tenth) / 10
            #expect(CamFov.displayTenths(factor) == factor)
            let lens = CamFov.pinchLens(for: factor)
            if let lastLens {
                #expect(lens > lastLens, "\(factor)× lens must advance toward 12×")
            }
            lastLens = lens
        }
    }

    @Test func recordUnchanged() {
        #expect(Commands.recordStart().payload == [0x01])
        #expect(Commands.recordStop().payload == [0x00])
        #expect(Commands.setShootingMode(.photo).payload == [0x17])
    }

    @Test func commandReplyFlagsAndOpcodeKey() {
        #expect(Duml.isCommandReply(0xC0))
        #expect(Duml.isCommandReply(0x80))
        #expect(!Duml.isCommandReply(0x40))
        #expect(!Duml.isCommandReply(0x00))
        #expect(Duml.opcodeKey(set: 0x02, cmd: 0x28) == 0x0228)
        #expect(Duml.opcodeKey(set: 0x02, cmd: 0x1E) == 0x021E)
        #expect(Duml.opcodeKey(set: 0x02, cmd: 0x2A) == 0x022A)
        #expect(Duml.opcodeKey(set: 0x02, cmd: 0x2E) == 0x022E)
        #expect(Duml.isLiveCameraControl(set: 0x02, cmd: 0x2E))
        #expect(Duml.isLiveCameraControl(set: 0x02, cmd: 0x68))
        #expect(Duml.isLiveCameraControl(set: 0x02, cmd: 0xB8))
        #expect(Duml.shouldHoldReply(set: 0x02, cmd: 0xB8))
        #expect(Duml.shouldHoldReply(set: 0x02, cmd: 0x02))
        #expect(!Duml.isLiveCameraControl(set: 0x09, cmd: 0xA8))
        #expect(Duml.hex([0x01, 0x32, 0x80, 0x00, 0x00, 0x00, 0x40]) == "01 32 80 00 00 00 40")
        #expect(Duml.hex([]) == "-")
        #expect(Commands.setIsoIndex(.iso1600).payload == [0x07])
        #expect(Commands.setExpoMode(.auto).payload == [0x01, 0x00])
        #expect(Commands.setExpoMode(.manual).payload == [0x04, 0x00])
    }

    @Test func mailboxCoalesceLastWins() {
        var box = CameraSetMailbox()
        let key = Duml.opcodeKey(set: 0x02, cmd: 0x28)
        #expect(box.offer(key: key, urgent: false, now: 0) == .launch)
        box.beginLaunch(key: key, now: 0)
        box.noteTransmit(key: key, seq: 100)
        #expect(box.offer(key: key, urgent: false, now: 0.01) == .coalescePending)
        #expect(box.offer(key: key, urgent: false, now: 0.02) == .coalescePending)
        #expect(box.decideAck(key: key, seq: 100) == .accept)
        #expect(box.pendingLaunch(key: key, now: 0.02) == .afterHold)
        #expect(box.pendingLaunch(key: key, now: 0.12) == .immediate)
        #expect(box.pendingLaunch(key: key, now: 0.12) == .none)
    }

    @Test func mailboxRateLimitsSliderAfterAck() {
        var zoom = CameraSetMailbox()
        let zoomKey = CameraSetMailbox.zoomOpcodeKey
        #expect(zoom.offer(key: zoomKey, urgent: false, now: 0) == .launch)
        zoom.beginLaunch(key: zoomKey, now: 0)
        zoom.noteTransmit(key: zoomKey, seq: 10)
        #expect(zoom.decideAck(key: zoomKey, seq: 10) == .accept)
        #expect(zoom.offer(key: zoomKey, urgent: false, now: 0.02) == .coalescePending)
        #expect(zoom.offer(key: zoomKey, urgent: true, now: 0.02) == .launch)
        #expect(zoom.offer(key: zoomKey, urgent: false, now: 0.05) == .launch)

        var shutter = CameraSetMailbox()
        let shutterKey = Duml.opcodeKey(set: 0x02, cmd: 0x28)
        #expect(shutter.offer(key: shutterKey, urgent: false, now: 0) == .launch)
        shutter.beginLaunch(key: shutterKey, now: 0)
        shutter.noteTransmit(key: shutterKey, seq: 11)
        #expect(shutter.decideAck(key: shutterKey, seq: 11) == .accept)
        #expect(shutter.offer(key: shutterKey, urgent: false, now: 0.04) == .coalescePending)
        #expect(shutter.offer(key: shutterKey, urgent: false, now: 0.1) == .launch)
    }

    /// Mimo pinch streams `0A 4E` at 20 Hz. Waiting for ACK made the lens
    /// jump only when the fingers paused (or after the 2 s SET timeout).
    @Test func mailboxPipelinesZoomWithoutAck() {
        var zoom = CameraSetMailbox()
        let key = CameraSetMailbox.zoomOpcodeKey
        #expect(CameraSetMailbox.pipelinesWhileOpen(key))
        #expect(!CameraSetMailbox.pipelinesWhileOpen(Duml.opcodeKey(set: 0x02, cmd: 0x28)))
        #expect(zoom.offer(key: key, urgent: false, now: 0) == .launch)
        zoom.beginLaunch(key: key, now: 0)
        zoom.noteTransmit(key: key, seq: 1)
        #expect(zoom.offer(key: key, urgent: false, now: 0.02) == .coalescePending)
        #expect(zoom.offer(key: key, urgent: true, now: 0.02) == .launch)
        #expect(zoom.offer(key: key, urgent: false, now: 0.05) == .launch)
        zoom.beginLaunch(key: key, now: 0.05)
        zoom.noteTransmit(key: key, seq: 2)
        #expect(zoom.decideAck(key: key, seq: 1) == .dropSuperseded)
        #expect(zoom.hasOpen(key))
        #expect(zoom.offer(key: key, urgent: false, now: 0.1) == .launch)
        zoom.beginLaunch(key: key, now: 0.1)
        zoom.noteTransmit(key: key, seq: 3)
        #expect(zoom.decideAck(key: key, seq: 2) == .dropSuperseded)
        #expect(zoom.decideAck(key: key, seq: 3) == .accept)
        #expect(!CameraSetMailbox.timeoutImpliesUplinkFailure(.waitLate, key: key))
        #expect(CameraSetMailbox.timeoutImpliesUplinkFailure(.waitLate))
    }

    @Test func mailboxAcceptsLateAckForOpenSeq() {
        var box = CameraSetMailbox()
        let key = Duml.opcodeKey(set: 0x02, cmd: 0x42)
        #expect(box.offer(key: key, urgent: true, now: 0) == .launch)
        box.beginLaunch(key: key, now: 0)
        box.noteTransmit(key: key, seq: 41_063)
        #expect(box.timeout(key: key, subscribeMatches: false) == .waitLate)
        #expect(box.decideAck(key: key, seq: 41_100) == .dropUnknown)
        #expect(box.isAwaitingLate(key))
        #expect(box.decideAck(key: key, seq: 41_063) == .acceptLate)
    }

    @Test func mailboxSubscribeMatchIsSuccess() {
        var box = CameraSetMailbox()
        let key = Duml.opcodeKey(set: 0x02, cmd: 0x28)
        #expect(box.offer(key: key, urgent: false, now: 0) == .launch)
        box.beginLaunch(key: key, now: 0)
        box.noteTransmit(key: key, seq: 7)
        #expect(box.timeout(key: key, subscribeMatches: true) == .subscribeMatches)
        #expect(box.decideAck(key: key, seq: 7) == .dropUnknown)
    }

    @Test func mailboxDropsSupersededAndFloodSeqs() {
        var box = CameraSetMailbox()
        let key = Duml.opcodeKey(set: 0x02, cmd: 0xB8)
        #expect(box.offer(key: key, urgent: false, now: 0) == .launch)
        box.beginLaunch(key: key, now: 0)
        box.noteTransmit(key: key, seq: 41_063)
        #expect(box.offer(key: key, urgent: false, now: 0.01) == .coalescePending)
        #expect(box.timeout(key: key, subscribeMatches: false) == .launchPending)
        #expect(box.pendingLaunch(key: key, now: 0.12) == .immediate)
        #expect(box.offer(key: key, urgent: false, now: 0.12) == .launch)
        box.beginLaunch(key: key, now: 0.12)
        box.noteTransmit(key: key, seq: 41_200)
        #expect(box.decideAck(key: key, seq: 41_063) == .dropSuperseded)
        #expect(box.hasOpen(key))
        #expect(box.decideAck(key: key, seq: 41_100) == .dropUnknown)
        #expect(box.hasOpen(key))
        #expect(box.decideAck(key: key, seq: 41_200) == .accept)
    }

    @Test func mailboxRetransmitSeqStaysOpen() {
        var box = CameraSetMailbox()
        let key = Duml.opcodeKey(set: 0x02, cmd: 0x2A)
        #expect(box.offer(key: key, urgent: false, now: 0) == .launch)
        box.beginLaunch(key: key, now: 0)
        box.noteTransmit(key: key, seq: 8)
        box.noteTransmit(key: key, seq: 9)
        #expect(box.decideAck(key: key, seq: 8) == .accept)
    }

    /// Rapid shutter wheel: 1/160 is superseded by 1/8. That timeout is not
    /// half-dead uplink and must not stack with a UDP tear-down.
    @Test func supersededShutterTimeoutIsNotUplinkDeath() {
        var box = CameraSetMailbox()
        let key = Duml.opcodeKey(set: 0x02, cmd: 0x28)
        #expect(box.offer(key: key, urgent: false, now: 0) == .launch)
        box.beginLaunch(key: key, now: 0)
        box.noteTransmit(key: key, seq: 160)
        #expect(box.offer(key: key, urgent: false, now: 0.01) == .coalescePending)
        let superseded = box.timeout(key: key, subscribeMatches: false)
        #expect(superseded == .launchPending)
        #expect(!CameraSetMailbox.timeoutImpliesUplinkFailure(superseded))
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: true, videoFresh: true,
            rebuildInFlight: false, secondsSinceLastRebuild: nil))

        box.beginLaunch(key: key, now: 0.12)
        box.noteTransmit(key: key, seq: 8)
        let latest = box.timeout(key: key, subscribeMatches: false)
        #expect(latest == .waitLate)
        #expect(CameraSetMailbox.timeoutImpliesUplinkFailure(latest))
        #expect(!CameraSoftAP.shouldRebuildAfterCommandTimeouts(
            timeoutsInWindow: 2, downlinkFresh: true, videoFresh: true,
            rebuildInFlight: false, secondsSinceLastRebuild: nil),
            "latest SET timed out but video is fresh — leave UDP")
    }
}
