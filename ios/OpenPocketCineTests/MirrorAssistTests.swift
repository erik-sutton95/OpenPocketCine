import CoreImage
import OpenCineAppKit
import OpenCineCameraControls
import XCTest
import OpenCineMedia

@testable import OpenPocketCine

final class MirrorAssistTests: XCTestCase {
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

    @MainActor
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
        MonitorAssistSnapshot(state).apply(to: restored)
        XCTAssertFalse(restored.mirrorHorizontal)
        XCTAssertTrue(restored.mirrorVertical)
    }

    func testMirrorAloneDoesNotForceGPUFeed() {
        var fx = MonitorFrameEffects()
        fx.mirror = true
        XCTAssertFalse(
            fx.needsGPUFeed,
            "OpenZCine keeps mirror off the effects graph so identity HEVC still flips")
    }

    func testCompositorDoesNotFlipRasterWhenMirrorIsSet() {
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 4))
        var fx = MonitorFrameEffects()
        fx.mirror = true
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        XCTAssertEqual(output.extent, source.extent)
        XCTAssertEqual(
            output.extent.minX, source.extent.minX,
            "CI must not apply the old buffer-space flip")
    }
}
