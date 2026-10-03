import Foundation

// GimbalWaypoint, GimbalWaypointSlot, GimbalProgram and the straight-line pose math
// (GimbalPath) live in OpenCineCore's OpenCineMotion. The DJI native-target engine stays here.

/// First-order follow on analog throw. Off is a passthrough.
public struct GimbalRampFilter: Equatable, Sendable {
    public var x: Double = 0
    public var y: Double = 0

    public init(x: Double = 0, y: Double = 0) {
        self.x = x
        self.y = y
    }

    public mutating func reset() {
        x = 0
        y = 0
    }

    public mutating func tick(
        targetX: Double, targetY: Double, ramp: GimbalRamp, dt: TimeInterval
    ) -> (Double, Double) {
        let tau = ramp.tau
        if tau <= 0 || dt <= 0 {
            x = targetX
            y = targetY
            return (x, y)
        }
        let alpha = 1 - exp(-dt / tau)
        x += (targetX - x) * alpha
        y += (targetY - y) * alpha
        return (x, y)
    }
}

/// Project a stored yaw/pitch onto the live picture. Each waypoint is a
/// direction on the unit sphere in gimbal space; as live `0x04/0x05`
/// yaw/pitch change, that sphere rotates with the camera.
public enum GimbalWaypointOverlay {
    /// Pocket 3 is 20 mm equivalent on the full 3:2 sensor width:
    /// 2·atan(18/20) = 84°. Knob — verify with a letter on a frame-edge feature.
    public static let wideHFovDeg = 84.0
    /// Waypoint pitch is look-up positive (`GimbalStick.pitchTenthDeg`). +1
    /// draws look-up above center. Flip if a device disagrees.
    public static let pitchUpSign = 1.0

    public struct Mark: Equatable, Sendable {
        public var slot: GimbalWaypointSlot
        public var nx: Double
        public var ny: Double
        public var onScreen: Bool

        public init(slot: GimbalWaypointSlot, nx: Double, ny: Double, onScreen: Bool) {
            self.slot = slot
            self.nx = nx
            self.ny = ny
            self.onScreen = onScreen
        }
    }

    /// Digital zoom scales the image, i.e. the tangent, not the angle.
    public static func tanHalfHFov(zoom: Double) -> Double {
        tan(wideHFovDeg / 2 * .pi / 180) / max(zoom, 1)
    }

    public static func project(
        waypoint: GimbalWaypoint,
        slot: GimbalWaypointSlot,
        live: GimbalWaypoint,
        aspect: Double
    ) -> Mark {
        let tanH = tanHalfHFov(zoom: live.zoom)
        let tanV = tanH / max(aspect, 0.1)
        let dYaw = (waypoint.yawDeg - live.yawDeg) * .pi / 180
        let tp = pitchUpSign * waypoint.pitchDeg * .pi / 180
        let cp = pitchUpSign * live.pitchDeg * .pi / 180
        // Target direction with the camera yaw removed: (right, up, forward).
        let x = sin(dYaw) * cos(tp)
        let y = sin(tp)
        let z = cos(dYaw) * cos(tp)
        // Remove the camera pitch (rotation about the right axis).
        let yc = y * cos(cp) - z * sin(cp)
        let zc = y * sin(cp) + z * cos(cp)
        guard zc > 1e-6 else {
            return Mark(slot: slot, nx: x >= 0 ? 1 : 0, ny: 0.5, onScreen: false)
        }
        let nx = 0.5 + (x / zc) / (2 * tanH)
        let ny = 0.5 - (yc / zc) / (2 * tanV)
        let onScreen = nx >= 0 && nx <= 1 && ny >= 0 && ny <= 1
        return Mark(
            slot: slot,
            nx: min(max(nx, 0), 1),
            ny: min(max(ny, 0), 1),
            onScreen: onScreen)
    }

    public static func marks(
        program: GimbalProgram, live: GimbalWaypoint, aspect: Double
    ) -> [Mark] {
        GimbalWaypointSlot.allCases.compactMap { slot in
            guard let point = program[slot] else { return nil }
            return project(waypoint: point, slot: slot, live: live, aspect: aspect)
        }
    }
}
