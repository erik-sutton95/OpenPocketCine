import Testing

@testable import OpenPocketViewCore

@Suite struct BleAdvertTests {
    // The real Osmo Pocket 4 Pro advert (new format): productType 0x00da = 218 -> model 0x22.
    @Test func pocket4ProNewFormat() {
        let payload: [UInt8] = [
            0x00, 0x00, 0x00, 0xEE, 0x00, 0x04, 0xBD, 0x6E, 0x56, 0x20, 0xDA, 0x00, 0x00, 0x10,
        ]
        let d = BleAdvert.decode(payload)
        #expect(d.modelId == 0x22)
        #expect(d.newFormat == true)
        #expect(d.rawProductType == 218)
    }

    // Classic format: model id in bytes [0:2], new-format flag (byte5 bit2) clear.
    @Test func classicPocket4() {
        let payload: [UInt8] = [0x21, 0x00, 0x00, 0x58, 0xB8, 0x00, 0x11, 0x22, 0x33, 0x44]
        let d = BleAdvert.decode(payload)
        #expect(d.modelId == 0x21)
        #expect(d.newFormat == false)
    }

    @Test func emptyIsNil() {
        #expect(BleAdvert.modelId([]) == nil)
        #expect(BleAdvert.modelId([0x00, 0x00]) == nil)  // zero is not a model
    }

    @Test func modelResolvesToPocket() {
        #expect(CameraModel.resolve(modelId: 0x22, name: nil).name == "Osmo Pocket 4 Pro")
        #expect(CameraModel.resolve(modelId: 0x22, name: nil).datalinkPort == 9004)
        // Pocket 3 sends no manufacturer data -> resolves by name.
        #expect(CameraModel.resolve(modelId: nil, name: "OsmoPocket3-A1B2").name == "Osmo Pocket 3")
        // "pocket4p" must win over "pocket4".
        #expect(
            CameraModel.resolve(modelId: nil, name: "OsmoPocket4P-AAAA").name == "Osmo Pocket 4 Pro"
        )
        let nano = CameraModel.resolve(modelId: 0x19, name: nil)
        #expect(nano.name == "Osmo Nano")
        #expect(nano.family == .nano)
        #expect(nano.usesCapturedLiveEnable)
        #expect(!nano.supportsTapFocus)
        #expect(!nano.supportsFocusMode)
        #expect(CameraModel.resolve(modelId: 0x22, name: nil).supportsTapFocus)
        #expect(CameraModel.resolve(modelId: 0x22, name: nil).supportsFocusMode)
        #expect(CameraModel.resolve(modelId: 0x22, name: nil).usesCapturedLiveEnable)
        #expect(CameraModel.default.usesCapturedLiveEnable)
        #expect(!CameraModel.resolve(modelId: 0x15, name: nil).usesCapturedLiveEnable)
    }
}

@Suite struct CommandsTests {
    @Test func pairingFrameMatchesKnownBytes() {
        let f = Duml.encode(Commands.setPairingPin(pin: "osmo"))
        #expect(f.count == 51)
        #expect(
            Array(f.prefix(11)) == [
                0x55, 0x33, 0x04, 0xC2, 0x02, 0x07, 0x92, 0x80, 0x40, 0x07, 0x45,
            ])
    }

    @Test func sessionWakeAndKeepalive() {
        #expect(Commands.sessionWake().payload == [0x04, 0x00])
        #expect(Commands.sessionKeepalive().payload == [0x01, 0x01])
        #expect(Commands.sessionWake().receiver == Duml.rxSession)  // 0xF0, not the camera
        #expect(Commands.session5310().receiver == Duml.rx1C)  // 0x1C
    }

    // Subscription payload sizes verified against Osmosis captures: fov 29, base 30, video_format 38.
    @Test func subscriptionPayloadSizes() {
        #expect(Commands.subscriptionPayload("camcap_fov", 0x69DF).count == 29)
        #expect(Commands.subscriptionPayload("camcap_base", 0x69DF).count == 30)
        #expect(Commands.subscriptionPayload("camcap_video_format", 0x69DF).count == 38)
        // Layout spot-check: header, subId LE, innerLen = nameLen + 6.
        let p = Commands.subscriptionPayload("camcap_fov", 0x69DF)
        #expect(Array(p[0..<4]) == [0x02, 0x02, 0x00, 0x00])
        #expect(Array(p[4..<8]) == [0xDF, 0x69, 0x00, 0x00])
        #expect(p[11] == UInt8(10 + 6))  // innerLen low byte
    }

    @Test func deviceInfoIsSixtyTwoBytes() {
        let f = Commands.appDeviceInfo(seq: 0xA000)
        #expect(f.payload.count == 62)
        #expect(Array(f.payload[0..<4]) == [0x00, 0x41, 0x50, 0x50])  // \0 A P P
        #expect(f.payload[41] == 0x02 && f.payload[50] == 0x02 && f.payload[51] == 0x08)
        #expect(f.flags == 0x80)  // cmdType 4
        #expect(f.receiver == (2 << 5) | 0x08)  // DM368 id 2
    }

    /// Osmosis §11/12/13a/14 — App → Camera `0x01`, flags `0x40`.
    @Test func cameraControlFrames() {
        let rec = Commands.recordStart()
        #expect(rec.receiver == Duml.rxCamera)
        #expect(rec.flags == Duml.flagRequest)
        #expect(rec.cmdSet == 0x02 && rec.cmdId == 0x02)
        #expect(rec.payload == [0x01])
        #expect(Commands.recordStop().payload == [0x00])
        #expect(Commands.shootPhoto().cmdId == 0x01)
        #expect(Commands.shootPhoto().payload == [0x01])

        let mode = Commands.setShootingMode(.photo)
        #expect(mode.cmdId == 0xE1)
        #expect(mode.payload == [0x17])  // Pocket 4; Nano 0x05 answers 0xEE
        let tap = Commands.tapFocusPoint(0.511, 0.498)
        #expect(tap.cmdId == 0x30)
        #expect(tap.payload.count == 21)
        let burst = Commands.tapFocus(0.511, 0.498)
        #expect(burst.map(\.cmdId) == [0x22, 0x30, 0x68, 0x32])
        #expect(burst[0].payload == [0x02])
        #expect(burst[2].payload == [0x08])
        #expect(Commands.tapFocusPrepare().cmdId == 0x22)
        #expect(Commands.tapFocusLiveHint().cmdId == 0x68)
        #expect(Commands.tapFocusLiveHint().payload == [0x08])
        #expect(Commands.liveViewPrepare().cmdId == 0x68)
        #expect(Commands.liveViewPrepare().payload == [0x08])
        #expect(
            Commands.setShutter(denom: 40).payload == [0x01, 0x28, 0x80, 0x00, 0x00, 0x00, 0x40])
        #expect(Commands.setExpoMode(.manual).cmdId == 0x1E)
        #expect(Commands.setExpoMode(.manual).payload == [0x04, 0x00])
        #expect(Commands.setExpoMode(.auto).payload == [0x01, 0x00])
        #expect(ExpoMode.allCases.map(\.label) == ["Auto", "Manual"])
        #expect(ExpoMode.auto.setPayload == [0x01, 0x00])
        #expect(ExpoMode.manual.setPayload == [0x04, 0x00])
        #expect(Commands.setExpoManual(true).payload == [0x04, 0x00])
        #expect(Commands.setExpoManual(false).payload == [0x01, 0x00])
        // No 0x1E GET in mimo-settings-1. Unpack the status echo (`cam_expo_param` `@7`).
        var manualExpo = [UInt8](repeating: 0, count: 46)
        manualExpo[0] = 0x30
        manualExpo[1] = 0x02
        manualExpo[7] = 0x04
        #expect(ExpoMode.parseExpoParam(manualExpo) == .manual)
        var autoExpo = [UInt8](repeating: 0, count: 46)
        autoExpo[7] = 0x01
        #expect(ExpoMode.parseExpoParam(autoExpo) == .auto)
        #expect(ExpoMode.parseExpoParam([0x00]) == nil)

        let get = Commands.paramGet(.isoLimit)
        #expect(get.cmdId == 0x8E)
        #expect(get.payload == [0x00, 0x01, 0x0F, 0x00])
        #expect(Commands.getIsoLimit().payload == [0x00, 0x01, 0x0F, 0x00])
        let set = Commands.setIsoLimit(.range800)
        #expect(set.payload == [0x01, 0x01, 0x0F, 0x00, 0x01, 0x04])
        #expect(Commands.setIsoLimit(.max1600).payload == [0x01, 0x01, 0x0F, 0x00, 0x01, 0x05])
        #expect(Commands.setIsoLimit(.max6400).payload == [0x01, 0x01, 0x0F, 0x00, 0x01, 0x07])
        #expect(Commands.setIsoLimit(.max25600).payload == [0x01, 0x01, 0x0F, 0x00, 0x01, 0x09])
        #expect(Commands.setFov(.wide).payload == [0x01, 0x01, 0x09, 0x00, 0x01, 0x01])

        #expect(Commands.setEv(EvComp.zero).cmdId == 0x2E)
        #expect(Commands.setEv(EvComp.zero).payload == [0x10])
        #expect(Commands.setEv(EvComp(thirds: 1)).payload == [0x11])
        #expect(Commands.setEv(EvComp(thirds: 2)).payload == [0x12])
        #expect(Commands.setEv(EvComp(thirds: -1)).payload == [0x0F])
        #expect(Commands.setEv(EvComp(thirds: -9)).payload == [0x07])
        #expect(Commands.setEv(EvComp(thirds: 9)).payload == [0x19])
    }

    @Test func cameraReplyOracle() {
        #expect(CameraReply.parse([0x00]) == .ok)
        #expect(CameraReply.parse([0xD9]) == .wrongState)
        #expect(CameraReply.parse([0xDF]) == .badParameter)
        #expect(CameraReply.parse([0xE3]) == .badParameter)
        #expect(CameraReply.parse([0xE0]) == .unsupported)
        #expect(CameraReply.parse([0xEE]) == .badParameter)
        #expect(CameraReply.parse([0xEE]).message == "camera rejected that value")
        #expect(ShootingMode.photo.isPhoto)
        #expect(!ShootingMode.video.isPhoto)
    }
}

@Suite struct CameraStatusTests {
    // 0x0d/0x02 battery: percent @20, mV @1, dock @27, charging @32.
    @Test func batteryDecode() {
        var p = [UInt8](repeating: 0, count: 40)
        p[1] = 0x10
        p[2] = 0x0F  // mV = 0x0F10 = 3856
        p[20] = 85  // percent
        p[27] = 1  // docked
        p[32] = 1  // charging
        var s = CameraStatus()
        let handled = CameraStatusDecoder.apply(
            .init(sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x0D, cmdId: 0x02, payload: p),
            to: &s)
        #expect(handled)
        #expect(s.batteryPercent == 85)
        #expect(s.batteryMilliVolts == 3856)
        #expect(s.docked && s.charging)
    }

    // 0x02/0xdc storage: SD @6/@10; a 40-byte body also carries built-in @24/@28.
    @Test func storageDecodeTwoStores() {
        var p = [UInt8](repeating: 0, count: 40)
        func put(_ v: UInt32, _ i: Int) {
            p[i] = UInt8(v & 0xFF)
            p[i + 1] = UInt8((v >> 8) & 0xFF)
        }
        put(64000, 6)
        put(32000, 10)  // SD total/free
        put(48980, 24)
        put(1000, 28)  // built-in total/free
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x02, cmdId: 0xDC, payload: p),
                to: &s))
        #expect(s.sdTotalMb == 64000 && s.sdFreeMb == 32000)
        #expect(s.internalTotalMb == 48980)
    }

    @Test func singleStoreConfirmsNoInternal() {
        let p = [UInt8](repeating: 1, count: 22)  // 22-byte body = single store
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x02, cmdId: 0xDC, payload: p),
                to: &s))
        #expect(s.internalTotalMb == 0)  // confirmed absent, not unknown(-1)
    }

    @Test func gimbalHeartbeatSwallowed() {
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x04, cmdId: 0x05, payload: []
                ), to: &s))
    }

    // live1 idle `0x02/0x80`: @0=0x01 (not recording), @57=0x01 Video, @29 elapsed=0.
    @Test func stateInfoRecordingAndMode() {
        var p = [UInt8](repeating: 0, count: 60)
        p[0] = 0x01
        p[5] = 0x10
        p[9] = 0x08  // storage total/free (plausible MiB)
        p[57] = 0x01  // Video
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x02, cmdId: 0x80, payload: p),
                to: &s))
        #expect(!s.isRecording)
        #expect(s.shootingMode == 0x01 && s.shootingModeLabel == "Video")
        #expect(s.recordElapsedSec == 0)

        p[0] = 0x81  // bit7 = recording
        p[29] = 8  // elapsed 8 s
        #expect(
            CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x02, cmdId: 0x80, payload: p),
                to: &s))
        #expect(s.isRecording && s.recordElapsedSec == 8)
    }

    @Test func timecodePushFromMimo() {
        // `00 00 00 05 16 2f 12 00` → @3–6 = 05:22:47:18 (Mimo 2026-08-14)
        let value: [UInt8] = [0x00, 0x00, 0x00, 0x05, 0x16, 0x2F, 0x12, 0x00]
        let payload = SubscribePush.pack(name: "timecode_info", value: value)
        #expect(SubscribePush.parse(payload)?.name == "timecode_info")
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0x00, cmdId: 0x99,
                    payload: payload), to: &s))
        #expect(s.timecode == "05:22:47:18")
        #expect(s.timecodeClock == "05:22:47")
    }

    @Test func expoAndFpsPushesFromLive1() {
        var expo = [UInt8](repeating: 0, count: 46)
        expo[2] = 0x40
        expo[3] = 0x86  // 1/1600 = 0x8640 (denom | 0x8000)
        expo[5] = 0x04  // ISO index 200
        expo[13] = 0xC8
        expo[14] = 0x00  // leftover 200 — not ISO
        expo[16] = 0xC8
        expo[17] = 0x00  // ISO value 200
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.iso == 200 && s.shutterDenom == 1600 && s.isoIndex == .iso200)
        #expect(s.expoMode == nil)  // @7 == 0 — not a captured auto/manual value
        #expect(s.evComp == nil)  // @6 == 0 — outside −3.0…+3.0

        expo[6] = 0x10
        expo[7] = 0x04
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.expoMode == .manual)
        #expect(s.evComp == EvComp.zero)
        expo[6] = 0x0F
        expo[7] = 0x01
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.expoMode == .auto)
        #expect(s.evComp == EvComp(thirds: -1))
        #expect(s.evComp?.label == "\(EvComp.minusSign)0.3")

        let video: [UInt8] = [0x10, 0x02, 0x00, 0x00, 0x00, 0x02, 0x01, 0x00, 0x11, 0x01]
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_video_param_v2", value: video), to: &s))
        #expect(s.fps == 25)
        #expect(s.videoResolution == .p4K)
        #expect(s.videoFormat == VideoFormat(resolution: .p4K, frameRate: .fps25))
    }

    @Test func subscribeAckIsIgnored() {
        var s = CameraStatus()
        #expect(
            !CameraStatusDecoder.apply(
                .init(
                    sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x00, cmdId: 0x99,
                    payload: [0x00]), to: &s))
    }
}
