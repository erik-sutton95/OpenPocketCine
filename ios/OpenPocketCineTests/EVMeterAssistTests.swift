import AVFoundation
import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class EVMeterAssistTests: XCTestCase {
    func testEVAloneRequestsTheSharedHistogramWithoutGPUOrPointWork() {
        var effects = LiveImageEffects(evMeter: true)
        XCTAssertTrue(effects.needsSample)
        XCTAssertTrue(effects.needsScopes)
        XCTAssertFalse(effects.needsGPUFeed)
        XCTAssertFalse(effects.needsScopePoints)
        XCTAssertEqual(effects.activeScopeCount, 1)
        effects.ndMeter = true
        effects.histogram = true
        XCTAssertEqual(effects.activeScopeCount, 3)
        XCTAssertEqual(
            PocketScopeSampler.minInterval(
                activeScopeCount: effects.activeScopeCount, thermalState: .nominal), 0.1)
        XCTAssertFalse(LiveImageEffects().needsScopes)
    }

    func testCleanAndPlaybackVisibilityDriveDemand() {
        let assist = LiveAssistState()
        assist.evMeter = true
        assist.clean = true
        assist.cleanViewPinnedTools = []
        XCTAssertFalse(assist.effects.evMeter)
        assist.cleanViewPinnedTools = [.evMeter]
        XCTAssertTrue(assist.effects.evMeter)
        assist.playbackVisibleTools = []
        XCTAssertFalse(assist.playbackEffects.evMeter)
        assist.playbackVisibleTools = [.evMeter]
        XCTAssertTrue(assist.playbackEffects.evMeter)
    }

    func testInspectorCanMeterWithTheToolOff() {
        let effects = LiveImageEffects().withInspectorDemand(.evMeter)
        XCTAssertTrue(effects.evMeter)
        XCTAssertTrue(effects.needsScopes)
        XCTAssertFalse(effects.needsGPUFeed)
    }

    func testPlaybackAndResetCannotShowRetainedCameraValues() {
        let samples = LiveFrameSampleBus()
        samples.bundle.samples.histogramLuma[128] = 100
        XCTAssertNotNil(EVMeterAssist.reading(from: samples).stops)
        samples.usesPlaybackSource = true
        XCTAssertNil(EVMeterAssist.reading(from: samples).stops)
        samples.playbackBundle = ScopeAssistBundle()
        samples.playbackBundle?.samples.histogramLuma[180] = 100
        XCTAssertNotNil(EVMeterAssist.reading(from: samples).stops)
        samples.reset()
        XCTAssertNil(EVMeterAssist.reading(from: samples).stops)
    }

    func testChangingPlaybackItemsRetiresThePreviousMeterBeforeLoading() {
        let samples = LiveFrameSampleBus()
        let session = PlaybackFeedSession()
        session.setEffects(LiveImageEffects(evMeter: true), transfer: .rec709, sampleBus: samples)
        let first = AVPlayerItem(asset: AVMutableComposition())
        session.prepare(first)
        samples.playbackBundle = ScopeAssistBundle()
        samples.playbackBundle?.samples.histogramLuma[180] = 100
        XCTAssertNotNil(EVMeterAssist.reading(from: samples).stops)
        session.beginSourceChange()
        XCTAssertNil(EVMeterAssist.reading(from: samples).stops)
        XCTAssertFalse(first.outputs.contains(where: { $0 === session.output }))
        let next = AVPlayerItem(asset: AVMutableComposition())
        session.prepare(next)
        XCTAssertNil(EVMeterAssist.reading(from: samples).stops)
        XCTAssertTrue(next.outputs.contains(where: { $0 === session.output }))
        session.shutdown()
    }

    func testPositionAndSizePersistSeparatelyForEachOrientation() throws {
        let suite = "EVMeterAssistTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let landscape = CGRect(x: 0, y: 0, width: 900, height: 400)
        let portrait = CGRect(x: 0, y: 0, width: 400, height: 900)
        let store = EVMeterStore(defaults: defaults)
        XCTAssertEqual(store.center(in: landscape), CGPoint(x: 450, y: 200))
        store.setCenter(CGPoint(x: 225, y: 100), in: landscape)
        store.setCenter(CGPoint(x: 300, y: 450), in: portrait)
        store.setScale(1.4)
        let restored = EVMeterStore(defaults: defaults)
        XCTAssertEqual(restored.center(in: landscape), CGPoint(x: 225, y: 100))
        XCTAssertEqual(restored.center(in: portrait), CGPoint(x: 300, y: 450))
        XCTAssertEqual(restored.options.scale, 1.4)
    }
}
