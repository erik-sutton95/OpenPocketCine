import Testing

@testable import OpenPocketViewCore

/// Bytes from the Action 6 survey (2026-09-21, V01.02.0521); handbook `devices/action-6/`.
@Suite struct Action6Tests {
    let action6 = CameraModel.resolve(modelId: 0x18, name: nil)

    @Test func liveEnableIsNanoReceiverWithoutGateOrPrepare() {
        #expect(CameraModel.resolve(modelId: nil, name: "OsmoAction6-AB12") == action6)
        #expect(action6.isAction6)
        #expect(action6.family == .other)
        #expect(action6.usesCapturedLiveEnable)
        #expect(action6.liveViewEnableReceiver == Commands.liveViewEnableReceiverNano)
        #expect(!action6.usesNanoLiveViewGate)
        #expect(!action6.sendsLiveViewPrepare)
        #expect(!action6.needsFirstPictureFormatPoke)
        #expect(!action6.hasGimbal)
        #expect(!action6.supportsTapFocus)
        #expect(!action6.supportsFocusMode)
        #expect(action6.supportsAperture)
        #expect(action6.zoomStops == [1])

        let pocket = CameraModel.resolve(modelId: 0x22, name: nil)
        #expect(pocket.sendsLiveViewPrepare && !pocket.supportsAperture)
        #expect(!CameraModel.resolve(modelId: 0x19, name: nil).sendsLiveViewPrepare)
        let action5 = CameraModel.resolve(modelId: 0x15, name: nil)
        #expect(!action5.usesCapturedLiveEnable && !action5.supportsAperture)
    }

    @Test func colorIsNormal10AndDLogMOnNanoBytes() {
        #expect(ColorMode.available(for: action6) == [.normal10, .dLogM])
        #expect(ColorMode.normal10.wireByte(for: action6) == 0x3F)
        #expect(ColorMode.dLogM.wireByte(for: action6) == 0x3D)
        #expect(ColorMode.fromWire(0x3F, model: action6) == .normal10)
        #expect(ColorMode.fromWire(0x3D, model: action6) == .dLogM)
        #expect(CamCapColorMode.parse([0x01, 0x03, 0x00, 0x02, 0x3F, 0x3D], model: action6) == [
            .normal10, .dLogM,
        ])
        #expect(OfficialDJILUT.auto(colorMode: .dLogM, family: .other, cameraName: action6.name)
            == .action6DLogM)
    }

    @Test func photoIs05AndTimeLapseUsesShutter() {
        #expect(ShootingMode.photo.wireByte(for: action6) == 0x05)
        let lapse = CaptureCommand.frame(mode: .timeLapse, model: action6, isRecording: false)
        #expect(lapse.cmdId == 0x01 && lapse.payload == [0x01])
        let stop = CaptureCommand.frame(mode: .timeLapse, model: action6, isRecording: true)
        #expect(stop.cmdId == 0x01 && stop.payload == [0x00])
        let hyper = CaptureCommand.frame(mode: .hyperLapse, model: action6, isRecording: false)
        #expect(hyper.cmdId == 0x02 && hyper.payload == [0x01])
    }

    @Test func favoriteMovesOnOffToByteOne() {
        let on = Commands.setMediaFavorite(
            handle: 0x0403_0201, on: true, counter: 9, model: action6)
        #expect(on.cmdId == 0xBF)
        #expect(on.payload == [
            0x01, 0x01, 0x01, 0x02, 0x03, 0x04, 0x01, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
            0x00,
        ])
        let off = Commands.setMediaFavorite(
            handle: 0x0403_0201, on: false, counter: 9, model: action6)
        #expect(off.payload[1] == 0x00 && off.payload[11] == 0x01)
        // Pocket keeps the shared layout.
        let pocket = Commands.setMediaFavorite(handle: 1, on: false, counter: 9)
        #expect(pocket.payload[1] == 0x01 && pocket.payload[11] == 0x00)
    }

    @Test func apertureKeysAreAppendedForAction6Only() {
        let keys = Commands.subscriptionKeys(for: action6)
        #expect(Array(keys.prefix(Commands.subscriptionKeys.count)) == Commands.subscriptionKeys)
        #expect(keys.suffix(2) == [ApertureStrategy.stateKey, ApertureStrategy.capabilityKey])
        #expect(
            Commands.subscriptionKeys(for: CameraModel.resolve(modelId: 0x21, name: nil))
                == Commands.subscriptionKeys)
    }

    @Test func apertureCapabilityHonorsCount() {
        #expect(ApertureStrategy.parseCapability([0x01, 0x04, 0x00, 0x03, 0x04, 0x02, 0x03]) == [
            .auto, .f28, .starburst,
        ])
        // Manual: trailing `03 04` are not choices.
        #expect(
            ApertureStrategy.parseCapability([
                0x01, 0x06, 0x00, 0x03, 0x01, 0x02, 0x03, 0x03, 0x04,
            ]) == [.f26, .f28, .starburst])
        #expect(ApertureStrategy.parseCapability([0x01, 0x04, 0x00, 0x03, 0x00, 0x02, 0x03]) == [
            .f2, .f28, .starburst,
        ])
        #expect(ApertureStrategy.parseCapability([0x01, 0x03, 0x00, 0x02, 0x02, 0x03]) == [
            .f28, .starburst,
        ])
        #expect(ApertureStrategy.parseCapability([0x01, 0x09, 0x00, 0x03]).isEmpty)
        #expect(ApertureStrategy.parseState([0x01, 0x00, 0x00, 0x04]) == .auto)
    }

    @Test func apertureFallbackFollowsExposureAndMode() {
        #expect(ApertureStrategy.fallback(expoMode: .auto, shootingMode: 1) == [
            .auto, .f28, .starburst,
        ])
        #expect(ApertureStrategy.fallback(expoMode: .manual, shootingMode: 1) == [
            .f26, .f28, .starburst,
        ])
        #expect(ApertureStrategy.fallback(expoMode: .auto, shootingMode: 0x28) == [
            .f2, .f28, .starburst,
        ])
    }

    @Test func apertureSetIsParam44() {
        let frame = ApertureStrategy.starburst.setFrame
        #expect(frame.cmdSet == 0x02 && frame.cmdId == 0x8E)
        #expect(frame.payload == [0x01, 0x01, 0x44, 0x00, 0x01, 0x03])
    }

    @Test func statusDecodesStrategyAndIris() {
        var expo = [UInt8](repeating: 0, count: 23)
        expo[7] = 0x01
        expo[13] = 0x22  // 290 = f/2.9
        expo[14] = 0x01
        var status = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: expo), to: &status,
                model: action6))
        #expect(status.irisHundredths == 290)
        #expect(ApertureStrategy.fNumberLabel(hundredths: 290) == "f/2.9")

        var pocket = CameraStatus()
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: "cam_expo_param", value: expo), to: &pocket,
            model: CameraModel.resolve(modelId: 0x22, name: nil))
        #expect(pocket.irisHundredths == nil)

        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: ApertureStrategy.stateKey, value: [1, 0, 0, 2]),
                to: &status, model: action6))
        #expect(status.apertureStrategy == .f28)
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(
                    name: ApertureStrategy.capabilityKey, value: [1, 4, 0, 3, 4, 2, 3]),
                to: &status, model: action6))
        #expect(status.availableApertureStrategies == [.auto, .f28, .starburst])
    }
}
