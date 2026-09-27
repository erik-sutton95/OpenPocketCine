import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite("Link diagnosis")
struct LinkDiagnosisTests {
    /// Each link symptom maps to one failure and its repair. Present stalls and a
    /// wedged decoder repair nothing on the link; a first picture never claims an
    /// encoder pause.
    @Test(
        arguments: [
            (Probe(), .none, .none),
            (
                Probe(pathReady: false, decoderFailed: true, udpReceiveAlive: false),
                .softAPLost, .rejoinSoftAP
            ),
            (
                Probe(decoderFailed: true, udpReceiveAlive: true, presentAge: 4),
                .decoderWedged, .none
            ),
            (Probe(udpReceiveAlive: true, presentAge: 2.5), .presentStalled, .none),
            (
                Probe(udpReceiveAlive: true, presentAge: FeedWatchdog.stallThreshold),
                .none, .none
            ),
            (
                Probe(bleNotifyAge: 9, statusAge: 0.3, udpReceiveAlive: false),
                .encoderPaused, .resendEnable
            ),
            (
                Probe(statusAge: 0.3, udpReceiveAlive: true, presentAge: 4.2),
                .presentStalled, .none
            ),
            (
                Probe(statusAge: 0.3, udpReceiveAlive: false, presentAge: 4.2),
                .encoderPaused, .resendEnable
            ),
            (
                Probe(bleNotifyAge: 8.1, statusAge: 3, udpReceiveAlive: false),
                .bleLost, .fullReconnect
            ),
            (
                Probe(bleNotifyAge: nil, statusAge: nil, udpReceiveAlive: false),
                .bleLost, .fullReconnect
            ),
            (
                Probe(bleNotifyAge: 0.2, statusAge: 3, udpReceiveAlive: false),
                .udpFlowDead, .rebindUDP
            ),
            (Probe(flowHealthy: false, udpReceiveAlive: true), .udpFlowDead, .rebindUDP),
            (
                Probe(statusAge: 0.3, udpReceiveAlive: false, hadVideo: false),
                .udpFlowDead, .rebindUDP
            ),
        ] as [(Probe, LinkFailure, LinkRepair)])
    func symptomMapsToFailureAndRepair(probe: Probe, failure: LinkFailure, repair: LinkRepair) {
        #expect(diagnose(probe) == failure)
        #expect(LinkDiagnoser.repair(for: failure) == repair)
    }

    /// A camera SET, enable IDR gap, AF-C, zoom or gimbal throw can pause HEVC
    /// while status stays fresh. That is not a dead socket until its grace ends.
    @Test(
        arguments: [
            (Probe(statusAge: 0.3, udpReceiveAlive: false, secondsSinceLastEnable: 2.5), .none),
            (
                Probe(
                    statusAge: 3, udpReceiveAlive: false,
                    secondsSinceLastEnable: CameraSoftAP.firstPictureIDRGrace),
                .udpFlowDead
            ),
            (Probe(statusAge: 0.3, udpReceiveAlive: false, secondsSinceFocusTrackSet: 1.8), .none),
            (
                Probe(
                    statusAge: 3, udpReceiveAlive: false,
                    secondsSinceFocusTrackSet: FocusTrackMode.videoGrace),
                .udpFlowDead
            ),
            (Probe(statusAge: 0.3, udpReceiveAlive: false, secondsSinceZoomSet: 1.8), .none),
            (
                Probe(statusAge: 3, udpReceiveAlive: false, secondsSinceZoomSet: CamFov.videoGrace),
                .udpFlowDead
            ),
            (Probe(statusAge: 0.3, udpReceiveAlive: false, secondsSinceGimbalThrow: 1.0), .none),
            (
                Probe(
                    statusAge: 3, udpReceiveAlive: false,
                    secondsSinceGimbalThrow: GimbalStick.videoGrace),
                .udpFlowDead
            ),
            (Probe(statusAge: 0.3, udpReceiveAlive: false, gimbalStickHeld: true), .none),
            (Probe(statusAge: 0.3, udpReceiveAlive: false, secondsSinceCameraSet: 1.0), .none),
            (
                Probe(
                    statusAge: 3, udpReceiveAlive: false,
                    secondsSinceCameraSet: FeedWatchdog.cameraSetGrace),
                .udpFlowDead
            ),
        ] as [(Probe, LinkFailure)])
    func controlHoldIsNotADeadSocketUntilGraceEnds(probe: Probe, failure: LinkFailure) {
        #expect(diagnose(probe) == failure)
    }

    @Test func diagnoseReadsWatchdogSnapshot() {
        var snap = encoderPauseSnapshot()
        #expect(LinkDiagnoser.diagnose(snap) == .encoderPaused)
        #expect(LinkDiagnoser.repair(for: LinkDiagnoser.diagnose(snap)) == .resendEnable)

        snap.lastVideoPacketAge = 0.1
        snap.lastAccessUnitAge = 0.1
        snap.lastDecodedFrameAge = 3.0
        #expect(
            LinkDiagnoser.diagnose(snap) == .presentStalled,
            "UDP alive + stale present is a canvas freeze, not a link repair")
    }

    @Test func observeLineNamesDiagnoserAndWatchdog() {
        let snap = encoderPauseSnapshot()
        var dog = FeedWatchdog()
        let action = dog.tick(snap)
        #expect(action == .resendLiveViewEnable)
        let line = LinkDiagnoser.observeLine(snap: snap, watchdog: action)
        #expect(line.hasPrefix("feed: observe "))
        #expect(line.contains("diagnose=encoderPaused"))
        #expect(line.contains("repair=resendEnable"))
        #expect(line.contains("watchdog=resendLiveViewEnable"))
        #expect(line.contains("lastVideo=4.2"))
        #expect(line.contains("lastStatus=0.3"))
    }

    @Test func observeLineFlagsDisagreementWhenFlowUnhealthyButUDPAlive() {
        let snap = FeedWatchdog.Snapshot(
            now: 10,
            lastDecodedFrameAge: 0.2,
            lastVideoPacketAge: 0.1,
            lastAccessUnitAge: 0.1,
            lastStatusAge: 0.1,
            flowHealthy: false,
            pathReady: true,
            hasFormat: true,
            decoderFailed: false,
            live: true,
            sawPicture: true,
            lastBleNotifyAge: 0.2,
            hadVideo: true,
            secondsSinceLastEnable: 20
        )
        var dog = FeedWatchdog()
        let action = dog.tick(snap)
        #expect(action == .none, "UDP alive short-circuits the watchdog")
        #expect(LinkDiagnoser.diagnose(snap) == .udpFlowDead)
        #expect(LinkDiagnoser.repair(for: .udpFlowDead) == .rebindUDP)
        let line = LinkDiagnoser.observeLine(snap: snap, watchdog: action)
        #expect(line.contains("disagree=1"))
        #expect(line.contains("diagnose=udpFlowDead"))
        #expect(line.contains("watchdog=none"))
    }

    private func encoderPauseSnapshot() -> FeedWatchdog.Snapshot {
        FeedWatchdog.Snapshot(
            now: 10,
            lastDecodedFrameAge: 4.2,
            lastVideoPacketAge: 4.2,
            lastStatusAge: 0.3,
            flowHealthy: true,
            pathReady: true,
            hasFormat: true,
            decoderFailed: false,
            live: true,
            sawPicture: true,
            lastBleNotifyAge: 0.2,
            hadVideo: true,
            secondsSinceLastEnable: 20
        )
    }

    /// One `LinkDiagnoser.diagnose` input. Defaults are a healthy live link.
    struct Probe: Sendable {
        var pathReady = true
        var bleNotifyAge: TimeInterval? = 0.2
        var statusAge: TimeInterval? = 0.1
        var flowHealthy = true
        var decoderFailed = false
        var udpReceiveAlive = true
        var hadVideo = true
        var secondsSinceLastEnable: TimeInterval? = 20
        var secondsSinceFocusTrackSet: TimeInterval? = nil
        var secondsSinceZoomSet: TimeInterval? = nil
        var secondsSinceGimbalThrow: TimeInterval? = nil
        var gimbalStickHeld = false
        var secondsSinceCameraSet: TimeInterval? = nil
        var presentAge: TimeInterval? = nil
    }

    private func diagnose(_ probe: Probe) -> LinkFailure {
        LinkDiagnoser.diagnose(
            pathReady: probe.pathReady,
            bleNotifyAge: probe.bleNotifyAge,
            videoAge: 0.1,
            statusAge: probe.statusAge,
            flowHealthy: probe.flowHealthy,
            decoderFailed: probe.decoderFailed,
            udpReceiveAlive: probe.udpReceiveAlive,
            hadVideo: probe.hadVideo,
            secondsSinceLastEnable: probe.secondsSinceLastEnable,
            secondsSinceFocusTrackSet: probe.secondsSinceFocusTrackSet,
            secondsSinceZoomSet: probe.secondsSinceZoomSet,
            secondsSinceGimbalThrow: probe.secondsSinceGimbalThrow,
            gimbalStickHeld: probe.gimbalStickHeld,
            presentAge: probe.presentAge,
            secondsSinceCameraSet: probe.secondsSinceCameraSet)
    }
}

@Suite("Connect timeline")
struct ConnectTimelineTests {
    /// Marks print in insertion order, not sorted by time, with two decimals.
    @Test(
        arguments: [
            (10.0, [], "connect:"),
            (
                10.0, [("gatt", 10.40), ("pair", 11.10), ("path", 13.20)],
                "connect: gatt=0.40s pair=1.10s path=3.20s"
            ),
            (0.0, [("path", 3.20), ("gatt", 0.40)], "connect: path=3.20s gatt=0.40s"),
        ] as [(Double, [(String, Double)], String)])
    func lineListsMarks(start: Double, marks: [(String, Double)], line: String) {
        var timeline = ConnectTimeline(now: start)
        for (name, at) in marks {
            timeline.mark(name, now: at)
        }
        #expect(timeline.line() == line)
    }
}
