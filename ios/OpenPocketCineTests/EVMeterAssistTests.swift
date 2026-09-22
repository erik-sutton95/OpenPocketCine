import AVFoundation
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class EVMeterAssistTests: XCTestCase {
    func testFeedRecoveryRetiresCameraMeterWithoutChangingCompensation() async {
        let session = CameraSession()
        session.status.evComp = EvComp(thirds: 3)
        session.status.meteredEv = EvComp(thirds: -4)
        session.startFeedRecovery {}
        XCTAssertNil(session.status.meteredEv)
        XCTAssertEqual(session.status.evComp?.thirds, 3)
        await Task.yield()
    }

    func testEVTogglePersistsWithoutRequestingImageProcessing() {
        XCTAssertTrue(LiveAssistTool.toolbarCases.contains(.evMeter))
        XCTAssertTrue(LiveAssistTool.settingsCases.contains(.evMeter))
        XCTAssertFalse(LiveAssistTool.cleanPinCases.contains(.evMeter))
        XCTAssertFalse(LiveAssistTool.playbackToolbarCases.contains(.evMeter))
        XCTAssertFalse(LiveAssistTool.evMeter.hasConfiguration)
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
        OperatorPrefs.Snapshot(assist).apply(to: restored)
        XCTAssertTrue(restored.evMeter)
        restored.clean = true
        restored.cleanViewPinnedTools = [.evMeter]
        restored.playbackVisibleTools = [.evMeter]
        XCTAssertFalse(restored.isVisible(.evMeter))
        XCTAssertFalse(restored.isPlaybackVisible(.evMeter))
        XCTAssertFalse(restored.playbackEffects.needsSample)
        assist.evMeter = false
        OperatorPrefs.Snapshot(assist).apply(to: restored)
        XCTAssertFalse(restored.evMeter)
    }

    func testFixedMeterStaysInsideTheLeftFeedEdgeAndVerticallyCentered() {
        for feed in [
            CGRect(x: 40, y: 80, width: 800, height: 450),
            CGRect(x: 10, y: 200, width: 370, height: 208),
            CGRect(x: 100, y: 50, width: 450, height: 800),
            CGRect(x: 0, y: 0, width: 200, height: 100),
        ] {
            let frame = CameraEVMeter.frame(in: feed)
            XCTAssertTrue(feed.contains(frame))
            XCTAssertEqual(frame.minX, feed.minX + 6)
            XCTAssertEqual(frame.midY, feed.midY)
            XCTAssertEqual(frame.width, 36)
            XCTAssertEqual(frame.height, min(156, feed.height - 12))
        }
        XCTAssertEqual(CameraEVMeter.frame(in: .zero), .zero)
    }

    func testLandscapeScaleFitsAboveTheCollapsedAssistPaletteWithoutMoving() {
        let feed = CGRect(x: 40, y: 80, width: 800, height: 450)
        let palette = CGRect(x: 18, y: 350, width: 100, height: 120)
        let frame = CameraEVMeter.frame(in: feed, avoiding: palette)
        XCTAssertEqual(frame.minX, feed.minX + 6)
        XCTAssertEqual(frame.midY, feed.midY)
        XCTAssertEqual(frame.maxY, palette.minY - 8)
        XCTAssertFalse(frame.intersects(palette))
    }

    func testChangingPlaybackItemsRetiresThePreviousScopeSamplesBeforeLoading() {
        let samples = LiveFrameSampleBus()
        let session = PlaybackFeedSession()
        session.setEffects(LiveImageEffects(histogram: true), transfer: .rec709, sampleBus: samples)
        let first = AVPlayerItem(asset: AVMutableComposition())
        session.prepare(first)
        samples.playbackBundle = ScopeAssistBundle()
        samples.playbackBundle?.samples.histogramLuma[180] = 100
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
