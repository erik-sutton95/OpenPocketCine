import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct CinematicTrackingPursuitTests {
    struct Run {
        var errors: [Double] = []
        var lost = false
        var requestedSpeed = 0.0
        var finalYaw = 0.0
        var finalSpeed = 0.0
        var tailYaws: [Double] = []
        var feedbackLost = false
        var stoppedAt: Double?
        var maxNativeSpeed = 0.0
        var maxStalledLead = 0.0
        var maxTargetStepSpeed = 0.0
    }

    /// Exercises the production controller, quantized command and native mailbox.
    /// The plant deliberately includes video/attitude delay, unlike a static-box test.
    private func follow(
        settings: CinematicTrackingSettings, speed: Double, duration: Double = 7,
        videoDelay: Int = 16, attitudeDelay: Int = 8, attitudeInterval: Int = 4,
        observationInterval: Int = 4, stalledAt: Double? = nil,
        subjectAngle: ((Double) -> Double)? = nil
    ) -> Run {
        var controller = CinematicTrackingController()
        var stream = GimbalNativeTargetStream()
        stream.begin(token: 1)
        var yaw = 0.0
        var target = 0.0
        var history = [Double]()
        var run = Run()
        var pose = GimbalWaypoint(yawDeg: 0, pitchDeg: 0, zoom: 1, nativePitchDeg: 170)
        var poseReceivedAt = 0.0
        var lastEmissionAt: Double?
        let angle = subjectAngle ?? { speed * max(0, $0 - 1) }
        for step in 0..<Int(duration * 100) {
            let now = Double(step) * 0.01
            history.append(yaw)
            let subject = angle(now)
            if step.isMultiple(of: attitudeInterval) {
                pose.yawDeg = (history[max(0, step - attitudeDelay)] * 10).rounded() / 10
                poseReceivedAt = now
            }
            if step.isMultiple(of: observationInterval) {
                let picturedSubject = angle(now - Double(videoDelay) * 0.01)
                let error = picturedSubject - history[max(0, step - videoDelay)]
                let x = 0.5 + tan(error * .pi / 180) / (2 * tan(40 * .pi / 180))
                let box = TrackingBox(x: x - 0.04, y: 0.4, width: 0.08, height: 0.15)
                controller.observe(box: box, measuredAt: now, now: now)
            }
            if step.isMultiple(of: 4) {
                guard
                    let point = controller.target(
                        pose: pose, now: now, settings: settings, pictureAspect: 1.77,
                        invertPan: false,
                        poseReceivedAt: poseReceivedAt),
                    let frame = Commands.gimbalTimedTarget(waypoint: point, duration: 0.1)
                else {
                    run.lost = true
                    run.feedbackLost = controller.feedbackLost
                    run.stoppedAt = now
                    _ = stream.cancel(token: 1)
                    #expect(stream.next(now: now + 0.05) == nil)
                    break
                }
                stream.submit(frame, token: 1, now: now)
                run.requestedSpeed = max(run.requestedSpeed, abs(controller.panSpeed))

            }
            // Native targets drain at 20 Hz from the existing ACK timer.
            if step.isMultiple(of: 5), let frame = stream.next(now: now) {
                let nextTarget =
                    Double(
                        Int16(bitPattern: UInt16(frame.payload[0]) | UInt16(frame.payload[1]) << 8))
                    / 10
                run.maxNativeSpeed = max(run.maxNativeSpeed, abs(nextTarget - yaw) / 0.1)
                if let lastEmissionAt {
                    run.maxTargetStepSpeed = max(
                        run.maxTargetStepSpeed,
                        abs(nextTarget - target) / (now - lastEmissionAt))
                }
                lastEmissionAt = now
                target = nextTarget
            }
            if let stalledAt, now >= stalledAt {
                run.maxStalledLead = max(run.maxStalledLead, abs(target - yaw))
            } else {
                yaw += (target - yaw) * (1 - exp(-0.01 / 0.1))
            }
            if now >= 3 { run.errors.append(abs(subject - yaw)) }
            if now >= duration - 2 { run.tailYaws.append(yaw) }
        }
        run.finalYaw = yaw
        run.finalSpeed = controller.panSpeed
        return run
    }

    @Test func highSpeedLimitCanKeepAContinuouslyMovingSubjectFramed() {
        for preset in CinematicTrackingSettings.Preset.allCases {
            var settings = CinematicTrackingSettings.preset(preset)
            settings.maxSpeed = 90
            let run = follow(settings: settings, speed: 12)
            let meanError = run.errors.reduce(0, +) / Double(max(1, run.errors.count))
            #expect(!run.lost, "\(preset): subject must stay in view")
            #expect(
                meanError < 10,
                "\(preset): moving subject trails by \(meanError) degrees despite a 90°/s cap")
        }
    }

    @Test func matchingKeepsPaceWithoutNeedingLargePersistentError() {
        for preset in CinematicTrackingSettings.Preset.allCases {
            var settings = CinematicTrackingSettings.preset(preset)
            settings.maxSpeed = 90
            let matching = follow(settings: settings, speed: 12)
            settings.motionMatching = 0
            let trailing = follow(settings: settings, speed: 12)
            let matchedError = matching.errors.reduce(0, +) / Double(max(1, matching.errors.count))
            let trailingError = trailing.errors.reduce(0, +) / Double(max(1, trailing.errors.count))
            #expect(matchedError < trailingError * 0.6)
        }
    }

    @Test func responsiveCanFollowFasterMovementAndStopAfterReversal() {
        var settings = CinematicTrackingSettings.preset(.responsive)
        settings.maxSpeed = 90
        let fast = follow(settings: settings, speed: 24)
        #expect(!fast.lost)
        let error = fast.errors.reduce(0, +) / Double(max(1, fast.errors.count))
        #expect(error < 8)
        let reversing = follow(settings: settings, speed: 24, duration: 12) { time in
            if time < 1 { return 0 }
            if time < 3.5 { return (time - 1) * 24 }
            if time < 4.5 { return 60 }
            if time < 7 { return 60 - (time - 4.5) * 24 }
            return 0
        }
        #expect(!reversing.lost)
        #expect(abs(reversing.finalYaw) < 4)
        #expect(abs(reversing.finalSpeed) < 0.5)
    }

    @Test func sparseDelayedAttitudeAndThermalCadenceStillFollowWithoutStationaryOscillation() {
        for delay in [8, 16, 24] {
            for video in [12, 20, 28] {
                for observations in [4, 20] {
                    var settings = CinematicTrackingSettings.preset(.balanced)
                    settings.maxSpeed = 90
                    let moving = follow(
                        settings: settings, speed: 12, videoDelay: video, attitudeDelay: delay,
                        attitudeInterval: 10, observationInterval: observations)
                    let error = moving.errors.reduce(0, +) / Double(max(1, moving.errors.count))
                    #expect(!moving.lost)
                    #expect(
                        error < 12,
                        "video \(video), attitude \(delay), cadence \(observations): error \(error)"
                    )
                    let still = follow(
                        settings: settings, speed: 0, duration: 16, videoDelay: video,
                        attitudeDelay: delay,
                        attitudeInterval: 10, observationInterval: observations,
                        subjectAngle: { _ in 18 })
                    #expect(!still.lost)
                    let spread = (still.tailYaws.max() ?? 0) - (still.tailYaws.min() ?? 0)
                    #expect(
                        spread < 1,
                        "Stationary oscillation with video \(video), attitude \(delay), cadence \(observations): \(spread)"
                    )
                }
            }
        }
    }

    @Test func delayedAttitudeDoesNotTurnNinetyDegreeSpeedLimitIntoATwentyDegreeLimit() {
        var settings = CinematicTrackingSettings.preset(.responsive)
        settings.maxSpeed = 90
        let run = follow(
            settings: settings, speed: 40, duration: 5, videoDelay: 16, attitudeDelay: 24,
            attitudeInterval: 10)
        let error = run.errors.reduce(0, +) / Double(max(1, run.errors.count))
        #expect(!run.lost)
        #expect(error < 12, "A 90°/s trajectory ceiling must permit 40°/s pursuit; error \(error)")
    }

    @Test func encodedFastReversalsRemainContinuousAndDelayedStallsEndTheTake() {
        var settings = CinematicTrackingSettings.preset(.responsive)
        settings.maxSpeed = 90
        // Reverse both ways within the physical pan sector. Inspect real encoded
        // targets, not only the controller's internal speed variables.
        let reversal = follow(
            settings: settings, speed: 40, duration: 19,
            attitudeDelay: 24, attitudeInterval: 10
        ) { time in
            let phase = min(max(0, time - 1), 4 * Double.pi)
            return 40 * (1 - cos(phase))  // Continuous turns; peak velocity 40°/s.
        }
        #expect(!reversal.lost)
        // Quantization and the 25Hz->20Hz mailbox can merge two trajectory steps.
        #expect(reversal.maxTargetStepSpeed <= settings.maxSpeed * 1.6 + 2)
        #expect(reversal.maxNativeSpeed < settings.maxSpeed * 1.6)
        #expect(abs(reversal.finalYaw) < 4)
        #expect(abs(reversal.finalSpeed) < 0.5)
        let stalled = follow(
            settings: settings, speed: 40, duration: 7,
            attitudeDelay: 24, attitudeInterval: 10, stalledAt: 3
        ) { time in
            min(80, 40 * max(0, time - 1))
        }
        #expect(stalled.feedbackLost)
        #expect((stalled.stoppedAt ?? .infinity) < 4.2)
        let bound = settings.maxSpeed * (CinematicTrackingFeedback.allowedLag + 0.1 + 0.1) + 0.3
        #expect(stalled.maxStalledLead <= bound)
    }

}
