import CoreMotion
import OpenPocketViewCore
import UIKit
import os

/// Shared local space: Calibrate Head Lock is identity. AirPods look
/// is the SET-relative nose. Stick throw closes live `0x04/0x05` onto
/// that pose. Roll is displayed only — Pocket stick has no roll axis.
/// Motion starts when Head Tracking is on.
@MainActor
final class HeadphoneMotionBridge: NSObject, CMHeadphoneMotionManagerDelegate {
    private struct HeadSample: Sendable {
        var w: Double
        var x: Double
        var y: Double
        var z: Double
        var gx: Double
        var gy: Double
        var gz: Double
        var yaw: Double
        var pitch: Double
        var roll: Double
        var quat: HeadTrack.Quat { HeadTrack.Quat(w: w, x: x, y: y, z: z) }
    }

    private weak var model: AppModel?
    private let motion = CMHeadphoneMotionManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "opv.head-track"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    nonisolated private let latestHead = OSAllocatedUnfairLock<HeadSample?>(initialState: nil)
    private var samplePump: Task<Void, Never>?
    private var originQuat = HeadTrack.Quat.identity
    private var originYaw = 0.0
    private var originPitch = 0.0
    private var originRoll = 0.0
    private var lastYaw = 0.0
    private var lastPitch = 0.0
    private var lastRoll = 0.0
    private var lastQuat = HeadTrack.Quat.identity
    private var lastGx = 0.0
    private var lastGy = 0.0
    private var lastGz = 0.0
    private var biasGx = 0.0
    private var biasGy = 0.0
    private var biasGz = 0.0
    private var intGx = 0.0
    private var intGy = 0.0
    private var intGz = 0.0
    private var didToastStill = false
    private var haveHead = false
    private var didToastNeedPods = false
    private var userStopped = false
    private var calibratedByUser = false
    private var pendingCalibrate = false
    private var lastMotionAt: Date?
    private var lastHudAt: Date?
    private var lastLogAt: Date?
    private var centerHaptic = UIImpactFeedbackGenerator(style: .medium)
    private var track = HeadTrack()
    private var driving = false
    private var restFor: TimeInterval = 0
    private var gimbalYaw0Deg = 0.0
    private var gimbalPitch0Deg = 0.0
    private var didToastLive = false

    func attach(model: AppModel) {
        detach()
        self.model = model
        motion.delegate = self
        sync()
    }

    func detach() {
        stopMotion()
        haveHead = false
        didToastNeedPods = false
        didToastStill = false
        userStopped = false
        calibratedByUser = false
        pendingCalibrate = false
        lastMotionAt = nil
        driving = false
        track.reset()
        didToastLive = false
        model?.headTrackControlTitle = LiveHeadTrackCalibrateButton.calibrateTitle
        model?.headTrackImuReadout = ""
        model?.headTrackAxisPose = nil
        motion.delegate = nil
        model = nil
    }

    func noteBlocked() {
        stopDrive()
    }

    func sync() {
        guard let model else { return }
        guard model.headTrackingEnabled else {
            stopMotion()
            haveHead = false
            didToastNeedPods = false
            didToastStill = false
            userStopped = false
            calibratedByUser = false
            pendingCalibrate = false
            lastMotionAt = nil
            driving = false
            track.reset()
            didToastLive = false
            model.headTrackControlTitle = LiveHeadTrackCalibrateButton.calibrateTitle
            model.headTrackImuReadout = ""
            model.headTrackAxisPose = nil
            return
        }
        publishTitle()
        startMotion()
        if haveHead { publishReadout(now: Date()) }
        if canDrive, !userStopped, calibratedByUser { apply(dt: 0) } else { stopDrive() }
    }

    func tapControl() {
        guard let model, model.headTrackingEnabled else { return }
        if !userStopped, calibratedByUser {
            userStopped = true
            calibratedByUser = false
            pendingCalibrate = false
            track.reset()
            stopDrive()
            resetRelative()
            model.session.controlNote = "Head lock cleared"
            ControlLiveLog.line("head-track: stopped")
            publishTitle()
            publishReadout(now: Date())
            return
        }
        userStopped = false
        pendingCalibrate = true
        startMotion()
        if haveHead {
            completeCalibrate()
        } else {
            model.session.controlNote = "Head tracking needs AirPods in your ears"
        }
    }

    private func completeCalibrate() {
        guard let model, pendingCalibrate, haveHead else { return }
        switch track.center(
            gimbalYawTenth: model.session.gimbalYawTenthDeg,
            gimbalPitchTenth: model.session.gimbalPitchTenthDeg,
            gyroLookRight: lastGx, gyroLookUp: lastGy, gyroYaw: lastGz)
        {
        case .waitingForGimbal:
            model.session.controlNote = "Head tracking waiting for gimbal"
            return
        case .waitingForStill:
            if !didToastStill {
                didToastStill = true
                model.session.controlNote = "Hold still to set forward"
            }
            return
        case .centered:
            break
        }
        originYaw = lastYaw
        originPitch = lastPitch
        originRoll = lastRoll
        originQuat = lastQuat
        gimbalYaw0Deg = model.session.gimbalYawTenthDeg.map { Double($0) / 10 } ?? 0
        gimbalPitch0Deg = model.session.gimbalPitchTenthDeg.map { Double($0) / 10 } ?? 0
        biasGx = lastGx
        biasGy = lastGy
        biasGz = lastGz
        intGx = 0
        intGy = 0
        intGz = 0
        pendingCalibrate = false
        calibratedByUser = true
        didToastLive = true
        restFor = 0
        model.session.prepHeadTrackGimbal()
        model.session.controlNote = "Head lock set — gimbal follows"
        ControlLiveLog.line("head-track: calibrated")
        if model.hapticsEnabled { centerHaptic.impactOccurred() }
        lastMotionAt = Date()
        publishTitle()
        apply(dt: 0)
        publishReadout(now: lastMotionAt)
    }

    private func resetRelative() {
        originYaw = lastYaw
        originPitch = lastPitch
        originRoll = lastRoll
        originQuat = lastQuat
        intGx = 0
        intGy = 0
        intGz = 0
        lastMotionAt = Date()
    }

    private func publishTitle() {
        model?.headTrackControlTitle =
            (!userStopped && calibratedByUser)
            ? LiveHeadTrackCalibrateButton.stopTitle
            : LiveHeadTrackCalibrateButton.calibrateTitle
    }

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            ControlLiveLog.line("head-track: AirPods connected")
            self.didToastNeedPods = false
            if self.model?.headTrackingEnabled == true { self.startMotion() }
            self.sync()
        }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor in
            ControlLiveLog.line("head-track: AirPods disconnected")
            self.haveHead = false
            self.calibratedByUser = false
            self.pendingCalibrate = false
            self.lastMotionAt = nil
            self.track.reset()
            self.stopDrive()
            self.model?.headTrackImuReadout = ""
            self.model?.headTrackAxisPose = nil
            self.publishTitle()
            if self.model?.headTrackingEnabled == true {
                self.model?.session.controlNote = "Head tracking needs AirPods in your ears"
            }
        }
    }

    private func startMotion() {
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        ControlLiveLog.line(
            "head-track: auth=\(Self.authLabel(auth)) available=\(motion.isDeviceMotionAvailable ? 1 : 0) active=\(motion.isDeviceMotionActive ? 1 : 0)"
        )
        if auth == .denied || auth == .restricted {
            if !didToastNeedPods {
                didToastNeedPods = true
                model?.session.controlNote = "Allow Motion & Fitness for OpenPocketCine in Settings"
            }
            return
        }
        if !motion.isConnectionStatusActive {
            motion.startConnectionStatusUpdates()
        }
        guard motion.isDeviceMotionAvailable else {
            if model?.headTrackingEnabled == true, !didToastNeedPods {
                didToastNeedPods = true
                model?.session.controlNote = "Head tracking needs AirPods with motion"
            }
            return
        }
        startSamplePump()
        guard !motion.isDeviceMotionActive else { return }
        latestHead.withLock { $0 = nil }
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] sample, error in
            if let error {
                Task { @MainActor in
                    ControlLiveLog.line("head-track: motion error \(error.localizedDescription)")
                    guard let self else { return }
                    if !self.didToastNeedPods {
                        self.didToastNeedPods = true
                        self.model?.session.controlNote = "Head tracking needs AirPods in your ears"
                    }
                }
                return
            }
            guard let sample, let self else { return }
            let q = sample.attitude.quaternion
            let r = sample.rotationRate
            let a = sample.attitude
            let next = HeadSample(
                w: q.w, x: q.x, y: q.y, z: q.z,
                gx: r.x, gy: r.y, gz: r.z,
                yaw: a.yaw, pitch: a.pitch, roll: a.roll)
            self.latestHead.withLock { $0 = next }
        }
    }

    private func startSamplePump() {
        guard samplePump == nil else { return }
        samplePump = Task { @MainActor [weak self] in
            let delay = Duration.milliseconds(
                Int((GimbalStick.streamInterval * 1_000).rounded(.up)))
            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                self.pullHead()
            }
        }
    }

    private func stopSamplePump() {
        samplePump?.cancel()
        samplePump = nil
    }

    private func pullHead() {
        guard let sample = latestHead.withLock({ $0 }) else { return }
        lastGx = sample.gx
        lastGy = sample.gy
        lastGz = sample.gz
        lastYaw = sample.yaw
        lastPitch = sample.pitch
        lastRoll = sample.roll
        lastQuat = sample.quat
        if !haveHead {
            resetRelative()
        }
        haveHead = true
        didToastNeedPods = false
        let now = Date()
        var dt = 0.0
        if let last = lastMotionAt {
            dt = now.timeIntervalSince(last)
            if dt < 0 || dt > 0.25 { dt = 0 }
        }
        lastMotionAt = now
        if calibratedByUser, dt > 0 {
            let toDeg = 180 / Double.pi
            intGx += (lastGx - biasGx) * dt * toDeg
            intGy += (lastGy - biasGy) * dt * toDeg
            intGz += (lastGz - biasGz) * dt * toDeg
        }
        if pendingCalibrate, !calibratedByUser {
            completeCalibrate()
        } else if calibratedByUser {
            apply(dt: dt)
        }
        publishReadout(now: now)
    }

    private var canDrive: Bool {
        guard let model else { return false }
        if model.session.isLocked { return false }
        if model.session.isBrowsingMedia { return false }
        if model.liveOperatorPanel != nil { return false }
        if model.isEditingChrome { return false }
        return model.isLive && model.session.datalink != nil
    }

    private func apply(dt: TimeInterval) {
        guard let model, model.headTrackingEnabled, haveHead, !userStopped else {
            stopDrive()
            return
        }
        guard canDrive else {
            stopDrive()
            return
        }
        if !calibratedByUser || !track.isCentered {
            stopDrive()
            return
        }
        if model.gimbalAnalogHeld {
            stopDrive()
            return
        }
        if model.session.isLiveVideoStale {
            stopDrive()
            return
        }
        let look = HeadTrack.look(current: lastQuat, origin: originQuat)
        let lookRight = look.right
        let lookUp = look.up
        guard
            let cmd = track.tick(
                lookRightDeg: lookRight, lookUpDeg: lookUp,
                gimbalYawTenth: model.session.gimbalYawTenthDeg,
                gimbalPitchTenth: model.session.gimbalPitchTenthDeg, dt: dt,
                gyroLookRight: lastGx, gyroLookUp: lastGy, gyroYaw: lastGz)
        else { return }
        // Mimo: 0x04/0x01 only while thrown. Do not grab/release in the same
        // second — that chatter paused HEVC (22:24:19 rest/throw/rest).
        if cmd.rest {
            restFor += max(dt, 0)
            if driving {
                ControlLiveLog.line(
                    String(
                        format: "head-track: stick rest head Y=%.1f P=%.1f", lookRight, lookUp))
                stopDrive()
            }
            return
        }
        restFor = 0
        if !driving {
            let axes = GimbalStick.encode(
                x: cmd.x, y: cmd.y,
                invertPan: GimbalStick.liveInvertPan(
                    poseInvert: model.session.gimbalPoseInvertPan,
                    assistMirror: model.assist.isVisible(.mirror)),
                linear: true)
            ControlLiveLog.line(
                String(
                    format:
                        "head-track: stick throw x=%.2f y=%.2f axis0=%u axis1=%u head Y=%.1f P=%.1f",
                    cmd.x, cmd.y, axes.axis0, axes.axis1, lookRight, lookUp))
        }
        driving = true
        model.session.updateGimbalStick(
            x: cmd.x, y: cmd.y, assistMirror: model.assist.isVisible(.mirror), linear: true)
    }

    private func stopDrive() {
        guard driving else { return }
        driving = false
        restFor = 0
        if model?.gimbalAnalogHeld != true {
            model?.session.endGimbalStick()
        }
    }

    private func stopMotion() {
        stopSamplePump()
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        if motion.isConnectionStatusActive { motion.stopConnectionStatusUpdates() }
        latestHead.withLock { $0 = nil }
    }

    private func publishReadout(now: Date?) {
        guard let model, model.headTrackingEnabled, haveHead else {
            model?.headTrackImuReadout = ""
            model?.headTrackAxisPose = nil
            return
        }
        let look = HeadTrack.look(current: lastQuat, origin: originQuat)
        let lookRight = look.right
        let lookUp = look.up
        let originYaw = calibratedByUser ? gimbalYaw0Deg : 0
        let originPitch = calibratedByUser ? gimbalPitch0Deg : 0
        let gimbalYawDeg = model.session.gimbalYawTenthDeg.map {
            HeadTrack.bodyLookRightDeg(liveYawDeg: Double($0) / 10, originYawDeg: originYaw)
        }
        let gimbalPitchDeg = model.session.gimbalPitchTenthDeg.map {
            HeadTrack.bodyLookUpDeg(livePitchDeg: Double($0) / 10, originPitchDeg: originPitch)
        }
        model.headTrackAxisPose = HeadTrackAxisPose(
            yawDeg: lookRight, pitchDeg: lookUp,
            gimbalYawDeg: gimbalYawDeg, gimbalPitchDeg: gimbalPitchDeg,
            locked: calibratedByUser)
        let hudDue: Bool
        if let now, let last = lastHudAt {
            hudDue = now.timeIntervalSince(last) >= LiveChromeThrottle.statusInterval
        } else {
            hudDue = true
        }
        let logDue: Bool
        if let now, let last = lastLogAt {
            logDue = now.timeIntervalSince(last) >= 0.5
        } else {
            logDue = true
        }
        guard hudDue || logDue else { return }

        let dY = lookRight
        let dP = lookUp
        let dR = HeadTrack.wrapDeg(
            HeadTrack.radToDeg(lastRoll) - HeadTrack.radToDeg(originRoll))
        let bodyY = gimbalYawDeg ?? 0
        let bodyP = gimbalPitchDeg ?? 0
        let rawY = model.session.gimbalYawTenthDeg.map { String($0) } ?? "-"
        let rawP = model.session.gimbalPitchTenthDeg.map { String($0) } ?? "-"
        let setMark = calibratedByUser ? "SET" : "no SET"
        if hudDue {
            lastHudAt = now
            model.headTrackImuReadout = String(
                format:
                    "%@  shared °\nhead   Y%+6.1f  P%+6.1f  R%+6.1f\nbody   Y%+6.1f  P%+6.1f  rawP %@\nerr    Y%+6.1f  P%+6.1f",
                setMark, dY, dP, dR, bodyY, bodyP, rawP, dY - bodyY, dP - bodyP)
        }
        if logDue {
            lastLogAt = now
            let att = model.session.lastGimbalAttitudeHex
            let dump = model.session.lastGimbalAttitudeDump
            ControlLiveLog.line(
                String(
                    format:
                        "head-imu: %@ head Y=%.1f P=%.1f R=%.1f  body Y=%.1f P=%.1f  err Y=%.1f P=%.1f  rawY=%@ rawP=%@ %@ att=%@",
                    setMark, dY, dP, dR, bodyY, bodyP, dY - bodyY, dP - bodyP, rawY, rawP,
                    dump.isEmpty ? "-" : dump, att.isEmpty ? "-" : att)
            )
        }
    }

    private static func authLabel(_ status: CMAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }
}
