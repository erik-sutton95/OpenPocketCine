import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct CinematicTrackingTests {
    private let pose = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 170)

    private func box(x: Double = 0.5, y: Double = 0.5) -> TrackingBox {
        TrackingBox(x: x - 0.05, y: y - 0.05, width: 0.1, height: 0.1)
    }

    @Test func rawPanMappingCancelsDisplayMirrorExactlyOnce() {
        #expect(
            !CinematicTrackingController.rawPanInverted(
                poseInverted: false, cameraViewMirrored: false))
        #expect(
            CinematicTrackingController.rawPanInverted(
                poseInverted: true, cameraViewMirrored: false))
        #expect(
            !CinematicTrackingController.rawPanInverted(
                poseInverted: true, cameraViewMirrored: true))
        #expect(
            CinematicTrackingController.rawPanInverted(
                poseInverted: false, cameraViewMirrored: true))
    }

    @Test func quietZoneRejectsStationaryJitter() throws {
        var controller = CinematicTrackingController()
        for tick in 0..<100 {
            let now = Double(tick) * 0.04
            controller.observe(box: box(x: 0.5 + sin(now * 15) * 0.04), measuredAt: now, now: now)
            let target = try #require(
                {
                    controller.target(
                        pose: pose, now: now, settings: .init(), pictureAspect: 16.0 / 9,
                        invertPan: false)
                }())
            #expect(target == pose)
        }
    }

    @Test func stepAndReversalRespectMotionLimits() throws {
        var controller = CinematicTrackingController()
        var settings = CinematicTrackingSettings.preset(.responsive)
        settings.maxSpeed = 18
        settings.maxAcceleration = 20
        settings.maxJerk = 60
        var live = pose
        var previousSpeed = 0.0
        var previousAcceleration = 0.0
        for tick in 0..<300 {
            let now = Double(tick) * 0.04
            controller.observe(box: box(x: tick < 150 ? 0.9 : 0.1), measuredAt: now, now: now)
            let target = try #require(
                {
                    controller.target(
                        pose: live, now: now, settings: settings, pictureAspect: 16.0 / 9,
                        invertPan: false)
                }())
            #expect(abs(controller.panSpeed) <= settings.maxSpeed)
            #expect(abs(controller.panAcceleration) <= settings.maxAcceleration)
            #expect(
                abs(controller.panSpeed - previousSpeed) <= settings.maxAcceleration * 0.04 + 1e-8)
            #expect(
                abs(controller.panAcceleration - previousAcceleration) <= settings.maxJerk * 0.04
                    + 1e-8)
            #expect(abs(target.yawDeg - live.yawDeg) <= settings.maxSpeed * 0.04 + 1e-8)
            live = target
            previousSpeed = controller.panSpeed
            previousAcceleration = controller.panAcceleration
        }
        #expect(controller.panSpeed < -1)
    }

    @Test func subDegreeMotionSurvivesNativeCommandQuantization() throws {
        var controller = CinematicTrackingController()
        var settings = CinematicTrackingSettings.preset(.responsive)
        settings.sensitivity = 0.1
        settings.deadBand = 0
        settings.lerp = 0
        var furthest = 0.0
        for tick in 0..<100 {
            let now = Double(tick) * 0.04
            controller.observe(box: box(x: 0.52), measuredAt: now, now: now)
            let target = try #require(
                {
                    controller.target(
                        pose: pose, now: now, settings: settings, pictureAspect: 1.77,
                        invertPan: false)
                }())
            #expect(abs(controller.panSpeed) < 0.5)
            let encoded = try #require(Commands.gimbalTimedTarget(waypoint: target, duration: 0.1))
            let origin = try #require(Commands.gimbalTimedTarget(waypoint: pose, duration: 0.1))
            if tick > 70 { #expect(encoded.payload != origin.payload) }
            furthest = max(furthest, target.yawDeg)
        }
        #expect(furthest > 0.1)
    }

    @Test func laggingFeedbackCannotAccumulateACommandAboveSpeedCap() throws {
        for speed in [1.0, 1.5, 18.0, 60.0] {
            var controller = CinematicTrackingController()
            var settings = CinematicTrackingSettings.preset(.responsive)
            settings.maxSpeed = speed
            for tick in 0..<150 {
                let now = Double(tick) * 0.04
                controller.observe(box: box(x: 0.9), measuredAt: now, now: now)
                let result = controller.target(
                    pose: pose, now: now, settings: settings, pictureAspect: 1.77, invertPan: false)
                let target = try #require(result)
                let encoded = try #require(
                    Commands.gimbalTimedTarget(waypoint: target, duration: 0.1))
                let yaw =
                    Double(
                        Int16(
                            bitPattern: UInt16(encoded.payload[0]) | UInt16(encoded.payload[1]) << 8
                        )) / 10
                #expect(abs(yaw - pose.yawDeg) / 0.1 <= speed + 1e-8)
            }
        }
    }

    @Test func staleMeasurementsAndSchedulerGapsResetMotion() throws {
        var controller = CinematicTrackingController()
        #expect({ !controller.observe(box: box(), measuredAt: 1, now: 1.3) }())
        #expect({ !controller.observe(box: box(), measuredAt: 2, now: 1) }())
        #expect({ controller.observe(box: box(x: 0.8), measuredAt: 1, now: 1) }())
        #expect({ !controller.observe(box: box(x: 0.8), measuredAt: 1, now: 1.1) }())
        _ = try #require(
            {
                controller.target(
                    pose: pose, now: 1, settings: .init(), pictureAspect: 1.77, invertPan: false)
            }())
        #expect(
            {
                controller.target(
                    pose: pose, now: 1.3, settings: .init(), pictureAspect: 1.77, invertPan: false)
                    == nil
            }())
        #expect(controller.panSpeed == 0)
        controller.observe(box: box(x: 0.8), measuredAt: 2, now: 2)
        _ = controller.target(
            pose: pose, now: 2, settings: .init(), pictureAspect: 1.77, invertPan: false)
        controller.observe(box: box(x: 0.8), measuredAt: 2.2, now: 2.2)
        #expect(
            {
                controller.target(
                    pose: pose, now: 2.2, settings: .init(), pictureAspect: 1.77, invertPan: false)
                    == nil
            }())
    }

    @Test func mirrorPitchNativeReferenceAndAxisLocks() throws {
        var normal = CinematicTrackingController()
        var mirrored = CinematicTrackingController()
        var locked = CinematicTrackingController()
        var settings = CinematicTrackingSettings()
        settings.panEnabled = false
        for tick in 0..<50 {
            let now = Double(tick) * 0.04
            do {
                normal.observe(box: box(x: 0.8, y: 0.2), measuredAt: now, now: now)
                mirrored.observe(box: box(x: 0.8, y: 0.2), measuredAt: now, now: now)
                locked.observe(box: box(x: 0.8, y: 0.2), measuredAt: now, now: now)
            }
            let a = try #require(
                {
                    normal.target(
                        pose: pose, now: now, settings: .init(), pictureAspect: 1.77,
                        invertPan: false)
                }())
            let b = try #require(
                {
                    mirrored.target(
                        pose: pose, now: now, settings: .init(), pictureAspect: 1.77,
                        invertPan: true)
                }())
            let c = try #require(
                {
                    locked.target(
                        pose: pose, now: now, settings: settings, pictureAspect: 1.77,
                        invertPan: false)
                }())
            #expect(a.yawDeg > 0 && b.yawDeg == -a.yawDeg)
            #expect(a.pitchDeg > 0 && a.pitchDeg == b.pitchDeg)
            #expect(abs(try #require(a.nativePitchDeg) - (170 - a.pitchDeg)) < 1e-8)
            #expect(c.yawDeg == 0 && locked.panSpeed == 0)
        }
    }

    @Test func stopsCannotAccumulateWindupOrCrossMissingPanSector() throws {
        var controller = CinematicTrackingController()
        let edge = GimbalWaypoint(yawDeg: 225, pitchDeg: 70, zoom: 1, nativePitchDeg: 100)
        for tick in 0..<80 {
            let now = Double(tick) * 0.04
            controller.observe(box: box(x: 0.9, y: 0.1), measuredAt: now, now: now)
            let target = try #require(
                {
                    controller.target(
                        pose: edge, now: now, settings: .init(), pictureAspect: 1.77,
                        invertPan: false)
                }())
            #expect(target == edge)
            #expect(controller.panSpeed == 0 && controller.tiltSpeed == 0)
        }
    }

    @Test func invalidInputsAndIdentityJumpsAreRejected() {
        #expect(
            !CinematicTrackingController.usable(TrackingBox(x: .nan, y: 0, width: 0.1, height: 0.1))
        )
        #expect(
            !CinematicTrackingController.usable(TrackingBox(x: 0.99, y: 0, width: 0.1, height: 0.1))
        )
        #expect(
            !CinematicTrackingController.continuous(from: box(x: 0.2), to: box(x: 0.8), dt: 0.07))
        #expect(
            CinematicTrackingController.continuous(from: box(x: 0.4), to: box(x: 0.42), dt: 0.07))
        var controller = CinematicTrackingController()
        controller.observe(box: box(x: 0.8), measuredAt: 0, now: 0)
        var settings = CinematicTrackingSettings()
        settings.lerp = .nan
        #expect(
            {
                controller.target(
                    pose: pose, now: 0, settings: settings, pictureAspect: 1.77, invertPan: false)
                    == nil
            }())
    }

    @Test func lerpAndSmoothnessReduceEarlyMotionAndRespectElapsedTime() {
        func response(dt: Double, settings: CinematicTrackingSettings, zoom: Double = 1) -> Double {
            var controller = CinematicTrackingController()
            var current = pose
            current.zoom = zoom
            for tick in 0..<Int((0.8 / dt).rounded()) {
                let now = Double(tick) * dt
                controller.observe(box: box(x: 0.7), measuredAt: now, now: now)
                if let target = controller.target(
                    pose: current, now: now, settings: settings, pictureAspect: 1.77,
                    invertPan: false)
                {
                    current = target
                }
            }
            return controller.panSpeed
        }
        var fast = CinematicTrackingSettings.preset(.responsive)
        fast.lerp = 0
        var slow = fast
        slow.lerp = 0.6
        slow.smoothness = 0.8
        #expect(response(dt: 0.04, settings: slow) < response(dt: 0.04, settings: fast))
        #expect(abs(response(dt: 0.04, settings: slow) - response(dt: 0.02, settings: slow)) < 0.2)
        #expect(response(dt: 0.04, settings: fast, zoom: 3) < response(dt: 0.04, settings: fast))
        for preset in CinematicTrackingSettings.Preset.allCases {
            #expect(CinematicTrackingSettings.preset(preset).isValid)
        }
    }
}
