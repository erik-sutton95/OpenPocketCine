import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite("Link diagnosis")
struct LinkDiagnosisTests {
    @Test func healthyLinkIsNone() {
        #expect(diagnose() == .none)
        #expect(LinkDiagnoser.repair(for: .none) == .none)
    }

    @Test func missingPathIsSoftAPLost() {
        let failure = diagnose(
            pathReady: false, decoderFailed: true, udpReceiveAlive: false)
        #expect(failure == .softAPLost)
        #expect(LinkDiagnoser.repair(for: failure) == .rejoinSoftAP)
    }

    @Test func decoderFailedIsWedged() {
        let failure = diagnose(
            decoderFailed: true, udpReceiveAlive: true, presentAge: 4)
        #expect(failure == .decoderWedged)
        #expect(LinkDiagnoser.repair(for: failure) == .none)
    }

    @Test func presentStalledWhenUDPAliveAndCanvasFrozen() {
        let failure = diagnose(udpReceiveAlive: true, presentAge: 2.5)
        #expect(failure == .presentStalled)
        #expect(LinkDiagnoser.repair(for: failure) == .none)
        #expect(diagnose(udpReceiveAlive: true, presentAge: FeedWatchdog.stallThreshold) == .none)
        #expect(diagnose(udpReceiveAlive: true, presentAge: nil) == .none)
    }

    @Test func encoderPausedResendsEnable() {
        let failure = diagnose(
            bleNotifyAge: 9, statusAge: 0.3, udpReceiveAlive: false)
        #expect(failure == .encoderPaused)
        #expect(LinkDiagnoser.repair(for: failure) == .resendEnable)
    }

    @Test func presentStalledIsNotEncoderPaused() {
        let stalled = diagnose(
            statusAge: 0.3, udpReceiveAlive: true, presentAge: 4.2)
        #expect(stalled == .presentStalled)
        #expect(LinkDiagnoser.repair(for: stalled) == .none)

        let paused = diagnose(
            statusAge: 0.3, udpReceiveAlive: false, presentAge: 4.2)
        #expect(paused == .encoderPaused)
        #expect(LinkDiagnoser.repair(for: paused) == .resendEnable)
    }

    @Test func gopResetHoldIsNone() {
        #expect(
            diagnose(
                statusAge: 0.3, udpReceiveAlive: false, secondsSinceLastEnable: 2.5)
                == .none,
            "IDR gap after 0x09/0xa8 is not a dead socket")
        #expect(
            diagnose(
                statusAge: 3,
                udpReceiveAlive: false,
                secondsSinceLastEnable: CameraSoftAP.firstPictureIDRGrace)
                == .udpFlowDead)
    }

    @Test func afcHoldIsNone() {
        #expect(
            diagnose(
                statusAge: 0.3, udpReceiveAlive: false, secondsSinceFocusTrackSet: 1.8)
                == .none,
            "AF-C 0x3B SET can pause HEVC")
        #expect(
            diagnose(
                statusAge: 3,
                udpReceiveAlive: false,
                secondsSinceFocusTrackSet: FocusTrackMode.videoGrace)
                == .udpFlowDead)
    }

    @Test func bleLostWhenNotifyAndUDPAndStatusAreStale() {
        let failure = diagnose(
            bleNotifyAge: 8.1, statusAge: 3, udpReceiveAlive: false)
        #expect(failure == .bleLost)
        #expect(LinkDiagnoser.repair(for: failure) == .fullReconnect)
    }

    @Test func nilBleNotifyWithSilentUDPAndStatusIsBleLost() {
        let failure = diagnose(
            bleNotifyAge: nil, statusAge: nil, udpReceiveAlive: false)
        #expect(failure == .bleLost)
        #expect(LinkDiagnoser.repair(for: failure) == .fullReconnect)
    }

    @Test func freshBleWithDeadUDPIsFlowDead() {
        let failure = diagnose(
            bleNotifyAge: 0.2, statusAge: 3, udpReceiveAlive: false)
        #expect(failure == .udpFlowDead)
        #expect(LinkDiagnoser.repair(for: failure) == .rebindUDP)
    }

    @Test func unhealthyFlowIsUDPDead() {
        let failure = diagnose(flowHealthy: false, udpReceiveAlive: true)
        #expect(failure == .udpFlowDead)
        #expect(LinkDiagnoser.repair(for: failure) == .rebindUDP)
    }

    @Test func firstPictureDoesNotClaimEncoderPause() {
        #expect(
            diagnose(statusAge: 0.3, udpReceiveAlive: false, hadVideo: false)
                == .udpFlowDead)
    }

    private func diagnose(
        pathReady: Bool = true,
        bleNotifyAge: TimeInterval? = 0.2,
        videoAge: TimeInterval? = 0.1,
        statusAge: TimeInterval? = 0.1,
        flowHealthy: Bool = true,
        decoderFailed: Bool = false,
        udpReceiveAlive: Bool = true,
        hadVideo: Bool = true,
        secondsSinceLastEnable: TimeInterval? = 20,
        secondsSinceFocusTrackSet: TimeInterval? = nil,
        presentAge: TimeInterval? = nil
    ) -> LinkFailure {
        LinkDiagnoser.diagnose(
            pathReady: pathReady,
            bleNotifyAge: bleNotifyAge,
            videoAge: videoAge,
            statusAge: statusAge,
            flowHealthy: flowHealthy,
            decoderFailed: decoderFailed,
            udpReceiveAlive: udpReceiveAlive,
            hadVideo: hadVideo,
            secondsSinceLastEnable: secondsSinceLastEnable,
            secondsSinceFocusTrackSet: secondsSinceFocusTrackSet,
            presentAge: presentAge)
    }
}

@Suite("Connect timeline")
struct ConnectTimelineTests {
    @Test func emptyLine() {
        let timeline = ConnectTimeline(now: 10)
        #expect(timeline.line() == "connect:")
    }

    @Test func marksInInsertionOrderWithTwoDecimals() {
        var timeline = ConnectTimeline(now: 10)
        timeline.mark("gatt", now: 10.40)
        timeline.mark("pair", now: 11.10)
        timeline.mark("path", now: 13.20)
        #expect(timeline.line() == "connect: gatt=0.40s pair=1.10s path=3.20s")
    }

    @Test func insertionOrderIsNotSortedByTime() {
        var timeline = ConnectTimeline(now: 0)
        timeline.mark("path", now: 3.20)
        timeline.mark("gatt", now: 0.40)
        #expect(timeline.line() == "connect: path=3.20s gatt=0.40s")
    }
}
