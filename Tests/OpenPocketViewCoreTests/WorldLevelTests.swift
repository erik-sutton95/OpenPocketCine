import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct WorldLevelTests {
    /// Captured `0x04/0x05` payloads (2026-09-12 reliability logs) and the tilt of the fit.
    static let fixtures: [(hex: String, tilt: Double)] = [
        ("F606000006008600FAFF00020E6DBE041EBA0000EAFF0400EA71193910F57F3F41C41B3C7F917FBC00000000010000000000", 1.788),
        ("5B0500002AFF8600D3000002965BC9057BBD000056FE0200382CF83C23B86D3F15519F3DBC22B9BE00000000000000000005", 42.552),
        ("5EF900000E008600F4FF0002D20CBF0470BE00006A0035006FF1173C92967DBFC5AFD6BD7077B3BD00000000000000000005", -10.111),
        ("0807000000008600000000020219CD05B3C5000000000200AA10D73532D7763F15BB873E1FB8B43600000000010000000000", -0.001),
    ]

    static func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    /// World→camera pose: look-up `tilt`, then `roll` about the lens.
    static func payload(tilt: Double, roll: Double = 0, count: Int = 50) -> [UInt8] {
        let q = HeadTrack.Quat.axisAngle(x: 1, y: 0, z: 0, deg: -roll)
            .multiply(HeadTrack.Quat.axisAngle(x: 0, y: 0, z: 1, deg: -tilt))
        return payload(w: q.w, x: q.x, y: q.y, z: q.z, count: count)
    }

    static func payload(w: Double, x: Double, y: Double, z: Double, count: Int = 50) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: count)
        for (offset, v) in [(24, x), (28, w), (32, y), (36, z)] where offset + 4 <= count {
            let bits = Float(v).bitPattern
            for k in 0..<4 { p[offset + k] = UInt8((bits >> (8 * UInt32(k))) & 0xFF) }
        }
        return p
    }

    static func gauges(_ mode: LevelReading.Mode) -> (roll: Double, tilt: Double)? {
        if case let .gauges(roll, tilt) = mode { return (roll, tilt) }
        return nil
    }

    static func bubble(_ mode: LevelReading.Mode) -> (x: Double, y: Double)? {
        if case let .bubble(x, y) = mode { return (x, y) }
        return nil
    }

    @Test func capturedFramesDecodeToFittedTiltWithLevelRoll() throws {
        for fixture in Self.fixtures {
            var reading = LevelReading()
            reading.ingest(Self.bytes(fixture.hex), now: 1)
            let g = try #require(Self.gauges(reading.mode(now: 1, viewFlip: false)))
            #expect(abs(g.tilt - fixture.tilt) < 0.01)
            #expect(abs(g.roll) < 0.01)
        }
    }

    @Test func rejectsShortNonFiniteAndNonUnitQuaternions() {
        #expect(WorldLevel.attitude(Self.payload(tilt: 0, count: 39)) == nil)
        #expect(WorldLevel.attitude(Self.payload(w: .nan, x: 0, y: 0, z: 0)) == nil)
        #expect(WorldLevel.attitude(Self.payload(w: 1.01, x: 0, y: 0, z: 0)) == nil)
        #expect(WorldLevel.attitude(Self.payload(tilt: 0)) != nil)
    }

    @Test func rollFollowsThePictureFlip() throws {
        var reading = LevelReading()
        reading.ingest(Self.payload(tilt: 0, roll: 5), now: 1)
        let plain = try #require(Self.gauges(reading.mode(now: 1, viewFlip: false)))
        let flipped = try #require(Self.gauges(reading.mode(now: 1, viewFlip: true)))
        #expect(abs(plain.roll - 5) < 0.01)
        #expect(abs(flipped.roll + 5) < 0.01)
    }

    @Test func bubbleTakesOverNearPlumbWithHysteresis() {
        var reading = LevelReading()
        var t = 0.0
        func feed(_ tilt: Double) -> LevelReading.Mode {
            // Settle the smoothing on one pose before judging it.
            for _ in 0..<40 {
                t += 0.1
                reading.ingest(Self.payload(tilt: tilt), now: t)
            }
            return reading.mode(now: t, viewFlip: false)
        }
        #expect(Self.gauges(feed(-59)) != nil)
        #expect(Self.gauges(feed(-62)) != nil)
        #expect(Self.bubble(feed(-70)) != nil)
        #expect(Self.bubble(feed(-62)) != nil)
        #expect(Self.gauges(feed(-59)) != nil)
    }

    @Test func bubbleReadsOffsetFromPlumbInPictureAxes() throws {
        for (tilt, roll, x, y) in [(-88.0, 0.0, 0.0, 2.0), (-92.0, 0.0, 0.0, -2.0), (88.0, 0.0, 0.0, 2.0)] {
            var reading = LevelReading()
            reading.ingest(Self.payload(tilt: tilt, roll: roll), now: 1)
            reading.ingest(Self.payload(tilt: tilt, roll: roll), now: 1)
            let b = try #require(Self.bubble(reading.mode(now: 1, viewFlip: false)))
            #expect(abs(b.x - x) < 0.01)
            #expect(abs(b.y - y) < 0.01)
        }
        var lateral = LevelReading()
        let q = HeadTrack.Quat.axisAngle(x: 0, y: 1, z: 0, deg: 3)
            .multiply(HeadTrack.Quat.axisAngle(x: 0, y: 0, z: 1, deg: 90))
        lateral.ingest(Self.payload(w: q.w, x: q.x, y: q.y, z: q.z), now: 1)
        let plain = try #require(Self.bubble(lateral.mode(now: 1, viewFlip: false)))
        let flipped = try #require(Self.bubble(lateral.mode(now: 1, viewFlip: true)))
        #expect(abs(plain.x) > 2.9)
        #expect(abs(plain.x + flipped.x) < 1e-9)
    }

    @Test func goesUnavailableWithoutFreshSamples() {
        var reading = LevelReading()
        #expect(reading.mode(now: 0, viewFlip: false) == .unavailable)
        reading.ingest(Self.payload(tilt: 0), now: 10)
        #expect(reading.mode(now: 10.9, viewFlip: false) != .unavailable)
        #expect(reading.mode(now: 11.01, viewFlip: false) == .unavailable)
        #expect(reading.tiltDeg(now: 11.01) == nil)
        reading.ingest(Self.payload(tilt: 0, count: 30), now: 11.5)
        #expect(reading.mode(now: 11.5, viewFlip: false) == .unavailable)
    }

    @Test func smoothingMovesThirtyPercentTowardANewSampleAtMostTenHertz() throws {
        var reading = LevelReading()
        reading.ingest(Self.payload(tilt: 0), now: 1)
        reading.ingest(Self.payload(tilt: 10), now: 1.02)
        #expect(abs(try #require(reading.tiltDeg(now: 1.02))) < 1e-6)
        reading.ingest(Self.payload(tilt: 10), now: 1.1)
        let r = 10 * Double.pi / 180
        let expected = atan2(0.3 * sin(r), 0.7 + 0.3 * cos(r)) * 180 / .pi
        #expect(abs(try #require(reading.tiltDeg(now: 1.1)) - expected) < 1e-3)
    }

    @Test func nearestTargetSplitsAtFortyFiveDegrees() {
        #expect(WorldLevelTarget.nearest(tiltDeg: 44.9) == .horizon)
        #expect(WorldLevelTarget.nearest(tiltDeg: -44.9) == .horizon)
        #expect(WorldLevelTarget.nearest(tiltDeg: -45) == .plumbDown)
        #expect(WorldLevelTarget.nearest(tiltDeg: 45) == .plumbUp)
    }

    @Test func snapPlansOneTimedTargetFromTheLiveNativePitch() throws {
        // Captured relation: native = 180 − look-up tilt (wrapped).
        let pose = GimbalWaypoint(yawDeg: 12, pitchDeg: -60, zoom: 1, nativePitchDeg: -120)
        let (snap, frame) = try #require(WorldLevelSnap.plan(tiltDeg: -60, pose: pose, now: 5))
        #expect(snap.target == .plumbDown)
        #expect(frame.cmdSet == 4 && frame.cmdId == 0x14)
        let expected = try #require(
            Commands.gimbalTimedTarget(yawDeg: 12, nativePitchDeg: -90, duration: 1.5))
        #expect(frame.payload == expected.payload)
        #expect(snap.deadline == 5 + 1.5 + 1.5)

        let wrap = GimbalWaypoint(yawDeg: 0, pitchDeg: 2, zoom: 1, nativePitchDeg: 178)
        let (_, level) = try #require(WorldLevelSnap.plan(tiltDeg: 2, pose: wrap, now: 0))
        let levelExpected = try #require(
            Commands.gimbalTimedTarget(yawDeg: 0, nativePitchDeg: 180, duration: 0.5))
        #expect(level.payload == levelExpected.payload)

        let longMove = GimbalWaypoint(yawDeg: 0, pitchDeg: 80, zoom: 1, nativePitchDeg: 100)
        #expect(try #require(WorldLevelSnap.plan(tiltDeg: 80, pose: longMove, now: 0)).snap.target == .plumbUp)
    }

    @Test func snapRefusesWithoutNativePitchOrReachableYaw() {
        let noNative = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1)
        #expect(WorldLevelSnap.plan(tiltDeg: 3, pose: noNative, now: 0) == nil)
        let gap = GimbalWaypoint(yawDeg: -100, pitchDeg: 0, zoom: 1, nativePitchDeg: 180)
        #expect(WorldLevelSnap.plan(tiltDeg: 3, pose: gap, now: 0) == nil)
    }

    @Test func snapJudgesArrivalTimeoutAndStaleReadings() throws {
        let pose = GimbalWaypoint(yawDeg: 0, pitchDeg: -80, zoom: 1, nativePitchDeg: -100)
        let snap = try #require(WorldLevelSnap.plan(tiltDeg: -80, pose: pose, now: 0)).snap
        #expect(snap.evaluate(tiltDeg: -85, now: 0.5) == .pending)
        #expect(snap.evaluate(tiltDeg: -89.6, now: 0.6) == .arrived)
        #expect(snap.evaluate(tiltDeg: -87.7, now: snap.deadline) == .failed(errorDeg: 2.3))
        #expect(snap.evaluate(tiltDeg: nil, now: 0.7) == .failed(errorDeg: nil))
    }

    @Test func doubleTapDefaultsToRecenter() {
        #expect(GimbalDoubleTap.pickerOrder == [.recenter, .level])
        #expect(GimbalDoubleTap(rawValue: 0) == .recenter)
        #expect(GimbalDoubleTap.level.label == "Level")
    }

    @Test func freshSampleAfterAGapIsNotBlendedWithStaleGravity() throws {
        var reading = LevelReading()
        reading.ingest(Self.payload(tilt: 0), now: 1)
        reading.ingest(Self.payload(tilt: 10), now: 3)
        #expect(abs(try #require(reading.tiltDeg(now: 3)) - 10) < 1e-6)
        var bubble = LevelReading()
        bubble.ingest(Self.payload(tilt: -70), now: 1)
        bubble.ingest(Self.payload(tilt: -62), now: 3)
        #expect(Self.gauges(bubble.mode(now: 3, viewFlip: false)) != nil)
    }

    @Test func pitchIsUnfoldedPastPlumbForTheSnap() throws {
        var reading = LevelReading()
        reading.ingest(Self.payload(tilt: -92), now: 1)
        #expect(abs(try #require(reading.tiltDeg(now: 1)) + 88) < 0.01)
        let pitch = try #require(reading.pitchDeg(now: 1))
        #expect(abs(pitch + 92) < 0.01)
        #expect(reading.pitchDeg(now: 2.5) == nil)
        // Past nadir the lens must come back up: native pitch decreases.
        let pose = GimbalWaypoint(yawDeg: 0, pitchDeg: -92, zoom: 1, nativePitchDeg: -88)
        let (snap, frame) = try #require(WorldLevelSnap.plan(tiltDeg: pitch, pose: pose, now: 0))
        #expect(snap.target == .plumbDown)
        let expected = try #require(
            Commands.gimbalTimedTarget(yawDeg: 0, nativePitchDeg: -90, duration: 0.5))
        #expect(frame.payload == expected.payload)
        #expect(snap.evaluate(tiltDeg: -90.3, now: 0.2) == .arrived)
    }

    @Test func snapExpiresInsteadOfJudgingLongAfterItsDeadline() throws {
        let pose = GimbalWaypoint(yawDeg: 0, pitchDeg: -80, zoom: 1, nativePitchDeg: -100)
        let snap = try #require(WorldLevelSnap.plan(tiltDeg: -80, pose: pose, now: 0)).snap
        #expect(snap.evaluate(tiltDeg: -85, now: snap.deadline + 0.5) == .failed(errorDeg: 5))
        #expect(snap.evaluate(tiltDeg: -85, now: snap.deadline + 1.01) == .expired)
        #expect(snap.evaluate(tiltDeg: -90, now: snap.deadline + 60) == .expired)
    }
}
