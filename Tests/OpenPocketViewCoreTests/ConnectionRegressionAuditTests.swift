import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct ConnectionRegressionAuditTests {
    @Test func freshPacketsWithoutFirstPictureEventuallyLeaveWaiting() {
        var decisions: [CameraSoftAP.FirstPictureStep] = []
        for second in 8...180 {
            decisions.append(
                CameraSoftAP.firstPictureStep(
                    videoPackets: second * 100, enableSends: 2,
                    secondsSinceLastEnable: Double(second),
                    secondsSinceLastVideo: 0.01,
                    hasPresentedPicture: false))
        }
        #expect(
            decisions.contains { $0 != .wait },
            "Two enables followed by uninterrupted P-frames cannot leave first picture waiting forever"
        )
    }

    @Test func ongoingCameraSetsCannotSuppressSilentNativeOutputForever() {
        var dog = FeedWatchdog()
        var actions: [FeedWatchdog.Action] = []
        for second in 3...60 {
            var snapshot = Self.stalledPicture(age: Double(second))
            snapshot.lastAccessUnitAge = 0.01
            snapshot.secondsSinceCameraSet = Double(second % 3)
            actions.append(dog.tick(snapshot))
        }
        #expect(
            actions.contains(.rebuildVTSession),
            "A SET every three seconds cannot suppress native-output recovery for a minute")
    }

    @Test func ongoingCameraSetsCannotSuppressIncompleteAccessUnitsForever() {
        var dog = FeedWatchdog()
        var actions: [FeedWatchdog.Action] = []
        for second in 3...60 {
            var snapshot = Self.stalledPicture(age: Double(second))
            snapshot.lastAccessUnitAge = Double(second)
            snapshot.secondsSinceCameraSet = Double(second % 3)
            actions.append(dog.tick(snapshot))
        }
        #expect(
            actions.contains(.resendLiveViewEnable),
            "Fresh incomplete fragments must not renew SET grace after a minute without a complete picture"
        )
    }

    @Test func firstPictureDeadlinePreservesGraceAndFormatPokeOwnership() {
        for elapsed in [0.0, 2, 5, 8, 15.99] {
            #expect(
                CameraSoftAP.firstPictureStep(
                    videoPackets: 100, enableSends: 2, secondsSinceLastEnable: elapsed,
                    secondsSinceLastVideo: 0.01) == .wait)
        }
        #expect(
            CameraSoftAP.firstPictureStep(
                videoPackets: 100, enableSends: 2, secondsSinceLastEnable: 16,
                secondsSinceLastVideo: 0.01) == .rejoin)
        #expect(
            CameraSoftAP.firstPictureStep(
                videoPackets: 100, enableSends: 1, secondsSinceLastEnable: 5,
                secondsSinceLastVideo: 0.01) == .resendEnable)
        #expect(
            CameraSoftAP.firstPictureStep(
                videoPackets: 100, enableSends: 2, secondsSinceLastEnable: 60,
                secondsSinceLastVideo: 0.01, hasPresentedPicture: true) == .wait)
        #expect(
            CameraSoftAP.firstPictureStep(
                videoPackets: 100, enableSends: 2, secondsSinceLastEnable: 60,
                secondsSinceLastVideo: 0.01, needsRecordingFormatPoke: true,
                recordingFormatPokeInFlight: true) == .wait)
        #expect(
            CameraSoftAP.firstPictureStep(
                videoPackets: 100, enableSends: 2, secondsSinceLastEnable: 16,
                secondsSinceLastVideo: 0.01, needsRecordingFormatPoke: true) == .pokeRecordingFormat
        )
        #expect(
            CameraSoftAP.firstPictureStep(
                videoPackets: 100, enableSends: 2, secondsSinceLastEnable: 16,
                secondsSinceLastVideo: 0.01, needsRecordingFormatPoke: true,
                isRecording: true) == .rejoin)
    }

    @Test func allControlGracesExpireAgainstTheFailedStage() {
        for assemblyStalled in [false, true] {
            for control in 0..<4 {
                var dog = FeedWatchdog()
                var snapshot = Self.stalledPicture(age: 3)
                snapshot.lastAccessUnitAge = assemblyStalled ? 3 : 0.01
                switch control {
                case 0: snapshot.secondsSinceCameraSet = 0.1
                case 1: snapshot.secondsSinceFocusTrackSet = 0.1
                case 2: snapshot.secondsSinceZoomSet = 0.1
                default: snapshot.secondsSinceGimbalThrow = 0.1
                }
                #expect(dog.tick(snapshot) == .none)
                snapshot.now += 4
                snapshot.lastDecodedFrameAge = 7
                snapshot.lastDecoderOutputAge = 7
                snapshot.lastAccessUnitAge = assemblyStalled ? 7 : 0.01
                #expect(
                    dog.tick(snapshot)
                        == (assemblyStalled ? .resendLiveViewEnable : .rebuildVTSession))
            }
        }
    }

    @Test func boundedControlGracePreservesHealthyOutputHeldMotionAndReadiness() {
        for assemblyStalled in [false, true] {
            var snapshot = Self.stalledPicture(age: 60)
            snapshot.lastAccessUnitAge = assemblyStalled ? 60 : 0.01
            snapshot.secondsSinceCameraSet = 0.1
            var dog = FeedWatchdog()
            snapshot.gimbalStickHeld = true
            #expect(dog.tick(snapshot) == .none)
            snapshot.gimbalStickHeld = false
            snapshot.zoomPinchActive = true
            #expect(dog.tick(snapshot) == .none)
            snapshot.zoomPinchActive = false
            snapshot.repairReady = false
            #expect(dog.tick(snapshot) == .none)
            snapshot.repairReady = true
            snapshot.secondsSinceLastEnable = 1
            #expect(dog.tick(snapshot) == .none)
            snapshot.secondsSinceLastEnable = nil
            snapshot.lastDecoderOutputAge = 0.01
            #expect(dog.tick(snapshot) == .none, "Fresh native output remains presentation-only")
            snapshot.lastDecodedFrameAge = 0.01
            #expect(dog.tick(snapshot) == .none)
        }
    }

    private static func stalledPicture(age: TimeInterval) -> FeedWatchdog.Snapshot {
        FeedWatchdog.Snapshot(
            now: 100 + age,
            lastDecodedFrameAge: age,
            lastVideoPacketAge: 0.01,
            lastAccessUnitAge: 0.01,
            lastStatusAge: 0.01,
            flowHealthy: true,
            pathReady: true,
            hasFormat: true,
            decoderFailed: false,
            live: true,
            sawPicture: true,
            lastDecoderOutputAge: age,
            decoderOutputExpected: true)
    }
}
