import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite("Live chrome status throttle")
struct LiveChromeThrottleTests {
    @Test func equalStatusNeverNotifies() {
        let a = CameraStatus()
        #expect(LiveChromeThrottle.shouldNotify(previous: a, next: a, elapsed: 1) == false)
    }

    @Test func recordingFlipIsImmediate() {
        var next = CameraStatus()
        next.isRecording = true
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0))
    }

    @Test func expoModeFlipIsImmediate() {
        var next = CameraStatus()
        next.expoMode = .manual
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0))
    }

    @Test func isoShutterWaitForInterval() {
        var next = CameraStatus()
        next.iso = 800
        next.isoIndex = .iso800
        next.shutterDenom = 50
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next) == false)
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0) == false)
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
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0) == false)
        #expect(
            LiveChromeThrottle.shouldNotify(
                previous: CameraStatus(), next: next, elapsed: LiveChromeThrottle.statusInterval))
    }

    @Test func zoomRawIsImmediate() {
        var next = CameraStatus()
        next.zoomFactorRaw = 3072
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0))
    }

    @Test func audioOperatorFieldsAreImmediate() {
        var next = CameraStatus()
        next.audioChannel = .stereo
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        next = CameraStatus()
        next.vocalBoost = .on
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        next = CameraStatus()
        next.windNR = .on
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        next = CameraStatus()
        next.directionalAudio = .front
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
    }

    @Test func shutterCapListIsImmediate() {
        var next = CameraStatus()
        next.availableShutterDenoms = [50, 60, 100]
        #expect(LiveChromeThrottle.isImmediate(CameraStatus(), next))
        #expect(LiveChromeThrottle.shouldNotify(previous: CameraStatus(), next: next, elapsed: 0))
    }
}
