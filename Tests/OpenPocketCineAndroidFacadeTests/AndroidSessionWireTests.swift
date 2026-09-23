import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct AndroidSessionWireTests {
    @Test func cameraMeterRoundTripsSeparatelyFromConfiguredEV() {
        var status = CameraStatus()
        status.evComp = .zero
        status.meteredEv = EvComp(thirds: -4)
        let decoded = AndroidSessionWire.status(fromJSON: AndroidSessionWire.statusJSON(status))
        #expect(decoded.evComp == .zero)
        #expect(decoded.meteredEv?.thirds == -4)
        #expect(AndroidSessionWire.status(fromJSON: "{}").meteredEv == nil)
        #expect(AndroidSessionWire.status(fromJSON: "{\"evComp\":16}").meteredEv == nil)
        #expect(AndroidSessionWire.status(fromJSON: "{\"meteredEv\":-1}").meteredEv == nil)
        #expect(AndroidSessionWire.status(fromJSON: "{\"meteredEv\":272}").meteredEv == nil)
    }

    @Test func action6ModelJSONAndApertureCommand() {
        let json = AndroidSessionWire.cameraModelJSON(modelId: 0x18, name: nil)
        #expect(json.contains("\"liveViewEnableReceiver\":65"))
        #expect(json.contains("\"sendsLiveViewPrepare\":false"))
        #expect(json.contains("\"supportsAperture\":true"))
        #expect(json.contains("\"supportsFocusMode\":false"))
        let set = AndroidSessionWire.encodeCommand(kind: .setApertureStrategy, seq: 1, extra: "3")
        #expect(set?.payload == [0x01, 0x01, 0x44, 0x00, 0x01, 0x03])
        #expect(
            AndroidSessionWire.encodeCommand(kind: .setApertureStrategy, seq: 1, extra: "9") == nil)
    }

    @Test func shutterCommandPreservesPhotoAndSupportsTimelapseStop() {
        for extra: String? in [nil, "", "1"] {
            let frame = AndroidSessionWire.encodeCommand(kind: .shootPhoto, seq: 7, extra: extra)
            #expect(frame?.cmdSet == 0x02)
            #expect(frame?.cmdId == 0x01)
            #expect(frame?.payload == [0x01])
        }
        #expect(
            AndroidSessionWire.encodeCommand(kind: .shootPhoto, seq: 7, extra: "0")?.payload == [
                0x00
            ])
        for extra in ["2", "-1", "false", "1,0"] {
            #expect(
                AndroidSessionWire.encodeCommand(kind: .shootPhoto, seq: 7, extra: extra) == nil)
        }
    }

    @Test func blockedWatchdogEnableDoesNotSpendNativeRetryBudget() {
        let handle = AndroidSessionWire.feedWatchdogCreate()
        defer { AndroidSessionWire.feedWatchdogDestroy(handle: handle) }
        func tick(_ now: Int) -> String {
            AndroidSessionWire.feedWatchdogTick(
                handle: handle,
                snapshotJSON: """
                    {"now":\(now),"live":true,"sawPicture":true,"pathReady":true,
                    "hasFormat":true,"hadVideo":true,"lastVideoPacketAge":3,
                    "lastAccessUnitAge":3,"lastDecodedFrameAge":3,"lastStatusAge":0.1}
                    """)
        }
        #expect(tick(100) == "resendLiveViewEnable")
        for _ in 0..<2 {
            #expect(
                AndroidSessionWire.feedWatchdogTick(
                    handle: handle, snapshotJSON: "{\"rollbackLastAction\":true}") == "none")
        }
        #expect(tick(101) == "resendLiveViewEnable")
        #expect(tick(106) == "reopenDatalink")
    }

    @Test
    func setExpoModeExtrasMatchIosPayload() {
        let auto = AndroidSessionWire.encodeCommand(kind: .setExpoMode, seq: 1, extra: "auto")
        let manual = AndroidSessionWire.encodeCommand(kind: .setExpoMode, seq: 1, extra: "manual")
        let rawManual = AndroidSessionWire.encodeCommand(kind: .setExpoMode, seq: 1, extra: "4")
        #expect(auto?.cmdSet == 0x02)
        #expect(auto?.cmdId == 0x1E)
        #expect(auto?.payload == [0x01, 0x00])
        #expect(manual?.payload == [0x04, 0x00])
        #expect(rawManual?.payload == [0x04, 0x00])
        #expect(auto?.payload == Commands.setExpoMode(.auto, seq: 1).payload)
        #expect(manual?.payload == Commands.setExpoMode(.manual, seq: 1).payload)
        #expect(ExpoMode.allCases.map(\.label) == ["Auto", "Manual"])
    }

    @Test
    func setWhiteBalanceAutoExtraKeepsTint() {
        let zero = AndroidSessionWire.encodeCommand(
            kind: .setWhiteBalanceAuto, seq: 1, extra: nil)
        let tint20 = AndroidSessionWire.encodeCommand(
            kind: .setWhiteBalanceAuto, seq: 1, extra: "20")
        let custom = AndroidSessionWire.encodeCommand(
            kind: .setWhiteBalanceCustom, seq: 1, extra: "4200\u{1f}20")
        #expect(zero?.cmdId == 0x2C)
        #expect(zero?.payload == [0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(tint20?.payload == [0x00, 0x00, 0x00, 0x14, 0x00])
        #expect(custom?.payload == [0x06, 0x2A, 0x00, 0x14, 0x00])
        #expect(tint20?.payload == Commands.setWhiteBalanceAuto(tint: 20, seq: 1).payload)
    }

    @Test
    func gimbalStickEncodeInvertsPanWhenAsked() {
        let front = AndroidSessionWire.gimbalStickEncode(
            x: 1, y: 0, invertPan: false, sensitivity: 4)
        let selfie = AndroidSessionWire.gimbalStickEncode(
            x: 1, y: 0, invertPan: true, sensitivity: 4)
        let selfieUp = AndroidSessionWire.gimbalStickEncode(
            x: 0, y: 1, invertPan: true, sensitivity: 4)
        #expect(front == "\(GimbalStick.center),\(GimbalStick.max)")
        #expect(selfie == "\(GimbalStick.center),\(GimbalStick.min)")
        #expect(selfieUp == "\(GimbalStick.max),\(GimbalStick.center)")
    }

    @Test
    func statusJSONRoundTripsGimbalFace() {
        var selfie = CameraStatus()
        selfie.gimbalFace = .selfie
        let selfieJSON = AndroidSessionWire.statusJSON(selfie)
        #expect(AndroidSessionWire.status(fromJSON: selfieJSON).gimbalFace == .selfie)

        var front = CameraStatus()
        front.gimbalFace = .front
        #expect(
            AndroidSessionWire.status(fromJSON: AndroidSessionWire.statusJSON(front)).gimbalFace
                == .front)

        #expect(AndroidSessionWire.status(fromJSON: "{}").gimbalFace == nil)
    }

    @Test
    func cameraModeFamilySurvivesTheAndroidStatusBoundary() {
        var payload = [UInt8](repeating: 0, count: 50)
        var status = CameraStatus()
        let reports: [(UInt8, GimbalModeFamily)] = [
            (0x24, .directionLock), (0x84, .follow), (0x44, .fpv),
        ]
        for (flags, expected) in reports {
            payload[6] = flags
            let frame = Duml.Frame(
                sender: 4, receiver: 2, seq: 1, flags: Duml.flagNotify,
                cmdSet: 4, cmdId: 5, payload: payload)
            #expect(CameraStatusDecoder.apply(frame, to: &status))
            #expect(status.gimbalModeFamily == expected)
            status = AndroidSessionWire.status(fromJSON: AndroidSessionWire.statusJSON(status))
            #expect(status.gimbalModeFamily == expected)
        }
        payload[6] = 0xC4
        let unknown = Duml.Frame(
            sender: 4, receiver: 2, seq: 2, flags: Duml.flagNotify,
            cmdSet: 4, cmdId: 5, payload: payload)
        #expect(CameraStatusDecoder.apply(unknown, to: &status))
        #expect(status.gimbalModeFamily == nil)
        #expect(AndroidSessionWire.status(fromJSON: "{}").gimbalModeFamily == nil)
    }

    @Test
    func statusJSONRoundTripsSelfieFlip() {
        var on = CameraStatus()
        on.selfieFlip = .on
        let onJSON = AndroidSessionWire.statusJSON(on)
        #expect(AndroidSessionWire.status(fromJSON: onJSON).selfieFlip == .on)

        var off = CameraStatus()
        off.selfieFlip = .off
        #expect(
            AndroidSessionWire.status(fromJSON: AndroidSessionWire.statusJSON(off)).selfieFlip
                == .off)

        #expect(AndroidSessionWire.status(fromJSON: "{}").selfieFlip == nil)
        #expect(
            AndroidSessionWire.encodeCommand(kind: .getSelfieFlip, seq: 1, extra: nil)?.payload
                == Commands.getSelfieFlip(seq: 1).payload)
    }

    @Test
    func watchdogJSONHoldsGimbalThrowGrace() {
        let json =
            "{\"now\":10,\"lastDecodedFrameAge\":4.2,\"lastVideoPacketAge\":4.2,\"lastAccessUnitAge\":4.2,\"lastStatusAge\":0.3,\"flowHealthy\":true,\"pathReady\":true,\"hasFormat\":true,\"decoderFailed\":false,\"live\":true,\"sawPicture\":true,\"tcpPokeReady\":true,\"hadVideo\":true,\"secondsSinceLastEnable\":20,\"secondsSinceGimbalThrow\":1.0}"
        #expect(
            AndroidSessionWire.feedWatchdogAction(snapshotJSON: json) == "none",
            "JNI must parse secondsSinceGimbalThrow or Android GOP-cuts mid-stick")
        let past =
            "{\"now\":10,\"lastDecodedFrameAge\":4.2,\"lastVideoPacketAge\":4.2,\"lastAccessUnitAge\":4.2,\"lastStatusAge\":0.3,\"flowHealthy\":true,\"pathReady\":true,\"hasFormat\":true,\"decoderFailed\":false,\"live\":true,\"sawPicture\":true,\"tcpPokeReady\":true,\"hadVideo\":true,\"secondsSinceLastEnable\":20,\"secondsSinceGimbalThrow\":3.1}"
        #expect(AndroidSessionWire.feedWatchdogAction(snapshotJSON: past) == "resendLiveViewEnable")
    }

    @Test
    func setVideoFormatExtraKeepsTwoArgTrailerAndOptionalSlowMoMode() {
        let unit = "\u{1f}"
        let video = AndroidSessionWire.encodeCommand(
            kind: .setVideoFormat, seq: 1, extra: "16\(unit)1")
        #expect(video?.cmdId == 0x18)
        #expect(video?.payload == [0x10, 0x01, 0x00, 0x00, 0x00])
        #expect(
            video?.payload
                == Commands.setVideoFormat(resolution: .p4K, frameRate: .fps24, seq: 1).payload)

        let slow120 = AndroidSessionWire.encodeCommand(
            kind: .setVideoFormat, seq: 1, extra: "16\(unit)7\(unit)0")
        #expect(slow120?.payload == [0x10, 0x07, 0x00, 0x04, 0x00])

        let slow200 = AndroidSessionWire.encodeCommand(
            kind: .setVideoFormat, seq: 1, extra: "16\(unit)19\(unit)0")
        #expect(slow200?.payload == [0x10, 0x13, 0x00, 0x04, 0x00])

        let slow240 = AndroidSessionWire.encodeCommand(
            kind: .setVideoFormat, seq: 1, extra: "10\(unit)8\(unit)0")
        #expect(slow240?.payload == [0x0A, 0x08, 0x00, 0x08, 0x00])

        let lowLight = AndroidSessionWire.encodeCommand(
            kind: .setVideoFormat, seq: 1, extra: "16\(unit)3\(unit)40")
        #expect(lowLight?.payload == [0x10, 0x03, 0x00, 0x00, 0x00])
    }

    @Test
    func cameraModelJSONCarriesZoomStops() {
        let pro = AndroidSessionWire.cameraModelJSON(modelId: 0x0022, name: nil)
        #expect(
            pro.contains("\"zoomStops\":[1.0,3.0,6.0,12.0]")
                || pro.contains("\"zoomStops\":[1,3,6,12]"))
        let pocket4 = AndroidSessionWire.cameraModelJSON(modelId: 0x0021, name: nil)
        #expect(
            pocket4.contains("\"zoomStops\":[1.0,2.0,4.0]")
                || pocket4.contains("\"zoomStops\":[1,2,4]"))
        let nano = AndroidSessionWire.cameraModelJSON(modelId: 0x0019, name: nil)
        #expect(nano.contains("\"zoomStops\":[1.0]") || nano.contains("\"zoomStops\":[1]"))
    }

    @Test
    func cameraModelJSONCarriesBodyCapabilities() {
        let pro = AndroidSessionWire.cameraModelJSON(modelId: 0x0022, name: nil)
        #expect(pro.contains("\"hasGimbal\":true"))
        #expect(pro.contains("\"supportsZoom\":true"))
        let nano = AndroidSessionWire.cameraModelJSON(modelId: 0x0019, name: nil)
        #expect(nano.contains("\"hasGimbal\":false"))
        #expect(nano.contains("\"supportsZoom\":false"))
    }

    @Test
    func statusJSONRoundTripsAvailableVideoFormats() {
        var status = CameraStatus()
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24),
            VideoFormat(resolution: .p1080, frameRate: .fps60),
        ]
        let json = AndroidSessionWire.statusJSON(status)
        let decoded = AndroidSessionWire.status(fromJSON: json)
        #expect(decoded.availableVideoFormats == status.availableVideoFormats)
    }

    @Test
    func cameraSoftAPHandshakeTimeoutMatchesCore() {
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON: "{\"pathReady\":true,\"rebindsUsed\":0,\"inboundDatagrams\":0}"
            )
                == CameraSoftAP.handshakeTimeoutStep(
                    pathReady: true, rebindsUsed: 0, inboundDatagrams: 0
                ).rawValue)
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON: "{\"pathReady\":true,\"rebindsUsed\":0,\"inboundDatagrams\":1}"
            ) == "keepSocket")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON: "{\"pathReady\":false,\"rebindsUsed\":0,\"inboundDatagrams\":0}"
            ) == "fail")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "handshakeTimeoutStep",
                requestJSON:
                    "{\"pathReady\":true,\"rebindsUsed\":\(CameraSoftAP.handshakeRebindLimit),\"inboundDatagrams\":0}"
            ) == "fail")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldKickAfterHandshakeTimeout",
                requestJSON: "{\"pathReady\":true}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldKickAfterHandshakeTimeout",
                requestJSON: "{\"pathReady\":false}"
            ) == "true")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldGiveUpOpenRetry",
                requestJSON: "{\"attempts\":5}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldGiveUpOpenRetry",
                requestJSON: "{\"attempts\":6}"
            ) == "true")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "canSendHandshake",
                requestJSON: "{\"receiveArmed\":false,\"connectionReady\":true}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "canSendHandshake",
                requestJSON: "{\"receiveArmed\":true,\"connectionReady\":true}"
            ) == "true")
    }

    @Test
    func cameraSoftAPFirstPictureMatchesCore() {
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":0,\"secondsSinceLastEnable\":0,\"hasPresentedPicture\":false}"
            ) == "resendEnable")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":1,\"secondsSinceLastEnable\":3,\"hasPresentedPicture\":false}"
            ) == "wait")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":1,\"secondsSinceLastEnable\":9,\"hasPresentedPicture\":false}"
            )
                == CameraSoftAP.firstPictureStep(
                    videoPackets: 0, enableSends: 1, secondsSinceLastEnable: 9
                ).rawValue)
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "firstPictureStep",
                requestJSON:
                    "{\"videoPackets\":0,\"enableSends\":1,\"secondsSinceLastEnable\":9,\"hasPresentedPicture\":true}"
            ) == "wait")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldForceEnableAfterUDPRebuild",
                requestJSON: "{\"hadVideo\":true}"
            ) == "false")
        #expect(
            AndroidSessionWire.cameraSoftAPDecision(
                kind: "shouldForceEnableAfterUDPRebuild",
                requestJSON: "{\"hadVideo\":false}"
            ) == "true")
    }
}

@Suite
struct MulticamWireTests {
    @Test func multicamCommandsEncodeCoreFrames() {
        let work = AndroidSessionWire.encodeCommand(kind: .multicamWifiWorkMode, seq: 9, extra: nil)
        #expect(work?.cmdSet == 7 && work?.cmdId == 0x39 && work?.payload == [0])
        #expect(work?.seq == 9)
        let station = AndroidSessionWire.encodeCommand(
            kind: .multicamStationMode, seq: 9, extra: "1")
        #expect(station?.cmdSet == 7 && station?.cmdId == 0x48 && station?.payload == [1])
        #expect(
            AndroidSessionWire.encodeCommand(kind: .multicamStationMode, seq: 9, extra: "0")?
                .payload == [0])
        #expect(
            AndroidSessionWire.encodeCommand(kind: .multicamStationMode, seq: 9, extra: nil) == nil)
        let video = AndroidSessionWire.encodeCommand(kind: .multicamVideoMode, seq: 9, extra: nil)
        #expect(video?.cmdSet == 2 && video?.cmdId == 0xe1 && video?.payload == [1])
        let join = AndroidSessionWire.encodeCommand(
            kind: .multicamJoin, seq: 9, extra: "Studio\u{1f}secret")
        #expect(join == (try? MulticamCommands.join(ssid: "Studio", password: "secret", seq: 9)))
        #expect(join?.cmdSet == 7 && join?.cmdId == 0x47)
        #expect(
            AndroidSessionWire.encodeCommand(kind: .multicamJoin, seq: 9, extra: "\u{1f}pw") == nil)
        #expect(
            AndroidSessionWire.encodeCommand(kind: .multicamJoin, seq: 9, extra: "Studio") == nil)
        let scan = AndroidSessionWire.encodeCommand(kind: .multicamWiFiScan, seq: 9, extra: nil)
        #expect(scan?.receiver == 0x1b && scan?.cmdSet == 7 && scan?.cmdId == 0xab)
        #expect(scan?.payload == [])
    }

    @Test func multicamDecisionKinds() {
        func decide(_ kind: String, _ json: String) -> String {
            AndroidSessionWire.multicamDecision(kind: kind, requestJSON: json)
        }
        #expect(decide("joinDecision", #"{"reply":"0000","attempt":1}"#) == "connected")
        #expect(decide("joinDecision", #"{"reply":"01ff","attempt":1}"#) == "retry")
        #expect(decide("joinDecision", #"{"reply":"01ff","attempt":3}"#) == "rejected")
        #expect(decide("joinDecision", #"{"reply":"","attempt":1}"#) == "rejected")
        #expect(
            decide("stationDecision", #"{"reply":"0001","allowMissingQuery":false}"#)
                == "alreadyStation")
        #expect(
            decide("stationDecision", #"{"reply":"0000","allowMissingQuery":false}"#)
                == "setAndVerify")
        #expect(
            decide("stationDecision", #"{"reply":"e0","allowMissingQuery":true}"#)
                == "setWithoutReadback")
        #expect(decide("stationDecision", #"{"reply":"e0","allowMissingQuery":false}"#) == "reject")
        #expect(decide("acceptsSetter", #"{"reply":"00","missingQuery":true}"#) == "true")
        #expect(decide("acceptsSetter", #"{"reply":"00","missingQuery":false}"#) == "false")
        let scan: [UInt8] =
            [1, 0x11, 0, 0, 9, 0, 0, 0, 0, 0] + Array("Cam".utf8)
            + [9, 0, 0, 0, 0, 0] + Array("Two".utf8)
        let payload = scan.map { String(format: "%02x", $0) }.joined()
        #expect(decide("wifiScanNames", "{\"payload\":\"\(payload)\"}") == "Cam\u{1f}Two")
        #expect(decide("wifiScanNames", #"{"payload":""}"#) == "")
        #expect(
            decide(
                "discoveryHosts",
                #"{"address":"192.168.1.10","mask":"255.255.255.248","excluding":"192.168.1.9, 192.168.1.11"}"#
            )
                == "192.168.1.12,192.168.1.13,192.168.1.14")
        #expect(
            decide("discoveryHosts", #"{"address":"10.0.0.2","mask":"255.255.0.0","excluding":""}"#)
                == "unsupported")
        #expect(
            decide("support", #"{"modelId":34,"name":"Osmo Pocket 4 Pro"}"#)
                == #"{"appears":true,"preview":true,"missingRoleQueryE0":false}"#)
        // JSONObject.quote escapes `/` as `\/`; the name still resolves.
        #expect(
            decide("support", #"{"name":"OsmoPocket3 \/ A"}"#)
                == #"{"appears":true,"preview":true,"missingRoleQueryE0":true}"#)
        #expect(
            decide("support", #"{"modelId":23,"name":"Osmo 360"}"#)
                == #"{"appears":true,"preview":false,"missingRoleQueryE0":false}"#)
        #expect(
            decide("support", #"{"modelId":126,"name":"DJI Neo"}"#)
                == #"{"appears":false,"preview":false,"missingRoleQueryE0":false}"#)
        #expect(
            decide("joinPolicy", "{}")
                == #"{"maximumAttempts":3,"prepareSettleSeconds":10,"replyTimeoutSeconds":45,"retryDelaySeconds":5}"#
        )
        #expect(decide("nope", "{}") == "")
    }

    @Test func multiviewRecoveryHandleRunsBoundedLadder() {
        let handle = AndroidSessionWire.multiviewRecoveryCreate()
        defer { AndroidSessionWire.multiviewRecoveryDestroy(handle: handle) }
        func call(_ op: String, _ json: String = "{}") -> String {
            AndroidSessionWire.multiviewRecoveryCall(handle: handle, op: op, snapshotJSON: json)
        }
        func firstPicture(_ now: Int) -> String {
            call(
                "action",
                """
                {"now":\(now),"live":true,"pathReady":true,"flowHealthy":true,"hadVideo":false,
                "sawPicture":false,"hasFormat":false,"secondsSinceLastEnable":50}
                """)
        }
        #expect(firstPicture(100) == "resendLiveViewEnable")
        #expect(firstPicture(110) == "reopenDatalink")
        #expect(firstPicture(120) == "none")
        #expect(firstPicture(130) == "fullSessionRejoin")
        #expect(call("failed") == "false")
        #expect(call("beginRejoin") == "true")
        #expect(call("beginRejoin") == "true")
        #expect(call("beginRejoin") == "false")
        #expect(call("failed") == "true")
        #expect(firstPicture(200) == "none")
        #expect(call("reset") == "")
        #expect(call("failed") == "false")
        #expect(call("fail") == "")
        #expect(call("failed") == "true")
        #expect(call("bogus") == "")
        AndroidSessionWire.multiviewRecoveryDestroy(handle: handle)
        #expect(call("failed") == "")
    }
}
