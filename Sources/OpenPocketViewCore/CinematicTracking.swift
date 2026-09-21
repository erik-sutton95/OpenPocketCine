import Foundation

/// Experimental phone-side framing policy. Vision and motor I/O belong to the shell.
public struct CinematicTrackingSettings: Equatable, Sendable {
    public var sensitivity = 1.0
    public var smoothness = 0.65
    /// Half-width/height of the quiet zone, in fractions of the picture.
    public var deadBand = 0.06
    /// Exponential interpolation half-life in seconds; zero bypasses this stage.
    public var lerp = 0.18
    public var maxSpeed = 24.0
    public var maxAcceleration = 45.0
    public var maxJerk = 180.0
    public var confidence = 0.65
    public var framingX = 0.5
    public var framingY = 0.5
    public var panEnabled = true
    public var tiltEnabled = true

    public init() {}

    public enum Preset: String, CaseIterable, Sendable {
        case gentle = "Gentle"
        case balanced = "Balanced"
        case responsive = "Responsive"
    }

    public static func preset(_ preset: Preset) -> Self {
        var value = Self()
        switch preset {
        case .gentle: break
        case .balanced:
            value.sensitivity = 1.4
            value.smoothness = 0.4
            value.deadBand = 0.04
            value.lerp = 0.1
            value.maxSpeed = 40
            value.maxAcceleration = 75
            value.maxJerk = 350
        case .responsive:
            value.sensitivity = 2
            value.smoothness = 0.2
            value.deadBand = 0.02
            value.lerp = 0.04
            value.maxSpeed = 60
            value.maxAcceleration = 120
            value.maxJerk = 600
        }
        return value
    }

    public var isValid: Bool {
        (0.1...3).contains(sensitivity) && (0...1).contains(smoothness)
            && (0...0.3).contains(deadBand) && (0...1.5).contains(lerp)
            && (1...90).contains(maxSpeed) && (5...180).contains(maxAcceleration)
            && (10...900).contains(maxJerk) && (0.3...0.95).contains(confidence)
            && (0.1...0.9).contains(framingX) && (0.1...0.9).contains(framingY)
    }
}

/// Image-space visual servo with separate noise rejection and artistic easing.
/// Commanded speed/acceleration/jerk are bounded; firmware motion still needs measurement.
public struct CinematicTrackingController: Sendable {
    public static let maxObservationAge = 0.25
    public static let commandDuration = 0.1
    public static let maxTickGap = 0.12
    public private(set) var panSpeed = 0.0
    public private(set) var tiltSpeed = 0.0
    public private(set) var panAcceleration = 0.0
    public private(set) var tiltAcceleration = 0.0
    private var pan = Axis()
    private var tilt = Axis()
    private var filterX = OneEuro()
    private var filterY = OneEuro()
    private var center: (x: Double, y: Double)?
    private var observationAt: TimeInterval?
    private var tickAt: TimeInterval?
    private var commandedYaw: Double?
    private var commandedPitch: Double?

    public init() {}

    public mutating func reset() { self = Self() }

    /// Selection and observations are raw camera pixels. The display transform
    /// has been undone; convert the existing screen-space stick sign back once.
    public static func rawPanInverted(poseInverted: Bool, cameraViewMirrored: Bool) -> Bool {
        poseInverted != cameraViewMirrored
    }

    public static func usable(_ box: TrackingBox) -> Bool {
        [box.x, box.y, box.width, box.height].allSatisfy(\.isFinite)
            && box.width >= 0.025 && box.height >= 0.025
            && box.x >= 0 && box.y >= 0 && box.maxX <= 1 && box.maxY <= 1
    }

    /// A confidence score is not identity proof. Refuse a jump instead of chasing it.
    public static func continuous(from old: TrackingBox, to new: TrackingBox, dt: Double) -> Bool {
        guard usable(old), usable(new), dt > 0, dt <= maxObservationAge else { return false }
        let distance = hypot(old.centerX - new.centerX, old.centerY - new.centerY)
        let ratio = new.area / old.area
        return distance <= min(0.2, 0.045 + dt * 1.2) && (0.45...2.2).contains(ratio)
    }

    @discardableResult
    public mutating func observe(box: TrackingBox, measuredAt: TimeInterval, now: TimeInterval)
        -> Bool
    {
        guard Self.usable(box), measuredAt.isFinite, now.isFinite,
            now >= measuredAt, now - measuredAt <= Self.maxObservationAge,
            observationAt.map({ measuredAt > $0 }) ?? true
        else { return false }
        let dt = observationAt.map { measuredAt - $0 } ?? (1.0 / 15)
        center = (
            filterX.update(box.centerX, dt: dt), filterY.update(box.centerY, dt: dt)
        )
        observationAt = measuredAt
        return true
    }

    /// Raw camera pixels have already been unmirrored by the selection UI.
    /// `invertPan` includes camera pose and encoder mirroring, never the MIRROR assist.
    public mutating func target(
        pose: GimbalWaypoint, now: TimeInterval, settings: CinematicTrackingSettings,
        pictureAspect: Double, invertPan: Bool
    ) -> GimbalWaypoint? {
        guard settings.isValid, now.isFinite, pictureAspect.isFinite, pictureAspect > 0,
            let center, let observationAt, now >= observationAt,
            now - observationAt <= Self.maxObservationAge,
            let nativePitch = pose.nativePitchDeg, nativePitch.isFinite,
            (-180...180).contains(nativePitch), pose.zoom.isFinite, pose.zoom >= 1,
            GimbalMoveEngine.canSendNativeTarget(from: pose, to: pose)
        else {
            reset()
            return nil
        }
        let dt = tickAt.map { now - $0 } ?? GimbalStick.streamInterval
        guard dt > 0, dt <= Self.maxTickGap else {
            reset()
            return nil
        }
        tickAt = now

        // Nominal 80° horizontal FOV at 1×. This is a servo gain estimate, not
        // calibrated lens geometry; zoom compensation avoids an overactive tele view.
        let tangent = tan(40 * .pi / 180) / pose.zoom
        let x = Self.softDeadBand(center.x - settings.framingX, radius: settings.deadBand)
        let y = Self.softDeadBand(settings.framingY - center.y, radius: settings.deadBand)
        let yawError = atan(2 * x * tangent) * 180 / .pi * (invertPan ? -1 : 1)
        let pitchError = atan(2 * y * tangent / pictureAspect) * 180 / .pi
        let panRate = pan.step(
            error: yawError, enabled: settings.panEnabled, dt: dt, settings: settings)
        let tiltRate = tilt.step(
            error: pitchError, enabled: settings.tiltEnabled, dt: dt, settings: settings)
        // Keep fractional progress across 0.1° wire quantization. Re-anchoring
        // every target at feedback would erase every speed below 0.5°/s.
        // Feedback still bounds lead, so a stalled motor cannot wind up a move.
        let lead = floor(settings.maxSpeed * Self.commandDuration * 10) / 10
        let wantedYaw =
            settings.panEnabled ? (commandedYaw ?? pose.yawDeg) + panRate * dt : pose.yawDeg
        let wantedPitch =
            settings.tiltEnabled ? (commandedPitch ?? pose.pitchDeg) + tiltRate * dt : pose.pitchDeg
        let yaw = HeadTrack.Reach.clampPan(
            min(max(wantedYaw, pose.yawDeg - lead), pose.yawDeg + lead))
        let pitch = HeadTrack.Reach.clampTilt(
            min(max(wantedPitch, pose.pitchDeg - lead), pose.pitchDeg + lead))
        if yaw != wantedYaw { pan = Axis() }
        if pitch != wantedPitch { tilt = Axis() }
        commandedYaw = yaw
        commandedPitch = pitch
        panSpeed = pan.rate
        tiltSpeed = tilt.rate
        panAcceleration = pan.acceleration
        tiltAcceleration = tilt.acceleration
        return GimbalWaypoint(
            yawDeg: yaw, pitchDeg: pitch, zoom: pose.zoom,
            nativePitchDeg: GimbalMoveEngine.wrapAngle(nativePitch - (pitch - pose.pitchDeg)))
    }

    /// C1-continuous onset avoids a speed step at the dead-band boundary.
    public static func softDeadBand(_ error: Double, radius: Double) -> Double {
        let excess = max(0, abs(error) - radius)
        let knee = max(0.015, radius * 0.5)
        let softened = excess < knee ? excess * excess / (2 * knee) : excess - knee / 2
        return error < 0 ? -softened : softened
    }

    private struct Axis: Sendable {
        var interpolated = 0.0
        var rate = 0.0
        var acceleration = 0.0

        mutating func step(
            error: Double, enabled: Bool, dt: Double, settings: CinematicTrackingSettings
        ) -> Double {
            guard enabled else {
                self = Self()
                return 0
            }
            let wanted = min(
                max(error * settings.sensitivity, -settings.maxSpeed), settings.maxSpeed)
            // Actual elapsed time makes Lerp independent of frame/control rate.
            let alpha = settings.lerp == 0 ? 1 : -expm1(-log(2) * dt / settings.lerp)
            interpolated += (wanted - interpolated) * alpha
            let omega = 4.6 / (0.18 + 2.2 * settings.smoothness * settings.smoothness)
            // Integrate a critically damped rate spring in bounded substeps.
            let steps = max(1, Int(ceil(dt / 0.005)))
            let h = dt / Double(steps)
            for _ in 0..<steps {
                let jerk = min(
                    max(
                        omega * omega * (interpolated - rate) - 2 * omega * acceleration,
                        -settings.maxJerk), settings.maxJerk)
                acceleration = min(
                    max(
                        acceleration + jerk * h,
                        -settings.maxAcceleration), settings.maxAcceleration)
                rate = min(max(rate + acceleration * h, -settings.maxSpeed), settings.maxSpeed)
            }
            return rate
        }
    }

    /// Casiez et al., CHI 2012: adaptive low-pass for stable slow motion and less fast-motion lag.
    private struct OneEuro: Sendable {
        var previous: Double?
        var filtered = 0.0
        var derivative = 0.0

        mutating func update(_ value: Double, dt: Double) -> Double {
            guard let previous else {
                self.previous = value
                filtered = value
                return value
            }
            let derivativeAlpha = 1 / (1 + 1 / (2 * .pi * dt))
            derivative += (((value - previous) / dt) - derivative) * derivativeAlpha
            let cutoff = 1.2 + 4 * abs(derivative)
            let alpha = 1 / (1 + 1 / (2 * .pi * cutoff * dt))
            filtered += (value - filtered) * alpha
            self.previous = value
            return filtered
        }
    }
}
