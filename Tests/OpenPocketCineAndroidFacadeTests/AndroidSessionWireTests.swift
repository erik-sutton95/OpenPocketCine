import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct AndroidSessionWireTests {
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
    func statusJSONRoundTripsSelfieFlip() {
        var on = CameraStatus()
        on.selfieFlip = .on
        let onJSON = AndroidSessionWire.statusJSON(on)
        #expect(AndroidSessionWire.status(fromJSON: onJSON).selfieFlip == .on)

        var off = CameraStatus()
        off.selfieFlip = .off
        #expect(AndroidSessionWire.status(fromJSON: AndroidSessionWire.statusJSON(off)).selfieFlip == .off)

        #expect(AndroidSessionWire.status(fromJSON: "{}").selfieFlip == nil)
        #expect(
            AndroidSessionWire.encodeCommand(kind: .getSelfieFlip, seq: 1, extra: nil)?.payload
                == Commands.getSelfieFlip(seq: 1).payload)
    }
}
