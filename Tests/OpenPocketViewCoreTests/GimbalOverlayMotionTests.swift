import Testing

@testable import OpenPocketViewCore

@Suite struct GimbalOverlayMotionTests {
    private func point(_ yaw: Double, _ pitch: Double = 0) -> GimbalWaypoint {
        GimbalWaypoint(yawDeg: yaw, pitchDeg: pitch, zoom: 1, nativePitchDeg: 170)
    }

    @Test func measuredVelocityMovesMarkersBetweenReportsWithoutMovingSavedPoints() {
        var motion = GimbalOverlayMotion()
        let saved = point(10, 5)
        motion.observe(point(8, 4), at: 1)
        motion.observe(saved, at: 1.1)
        let halfway = motion.pose(at: 1.15)!
        #expect(abs(halfway.yawDeg - 11) < 1e-9)
        #expect(abs(halfway.pitchDeg - 5.5) < 1e-9)
        #expect(halfway.nativePitchDeg == nil)
        #expect(saved.yawDeg == 10)
        let rawMark = GimbalWaypointOverlay.project(waypoint: saved, slot: .a, live: saved, aspect: 16 / 9)
        let movingMark = GimbalWaypointOverlay.project(waypoint: saved, slot: .a, live: halfway, aspect: 16 / 9)
        #expect(movingMark.nx < rawMark.nx)
    }
}
