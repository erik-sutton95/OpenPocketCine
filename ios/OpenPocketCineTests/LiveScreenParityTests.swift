import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineDJIApple
import OpenPocketViewCore
import XCTest
import Testing

@testable import OpenPocketCine

/// The live screen moved to OpenCineCameraControls; this app keeps typed values. These pin each
/// against the app's original expression, frozen here, and the level read (10 Hz) for time.
@MainActor
final class LiveScreenParityTests: XCTestCase {
    func testZoomLabelsMatchTheAppForEveryFactor() {
        let model = AppModel()
        for tenth in 5...Int(CamFov.maxFactor * 10) {
            let factor = Double(tenth) / 10
            XCTAssertEqual(
                CamFov.displayLabel(factor: factor, ceiling: model.zoomCeiling),
                CamFov.displayLabel(factor: factor), "\(factor)")
        }
    }

    func testHostValuesMatchTheApp() {
        let model = AppModel()
        XCTAssertEqual(model.liveCapabilities, OsmoMonitorPresentation.capabilities(model.session))
        XCTAssertEqual(model.liveZoomCaption, OsmoMonitorPresentation.zoomCaption(model.session))
        XCTAssertNil(model.livePictureEV)
        #if targetEnvironment(simulator)
            XCTAssertEqual(model.simulatorLiveColorMode, MonitorUIReview.isActive ? nil : .dLog2)
        #endif
    }

    func testLevelReadMatchesTheAppAndIsNotSlower() {
        let model = AppModel()
        let session = model.session
        func shared(_ now: TimeInterval, _ flip: Bool) -> MonitorLevelDisplay {
            model.liveLevelDisplay(session.liveLevelReading.mode(now: now, viewFlip: flip))
        }
        func frozen(_ now: TimeInterval, _ flip: Bool) -> MonitorLevelDisplay {
            LevelAssist.display(session.gimbal.levelReading.mode(now: now, viewFlip: flip))
        }
        for flip in [false, true] {
            XCTAssertEqual(shared(0, flip), frozen(0, flip))
            XCTAssertEqual(shared(1_000, flip), frozen(1_000, flip))
        }
        func best(_ body: () -> Void) -> Double {
            (0..<5).map { _ in
                let start = ProcessInfo.processInfo.systemUptime
                body()
                return ProcessInfo.processInfo.systemUptime - start
            }.min()!
        }
        let iterations = 20_000
        var sink = 0
        let old = best { for i in 0..<iterations { if frozen(Double(i), false) == .unavailable { sink &+= 1 } } }
        let new = best { for i in 0..<iterations { if shared(Double(i), false) == .unavailable { sink &+= 1 } } }
        XCTAssertGreaterThanOrEqual(sink, 0)
        XCTAssertLessThanOrEqual(new, old * 1.5 + 0.002, "shared \(new * 1_000) ms vs app \(old * 1_000) ms")
    }
}


@MainActor @Suite struct TeleprompterAdoptionTests {
    @Test func memberMonitorSharesTheRootScriptAndPlaybackOwner() throws {
        let key = "teleprompter-owner-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: key))
        defer { defaults.removePersistentDomain(forName: key) }
        let owner = MonitorTeleprompterModel(defaults: defaults)
        let root = AppModel(teleprompter: owner)
        let stage = MultiviewSession()
        defer { stage.closeLiveView() }
        let tile = try #require(stage.tiles.first)
        tile.camera = DjiAppleSighting(id: UUID(), name: "Test camera",
            model: .resolve(modelId: 0x19, name: "OsmoNano-Test"), modelId: 0x19)
        tile.controlHost = "192.0.2.30"
        stage.openLiveView(tile, teleprompter: root.teleprompter)
        let member = try #require(tile.liveModel)
        #expect(member.teleprompter === root.teleprompter)
        member.teleprompter.previewPaste("Shared member script")
        member.teleprompter.useCandidate()
        member.teleprompter.position = 80
        #expect(root.teleprompter.script?.text == "Shared member script")
        #expect(root.teleprompter.position == 80)
    }

    @Test func readerPresentationRetainsTheCameraSessionAndDecoder() {
        let storage = UserDefaults.standard
        let keys = ["teleprompter.backgroundOpacity", "teleprompter.showsPreview"]
        let saved = keys.map { storage.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { storage.set(value, forKey: key) }
                else { storage.removeObject(forKey: key) }
            }
        }
        let model = AppModel()
        let session = model.session
        let decoder = session.decoder
        model.assist.teleprompterEnabled = true
        model.teleprompter.backgroundOpacity = 0.6
        model.teleprompter.showsPreview = false
        #expect(model.liveTeleprompter === model.teleprompter)
        #expect(model.session === session && model.session.decoder === decoder)
        #expect(model.shell.cover == nil)
        model.assist.teleprompterEnabled = false
        #expect(model.session === session && model.session.decoder === decoder)
        #expect(model.shell.cover == nil)
    }
}
