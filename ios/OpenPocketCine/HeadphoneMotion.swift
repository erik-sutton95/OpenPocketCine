import CoreMotion
import OpenPocketViewCore
import UIKit
import os

/// Calibrate Head Lock captures shared forward and camera-native pitch.
/// Nose direction maps to absolute targets; roll remains display-only.
@MainActor
final class HeadphoneMotionBridge: NSObject, CMHeadphoneMotionManagerDelegate {
    /// Optional axis rings and IMU/native-target readout. Diagnostic logs
    /// remain throttled independently of this operator display.
    static let debugHud = false

    private struct HeadSample: Sendable {
        var measuredAt: TimeInterval
        var sequence: UInt64
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
    private struct HeadInbox: Sendable {
        var sample: HeadSample?
        var gate = HeadTrackNativeSampleGate()
    }
    nonisolated private let latestHead = OSAllocatedUnfairLock(initialState: HeadInbox())
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
    private var track = HeadTrackNative()
    private var nativeToken: UInt64?
    private var lastHeadMeasuredAt: TimeInterval?
    private var lastHeadSequence: UInt64?
    private var didToastStaleHead = false
    private var driving = false
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
        guard let model, pendingCalibrate, haveHead, canDrive, !model.gimbalAnalogHeld,
            HeadTrackNative.headSampleIsFresh(measuredAt: lastHeadMeasuredAt, now: ProcessInfo.processInfo.systemUptime)
        else { return }
        guard let pose = model.session.freshGimbalWaypoint else {
            model.session.controlNote = "Head tracking waiting for gimbal"
            return
        }
        switch track.center(
            pose: pose,
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
        gimbalYaw0Deg = pose.yawDeg
        gimbalPitch0Deg = pose.pitchDeg
        biasGx = lastGx
        biasGy = lastGy
        biasGz = lastGz
        intGx = 0
        intGy = 0
        intGz = 0
        pendingCalibrate = false
        calibratedByUser = true
        didToastLive = true
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
            self.invalidateHeadCallbacks()
            if self.motion.isDeviceMotionActive { self.motion.stopDeviceMotionUpdates() }
            self.lastHeadMeasuredAt = nil
            self.lastHeadSequence = nil
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
        let generation = latestHead.withLock {
            $0.sample = nil
            return $0.gate.begin()
        }
        motion.startDeviceMotionUpdates(to: motionQueue) { [weak self] sample, error in
            if let error {
                Task { @MainActor in
                    ControlLiveLog.line("head-track: motion error \(error.localizedDescription)")
                    guard let self else { return }
                    let current = self.latestHead.withLock {
                        guard $0.gate.isCurrent(generation) else { return false }
                        $0.sample = nil
                        return true
                    }
                    guard current else { return }
                    self.lastHeadMeasuredAt = nil
                    self.lastHeadSequence = nil
                    self.stopDrive()
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
            var next = HeadSample(
                measuredAt: sample.timestamp, sequence: 0,
                w: q.w, x: q.x, y: q.y, z: q.z,
                gx: r.x, gy: r.y, gz: r.z,
                yaw: a.yaw, pitch: a.pitch, roll: a.roll)
            self.latestHead.withLock {
                guard $0.gate.accepts(generation, measuredAt: next.measuredAt,
                    now: ProcessInfo.processInfo.systemUptime),
                    next.measuredAt > ($0.sample?.measuredAt ?? -.infinity) else { return }
                next.sequence = ($0.sample?.sequence ?? 0) &+ 1
                $0.sample = next
            }
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
        let nowUptime = ProcessInfo.processInfo.systemUptime
        guard let sample = latestHead.withLock({ $0.sample }),
            HeadTrackNative.headSampleIsFresh(measuredAt: sample.measuredAt, now: nowUptime)
        else {
            stopDrive()
            if calibratedByUser, !didToastStaleHead {
                didToastStaleHead = true
                model?.session.controlNote = "Head motion lost — waiting for AirPods"
            }
            return
        }
        didToastStaleHead = false
        if sample.sequence == lastHeadSequence {
            if calibratedByUser { apply(dt: 0) }
            return
        }
        lastHeadSequence = sample.sequence
        lastHeadMeasuredAt = sample.measuredAt
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
        if !model.session.gimbalControlSceneActive || model.session.isLocked || model.session.gimbalMoveRunning { return false }
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
        guard HeadTrackNative.headSampleIsFresh(
            measuredAt: lastHeadMeasuredAt, now: ProcessInfo.processInfo.systemUptime),
            model.session.freshGimbalWaypoint != nil
        else { stopDrive(); return }
        let look = HeadTrack.look(current: lastQuat, origin: originQuat)
        guard let target = track.target(lookRightDeg: look.right, lookUpDeg: look.up) else {
            stopDrive()
            return
        }
        if nativeToken == nil { nativeToken = model.session.beginNativeHeadTrack() }
        guard let token = nativeToken else { return }
        guard model.session.updateNativeHeadTrack(target: target, token: token) else {
            stopDrive()
            return
        }
        driving = true
    }

    private func stopDrive() {
        driving = false
        guard let token = nativeToken else { return }
        nativeToken = nil
        model?.session.endNativeHeadTrack(token: token)
    }

    private func invalidateHeadCallbacks() {
        latestHead.withLock {
            $0.gate.invalidate()
            $0.sample = nil
        }
    }

    private func stopMotion() {
        invalidateHeadCallbacks()
        stopDrive()
        stopSamplePump()
        lastHeadMeasuredAt = nil
        lastHeadSequence = nil
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        if motion.isConnectionStatusActive { motion.stopConnectionStatusUpdates() }
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
        let originGimbalYaw = calibratedByUser ? gimbalYaw0Deg : 0
        let originGimbalPitch = calibratedByUser ? gimbalPitch0Deg : 0
        let gimbalYawDeg = model.session.gimbalYawTenthDeg.map {
            HeadTrack.bodyLookRightDeg(
                liveYawDeg: Double($0) / 10, originYawDeg: originGimbalYaw)
        }
        let gimbalPitchDeg = model.session.gimbalPitchTenthDeg.map {
            HeadTrack.bodyLookUpDeg(
                livePitchDeg: Double($0) / 10, originPitchDeg: originGimbalPitch)
        }
        model.headTrackAxisPose =
            Self.debugHud
            ? HeadTrackAxisPose(
                yawDeg: lookRight, pitchDeg: lookUp,
                gimbalYawDeg: gimbalYawDeg, gimbalPitchDeg: gimbalPitchDeg,
                locked: calibratedByUser)
            : nil
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
        // Native target, SET-relative like the measured body pose.
        let predY = calibratedByUser ? (track.lastTarget?.yawDeg ?? gimbalYaw0Deg) - gimbalYaw0Deg : 0
        let predP = calibratedByUser ? (track.lastTarget?.pitchDeg ?? gimbalPitch0Deg) - gimbalPitch0Deg : 0
        let rawY = model.session.gimbalYawTenthDeg.map { String($0) } ?? "-"
        let rawP = model.session.gimbalPitchTenthDeg.map { String($0) } ?? "-"
        let setMark = calibratedByUser ? "SET" : "no SET"
        if hudDue {
            lastHudAt = now
            model.headTrackImuReadout =
                Self.debugHud
                ? String(
                    format:
                        "%@  shared °\nhead   Y%+6.1f  P%+6.1f  R%+6.1f\nbody   Y%+6.1f  P%+6.1f  rawP %@\ntarget Y%+6.1f  P%+6.1f\nerr    Y%+6.1f  P%+6.1f",
                    setMark, dY, dP, dR, bodyY, bodyP, rawP, predY, predP, dY - predY,
                    dP - predP)
                : ""
        }
        if logDue {
            lastLogAt = now
            let att = model.session.lastGimbalAttitudeHex
            let dump = model.session.lastGimbalAttitudeDump
            ControlLiveLog.line(
                String(
                    format:
                        "head-imu: %@ head Y=%.1f P=%.1f R=%.1f  body Y=%.1f P=%.1f  target Y=%.1f P=%.1f  err Y=%.1f P=%.1f  rawY=%@ rawP=%@ %@ att=%@",
                    setMark, dY, dP, dR, bodyY, bodyP, predY, predP, dY - predY, dP - predP,
                    rawY, rawP, dump.isEmpty ? "-" : dump, att.isEmpty ? "-" : att)
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
