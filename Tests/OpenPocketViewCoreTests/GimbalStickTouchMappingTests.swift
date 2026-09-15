import Foundation
import OpenPocketViewCore
import Testing

@Suite
struct GimbalStickTouchMappingTests {
    private let stick: Double = 100
    private let knob: Double = 40

    private var outer: Double { stick / 2 }
    private var travel: Double { (stick - knob) / 2 }
    private var commandRadius: Double { 1.35 * outer }

    private func map(
        dx: Double, dy: Double, engaged: Bool = false
    ) -> GimbalStick.TouchMapping {
        GimbalStick.mapTouch(
            dx: dx, dy: dy, stickSize: stick, knobSize: knob, engaged: engaged)
    }

    @Test func visibleRingMapsToCommandOverOuterRadius() {
        let ring = map(dx: outer, dy: 0)
        #expect(abs(ring.commandX - (1 / 1.35)) < 1e-12)
        #expect(ring.commandY == 0)
        #expect(abs(ring.visualX - travel) < 1e-12)
        #expect(ring.visualY == 0)
        #expect(ring.emit)
        #expect(ring.engaged)
        #expect(!ring.isTap)
    }

    @Test func fullCommandRadiusIsOneAndVisualStaysAtKnobTravel() {
        let full = map(dx: commandRadius, dy: 0)
        #expect(abs(full.commandX - 1) < 1e-12)
        #expect(full.commandY == 0)
        #expect(abs(full.visualX - travel) < 1e-12)
        #expect(full.visualY == 0)

        let ring = map(dx: outer, dy: 0)
        #expect(ring.visualX == full.visualX)
        #expect(ring.commandX < full.commandX)
    }

    @Test func beyondCommandRadiusClampsRadiallyOnDiagonal() {
        let beyond = map(dx: 200, dy: 200)
        #expect(abs(hypot(beyond.commandX, beyond.commandY) - 1) < 1e-12)
        #expect(abs(beyond.commandX + beyond.commandY) < 1e-12)
        #expect(beyond.commandX > 0)
        #expect(beyond.commandY < 0)
        #expect(abs(hypot(beyond.visualX, beyond.visualY) - travel) < 1e-12)
        #expect(beyond.visualX > 0)
        #expect(beyond.visualY > 0)
    }

    @Test func responseCurvesDivergeAtVisibleRing() {
        let n = map(dx: outer, dy: 0).commandX
        let linear = GimbalStick.analogCurve(n, expo: GimbalStick.ResponseCurve.linear.expo)
        let standard = GimbalStick.analogCurve(n, expo: GimbalStick.ResponseCurve.standard.expo)
        let fine = GimbalStick.analogCurve(n, expo: GimbalStick.ResponseCurve.fine.expo)
        #expect(linear < 1)
        #expect(linear > standard)
        #expect(standard > fine)
    }

    @Test func engagedReturnToCenterEmitsZero() {
        let slop = travel * GimbalStick.tapSlop * 0.5
        let tap = map(dx: slop, dy: 0)
        #expect(tap.isTap)
        #expect(!tap.emit)
        #expect(!tap.engaged)

        let thrown = map(dx: outer, dy: 0, engaged: tap.engaged)
        #expect(thrown.emit)

        let rest = map(dx: 0, dy: 0, engaged: thrown.engaged)
        #expect(rest.commandX == 0)
        #expect(rest.commandY == 0)
        #expect(rest.visualX == 0)
        #expect(rest.visualY == 0)
        #expect(rest.isTap)
        #expect(rest.engaged)
        #expect(rest.emit)
    }

    @Test func initialTapRemainsTapInsideVisualSlop() {
        let inside = map(dx: travel * GimbalStick.tapSlop * 0.5, dy: 0)
        #expect(inside.isTap)
        #expect(!inside.emit)
        #expect(!inside.engaged)

        let edge = map(dx: travel * GimbalStick.tapSlop, dy: 0)
        #expect(!edge.isTap)
        #expect(edge.emit)
    }
}
