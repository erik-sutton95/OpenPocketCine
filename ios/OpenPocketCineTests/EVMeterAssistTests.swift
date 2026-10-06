import AVFoundation
import Observation
import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI
import XCTest
import OpenCineApple
import OpenCineMedia
import MonitorPresentation

@testable import OpenPocketCine

@MainActor
final class EVMeterAssistTests: XCTestCase {
    func testFeedRecoveryRetiresCameraMeterWithoutChangingCompensation() async {
        let session = CameraSession()
        let peer = ConnectionDonorPeer(cached: true)
        defer { session.disconnect(); withExtendedLifetime(peer) {} }
        guard await peer.admitExistingConnection(session) else { return }
        session.status.evComp = EvComp(thirds: 3)
        session.status.meteredEv = EvComp(thirds: -4)
        XCTAssertTrue(session.startFeedRecovery { _ in })
        XCTAssertNil(session.status.meteredEv)
        XCTAssertEqual(session.status.evComp?.thirds, 3)
        await Task.yield()
    }

    func testEVTogglePersistsWithoutRequestingImageProcessing() {
        XCTAssertTrue(MonitorAssistSelection.toolbarCases.contains(.evMeter))
        XCTAssertTrue(MonitorAssistSelection.settingsCases.contains(.evMeter))
        XCTAssertFalse(MonitorAssistSelection.cleanPinCases.contains(.evMeter))
        XCTAssertFalse(MonitorAssistSelection.playbackToolbarCases.contains(.evMeter))
        XCTAssertFalse(MonitorAssistSelection.evMeter.hasConfiguration)
        let assist = LiveAssistState()
        assist.clean = false
        assist.evMeter = false
        let baseline = assist.effects
        XCTAssertFalse(assist.isVisible(.evMeter))
        assist.evMeter = true
        XCTAssertTrue(assist.isVisible(.evMeter))
        XCTAssertEqual(assist.effects, baseline)
        XCTAssertEqual(assist.effects.withInspectorDemand(.evMeter), baseline)
        let restored = LiveAssistState()
        MonitorAssistSnapshot(assist).apply(to: restored)
        XCTAssertTrue(restored.evMeter)
        restored.clean = true
        restored.cleanViewPinnedTools = [.evMeter]
        restored.playbackVisibleTools = [.evMeter]
        XCTAssertFalse(restored.isVisible(.evMeter))
        XCTAssertFalse(restored.isPlaybackVisible(.evMeter))
        XCTAssertFalse(restored.playbackEffects.needsSample)
        assist.evMeter = false
        MonitorAssistSnapshot(assist).apply(to: restored)
        XCTAssertFalse(restored.evMeter)
    }

    func testSlimMeterStaysInsideTheLeftFeedEdgeAndAboveCenter() {
        for feed in [
            CGRect(x: 40, y: 80, width: 800, height: 450),
            CGRect(x: 10, y: 200, width: 370, height: 208),
            CGRect(x: 100, y: 50, width: 450, height: 800),
            CGRect(x: 0, y: 0, width: 200, height: 100),
        ] {
            let frame = CameraEVMeter.frame(in: feed)
            XCTAssertTrue(feed.contains(frame))
            XCTAssertEqual(frame.minX, feed.minX + 6)
            XCTAssertLessThanOrEqual(frame.midY, feed.midY)
            XCTAssertEqual(frame.width, 28)
            XCTAssertEqual(frame.height, min(180, feed.height - 12))
        }
        XCTAssertEqual(CameraEVMeter.frame(in: .zero), .zero)
    }

    func testMeterMovesUpToClearToolbarBeforeReducingItsHeight() {
        let feed = CGRect(x: 40, y: 80, width: 800, height: 450)
        let palette = CGRect(x: 18, y: 350, width: 100, height: 120)
        let frame = CameraEVMeter.frame(in: feed, avoiding: palette)
        XCTAssertEqual(frame.minX, feed.minX + 6)
        XCTAssertEqual(frame.height, 180)
        XCTAssertEqual(frame.maxY, palette.minY - 12)
        XCTAssertFalse(frame.intersects(palette))
    }

    func testMeterNeverOverlapsExpandedToolbarEvenWhenVerticalSpaceIsLimited() {
        let feed = CGRect(x: 0, y: 0, width: 400, height: 300)
        for palette in [
            CGRect(x: 0, y: 125, width: 100, height: 175),
            CGRect(x: 0, y: 0, width: 100, height: 180),
            CGRect(x: 0, y: 40, width: 100, height: 240),
        ] {
            let frame = CameraEVMeter.frame(in: feed, avoiding: palette)
            if !frame.isEmpty {
                XCTAssertTrue(feed.contains(frame))
                XCTAssertFalse(frame.intersects(palette.insetBy(dx: 0, dy: -11.9)))
                XCTAssertGreaterThanOrEqual(frame.height, 72)
            }
        }
        XCTAssertEqual(
            CameraEVMeter.frame(in: feed, avoiding: feed), .zero,
            "A fully covered left edge hides the meter until the palette closes")
    }

    func testChangingPlaybackItemsRetiresThePreviousScopeSamplesBeforeLoading() async throws {
        let samples = LiveFrameSampleBus()
        let session = PlaybackFeedSession()
        session.setEffects(
            MonitorFrameEffects(histogram: true).playbackFrameEffects, transfer: .rec709,
            sampleBus: samples)
        let fixture = try await PlaybackOutputFixture.make(in: self)
        defer { session.shutdown(); fixture.close() }
        let first = fixture.item
        fixture.prepare(session)
        try await fixture.publishScopes(using: session, samples: samples, in: self)
        XCTAssertGreaterThan(samples.playbackBundle?.samples.histogramLuma[180] ?? 0, 0)
        session.beginSourceChange()
        XCTAssertNil(samples.playbackBundle)
        XCTAssertFalse(first.outputs.contains(where: { $0 === session.output }))
        let next = AVPlayerItem(asset: AVMutableComposition())
        session.prepare(next)
        XCTAssertNil(samples.playbackBundle)
        XCTAssertTrue(next.outputs.contains(where: { $0 === session.output }))
        session.shutdown()
    }
}
