import Testing

@testable import OpenPocketViewCore

struct GimbalWaypointPresentationTests {
    @Test func selfieWaypointMovesLeftWhenPicturePansRight() {
        let mapping = GimbalStickMapping(commanded180: true)
        let saved = GimbalWaypoint(yawDeg: 180, pitchDeg: 0, zoom: 1)
        let live = GimbalWaypoint(yawDeg: 175, pitchDeg: 0, zoom: 1)
        let mark = GimbalWaypointOverlay.project(
            waypoint: saved, slot: .a, live: live, aspect: 16 / 9)
        let displayedX = GimbalWaypointPresentation.normalizedX(
            mark.nx, poseInvertPan: mapping.invertPan, assistMirror: false)

        #expect(displayedX < 0.5, "A saved scene point must move left as the selfie picture pans right")
    }

    @Test func orientationTableUsesTT180RatherThanDecoderExtraMirror() {
        // Selfie Flip changes both the encoded picture and decoder compensation.
        // It must not change the final native-yaw-to-picture direction.
        let cases: [(tt180: Bool, selfieFlip: Bool?, mirror: Bool, expected: Double)] = [
            (false, nil, false, 0.2), (false, nil, true, 0.8),
            (false, false, false, 0.2), (false, false, true, 0.8),
            (false, true, false, 0.2), (false, true, true, 0.8),
            (true, nil, false, 0.8), (true, nil, true, 0.2),
            (true, false, false, 0.8), (true, false, true, 0.2),
            (true, true, false, 0.8), (true, true, true, 0.2),
        ]
        for row in cases {
            let mapping = GimbalStickMapping(
                commanded180: row.tt180, selfieFlip: row.selfieFlip ?? false)
            #expect(
                abs(displayedX(0.2, mapping: mapping, mirror: row.mirror) - row.expected) < 1e-9)
        }
    }

    @Test func frontWaypointStillMovesLeftWhenPicturePansRight() {
        let saved = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        let live = GimbalWaypoint(yawDeg: 5, pitchDeg: 0, zoom: 1)
        let mark = GimbalWaypointOverlay.project(
            waypoint: saved, slot: .a, live: live, aspect: 16 / 9)

        #expect(displayedX(mark.nx, mapping: GimbalStickMapping()) < 0.5)
        #expect(displayedX(mark.nx, mapping: GimbalStickMapping(), mirror: true) > 0.5)
    }

    @Test func appRotateChangesOverlayOnlyWhenExistingTT180MappingSettles() {
        var mapping = GimbalStickMapping(yawTenthDeg: 0, poseSeeded: true)
        mapping.noteRotate180()
        mapping.applyAttitude(attitude(901))
        #expect(displayedX(0.2, mapping: mapping) == 0.2)
        mapping.applyAttitude(attitude(1650))
        #expect(displayedX(0.2, mapping: mapping) == 0.8)
        mapping.noteRotate180()
        mapping.applyAttitude(attitude(899))
        #expect(displayedX(0.2, mapping: mapping) == 0.8)
        mapping.applyAttitude(attitude(100))
        #expect(displayedX(0.2, mapping: mapping) == 0.2)
    }

    @Test func manualPanTo180DoesNotBecomeTT180() {
        var mapping = GimbalStickMapping(yawTenthDeg: 0, poseSeeded: true)
        mapping.applyAttitude(attitude(1800))
        #expect(mapping.rotated180)
        #expect(displayedX(0.2, mapping: mapping) == 0.2)
    }

    @Test func bodyFlipAndReconnectUseExistingTT180State() {
        var body = GimbalStickMapping(yawTenthDeg: 0, poseSeeded: true)
        body.noteBodyFace(.front)
        body.noteBodyFace(.selfie)
        #expect(displayedX(0.2, mapping: body) == 0.8)

        var reconnect = GimbalStickMapping()
        reconnect.applyAttitude(attitude(0))
        #expect(displayedX(0.2, mapping: reconnect) == 0.2)
        reconnect.applyAttitude(attitude(-1800))
        #expect(displayedX(0.2, mapping: reconnect) == 0.8)
    }

    @Test func curveSamplesAndClampedEdgesUseTheSameHorizontalTransform() throws {
        let a = GimbalWaypoint(yawDeg: 165, pitchDeg: 0, zoom: 1)
        let b = GimbalWaypoint(yawDeg: 180, pitchDeg: 10, zoom: 1)
        let c = GimbalWaypoint(yawDeg: 200, pitchDeg: 0, zoom: 1)
        let program = GimbalProgram(a: a, b: b, c: c, smoothness: 0.5)
        let curve = try #require(GimbalProgramCurve(program: program))
        let mapping = GimbalStickMapping(commanded180: true)
        for pose in curve.samples() {
            let mark = GimbalWaypointOverlay.project(
                waypoint: pose, slot: .b, live: b, aspect: 16 / 9)
            #expect(abs(displayedX(mark.nx, mapping: mapping) + mark.nx - 1) < 1e-9)
            #expect(abs(displayedX(mark.nx, mapping: mapping, mirror: true) - mark.nx) < 1e-9)
        }
        #expect(displayedX(0, mapping: mapping) == 1)
        #expect(displayedX(1, mapping: mapping) == 0)
        #expect(displayedX(0.5, mapping: mapping) == 0.5)
    }

    private func displayedX(
        _ x: Double, mapping: GimbalStickMapping, mirror: Bool = false
    ) -> Double {
        GimbalWaypointPresentation.normalizedX(
            x, poseInvertPan: mapping.invertPan, assistMirror: mirror)
    }

    private func attitude(_ yaw: Int16) -> [UInt8] {
        let bits = UInt16(bitPattern: yaw)
        return [0, 0, 0, 0, UInt8(truncatingIfNeeded: bits), UInt8(bits >> 8)]
    }
}
