import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite("Live chrome status throttle")
struct LiveChromeThrottleTests {
    @Test func equalStatusNeverNotifies() {
        let a = CameraStatus()
        #expect(LiveChromeThrottle.shouldNotify(previous: a, next: a, elapsed: 1) == false)
    }

    /// Operator-facing fields land on the next render, not the HUD interval.
    @Test(
        arguments: [
            ("recording", { @Sendable in $0.isRecording = true }),
            ("expoMode", { @Sendable in $0.expoMode = .manual }),
            ("zoomRaw", { @Sendable in $0.zoomFactorRaw = 3072 }),
            ("selfieFlip", { @Sendable in $0.selfieFlip = .on }),
            ("audioChannel", { @Sendable in $0.audioChannel = .stereo }),
            ("vocalBoost", { @Sendable in $0.vocalBoost = .on }),
            ("windNR", { @Sendable in $0.windNR = .on }),
            ("directionalAudio", { @Sendable in $0.directionalAudio = .front }),
        ] as [(String, @Sendable (inout CameraStatus) -> Void)])
    func operatorFieldIsImmediate(field: String, change: @Sendable (inout CameraStatus) -> Void) {
        var next = CameraStatus()
        change(&next)
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0))
    }

    @Test func isoShutterWaitForInterval() {
        var next = CameraStatus()
        next.iso = 800
        next.isoIndex = .iso800
        next.shutterDenom = 50
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next) == false)
        #expect(
            LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0)
                == false)
        #expect(
            LiveChromeThrottle.shouldNotify(
                previous: CameraStatus(), next: next, elapsed: LiveChromeThrottle.statusInterval))
    }

    @Test func timecodeAndMetersWaitForInterval() {
        var next = CameraStatus()
        next.timecode = "01:02:03:04"
        next.audioMeters = AudioMeterLevels(
            left: AudioMeterChannel(levelDB: -12, peakDB: -6),
            right: AudioMeterChannel(levelDB: -14, peakDB: -8)
        )
        next.batteryMilliAmps = -1200
        next.batteryPercent = 80
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next) == false)
        #expect(
            LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0)
                == false)
        #expect(
            LiveChromeThrottle.shouldNotify(
                previous: CameraStatus(), next: next, elapsed: LiveChromeThrottle.statusInterval))
    }

    @Test func shutterCapListIsImmediate() {
        var next = CameraStatus()
        next.availableShutterDenoms = [50, 60, 100]
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0))
    }
}
