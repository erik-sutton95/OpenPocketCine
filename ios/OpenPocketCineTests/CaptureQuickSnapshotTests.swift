import MonitorPresentation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class CaptureQuickSnapshotTests: XCTestCase {
    func testRecordingConfirmationIsBoundToOriginalCameraState() {
        let request = RecordConfirmationContext(
            mode: 1, recording: false, locked: false, busy: false, phase: .live)
        XCTAssertTrue(request.canConfirm)
        let changedStates = [
            RecordConfirmationContext(
                mode: 0, recording: false, locked: false, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: true, locked: false, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: true, busy: false, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: false, busy: true, phase: .live),
            RecordConfirmationContext(
                mode: 1, recording: false, locked: false, busy: false, phase: .idle),
        ]
        for changed in changedStates {
            XCTAssertFalse(request == changed && changed.canConfirm)
        }
        for photo in [0x05, 0x17] {
            XCTAssertFalse(
                RecordConfirmationContext(
                    mode: photo, recording: false, locked: false, busy: false, phase: .live
                ).canConfirm)
        }
    }

    func testSourceIdentityIgnoresLiveHUDSelection() throws {
        var status = CameraStatus()
        status.expoMode = .manual
        let manual = try XCTUnwrap(CaptureQuickSnapshot.primary(.exposure, status: status))
        status.expoMode = .auto
        let automatic = try XCTUnwrap(CaptureQuickSnapshot.primary(.exposure, status: status))
        XCTAssertNotEqual(manual.selection, automatic.selection)
        XCTAssertEqual(manual.sourceIdentity, automatic.sourceIdentity)
    }

    func testStartingRecordingInvalidatesAnInFlightShootingModeAdjustment() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        let standby = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertTrue(standby.enabled)
        status.isRecording = true
        let recording = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertFalse(recording.enabled)
        XCTAssertNotEqual(standby, recording)
        XCTAssertNil(standby.changedValue(translation: -56, current: recording))
        XCTAssertNil(recording.changedValue(translation: -56, current: recording))
    }

    func testUnknownCameraValuesStayUnknownAndStationaryHoldCannotSelectTheirFallback() throws {
        var status = CameraStatus()
        status.expoMode = .auto
        let ev = try XCTUnwrap(CaptureQuickSnapshot.primary(.shutter, status: status))
        let wb = try XCTUnwrap(CaptureQuickSnapshot.primary(.wb, status: status))
        let focus = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true))
        for snapshot in [ev, wb, focus] {
            XCTAssertEqual(snapshot.selection, "")
            XCTAssertNil(
                MonitorDrumSelection.changedIndex(
                    origin: snapshot.index, translation: 0, count: snapshot.options.count))
            XCTAssertNil(
                MonitorDrumSelection.changedIndex(
                    origin: snapshot.index, translation: -3, count: snapshot.options.count))
        }
        XCTAssertEqual(ev.options[ev.index], "0.0", "A visual fallback is not camera truth")
        XCTAssertEqual(wb.options[wb.index], "Auto")
        XCTAssertEqual(focus.options[focus.index], "AF-S")
    }

    func testKnownValuesAndFocusCapabilityRemainAuthoritative() throws {
        var status = CameraStatus()
        status.expoMode = .auto
        status.evComp = .zero
        status.focusMode = .continuous
        status.whiteBalance = .auto
        XCTAssertEqual(CaptureQuickSnapshot.primary(.shutter, status: status)?.selection, "0.0")
        XCTAssertEqual(CaptureQuickSnapshot.primary(.wb, status: status)?.selection, "Auto")
        XCTAssertEqual(
            CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true)?
                .selection,
            "AF-C")
        XCTAssertNil(CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: false))
        let automatic = try XCTUnwrap(
            CaptureQuickSnapshot.primary(
                .shutter, status: status, facePriorityExposureEnabled: true))
        XCTAssertFalse(automatic.enabled)
    }

    func testHeldFocusIncludesTheSameTrackingChoicesAndNativeSelectionAsTap() throws {
        var status = CameraStatus()
        for option in FocusOption.allCases {
            status.focusMode = option.focusMode
            status.focusTrack = option.track
            let snapshot = try XCTUnwrap(
                CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true))
            XCTAssertEqual(snapshot.options, ["AF-S", "AF-C", "Showcase", "Lock", "Priority"])
            XCTAssertEqual(snapshot.selection, CaptureLists.focusOption(from: status)?.chip)
            XCTAssertEqual(snapshot.options[snapshot.index], option.chip)
        }
    }

    func testApertureTakesTheFocusSlotOnlyOnAction6() throws {
        let action6 = CameraModel.resolve(modelId: 0x0018, name: "Osmo Action 6")
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: "Osmo Pocket 4")
        var status = CameraStatus()
        status.expoMode = .manual
        let fallback = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.aperture, status: status, cameraModel: action6))
        XCTAssertEqual(fallback.options, ["f/2.6", "f/2.8", "Starburst f/4"])
        XCTAssertEqual(fallback.selection, "")
        status.availableApertureStrategies = [.auto, .f28]
        status.apertureStrategy = .f28
        let pushed = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.aperture, status: status, cameraModel: action6))
        XCTAssertEqual(pushed.options, ["Auto", "f/2.8"])
        XCTAssertEqual(pushed.selection, "f/2.8")
        XCTAssertNil(CaptureQuickSnapshot.primary(.aperture, status: status, cameraModel: pocket4))
        XCTAssertNil(CaptureQuickSnapshot.primary(.aperture, status: status))
    }

    func testPreviewOfUnknownValueOnlySelectsAfterCrossingADetentAndCanReturnToUnknown() throws {
        var status = CameraStatus()
        status.expoMode = .auto
        let snapshot = try XCTUnwrap(CaptureQuickSnapshot.primary(.shutter, status: status))
        var preview = CaptureDrumPresentation(
            id: UUID(), sheet: .shutter, snapshot: snapshot, position: Double(snapshot.index))
        XCTAssertEqual(preview.selection, "")
        for travel in [0.0, -3, -56, 0] {
            preview.position = MonitorDrumSelection.position(
                origin: snapshot.index, translation: travel, count: snapshot.options.count)
            XCTAssertEqual(preview.selection, travel == -56 ? "+0.3" : "")
            XCTAssertEqual(
                snapshot.changedValue(translation: travel, current: snapshot),
                travel == -56 ? "+0.3" : nil)
        }
        XCTAssertEqual(snapshot.selection, "", "A preview cannot become camera truth")
    }

    func testLiftRejectsAChangedSourceOrCapabilityAndUsesOnlyTheFinalDetent() throws {
        var status = CameraStatus()
        status.focusMode = .continuous
        status.focusTrack = .default
        let initial = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true))
        XCTAssertEqual(initial.changedValue(translation: -56, current: initial), "Showcase")
        XCTAssertNil(initial.changedValue(translation: 0, current: initial))

        status.focusTrack = .subjectLock
        let changed = CaptureQuickSnapshot.primary(.focus, status: status, supportsFocusMode: true)
        XCTAssertNil(initial.changedValue(translation: -56, current: changed))
        XCTAssertNil(initial.changedValue(translation: -56, current: nil))

        status.expoMode = .auto
        status.evComp = .zero
        let ev = try XCTUnwrap(CaptureQuickSnapshot.primary(.shutter, status: status))
        let automatic = CaptureQuickSnapshot.primary(
            .shutter, status: status, facePriorityExposureEnabled: true)
        XCTAssertNil(ev.changedValue(translation: -56, current: automatic))
        XCTAssertNil(automatic?.changedValue(translation: -56, current: automatic))
    }

    func testFormatColorAndModeSnapshotsMatchTheFullPickerPrimaryDrum() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps24)
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24),
            VideoFormat(resolution: .p4K, frameRate: .fps30),
            VideoFormat(resolution: .p1080, frameRate: .fps24),
        ]
        let format = try XCTUnwrap(CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertEqual(format.options, ["24p", "30p"])
        XCTAssertEqual(format.selection, "24p")
        XCTAssertEqual(format.changedValue(translation: -56, current: format), "30p")
        XCTAssertNil(format.changedValue(translation: 0, current: format))

        status.availableVideoFormats = [VideoFormat(resolution: .p4K, frameRate: .fps24)]
        let narrowed = CaptureQuickSnapshot.primary(.resolution, status: status)
        XCTAssertNil(format.changedValue(translation: -56, current: narrowed))

        status.colorMode = .normal
        status.availableColorModes = [.normal, .hdr, .dLog]
        let color = try XCTUnwrap(CaptureQuickSnapshot.primary(.color, status: status))
        XCTAssertEqual(color.options, ["Normal", "HDR", "D-Log"])
        XCTAssertEqual(color.selection, "Normal")
        XCTAssertEqual(color.changedValue(translation: -56, current: color), "HDR")

        status.availableColorModes = [.normal]
        let colorChanged = CaptureQuickSnapshot.primary(.color, status: status)
        XCTAssertNil(color.changedValue(translation: -56, current: colorChanged))

        status.shootingMode = Int(ShootingMode.video.rawValue)
        let mode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertEqual(
            mode.options, CaptureLists.operatorShootingModes(from: status).map(\.label))
        XCTAssertFalse(mode.options.contains(ShootingMode.livePhoto.label))
        XCTAssertEqual(mode.selection, "Video")
        XCTAssertNil(mode.changedValue(translation: 0, current: mode))
        XCTAssertEqual(mode.changedValue(translation: -56, current: mode), "TimeLapse")

        status.shootingMode = Int(ShootingMode.photo.rawValue)
        let photo = CaptureQuickSnapshot.primary(.mode, status: status)
        XCTAssertNil(mode.changedValue(translation: -56, current: photo))
        XCTAssertEqual(photo?.selection, "Photo")

        status.shootingMode = Int(ShootingMode.photoRawPocket3AndNano)
        let pocket3Photo = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertEqual(pocket3Photo.selection, "Photo")

        status.shootingMode = -1
        let unknown = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertEqual(unknown.selection, "")
        XCTAssertNil(unknown.changedValue(translation: 0, current: unknown))
    }

    func testPhotoHidesVideoFormatAndShutterAngle() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.photoRawPocket3AndNano)
        status.expoMode = .manual
        status.shutterDenom = 50
        status.fps = 30
        status.availableShutterDenoms = [25, 50, 60]
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24),
            VideoFormat(resolution: .p4K, frameRate: .fps30),
        ]

        let format = try XCTUnwrap(CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertEqual(format.kind, .format)
        XCTAssertEqual(format.selection, "Photo")
        XCTAssertFalse(format.enabled)
        XCTAssertTrue(format.options.isEmpty)
        XCTAssertNil(format.changedValue(translation: -56, current: format))

        let shutter = try XCTUnwrap(
            CaptureQuickSnapshot.primary(
                .shutter, status: status, shutterUsesAngle: true, shutterAngleDegrees: 180))
        XCTAssertEqual(shutter.kind, .shutter)
        XCTAssertNotEqual(shutter.kind, .angle)
        XCTAssertEqual(shutter.selection, "1/50")

        status.shootingMode = Int(ShootingMode.superNight.rawValue)
        let lowLightFormat = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertTrue(lowLightFormat.enabled)
        XCTAssertEqual(lowLightFormat.kind, .format)
        XCTAssertNotEqual(lowLightFormat.selection, "Photo")
    }

    func testLivePhotoUsesStillChromeAndHidesVideoColorAudio() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.livePhoto.rawValue)
        status.colorMode = .dLogM
        status.audioChannel = .stereo
        status.videoFormat = VideoFormat(resolution: .p4K, frameRate: .fps25)
        status.availableVideoFormats = [
            VideoFormat(resolution: .p4K, frameRate: .fps24)
        ]
        XCTAssertTrue(status.isPhoto)
        XCTAssertNil(CaptureQuickSnapshot.primary(.color, status: status))
        XCTAssertNil(CaptureQuickSnapshot.primary(.audio, status: status))
        let format = try XCTUnwrap(CaptureQuickSnapshot.primary(.resolution, status: status))
        XCTAssertEqual(format.selection, "Photo")
        XCTAssertFalse(format.enabled)
        let mode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertTrue(mode.options.contains(ShootingMode.livePhoto.label))
        XCTAssertEqual(mode.selection, ShootingMode.livePhoto.label)
        XCTAssertNil(mode.changedValue(translation: 0, current: mode))
        status.shootingMode = Int(ShootingMode.video.rawValue)
        let videoMode = try XCTUnwrap(CaptureQuickSnapshot.primary(.mode, status: status))
        XCTAssertFalse(videoMode.options.contains(ShootingMode.livePhoto.label))
    }

    func testSlowMo200UsesAdvertisedCapabilityNotInvented240() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.slowMo.rawValue)
        let tele200 = VideoFormat(resolution: .p4K, frameRate: .fps200)
        status.videoFormat = tele200
        status.availableVideoFormats = [tele200]
        let pro = CameraModel.resolve(modelId: 0x0022, name: "Osmo Pocket 4 Pro")
        let snapshot = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.resolution, status: status, cameraModel: pro))
        XCTAssertEqual(snapshot.options, ["200p"])
        XCTAssertEqual(snapshot.selection, "200p")
        XCTAssertTrue(snapshot.enabled)
        XCTAssertNil(snapshot.changedValue(translation: -56, current: snapshot))
        XCTAssertEqual(tele200.frameRate.drumLabel, "200p")
        XCTAssertEqual(VideoFrameRate(drumLabel: "200p"), .fps200)
        XCTAssertEqual(VideoFrameRate.fps(index: 0x13), 200)

        status.availableVideoFormats = []
        let empty = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.resolution, status: status, cameraModel: pro))
        XCTAssertFalse(empty.enabled)
        XCTAssertEqual(empty.options, ["200p"])
        XCTAssertNil(empty.changedValue(translation: -56, current: empty))
    }

    func testEmptyFormatTableIsReadOnlyCurrentPairOnUnsurveyedBodies() throws {
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.slowMo.rawValue)
        status.videoFormat = VideoFormat(resolution: .p1080, frameRate: .fps240)
        status.availableVideoFormats = []
        let pro = CameraModel.resolve(modelId: 0x0022, name: "Osmo Pocket 4 Pro")
        let snapshot = try XCTUnwrap(
            CaptureQuickSnapshot.primary(.resolution, status: status, cameraModel: pro))
        XCTAssertFalse(snapshot.enabled)
        XCTAssertEqual(snapshot.options, ["240p"])
        XCTAssertEqual(snapshot.selection, "240p")
        XCTAssertNil(snapshot.changedValue(translation: -56, current: snapshot))
    }

    func testPhotoFormatTapOpensModeInsteadOfResolution() {
        XCTAssertEqual(CaptureReadoutAdmission.opening(.resolution, isPhoto: true), .mode)
        XCTAssertEqual(CaptureReadoutAdmission.opening(.resolution, isPhoto: false), .resolution)
        XCTAssertEqual(CaptureReadoutAdmission.opening(.color, isPhoto: true), .mode)
        XCTAssertEqual(CaptureReadoutAdmission.opening(.audio, isPhoto: true), .audio)
        XCTAssertEqual(CaptureReadoutAdmission.opening(.mode, isPhoto: true), .mode)
        XCTAssertEqual(CaptureReadoutAdmission.retained(.color, isPhoto: true), .mode)
        XCTAssertEqual(CaptureReadoutAdmission.retained(.resolution, isPhoto: true), .mode)
        XCTAssertNil(CaptureReadoutAdmission.retained(.audio, isPhoto: true))
        XCTAssertEqual(CaptureReadoutAdmission.retained(.iso, isPhoto: true), .iso)
        XCTAssertNil(CaptureReadoutAdmission.retainedDrum(.color, isPhoto: true))
        XCTAssertEqual(CaptureReadoutAdmission.retained(.color, isPhoto: false), .color)
    }

    func testTopFullPickerSwitchesDirectlyToLowerControlAndViceVersa() {
        XCTAssertTrue(
            CaptureReadoutAdmission.canBegin(
                locked: false, sessionLocked: false, sceneActive: true, operatorPanel: false))
        XCTAssertFalse(
            CaptureReadoutAdmission.canBegin(
                locked: true, sessionLocked: false, sceneActive: true, operatorPanel: false))
        XCTAssertTrue(CaptureReadoutAdmission.canCommit(canBegin: true, captureSheet: nil))
        XCTAssertFalse(
            CaptureReadoutAdmission.canCommit(canBegin: true, captureSheet: .resolution),
            "A delayed SET cannot outlive a still-open persistent picker")
        XCTAssertEqual(CaptureReadoutAdmission.replacing(nil, with: .resolution), .resolution)
        XCTAssertEqual(
            CaptureReadoutAdmission.replacing(.resolution, with: .iso), .iso,
            "FORMAT details yield to a lower ISO tap")
        XCTAssertEqual(
            CaptureReadoutAdmission.replacing(.iso, with: .color), .color,
            "A lower picker yields to a top COLOR tap")
        XCTAssertNil(CaptureReadoutAdmission.replacing(.iso, with: .iso))
        XCTAssertFalse(
            CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: .resolution, drum: nil))
        XCTAssertFalse(
            CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: nil, drum: .color))
        XCTAssertTrue(CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: .iso, drum: nil))
        XCTAssertTrue(CaptureReadoutAdmission.hidesLowerCaptureValues(sheet: nil, drum: .wb))
    }

    func testShutterReadoutUsesLiveDenomWhenPreferredAngleDoesNotMap() {
        var status = CameraStatus()
        status.expoMode = .manual
        status.fps = 24
        status.shutterDenom = 48
        status.availableShutterDenoms = [24, 48, 50, 60, 120]
        XCTAssertEqual(
            CaptureQuickSnapshot.shutterReadout(
                status: status, shutterUsesAngle: true, shutterAngleDegrees: 180),
            "180°")
        status.shutterDenom = 120
        XCTAssertEqual(
            CaptureQuickSnapshot.shutterReadout(
                status: status, shutterUsesAngle: true, shutterAngleDegrees: 180),
            "72°",
            "HUD must not keep painting saved 180° after a 1/N step")
        let next = CamCapShutter.steppedDenom(
            from: 48, steps: -1, available: [16_000, 120, 60, 50, 48, 24])
        XCTAssertEqual(next, 50)
        let synced = CaptureQuickSnapshot.persistPreferredAngle(
            afterDenom: 50, fps: 24, usesAngle: true, isPhoto: false, expoIsAuto: false)
        XCTAssertEqual(synced, 172)
        status.shutterDenom = 50
        XCTAssertEqual(
            CaptureQuickSnapshot.shutterReadout(
                status: status, shutterUsesAngle: true, shutterAngleDegrees: synced ?? 180),
            "172°")
        status.shootingMode = Int(ShootingMode.photoRawPocket3AndNano)
        XCTAssertEqual(
            CaptureQuickSnapshot.shutterReadout(
                status: status, shutterUsesAngle: true, shutterAngleDegrees: 180),
            "1/50")
        XCTAssertNil(
            CaptureQuickSnapshot.persistPreferredAngle(
                afterDenom: 50, fps: 24, usesAngle: true, isPhoto: true, expoIsAuto: false))
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.expoMode = .auto
        status.evComp = .zero
        XCTAssertEqual(
            CaptureQuickSnapshot.shutterReadout(
                status: status, shutterUsesAngle: true, shutterAngleDegrees: 180),
            "0.0")
        XCTAssertNil(
            CaptureQuickSnapshot.persistPreferredAngle(
                afterDenom: 50, fps: 24, usesAngle: true, isPhoto: false, expoIsAuto: true))
    }
}
