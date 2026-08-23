import Testing

@testable import OpenPocketViewCore

@Suite("Audio meter dBFS conversion")
struct AudioMeterDecibelTests {
    @Test func fullScaleReadsZeroDB() {
        #expect(AudioMeterBallistics.decibels(fromLinear: 1) == 0)
    }

    @Test func halfAmplitudeReadsMinusSixDB() {
        #expect(abs(AudioMeterBallistics.decibels(fromLinear: 0.5) - (-6.0206)) < 0.01)
    }

    @Test func silenceAndOverdriveClampToTheScale() {
        #expect(AudioMeterBallistics.decibels(fromLinear: 0) == AudioMeterBallistics.floorDB)
        #expect(AudioMeterBallistics.decibels(fromLinear: -1) == AudioMeterBallistics.floorDB)
        #expect(AudioMeterBallistics.decibels(fromLinear: 0.000_01) == AudioMeterBallistics.floorDB)
        #expect(AudioMeterBallistics.decibels(fromLinear: 2) == 0)
    }
}

@Suite("Audio meter ballistics")
struct AudioMeterBallisticsTests {
    @Test func attackIsInstant() {
        let next = AudioMeterBallistics.step(.silent, peakLinear: 1, dt: 0.04)
        #expect(next.levelDB == 0)
        #expect(next.peakDB == 0)
        #expect(next.peakAge == 0)
    }

    @Test func levelDecaysAtTheDocumentedRate() {
        let loud = AudioMeterBallistics.step(.silent, peakLinear: 1, dt: 0.04)
        let dt = 0.5
        let next = AudioMeterBallistics.step(loud, peakLinear: 0, dt: dt)
        #expect(abs(next.levelDB - (-AudioMeterBallistics.levelDecayPerSecond * dt)) < 1e-9)
    }

    @Test func peakHoldsThroughTheHoldWindowThenDecays() {
        var channel = AudioMeterBallistics.step(.silent, peakLinear: 1, dt: 0.04)
        channel = AudioMeterBallistics.step(channel, peakLinear: 0, dt: 1.0)
        #expect(channel.peakDB == 0)
        #expect(channel.levelDB < 0)
        channel = AudioMeterBallistics.step(channel, peakLinear: 0, dt: 1.0)
        #expect(channel.peakAge > AudioMeterBallistics.peakHoldSeconds)
        #expect(channel.peakDB < 0)
    }
}

@Suite("cam_audio_status_v2")
struct CamAudioStatusTests {
    /// live1.pcap — room tone, left=2 right=2 (114 B).
    static let live1Quiet: [UInt8] = [
        0x00, 0x00, 0x00, 0x02, 0x00, 0x03, 0x00, 0x02, 0x00, 0x02, 0x00, 0x64, 0x00, 0x64,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A,
        0x08, 0x00, 0x00, 0xF4, 0xFF, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x0A, 0x08, 0x00, 0x00, 0xF4, 0xFF, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00,
    ]

    /// live1.pcap — louder frame, left=8 right=9 (114 B).
    static let live1Louder: [UInt8] = [
        0x00, 0x00, 0x00, 0x08, 0x00, 0x03, 0x00, 0x08, 0x00, 0x09, 0x00, 0x64, 0x00, 0x64,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0A,
        0x08, 0x00, 0x00, 0xF4, 0xFF, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x0A, 0x08, 0x00, 0x00, 0xF4, 0xFF, 0x0C, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00,
    ]

    @Test func subscribeKeyIsOnTheWireList() {
        #expect(Commands.subscriptionKeys.contains(CamAudioStatus.subscribeKey))
        #expect(Self.live1Quiet.count == CamAudioStatus.capturedSize)
        #expect(Self.live1Louder.count == CamAudioStatus.capturedSize)
    }

    @Test func capturedQuietIsAboveTheFloor() throws {
        let levels = try #require(CamAudioStatus.parse(Self.live1Quiet))
        let expected = AudioMeterBallistics.floorDB * (1 - 2.0 / 14.0)
        #expect(abs(levels.left.levelDB - expected) < 1e-9)
        #expect(abs(levels.right.levelDB - expected) < 1e-9)
        #expect(levels != AudioMeterLevels.silent)
    }

    @Test func capturedLouderRisesAboveQuiet() throws {
        let quiet = try #require(CamAudioStatus.parse(Self.live1Quiet))
        let loud = try #require(CamAudioStatus.parse(Self.live1Louder))
        #expect(loud.left.levelDB > quiet.left.levelDB)
        #expect(loud.right.levelDB > quiet.right.levelDB)
        #expect(abs(loud.left.levelDB - AudioMeterBallistics.floorDB * (1 - 8.0 / 14.0)) < 1e-9)
        #expect(abs(loud.right.levelDB - AudioMeterBallistics.floorDB * (1 - 9.0 / 14.0)) < 1e-9)
    }

    @Test func byte4IsNotAMeter() throws {
        // @4 is the constant 3. Using it as right would pin R at segment 3.
        let levels = try #require(CamAudioStatus.parsePocketV2(Self.live1Louder))
        #expect(abs(levels.right.levelDB - AudioMeterBallistics.floorDB * (1 - 9.0 / 14.0)) < 1e-9)
    }

    @Test func fifteenSegmentFallback() throws {
        let levels = try #require(CamAudioStatus.parse([7, 5, 11, 9]))
        #expect(abs(levels.left.levelDB - AudioMeterBallistics.floorDB * (1 - 7.0 / 14.0)) < 1e-9)
        #expect(abs(levels.left.peakDB - AudioMeterBallistics.floorDB * (1 - 11.0 / 14.0)) < 1e-9)
    }

    @Test func subscribePushLandsOnCameraStatus() {
        var status = CameraStatus()
        let payload = SubscribePush.pack(name: CamAudioStatus.subscribeKey, value: Self.live1Louder)
        #expect(CameraStatusDecoder.applySubscribePush(payload, to: &status))
        #expect(status.audioStatusRaw == Self.live1Louder)
        #expect(status.audioMeters.left.levelDB > AudioMeterBallistics.floorDB + 1)
        #expect(status.audioMeters != AudioMeterLevels.silent)
    }

    @Test func dumlSubscribeFrameLandsOnStatus() {
        var status = CameraStatus()
        let payload = SubscribePush.pack(name: CamAudioStatus.subscribeKey, value: Self.live1Louder)
        let frame = Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0xC0, cmdSet: 0x00, cmdId: 0x99,
            payload: payload)
        #expect(CameraStatusDecoder.apply(frame, to: &status))
        #expect(status.audioMeters.right.levelDB > status.audioMeters.left.levelDB)
    }
}
