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
}
