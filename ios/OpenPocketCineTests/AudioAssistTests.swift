import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class AudioAssistTests: XCTestCase {
    func testAudioOptionsAffectPresentationOnly() {
        XCTAssertEqual(AudioAssist.longPressPanelWidth, 400)
        XCTAssertEqual(AudioAssist.panelSize, CGSize(width: 28, height: 168))
        XCTAssertEqual(AudioAssist.barCrossAxis, 10)
        XCTAssertEqual(
            AudioAssist.panelSize(orientation: .horizontal), CGSize(width: 168, height: 28))
        XCTAssertEqual(
            AudioAssist.panelSize(orientation: .vertical).width,
            AudioAssist.panelSize(orientation: .horizontal).height)
        XCTAssertEqual(
            AudioAssist.helpCopy,
            "Meters the camera's audio. Available while live view is up.")
        XCTAssertEqual(AudioAssist.displayedSensitivity(nil), "—")
        XCTAssertEqual(AudioAssist.displayedSensitivity("  stereo "), "STEREO")
        XCTAssertTrue(LiveAssistTool.audioMeters.hasConfiguration)
    }

    func testFreshMeterStartsAtLeftAndCanvasVerticalCenter() {
        let canvas = CGRect(x: 40, y: 20, width: 844, height: 390)
        let movement = CGRect(x: 54, y: 70, width: 812, height: 268)
        let center = AudioAssist.center(
            stored: nil, size: AudioAssist.panelSize, canvas: canvas, movement: movement)
        XCTAssertEqual(center.x, movement.minX + AudioAssist.panelSize.width / 2)
        XCTAssertEqual(center.y, canvas.midY)
    }

    func testSavedMeterPositionIsReprojectedAndClampedForItsNewShape() {
        let original = CGRect(x: 0, y: 0, width: 800, height: 400)
        let stored = AudioAssist.StoredCenter(CGPoint(x: 760, y: 200), in: original)
        let canvas = CGRect(x: 20, y: 30, width: 400, height: 800)
        let movement = canvas.insetBy(dx: 12, dy: 24)
        let size = AudioAssist.panelSize(orientation: .horizontal)
        let center = AudioAssist.center(
            stored: stored, size: size, canvas: canvas, movement: movement)
        XCTAssertEqual(center.x, movement.maxX - size.width / 2)
        XCTAssertEqual(center.y, canvas.midY)
    }

    @MainActor
    func testMovingAndChangingMeterOptionsPreservesBothSavedPlacements() throws {
        let suite = "AudioAssistTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AudioAssistStore(defaults: defaults)
        XCTAssertNil(store.options.landscapeCenter)
        XCTAssertNil(store.options.portraitCenter)
        XCTAssertFalse(store.options.showsDB)
        let landscape = CGRect(x: 0, y: 0, width: 800, height: 400)
        let portrait = CGRect(x: 0, y: 0, width: 400, height: 800)
        let first = CGPoint(x: 430, y: 200)
        let second = CGPoint(x: 220, y: 350)
        store.setCenter(first, in: landscape)
        store.setCenter(second, in: portrait)
        store.options.orientation = .horizontal
        store.options.showsDB = true
        store.persist()
        let restored = AudioAssistStore(defaults: defaults)
        XCTAssertEqual(restored.options.orientation, .horizontal)
        XCTAssertTrue(restored.options.showsDB)
        let restoredLandscape = try XCTUnwrap(
            restored.storedCenter(in: landscape)?.point(in: landscape))
        let restoredPortrait = try XCTUnwrap(
            restored.storedCenter(in: portrait)?.point(in: portrait))
        XCTAssertEqual(restoredLandscape.x, first.x, accuracy: 0.000_001)
        XCTAssertEqual(restoredLandscape.y, first.y, accuracy: 0.000_001)
        XCTAssertEqual(restoredPortrait.x, second.x, accuracy: 0.000_001)
        XCTAssertEqual(restoredPortrait.y, second.y, accuracy: 0.000_001)
    }

    func testMeterPresentationClampsInvalidValuesWithoutChangingMeasurements() {
        XCTAssertEqual(AudioAssist.levelFraction(.nan), 0)
        XCTAssertEqual(AudioAssist.levelFraction(-120), 0)
        XCTAssertEqual(AudioAssist.levelFraction(12), 1)
        XCTAssertEqual(AudioAssist.dbText(.infinity), "−∞")
        XCTAssertEqual(AudioAssist.dbText(AudioMeterBallistics.floorDB), "−∞")
        XCTAssertEqual(AudioAssist.dbText(-12), "-12")
    }

    func testMeterReadsCameraStatusNotFloorDefaults() {
        var status = CameraStatus()
        XCTAssertEqual(status.audioMeters, .silent)
        // live1.pcap louder frame: L=8 R=9 on the 0…14 segment scale.
        let louder: [UInt8] = [
            0x00, 0x00, 0x00, 0x08, 0x00, 0x03, 0x00, 0x08, 0x00, 0x09, 0x00, 0x64, 0x00, 0x64,
        ]
        _ = CameraStatusDecoder.applySubscribePush(
            SubscribePush.pack(name: CamAudioStatus.subscribeKey, value: louder),
            to: &status)
        XCTAssertEqual(
            status.audioMeters.left.levelDB,
            AudioMeterBallistics.floorDB * (1 - 8.0 / 14.0),
            accuracy: 1e-9)
        XCTAssertEqual(
            status.audioMeters.right.levelDB,
            AudioMeterBallistics.floorDB * (1 - 9.0 / 14.0),
            accuracy: 1e-9)
        XCTAssertNotEqual(status.audioMeters, .silent)
    }

    func testCancelledPointerDoesNotRearmOrPersist() {
        var drag = AudioMeterDragLifecycle()
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let movement = bounds.insetBy(dx: 12, dy: 24)
        let size = AudioAssist.panelSize
        let start = AudioAssist.center(
            stored: nil, size: size, canvas: bounds, movement: movement)
        drag.applyChanged(
            translation: CGSize(width: 40, height: 0), visualCenter: start,
            currentBounds: bounds, size: size, canvas: bounds, movement: movement,
            locked: false, sceneActive: true, usable: true)
        XCTAssertNotNil(drag.center)
        drag.cancel(pointerActive: true)
        XCTAssertTrue(drag.cancelled)
        XCTAssertNil(drag.origin)
        XCTAssertNil(drag.center)
        drag.applyChanged(
            translation: CGSize(width: 120, height: 10), visualCenter: start,
            currentBounds: bounds, size: size, canvas: bounds, movement: movement,
            locked: false, sceneActive: true, usable: true)
        XCTAssertNil(drag.center)
        XCTAssertNil(
            drag.persistableCenter(
                locked: false, sceneActive: true, usable: true, currentBounds: bounds))
        drag.reset(pointerActive: true)
        XCTAssertFalse(drag.cancelled)
    }

    func testInactiveCancelAllowsALaterDragToPersist() {
        var drag = AudioMeterDragLifecycle()
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let movement = bounds.insetBy(dx: 12, dy: 24)
        let size = AudioAssist.panelSize
        let start = AudioAssist.center(
            stored: nil, size: size, canvas: bounds, movement: movement)
        drag.cancel(pointerActive: false)
        XCTAssertFalse(drag.cancelled)
        drag.applyChanged(
            translation: CGSize(width: 36, height: 0), visualCenter: start,
            currentBounds: bounds, size: size, canvas: bounds, movement: movement,
            locked: false, sceneActive: true, usable: true)
        let persisted = drag.persistableCenter(
            locked: false, sceneActive: true, usable: true, currentBounds: bounds)
        XCTAssertEqual(persisted, drag.center)
        XCTAssertNotEqual(persisted, start)
    }

    func testDragDoesNotPersistWhenLockedInactiveUnusableOrBoundsChange() {
        var drag = AudioMeterDragLifecycle()
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 400)
        let moved = CGRect(x: 0, y: 0, width: 400, height: 800)
        let movement = bounds.insetBy(dx: 12, dy: 24)
        let size = AudioAssist.panelSize
        let start = AudioAssist.center(
            stored: nil, size: size, canvas: bounds, movement: movement)
        drag.applyChanged(
            translation: CGSize(width: 24, height: 0), visualCenter: start,
            currentBounds: bounds, size: size, canvas: bounds, movement: movement,
            locked: false, sceneActive: true, usable: true)
        XCTAssertNil(
            drag.persistableCenter(
                locked: true, sceneActive: true, usable: true, currentBounds: bounds))
        XCTAssertNil(
            drag.persistableCenter(
                locked: false, sceneActive: false, usable: true, currentBounds: bounds))
        XCTAssertNil(
            drag.persistableCenter(
                locked: false, sceneActive: true, usable: false, currentBounds: bounds))
        XCTAssertNil(
            drag.persistableCenter(
                locked: false, sceneActive: true, usable: true, currentBounds: moved))
        drag.cancel(pointerActive: true)
        drag.applyChanged(
            translation: CGSize(width: 24, height: 0), visualCenter: start,
            currentBounds: bounds, size: size, canvas: bounds, movement: movement,
            locked: false, sceneActive: false, usable: true)
        XCTAssertNil(drag.center)
        drag.reset(pointerActive: false)
        drag.applyChanged(
            translation: CGSize(width: 24, height: 0), visualCenter: start,
            currentBounds: bounds, size: size, canvas: bounds, movement: movement,
            locked: false, sceneActive: true, usable: false)
        XCTAssertNil(drag.center)
    }

    func testAudioOverlayHidesHitsWhenLockedOrUnusableAndUsesFourPointSlop() {
        let usable = CGRect(x: 0, y: 0, width: 200, height: 200)
        let tiny = CGRect(x: 0, y: 0, width: 55, height: 55)
        XCTAssertTrue(AudioMeterOverlay.allowsHits(locked: false, movement: usable))
        XCTAssertFalse(AudioMeterOverlay.allowsHits(locked: true, movement: usable))
        XCTAssertFalse(AudioMeterOverlay.allowsHits(locked: false, movement: tiny))
        XCTAssertEqual(AudioMeterOverlay.pointerSlop, 4)
        XCTAssertFalse(ScopePanelPlacement.isUsable(tiny))
    }
}
