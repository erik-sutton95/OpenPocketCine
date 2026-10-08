import MonitorPresentation
import CoreImage
import OpenCineCameraControls
import OpenPocketViewCore
import XCTest
import OpenCineMedia

@testable import OpenPocketCine

final class DesqueezeAssistTests: XCTestCase {
    /// This test's monitored source (XCTest makes a fresh one per test).
    private let ceiling = OpenCineMedia.ScopeExposureCeiling(
        profile: PocketMonitorCalibration.clipProfile)
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

    @MainActor
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

    @MainActor
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

    @MainActor
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

    @MainActor
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
        var fx = MonitorFrameEffects()
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
        var zoom = MonitorPlaybackZoom()
        zoom.pinchChanged(
            magnification: 3, startAnchorX: 0.5, startAnchorY: 0.5,
            size: CGSize(width: 800, height: 225))
        zoom.panChanged(translation: CGSize(width: 900, height: 900))
        zoom.endGesture(size: CGSize(width: 400, height: 600))
        XCTAssertEqual(zoom.offset.width, 400)
        XCTAssertEqual(zoom.offset.height, 600)
    }

    @MainActor
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
            assist: assist, tool: .grid, transfer: .rec709, ceiling: ceiling)
        XCTAssertEqual(preview.desqueezeFactor, 1)
        assist.togglePlayback(.desqueeze)
        preview = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .grid, transfer: .rec709, ceiling: ceiling)
        XCTAssertEqual(preview.desqueezeFactor, 2)
        assist.togglePlayback(.desqueeze)
        preview = AssistInspectorPreviewPolicy.imageOptions(
            assist: assist, tool: .desqueeze, transfer: .rec709, ceiling: ceiling)
        XCTAssertEqual(
            preview.desqueezeFactor, 2, "The selected inspector previews an inactive tool")
        XCTAssertFalse(assist.isPlaybackVisible(.desqueeze))
    }
}
