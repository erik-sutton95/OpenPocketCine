import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct ConformPreviewTests {
    @Test func sixtyToTwentyFour() {
        #expect(ConformPreview.speed(captureRate: 60, targetRate: 24) == 0.4)
        #expect(ConformPreview.label(captureRate: 60, targetRate: 24) == "60 → 24 fps · 40%")
    }

    @Test func oneTwentyToTwentyFour() {
        #expect(ConformPreview.speed(captureRate: 120, targetRate: 24) == 0.2)
        let availability = ConformPreview.availability(for: ConformPreview.Source(captureRate: 120))
        #expect(availability.targets == ConformPreview.targetRates)
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

    @Test func conformedDurationStretches() {
        let speed = ConformPreview.speed(captureRate: 60, targetRate: 24)
        #expect(ConformPreview.conformedDuration(sourceSeconds: 6, speed: speed) == 15)
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

    @Test func fiftyFpsOffersHalfSpeedAtTwentyFive() {
        let source = ConformPreview.probe(nominalFrameRate: 50)
        let availability = ConformPreview.availability(for: source)
        #expect(source.captureRate == 50)
        #expect(availability.targets.contains(25))
        #expect(ConformPreview.speed(captureRate: 50, targetRate: 25) == 0.5)
        #expect(ConformPreview.targetLabel(captureRate: 50, targetRate: 25) == "25 fps · 50%")
    }

    @Test func probeFallsBackToListedRateWhenAssetIsSilent() {
        let source = ConformPreview.probe(listedRate: 50)
        #expect(source.captureRate == 50)
        #expect(!source.isVariableFrameRate)
        #expect(ConformPreview.availability(for: source).targets.contains(25))
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

    @Test func fiftyVersusTwentyFiveIsHighFrameRateNotVFR() {
        let source = ConformPreview.probe(
            nominalFrameRate: 25, minFrameDurationSeconds: 1 / 50)
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

    @Test func letterboxedFeedIsSmallerThanTheScreen() {
        let screen = CGRect(x: 0, y: 0, width: 844, height: 390)
        let feed = PlaybackVideoLayout.aspectFitRect(
            videoSize: CGSize(width: 3840, height: 2160), in: screen)
        #expect(feed.height <= screen.height + 0.01)
        #expect(feed.width < screen.width - 1)
        #expect(abs(feed.midY - screen.midY) < 0.01)
        #expect(abs(feed.width / feed.height - 16 / 9) < 0.01)
    }
}
