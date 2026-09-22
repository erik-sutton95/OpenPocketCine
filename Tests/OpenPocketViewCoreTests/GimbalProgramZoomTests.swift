import Testing
@testable import OpenPocketViewCore

@Suite struct GimbalProgramZoomTests {
    private let model = CameraModel.resolve(modelId: 0x22, name: "OsmoPocket4P")
    private var program: GimbalProgram {
        .init(a: .init(yawDeg: 0, pitchDeg: 0, zoom: 1),
            b: .init(yawDeg: 20, pitchDeg: 0, zoom: 3),
            c: .init(yawDeg: 30, pitchDeg: 0, zoom: 2), durationAB: 3, durationBC: 2)
    }
    private func status(_ color: ColorMode? = .normal, recording: Bool = false) -> CameraStatus {
        var value = CameraStatus()
        value.colorMode = color
        value.zoomLens = CamFov.lens1x
        value.shootingMode = 1
        value.isRecording = recording
        return value
    }
    private func push(_ name: String, _ value: [UInt8]) -> Duml.Frame {
        .init(sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 0, cmdId: 0x99,
            payload: SubscribePush.pack(name: name, value: value))
    }

    @Test(arguments: [false, true])
    func dLog2NeverEmitsZoomAndGimbalOnlyStillWorks(recording: Bool) {
        var zoom = GimbalProgramZoom(program: program, model: model, status: status(.dLog2, recording: recording))
        #expect(zoom.failureReason == "Zoom moves are unavailable in D-Log2")
        #expect(zoom.lensTarget(for: 2, at: 0) == nil)
        #expect(!zoom.hasSentTarget)
        var stationary = program
        stationary.b?.zoom = 1
        stationary.c?.zoom = 1
        #expect(!stationary.changesZoom)
        #expect(GimbalProgramZoom(program: stationary, model: model, status: status(.dLog2)).failureReason == nil)
    }

    @Test func receivedColorAndFormatOverrideAnInitiallyAllowedTake() {
        var zoom = GimbalProgramZoom(program: program, model: model, status: status())
        #expect(zoom.failureReason == nil)
        let color = push("cam_image_effect", [0, 0, ColorMode.dLog2.rawValue])
        #expect(GimbalProgramZoom.feedbackKey(color) == "cam_image_effect")
        zoom.observe(color, at: 0)
        #expect(zoom.failureReason == "Zoom moves are unavailable in D-Log2")
        #expect(zoom.lensTarget(for: 2, at: 0) == nil)
        var outOfRange = program
        outOfRange.b?.zoom = 6
        zoom = GimbalProgramZoom(program: outOfRange, model: model, status: status())
        var mode = [UInt8](repeating: 0, count: 58)
        mode[57] = ShootingMode.slowMo.rawValue
        zoom.observe(.init(sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 2, cmdId: 0x80, payload: mode), at: 0)
        #expect(zoom.failureReason == "Saved zoom exceeds the current FORMAT limit")
        #expect(GimbalProgramZoom(program: program, model: model, status: status(nil)).failureReason != nil)
    }

    @Test func lensDispatchIsDistinctAndNoFasterThanTwentyHertz() {
        var zoom = GimbalProgramZoom(program: program, model: model, status: status())
        #expect(zoom.lensTarget(for: 1, at: 0) == CamFov.lens1x)
        #expect(zoom.hasSentTarget)
        #expect(zoom.lensTarget(for: 2, at: 0.049) == nil)
        #expect(zoom.lensTarget(for: 2, at: 0.05) == CamFov.pinchLens(for: 2))
        #expect(zoom.lensTarget(for: 2, at: 0.1) == nil)
        #expect(zoom.nextWakeInterval(at: 0.12) > 0.029)
        #expect(zoom.lensTarget(for: 3, at: 0.149) == nil)
        #expect(zoom.lensTarget(for: 3, at: 0.15) == CamFov.lens3x)
        #expect(Commands.setZoomLens(CamFov.lens3x).payload == [0x0a, 0x4e, 0x8b, 0x02])
        var lens = [UInt8](repeating: 0, count: 16)
        lens[14] = 0x8b
        lens[15] = 0x02
        zoom.observe(push("cam_lens_state", lens), at: 0.2)
        #expect(zoom.liveZoom == 3)
    }

    @Test func exactZoomAmountsSurviveRoundedPathsAndMeasuredResume() {
        var saved = program
        saved.smoothness = 1
        let path = GimbalZoomPath(program: saved)
        #expect(abs(path.position(at: 1.45) - 2) < 1e-9)
        #expect(path.position(at: 2.98) == 3, "Look-ahead stops at B rather than skipping its zoom")
        #expect(path.position(at: 4.98) == 2)
        let resumed = path.remaining(after: 1.45, from: 2.4, quantized: true)
        #expect(resumed.position(at: 0, lookAhead: 0) == 2.4)
        #expect(abs(resumed.legs[0].duration - 1.6) < 1e-9)
        #expect(resumed.legs[1].duration == 2)
        #expect(resumed.position(at: 1.59) == 3)
        #expect(resumed.end == 2)
        let beforeB = path.remaining(after: 2.96, from: 2.9, quantized: false)
        #expect(abs(beforeB.legs[0].duration - 0.04) < 1e-9)
        #expect(abs(beforeB.duration - 2.04) < 1e-9)
        let lateResume = path.remaining(after: 4, from: 2.7, quantized: false)
        #expect(lateResume.legs.count == 1)
        #expect(lateResume.duration == 1)
        #expect(lateResume.position(at: 0, lookAhead: 0) == 2.7)
    }

    @Test func zoomOwnershipRetiresOnlyItsPendingManualMailbox() {
        var mailbox = CameraSetMailbox()
        let zoom = CameraSetMailbox.zoomOpcodeKey
        let shutter = Duml.opcodeKey(set: 2, cmd: 0x28)
        for key in [zoom, shutter] {
            _ = mailbox.offer(key: key, urgent: true, now: 0)
            mailbox.beginLaunch(key: key, now: 0)
            mailbox.noteTransmit(key: key, seq: 7)
        }
        _ = mailbox.offer(key: zoom, urgent: false, now: 0.01)
        mailbox.cancel(zoom)
        #expect(mailbox.pendingLaunch(key: zoom, now: 1) == .none)
        #expect(mailbox.decideAck(key: zoom, seq: 7) == .dropSuperseded)
        #expect(mailbox.decideAck(key: shutter, seq: 7) == .accept)
    }

    @Test func resumeNeedsFreshSettledZoomRatherThanFreshGimbalFeedback() {
        var zoom = GimbalProgramZoom(program: program, model: model, status: status())
        func lensFrame(_ position: UInt16) -> Duml.Frame {
            var payload = [UInt8](repeating: 0, count: 16)
            payload[14] = UInt8(position & 0xff)
            payload[15] = UInt8(position >> 8)
            return push("cam_lens_state", payload)
        }
        zoom.observe(lensFrame(651), at: 1)
        zoom.notePause(at: 1.1)
        zoom.observe(.init(sender: 0, receiver: 0, seq: 0, flags: 0, cmdSet: 4, cmdId: 5,
            payload: [UInt8](repeating: 0, count: 22)), at: 1.4)
        zoom.observe(push("cam_fov", [0xff, 0x2f, 0, 0]), at: 1.4)
        #expect(!zoom.canResume(at: 1.4), "FOV cannot refresh an older preferred lens measurement")
        zoom.observe(lensFrame(651), at: 1.5)
        zoom.observe(lensFrame(651), at: 1.7)
        #expect(zoom.canResume(at: 1.7))
        #expect(!zoom.canResume(at: 2.01))
        zoom.notePause(at: 2.1)
        zoom.observe(lensFrame(651), at: 2.2)
        zoom.observe(lensFrame(652), at: 2.3)
        zoom.observe(lensFrame(653), at: 2.4)
        #expect(!zoom.canResume(at: 2.4), "Cumulative lens drift must reset the settled window")
        zoom.notePause(at: 3)
        zoom.observe(lensFrame(651), at: 3.1)
        zoom.observe(lensFrame(651), at: 5)
        #expect(!zoom.canResume(at: 5), "A stale gap must restart the settled window")
        zoom.observe(lensFrame(651), at: 5.2)
        #expect(zoom.canResume(at: 5.2))
    }
}
