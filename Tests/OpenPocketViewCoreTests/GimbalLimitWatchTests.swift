import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct GimbalLimitWatchTests {
    @Test func holdWithoutMotionDoesNotPulse() {
        var watch = GimbalLimitWatch()
        var now: TimeInterval = 0
        var saw = GimbalLimitWatch.Contact()
        for _ in 0..<10 {
            now += 0.1
            saw.formUnion(tick(watch: &watch, x: 1, y: 0, yaw: 0, pitch: 0, now: now))
        }
        #expect(saw.isEmpty)
    }

    @Test func panPulsesAfterMoveThenStop() {
        var watch = GimbalLimitWatch()
        var now: TimeInterval = 0
        var yaw: Int16 = 0
        for _ in 0..<4 {
            now += 0.1
            yaw += 40
            #expect(tick(watch: &watch, x: 1, y: 0, yaw: yaw, pitch: 0, now: now).isEmpty)
        }
        var saw = GimbalLimitWatch.Contact()
        for _ in 0..<5 {
            now += 0.1
            saw.formUnion(tick(watch: &watch, x: 1, y: 0, yaw: yaw, pitch: 0, now: now))
        }
        #expect(saw.contains(.pan))
        #expect(!saw.contains(.tilt))
        now += 0.1
        #expect(tick(watch: &watch, x: 1, y: 0, yaw: yaw, pitch: 0, now: now).isEmpty)
        yaw += 40
        now += 0.1
        #expect(tick(watch: &watch, x: 1, y: 0, yaw: yaw, pitch: 0, now: now).isEmpty)
        var again = GimbalLimitWatch.Contact()
        for _ in 0..<5 {
            now += 0.1
            again.formUnion(tick(watch: &watch, x: 1, y: 0, yaw: yaw, pitch: 0, now: now))
        }
        #expect(again.contains(.pan))
    }

    @Test func tiltPulsesAfterPitchMovesThenStops() {
        var watch = GimbalLimitWatch()
        var now: TimeInterval = 0
        var pitch: Int16 = 0
        for _ in 0..<4 {
            now += 0.1
            pitch += 30
            #expect(tick(watch: &watch, x: 0, y: 1, yaw: 0, pitch: pitch, now: now).isEmpty)
        }
        var saw = GimbalLimitWatch.Contact()
        for _ in 0..<5 {
            now += 0.1
            saw.formUnion(tick(watch: &watch, x: 0, y: 1, yaw: 0, pitch: pitch, now: now))
        }
        #expect(saw.contains(.tilt))
        #expect(!saw.contains(.pan))
        #expect(watch.lastTiltSign == 1)
    }

    @Test func restClearsContact() {
        var watch = GimbalLimitWatch()
        var now: TimeInterval = 0
        var yaw: Int16 = 0
        for _ in 0..<4 {
            now += 0.1
            yaw += 40
            _ = tick(watch: &watch, x: -1, y: 0, yaw: yaw, pitch: 0, now: now)
        }
        for _ in 0..<5 {
            now += 0.1
            _ = tick(watch: &watch, x: -1, y: 0, yaw: yaw, pitch: 0, now: now)
        }
        now += 0.1
        #expect(tick(watch: &watch, x: 0, y: 0, yaw: yaw, pitch: 0, now: now).isEmpty)
        yaw = 0
        for _ in 0..<4 {
            now += 0.1
            yaw -= 40
            _ = tick(watch: &watch, x: -1, y: 0, yaw: yaw, pitch: 0, now: now)
        }
        var saw = GimbalLimitWatch.Contact()
        for _ in 0..<5 {
            now += 0.1
            saw.formUnion(tick(watch: &watch, x: -1, y: 0, yaw: yaw, pitch: 0, now: now))
        }
        #expect(saw.contains(.pan))
        #expect(watch.lastPanSign == -1)
    }

    @Test func settling180SkipsPan() {
        var watch = GimbalLimitWatch()
        var now: TimeInterval = 0
        var yaw: Int16 = 0
        var saw = GimbalLimitWatch.Contact()
        for _ in 0..<4 {
            now += 0.1
            yaw += 80
            saw.formUnion(
                watch.tick(
                    x: 1, y: 0, yawTenthDeg: yaw, pitchTenthDeg: 0, now: now, settling180: true))
        }
        for _ in 0..<5 {
            now += 0.1
            saw.formUnion(
                watch.tick(
                    x: 1, y: 0, yawTenthDeg: yaw, pitchTenthDeg: 0, now: now, settling180: true))
        }
        #expect(saw.isEmpty)
    }

    @Test func missingAttitudeDoesNotPulse() {
        var watch = GimbalLimitWatch()
        var now: TimeInterval = 0
        var saw = GimbalLimitWatch.Contact()
        for _ in 0..<8 {
            now += 0.1
            saw.formUnion(
                watch.tick(
                    x: 1, y: 1, yawTenthDeg: nil, pitchTenthDeg: nil, now: now, settling180: false))
        }
        #expect(saw.isEmpty)
    }

    @Test func triggerZoomIsHoldToRate() {
        #expect(CamFov.zoomStep(current: 1, y: 0, dt: 1, max: 12) == 1)
        #expect(
            abs(CamFov.zoomStep(current: 1, y: 1, dt: 1, max: 12) - (1 + CamFov.zoomRatePerSecond))
                < 0.001)
        let crawl = CamFov.zoomStep(current: 1, y: 0.2, dt: 1, max: 12)
        let full = CamFov.zoomStep(current: 1, y: 1, dt: 1, max: 12)
        #expect(crawl > 1)
        #expect(crawl < full)
        #expect(CamFov.zoomStep(current: 6, y: -1, dt: 1, max: 12) < 6)
        #expect(CamFov.zoomStep(current: 12, y: 1, dt: 1, max: 12) == 12)
        #expect(CamFov.zoomStep(current: 1, y: -1, dt: 1, max: 12) == 1)
        #expect(CamFov.triggerZoomAxis(left: 0, right: 1) == 1)
        #expect(CamFov.triggerZoomAxis(left: 1, right: 0) == -1)
        #expect(GimbalStick.linearThrow(0.04) == 0)
    }

    private func tick(
        watch: inout GimbalLimitWatch, x: Double, y: Double, yaw: Int16, pitch: Int16,
        now: TimeInterval
    ) -> GimbalLimitWatch.Contact {
        watch.tick(
            x: x, y: y, yawTenthDeg: yaw, pitchTenthDeg: pitch, now: now, settling180: false)
    }
}
