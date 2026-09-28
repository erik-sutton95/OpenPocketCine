import CoreImage
import XCTest

@testable import OpenPocketCine

final class MirrorAssistTests: XCTestCase {
    func testFeedScaleIsHorizontalNotVertical() {
        let off = MirrorAssist.feedScale(mirrored: false)
        XCTAssertEqual(off.width, 1)
        XCTAssertEqual(off.height, 1)

        let on = MirrorAssist.feedScale(mirrored: true)
        XCTAssertEqual(on.width, -1, "OpenZCine mirror is a negative X scale")
        XCTAssertEqual(on.height, 1, "Y must stay +1 — a negative Y is a vertical flip")
    }

    func testVerticalFlipIsNegativeYAndComposesWithMirror() {
        let v = MirrorAssist.feedScale(mirrored: false, flippedVertically: true)
        XCTAssertEqual(v.width, 1)
        XCTAssertEqual(v.height, -1)
        let both = MirrorAssist.feedScale(mirrored: true, flippedVertically: true)
        XCTAssertEqual(both.width, -1, "both axes is a 180° turn")
        XCTAssertEqual(both.height, -1)
    }

    func testVerticalFlipMapsTapBackToCameraSpace() {
        // Underslung: the operator taps the top-left of the screen, the camera sees bottom-left.
        let size = CGSize(width: 400, height: 200)
        let p = LiveFeedFocusGesture.cameraPoint(
            CGPoint(x: 100, y: 50), in: size, mirrored: false, flippedVertically: true)
        XCTAssertEqual(p.x, 0.25, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.75, accuracy: 1e-9)
        let box = LiveFeedFocusGesture.cameraBox(
            from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 50), in: size, mirrored: true,
            flippedVertically: true)
        XCTAssertEqual(box.x, 0.75, accuracy: 1e-9)
        XCTAssertEqual(box.y, 0.75, accuracy: 1e-9)
    }

    func testMirrorAxesPersistAndOnlyApplyWhileToolIsOn() {
        let state = LiveAssistState()
        state.mirror = false
        state.mirrorHorizontal = false
        state.mirrorVertical = true
        XCTAssertFalse(state.flipsVertically)
        state.mirror = true
        XCTAssertFalse(state.mirrorsHorizontally)
        XCTAssertTrue(state.flipsVertically)
        XCTAssertTrue(state.effects.mirrorVertical)
        XCTAssertFalse(state.effects.mirror)

        let restored = LiveAssistState()
        OperatorPrefs.Snapshot(state).apply(to: restored)
        XCTAssertFalse(restored.mirrorHorizontal)
        XCTAssertTrue(restored.mirrorVertical)
    }

    func testFeedScalePreservesDesqueezeOnXOnly() {
        let squeeze = CGSize(width: 1.33, height: 1)
        let on = MirrorAssist.feedScale(mirrored: true, squeeze: squeeze)
        XCTAssertEqual(on.width, -1.33, accuracy: 0.0001)
        XCTAssertEqual(on.height, 1)
    }

    func testMirrorAloneDoesNotForceGPUFeed() {
        var fx = LiveImageEffects()
        fx.mirror = true
        XCTAssertFalse(
            fx.needsGPUFeed,
            "OpenZCine keeps mirror off the effects graph so identity HEVC still flips")
    }

    func testCompositorDoesNotFlipRasterWhenMirrorIsSet() {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 4))
        var fx = LiveImageEffects()
        fx.mirror = true
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        XCTAssertEqual(output.extent, source.extent)
        XCTAssertEqual(
            output.extent.minX, source.extent.minX,
            "CI must not apply the old buffer-space flip")
    }
}
