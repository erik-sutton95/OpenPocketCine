import CoreImage
import XCTest

@testable import OpenPocketCine

final class DesqueezeAssistTests: XCTestCase {
    private let keys = [
        "OpenPocketCine.Assist.v1", "OpenPocketCine.PlaybackAssists.v1",
        "OpenPocketCine.CleanViewPins.v1",
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testPresetsAndHundredthStepsDoNotSelectANeighboringPreset() {
        XCTAssertEqual(DesqueezeRatio.allCases.map(\.factor), [1.1, 1.2, 1.33, 1.5, 1.6, 1.8, 2])
        for step in 100...200 {
            let factor = Double(step) / 100
            XCTAssertEqual(DesqueezeAssist.snap(factor), factor, accuracy: 0.000_001)
        }
        XCTAssertNil(DesqueezeRatio.matching(1.32))
        XCTAssertNil(DesqueezeRatio.matching(1.34))
        XCTAssertEqual(DesqueezeAssist.snap(1.337), 1.34)
        XCTAssertEqual(DesqueezeAssist.snap(1.005), 1.01)
        XCTAssertEqual(DesqueezeAssist.snap(1.335), 1.34)
        XCTAssertEqual(DesqueezeAssist.snap(0.5), 1)
        XCTAssertEqual(DesqueezeAssist.snap(3), 2)
        XCTAssertEqual(DesqueezeAssist.snap(.nan), 1.33)
        XCTAssertEqual(DesqueezeAssist.snap(.infinity), 1.33)
    }

    func testCustomChoiceSurvivesPresetCrossingsAndRestart() {
        let assist = LiveAssistState()
        XCTAssertFalse(assist.desqueeze)
        assist.selectDesqueezeCustom()
        assist.updateDesqueezeCustom(1.50)
        XCTAssertTrue(assist.desqueezeCustom)
        assist.updateDesqueezeCustom(1.47)
        assist.selectDesqueezePreset(.x2)
        XCTAssertFalse(assist.desqueezeCustom)
        assist.selectDesqueezeCustom()
        XCTAssertEqual(assist.desqueezeFactor, 1.47)
        assist.desqueezeHorizontal = false
        assist.toggle(.desqueeze)

        let restored = LiveAssistState()
        XCTAssertTrue(restored.desqueeze)
        XCTAssertTrue(restored.desqueezeCustom)
        XCTAssertFalse(restored.desqueezeHorizontal)
        XCTAssertEqual(restored.desqueezeFactor, 1.47)
        XCTAssertEqual(restored.desqueezeCustomFactor, 1.47)
    }

    func testLegacySnapshotRestoresAllOtherPreferencesAndInfersCustom() throws {
        let assist = LiveAssistState()
        assist.grid = true
        assist.desqueezeFactor = 1.65
        let data = try XCTUnwrap(OperatorPrefs.encoded(assist))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "desqueezeCustom")
        json.removeValue(forKey: "desqueezeCustomFactor")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        UserDefaults.standard.set(legacy, forKey: keys[0])
        let restored = LiveAssistState()
        XCTAssertTrue(restored.grid)
        XCTAssertTrue(restored.desqueezeCustom)
        XCTAssertEqual(restored.desqueezeFactor, 1.65)
    }

    func testLivePlaybackAndCleanVisibilityRemainIndependent() {
        let assist = LiveAssistState()
        assist.desqueezeFactor = 2
        assist.toggle(.desqueeze)
        XCTAssertEqual(assist.effects.desqueezeFactor, 2)
        XCTAssertEqual(assist.playbackEffects.desqueezeFactor, 1)
        assist.togglePlayback(.desqueeze)
        XCTAssertEqual(assist.playbackEffects.desqueezeFactor, 2)
        assist.clean = true
        assist.cleanViewPinnedTools = []
        XCTAssertEqual(assist.effects.desqueezeFactor, 1)
        XCTAssertEqual(assist.playbackEffects.desqueezeFactor, 2)
        XCTAssertTrue(assist.desqueeze)
        XCTAssertEqual(LiveAssistState().playbackEffects.desqueezeFactor, 2)
    }

    func testHorizontalAndVerticalFitTheEntireCorrectedRaster() {
        let source = CGSize(width: 1920, height: 1080)
        let viewport = CGRect(x: 20, y: 10, width: 800, height: 600)
        var fx = LiveImageEffects()
        fx.desqueezeFactor = 2
        let wide = DesqueezeAssist.presentationRect(sourceSize: source, in: viewport, effects: fx)
        XCTAssertEqual(wide.width, 800)
        XCTAssertEqual(wide.height, 225)
        XCTAssertEqual(wide.midX, viewport.midX)
        XCTAssertEqual(wide.midY, viewport.midY)
        fx.desqueezeHorizontal = false
        let tall = DesqueezeAssist.presentationRect(sourceSize: source, in: viewport, effects: fx)
        XCTAssertEqual(tall.height, 600)
        XCTAssertEqual(tall.width, 533.333_333, accuracy: 0.000_1)
        XCTAssertEqual(tall.midX, viewport.midX)
        XCTAssertEqual(tall.midY, viewport.midY)
    }

    func testFramingMatchesCorrectedSquareInsideLiveRasterAndHonorsCleanPins() {
        let assist = LiveAssistState()
        assist.desqueeze = true
        assist.desqueezeFactor = 2
        let host = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let framing = overlayFeedRect(host, assist, pictureAspect: 1)
        XCTAssertEqual(framing, CGRect(x: 350, y: 225, width: 900, height: 450))
        assist.clean = true
        assist.cleanViewPinnedTools = []
        XCTAssertEqual(
            overlayFeedRect(host, assist, pictureAspect: 1),
            CGRect(x: 350, y: 0, width: 900, height: 900))
    }

    func testCompositorCorrectsExtentOnceWithLUTAndPixelWarnings() {
        let source = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4))
            .cropped(to: CGRect(x: 0, y: 0, width: 160, height: 90))
        var fx = LiveImageEffects()
        fx.desqueezeFactor = 2
        fx.peaking = true
        fx.zebra = true
        // A real identity cube exercises the LUT/overlay composition before the stretch.
        fx.lutDimension = 2
        var cube: [Float] = []
        for index in 0..<8 {
            let red = Float(index % 2)
            let green = Float((index / 2) % 2)
            let blue = Float(index / 4)
            cube.append(contentsOf: [red, green, blue, 1])
        }
        fx.lutRGBA = cube.withUnsafeBytes { Data($0) }
        let wide = LiveMonitorCompositor.applyProduct(to: source, effects: fx).image
        XCTAssertEqual(wide.extent.size, CGSize(width: 320, height: 90))
        XCTAssertEqual(wide.extent.midX, source.extent.midX)
        XCTAssertEqual(wide.extent.midY, source.extent.midY)
        let rect = DesqueezeAssist.presentationRect(
            sourceSize: source.extent.size, in: source.extent, effects: fx)
        XCTAssertEqual(rect.width / rect.height, wide.extent.width / wide.extent.height)
        fx.desqueezeHorizontal = false
        let tall = LiveMonitorCompositor.applyProduct(to: source, effects: fx).image
        XCTAssertEqual(tall.extent.size, CGSize(width: 160, height: 180))
    }

    func testPlaybackZoomReclampsAfterChangingDirection() {
        var zoom = AnchoredPinchZoom()
        zoom.pinchChanged(
            magnification: 3, startAnchor: .center, size: CGSize(width: 800, height: 225))
        zoom.panChanged(translation: CGSize(width: 900, height: 900))
        zoom.endGesture(size: CGSize(width: 400, height: 600))
        XCTAssertEqual(zoom.offset.width, 400)
        XCTAssertEqual(zoom.offset.height, 600)
    }

    func testPortraitRasterAndRecordedPictureUseTheSameOpticalCorrection() {
        let assist = LiveAssistState()
        assist.desqueeze = true
        assist.desqueezeFactor = 2
        let host = CGRect(x: 0, y: 0, width: 400, height: 800)
        let raster = DesqueezeAssist.presentationRect(
            sourceSize: CGSize(width: 9, height: 16), in: host, effects: assist.effects)
        let framing = overlayFeedRect(
            host, assist, pictureAspect: 9.0 / 16, sourceAspect: 9.0 / 16)
        XCTAssertEqual(framing, raster)
        XCTAssertEqual(raster.width / raster.height, 18.0 / 16, accuracy: 0.000_1)
        XCTAssertEqual(raster.midY, host.midY)
        // Focus maps against the corrected raster: quarter-height stays .25,
        // independent of the letterbox padding around it.
        let quarterY = raster.minY + raster.height * 0.25
        XCTAssertEqual((quarterY - raster.minY) / raster.height, 0.25, accuracy: 0.000_001)
    }

    @MainActor
    func testPlaybackInspectorInheritsPlaybackCorrectionRatherThanHiddenLiveState() {
        let assist = LiveAssistState()
        assist.desqueeze = true
        assist.desqueezeFactor = 2
        assist.gradesClip = true
        var preview = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .grid, transfer: .rec709)
        XCTAssertEqual(preview.desqueezeFactor, 1)
        assist.togglePlayback(.desqueeze)
        preview = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .grid, transfer: .rec709)
        XCTAssertEqual(preview.desqueezeFactor, 2)
        assist.togglePlayback(.desqueeze)
        preview = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .desqueeze, transfer: .rec709)
        XCTAssertEqual(
            preview.desqueezeFactor, 2, "The selected inspector previews an inactive tool")
        XCTAssertFalse(assist.isPlaybackVisible(.desqueeze))
    }
}
