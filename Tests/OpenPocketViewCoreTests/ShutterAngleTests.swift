import Testing

@testable import OpenPocketViewCore

@Suite struct ShutterAngleTests {
    @Test func ladderRunsFromFivePointSixToThreeSixty() {
        #expect(ShutterAngle.labels.first == "5.6°")
        #expect(ShutterAngle.labels.last == "360°")
        #expect(ShutterAngle.labels.contains("180°"))
        #expect(ShutterAngle.labels.contains("86.4°"))
        #expect(ShutterAngle.labels.contains("172°"))
        #expect(ShutterAngle.parse("180°") == 180)
        #expect(ShutterAngle.parse("5.6°") == 5.6)
        #expect(ShutterAngle.label(180) == "180°")
        #expect(ShutterAngle.label(5.6) == "5.6°")
        #expect(ShutterAngle.label(11.2) == "11.2°")
    }

    @Test func oneEightyIsAHalfTurnAtAnyFps() {
        #expect(ShutterAngle.denom(degrees: 180, fps: 24) == 48)
        #expect(ShutterAngle.denom(degrees: 180, fps: 25) == 50)
        #expect(ShutterAngle.denom(degrees: 180, fps: 30) == 60)
        #expect(ShutterAngle.denom(degrees: 180, fps: 60) == 120)
        #expect(ShutterAngle.denom(degrees: 360, fps: 24) == 24)
        #expect(ShutterAngle.denom(degrees: 5.6, fps: 24) == 1_543)
    }

    @Test func liveSpeedSnapsToTheNearestStop() {
        #expect(ShutterAngle.nearestLabel(denom: 48, fps: 24) == "180°")
        #expect(ShutterAngle.nearestLabel(denom: 50, fps: 24) == "172°")
        #expect(ShutterAngle.nearestLabel(denom: 24, fps: 24) == "360°")
        #expect(ShutterAngle.nearestLabel(denom: 50, fps: 25) == "180°")
    }

    @Test func sendSnapsToTheCameraList() {
        #expect(
            ShutterAngle.denom(degrees: 180, fps: 24, available: [25, 50, 100, 200])
                == 50)
        #expect(ShutterAngle.denom(degrees: 180, fps: 24, available: []) == 48)
        #expect(ShutterAngle.effectiveFps(0) == 24)
        #expect(ShutterAngle.effectiveFps(60) == 60)
    }
}
