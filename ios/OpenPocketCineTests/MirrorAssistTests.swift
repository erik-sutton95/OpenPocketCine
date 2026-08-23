import CoreImage
import XCTest

@testable import OpenPocketCine

final class MirrorAssistTests: XCTestCase {
    func testMirrorIsTapOnlyLikeOpenZCine() {
        XCTAssertFalse(
            LiveAssistTool.mirror.hasConfiguration,
            "OpenZCine mirror has no long-press options")
    }

    func testFeedScaleIsHorizontalNotVertical() {
        let off = MirrorAssist.feedScale(mirrored: false)
        XCTAssertEqual(off.width, 1)
        XCTAssertEqual(off.height, 1)

        let on = MirrorAssist.feedScale(mirrored: true)
        XCTAssertEqual(on.width, -1, "OpenZCine mirror is a negative X scale")
        XCTAssertEqual(on.height, 1, "Y must stay +1 — a negative Y is a vertical flip")
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
