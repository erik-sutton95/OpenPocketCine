import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct ConformPreviewTests {
    @Test func speedLabelAndDurationFollowTheTargetRate() {
        #expect(ConformPreview.speed(captureRate: 60, targetRate: 24) == 0.4)
        #expect(ConformPreview.label(captureRate: 60, targetRate: 24) == "60 → 24 fps · 40%")
        #expect(ConformPreview.speed(captureRate: 120, targetRate: 24) == 0.2)
        let availability = ConformPreview.availability(for: ConformPreview.Source(captureRate: 120))
        #expect(availability.targets == ConformPreview.targetRates)
        let speed = ConformPreview.speed(captureRate: 60, targetRate: 24)
        #expect(ConformPreview.conformedDuration(sourceSeconds: 6, speed: speed) == 15)
    }

    @Test func onlySlowerTargets() {
        let thirty = ConformPreview.availability(for: ConformPreview.Source(captureRate: 30))
        #expect(thirty.targets == [23.976, 24, 25])
        let twentyFour = ConformPreview.availability(for: ConformPreview.Source(captureRate: 24))
        #expect(twentyFour == .notHighFrameRate)
        #expect(!twentyFour.isAvailable)
    }

    @Test func refusalsExplainWhy() {
        #expect(ConformPreview.availability(for: ConformPreview.Source()) == .unknownRate)
        #expect(
            ConformPreview.availability(
                for: ConformPreview.Source(captureRate: 120, isVariableFrameRate: true))
                == .variableRate)
        #expect(
            ConformPreview.availability(
                for: ConformPreview.Source(captureRate: 120, isAlreadyConformed: true))
                == .alreadyConformed)
        for source in [
            ConformPreview.Source(),
            ConformPreview.Source(captureRate: 120, isVariableFrameRate: true),
            ConformPreview.Source(captureRate: 120, isAlreadyConformed: true),
            ConformPreview.Source(captureRate: 24),
        ] {
            #expect(ConformPreview.availability(for: source).unavailableReason != nil)
        }
    }

    @Test func frameTapRestartsAtEnd() {
        #expect(PlaybackFrameTap.action(chromeVisible: true, reachedEnd: true) == .restartPlayback)
        #expect(PlaybackFrameTap.action(chromeVisible: true, reachedEnd: false) == .toggleTransport)
    }

    @Test func aspectFitCentersTheRaster() {
        let rect = PlaybackVideoLayout.aspectFitRect(
            videoSize: CGSize(width: 16, height: 9),
            in: CGRect(x: 0, y: 0, width: 320, height: 320))
        #expect(abs(rect.width - 320) < 0.01)
        #expect(abs(rect.height - 180) < 0.01)
        #expect(abs(rect.midY - 160) < 0.01)
    }

    @Test func squareRecordingPillarboxesInsideASixteenNineWell() {
        let well = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let picture = PlaybackVideoLayout.aspectFitRect(
            videoSize: CGSize(width: 1, height: 1), in: well)
        #expect(abs(picture.width - 1080) < 0.01)
        #expect(abs(picture.height - 1080) < 0.01)
        #expect(abs(picture.minX - 420) < 0.01)
        #expect(abs(picture.midY - well.midY) < 0.01)
    }

    @Test func probeUsesMinDurationWhenNominalIsZero() {
        let source = ConformPreview.probe(
            nominalFrameRate: 0, minFrameDurationSeconds: 1 / 50)
        #expect(source.captureRate == 50)
        #expect(!source.isVariableFrameRate)
    }

    @Test func timescaleArtifactIsNotVariableRate() {
        let source = ConformPreview.probe(
            nominalFrameRate: 50, minFrameDurationSeconds: 1 / 1000)
        #expect(source.captureRate == 50)
        #expect(!source.isVariableFrameRate)
    }

    @Test func listedResolutionBecomesTheFeedRaster() {
        #expect(
            PlaybackVideoLayout.size(fromResolution: "3840x2160")
                == CGSize(width: 3840, height: 2160))
        #expect(
            PlaybackVideoLayout.size(fromResolution: "1080×1920")
                == CGSize(width: 1080, height: 1920))
        #expect(PlaybackVideoLayout.size(fromResolution: nil) == nil)
        #expect(PlaybackVideoLayout.size(fromResolution: "n/a") == nil)
    }
}
