import Testing

@testable import OpenPocketViewCore

@Suite struct GamepadOperatorTests {
    @Test func discussion159FaceShoulderAndDpad() {
        #expect(GamepadOperatorMap.face(.a) == .record)
        #expect(GamepadOperatorMap.face(.b) == .recenter)
        #expect(GamepadOperatorMap.face(.x) == .flip)
        #expect(GamepadOperatorMap.face(.y) == .track)
        #expect(GamepadOperatorMap.shoulder(.left) == .zoomChipOut)
        #expect(GamepadOperatorMap.shoulder(.right) == .zoomChipIn)
        #expect(GamepadOperatorMap.dpad(.up) == .isoUp)
        #expect(GamepadOperatorMap.dpad(.down) == .isoDown)
        #expect(GamepadOperatorMap.dpad(.left) == .shutterOpen)
        #expect(GamepadOperatorMap.dpad(.right) == .shutterClose)
    }

    @Test func zoomChipOutDoesNotWrapToTele() {
        #expect(CamFov.previousJump(from: 1) == 1)
        #expect(CamFov.previousJump(from: 3) == 1)
        #expect(CamFov.previousJump(from: 6) == 3)
        #expect(CamFov.previousJump(from: 12) == 6)
        #expect(CamFov.previousJump(from: 2, stops: [1, 2, 4]) == 1)
        #expect(CamFov.previousJump(from: 4, stops: [1, 2, 4]) == 2)
        #expect(CamFov.previousJump(from: 1, stops: [1, 2, 4]) == 1)
    }

    @Test func gimbalStickDefaultsLeftAndIgnoresTheOtherAxes() {
        #expect(GamepadGimbalStick.default == .left)
        #expect(GamepadGimbalStick.parse(nil) == .left)
        #expect(GamepadGimbalStick.parse("") == .left)
        #expect(GamepadGimbalStick.parse("right") == .right)
        #expect(GamepadGimbalStick.fromLabel("Right") == .right)
        #expect(GamepadGimbalStick.fromLabel("Left") == .left)
        let left = GamepadGimbalStick.left.axes(leftX: 0.8, leftY: -0.2, rightX: -1, rightY: 1)
        #expect(left.x == 0.8)
        #expect(left.y == -0.2)
        let right = GamepadGimbalStick.right.axes(leftX: 0.8, leftY: -0.2, rightX: -1, rightY: 1)
        #expect(right.x == -1)
        #expect(right.y == 1)
        #expect(GamepadGimbalStick.restHeldMotion(from: .left, to: .right, driving: true))
        #expect(!GamepadGimbalStick.restHeldMotion(from: .left, to: .left, driving: true))
        #expect(!GamepadGimbalStick.restHeldMotion(from: .left, to: .right, driving: false))
    }

    @Test func shutterHudUsesLiveDenomWhenPreferredDoesNotMap() {
        let available = [24, 48, 50, 60, 120]
        #expect(
            GamepadShutterSync.angleLabel(
                denom: 48, fps: 24, available: available, preferredAngle: 180) == "180°")
        #expect(
            GamepadShutterSync.angleLabel(
                denom: 120, fps: 24, available: available, preferredAngle: 180) == "72°")
        #expect(
            GamepadShutterSync.shouldPersistPreferredAngle(
                usesAngle: true, isPhoto: false, expoIsAuto: false))
        #expect(
            !GamepadShutterSync.shouldPersistPreferredAngle(
                usesAngle: true, isPhoto: true, expoIsAuto: false))
        #expect(
            !GamepadShutterSync.shouldPersistPreferredAngle(
                usesAngle: true, isPhoto: false, expoIsAuto: true))
        let speedStops = [16_000, 120, 60, 50, 48, 24]
        #expect(CamCapShutter.steppedDenom(from: 48, steps: 1, available: speedStops) == 24)
        #expect(CamCapShutter.steppedDenom(from: 48, steps: -1, available: speedStops) == 50)
        let next = CamCapShutter.steppedDenom(from: 48, steps: -1, available: speedStops) ?? 0
        let synced = GamepadShutterSync.preferredAngle(afterDenom: next, fps: 24)
        #expect(synced == 172)
        #expect(
            GamepadShutterSync.angleLabel(
                denom: next, fps: 24, available: speedStops, preferredAngle: synced) == "172°")
        #expect(
            ShutterAngle.denom(degrees: synced, fps: 60)
                != ShutterAngle.denom(degrees: 180, fps: 60))
    }
}
