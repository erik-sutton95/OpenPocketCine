import Testing

@testable import OpenPocketViewCore

@Suite struct ShootingModeTests {
    @Test func livePhotoStatusUsesStillControlsAndShutter() {
        var status = CameraStatus()
        status.applyShootingMode(0x4D)
        #expect(status.isPhoto)
        #expect(status.shootingModeLabel == "Live Photo")
        #expect(ShootingMode.fromStatus(0x4D) == .livePhoto)
        #expect(!ShootingMode.livePhoto.offersVideoFormat)
        let command = CaptureCommand.frame(mode: .livePhoto, model: nil, isRecording: false)
        #expect(command.cmdId == 0x01)
        #expect(command.payload == [0x01])
    }

    @Test func observed200FpsRoundTripsThroughCapabilitySelection() {
        let bytes: [UInt8] = [0x01, 0x04, 0x00, 0x01, 0x10, 0x13, 0x00]
        let formats = CamCapVideoFormat.parse(bytes)
        let expected = VideoFormat(resolution: .p4K, frameRate: .fps200)
        #expect(formats == [expected])
        #expect(expected.frameRate.fps == 200)
        #expect(expected.frameRate.label == "200")
        #expect(expected.frameRate.drumLabel == "200p")
        #expect(VideoFrameRate(drumLabel: "200p") == .fps200)
        #expect(VideoFrameRate.fromFps(200) == .fps200)
        #expect(expected.setPayload(shootingMode: .slowMo) == [0x10, 0x13, 0, 4, 0])
        #expect(expected.setPayload(shootingMode: .video) == [0x10, 0x13, 0, 0, 0])
        let pro = CameraModel.resolve(modelId: 0x0022, name: nil)
        #expect(
            CamCapVideoFormat.allowsOperatorSet(
                expected, available: formats, model: pro, shootingMode: 0))
        #expect(
            !CamCapVideoFormat.allowsOperatorSet(
                VideoFormat(resolution: .p4K, frameRate: .fps240),
                available: formats, model: pro, shootingMode: 0))
    }

    @Test func photoExcludesSuperNightLowLightVideo() {
        #expect(ShootingMode.photo.isPhoto)
        #expect(!ShootingMode.video.isPhoto)
        #expect(!ShootingMode.slowMo.isPhoto)
        #expect(!ShootingMode.timeLapse.isPhoto)
        #expect(!ShootingMode.hyperLapse.isPhoto)
        #expect(!ShootingMode.superNight.isPhoto)
        #expect(ShootingMode.superNight.offersVideoFormat)
        #expect(!ShootingMode.photo.offersVideoFormat)
    }

    @Test func reportedPhoto05NormalizesToPhoto() {
        #expect(ShootingMode.fromWire(0x05) == .photo)
        #expect(ShootingMode.fromStatus(0x05) == .photo)
        #expect(ShootingMode.fromStatus(0x17) == .photo)
        #expect(ShootingMode.fromStatus(0x28) == .superNight)
        #expect(ShootingMode.fromStatus(-1) == nil)
        var status = CameraStatus()
        status.shootingMode = 0x05
        #expect(status.isPhoto)
        #expect(status.shootingModeLabel == "Photo")
        status.shootingMode = 0x28
        #expect(!status.isPhoto)
        #expect(status.shootingModeLabel == "SuperNight")
    }

    @Test func photoSetByteIsBodySpecificAndDefaultStaysPocket4() {
        #expect(Commands.setShootingMode(.photo).payload == [0x17])
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: "Osmo Pocket 3")
        let nano = CameraModel.resolve(modelId: 0x0019, name: "Osmo Nano")
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: "Osmo Pocket 4")
        let pro = CameraModel.resolve(modelId: 0x0022, name: "Osmo Pocket 4 Pro")
        #expect(Commands.setShootingMode(.photo, model: pocket3).payload == [0x05])
        #expect(Commands.setShootingMode(.photo, model: nano).payload == [0x05])
        #expect(Commands.setShootingMode(.photo, model: pocket4).payload == [0x17])
        #expect(Commands.setShootingMode(.photo, model: pro).payload == [0x17])
        #expect(Commands.setShootingMode(.video, model: pocket3).payload == [0x01])
        #expect(ShootingMode.photo.wireByte(for: nil) == 0x17)
    }

    @Test func captureCommandRoutesPhotoVideoAndPocket3Timelapse() {
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: "Osmo Pocket 3")
        let pro = CameraModel.resolve(modelId: 0x0022, name: "Osmo Pocket 4 Pro")
        #expect(
            CaptureCommand.frame(mode: .photo, model: pocket3, isRecording: false).cmdId == 0x01)
        #expect(
            CaptureCommand.frame(mode: .photo, model: pocket3, isRecording: false).payload == [0x01]
        )
        #expect(
            CaptureCommand.frame(mode: .video, model: pocket3, isRecording: false).cmdId == 0x02)
        #expect(
            CaptureCommand.frame(mode: .video, model: pocket3, isRecording: false).payload == [0x01]
        )
        #expect(
            CaptureCommand.frame(mode: .video, model: pocket3, isRecording: true).payload == [0x00])
        #expect(
            CaptureCommand.frame(mode: .superNight, model: pocket3, isRecording: false).cmdId
                == 0x02)
        let p3lapseStart = CaptureCommand.frame(
            mode: .timeLapse, model: pocket3, isRecording: false)
        #expect(p3lapseStart.cmdId == 0x01)
        #expect(p3lapseStart.payload == [0x01])
        #expect(
            CaptureCommand.frame(mode: .timeLapse, model: pocket3, isRecording: true).payload == [
                0x00
            ])
        let proLapse = CaptureCommand.frame(mode: .timeLapse, model: pro, isRecording: false)
        #expect(proLapse.cmdId == 0x02)
        #expect(proLapse.payload == [0x01])
        #expect(Commands.shutterTrigger(start: false).payload == [0x00])
    }

    @Test func surveyedBodiesPassSlowMoTrailerContext() {
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: "Osmo Pocket 3")
        let pro = CameraModel.resolve(modelId: 0x0022, name: "Osmo Pocket 4 Pro")
        #expect(VideoFormat.formatSetMode(model: pocket3, statusMode: .slowMo) == .slowMo)
        #expect(VideoFormat.formatSetMode(model: pro, statusMode: .slowMo) == .slowMo)
        #expect(VideoFormat.formatSetMode(model: nil, statusMode: .slowMo) == nil)
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        #expect(VideoFormat.formatSetMode(model: pocket4, statusMode: .slowMo) == nil)
    }

    @Test func modeTransitionClearsStaleCapabilitiesWithoutTouchingLiveFormat() {
        var status = CameraStatus()
        status.availableVideoFormats = [VideoFormat(resolution: .p4K, frameRate: .fps25)]
        status.availableShutterDenoms = [50]
        status.availableIsoIndices = [.iso400]
        status.availableColorModes = [.normal]
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
        status.fps = 25
        status.applyShootingMode(0x01)
        #expect(status.availableVideoFormats.count == 1)
        #expect(status.shootingMode == 0x01)

        status.applyShootingMode(0x01)
        #expect(status.availableVideoFormats.count == 1)

        status.applyShootingMode(0x28)
        #expect(status.availableVideoFormats.isEmpty)
        #expect(status.availableShutterDenoms.isEmpty)
        #expect(status.availableIsoIndices.isEmpty)
        #expect(status.availableColorModes.isEmpty)
        #expect(status.videoFormat?.resolution == .p4K)
        #expect(status.fps == 25)
        #expect(status.shootingMode == 0x28)
    }

    @Test func slowMoTrailerIsModeAndRateSpecificAndDefaultApiUnchanged() {
        let fourK120 = VideoFormat(resolution: .p4K, frameRate: .fps120)
        let fourK100 = VideoFormat(resolution: .p4K, frameRate: .fps100)
        let hd240 = VideoFormat(resolution: .p1080, frameRate: .fps240)
        let fourK30 = VideoFormat(resolution: .p4K, frameRate: .fps30)
        #expect(fourK120.setPayload == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(
            Commands.setVideoFormat(resolution: .p4K, frameRate: .fps120).payload
                == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: .slowMo) == [0x10, 0x07, 0x00, 0x04, 0x00])
        #expect(fourK100.setPayload(shootingMode: .slowMo) == [0x10, 0x0A, 0x00, 0x04, 0x00])
        #expect(hd240.setPayload(shootingMode: .slowMo) == [0x0A, 0x08, 0x00, 0x08, 0x00])
        #expect(fourK30.setPayload(shootingMode: .slowMo) == [0x10, 0x03, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: .video) == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(fourK120.setPayload(shootingMode: .superNight) == [0x10, 0x07, 0x00, 0x00, 0x00])
        #expect(
            Commands.setVideoFormat(
                resolution: .p4K, frameRate: .fps120, shootingMode: .slowMo
            ).payload == [0x10, 0x07, 0x00, 0x04, 0x00])
    }
}
