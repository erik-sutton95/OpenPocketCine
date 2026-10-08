import CoreImage
import OpenCineCameraVocabulary
import OpenPocketViewCore
import OpenCineCameraControls
import XCTest
import OpenCineApple
import OpenCineMedia

@testable import OpenPocketCine

/// Pins OpenZCine `AssistConfiguration.Zebra` + `AssistQuickSettingsContent.zebraRows`
/// (OperatorPreferences.swift, MonitorPanels.swift, MonitorControls.swift,
/// ImageEffectsCompositor.swift).
final class ZebraAssistTests: XCTestCase {
    /// This test's monitored source (XCTest makes a fresh one per test).
    private let ceiling = DJIScopeExposureCeiling()
    private let assistKey = "OpenPocketCine.Assist.v1"
    private let unitKey = "OpenPocketCine.zebraUnit"
    private var savedAssist: Data?
    private var savedUnit: String?

    override func setUp() {
        super.setUp()
        savedAssist = UserDefaults.standard.data(forKey: assistKey)
        savedUnit = UserDefaults.standard.string(forKey: unitKey)
        UserDefaults.standard.removeObject(forKey: assistKey)
        UserDefaults.standard.removeObject(forKey: unitKey)
    }

    override func tearDown() {
        if let savedAssist {
            UserDefaults.standard.set(savedAssist, forKey: assistKey)
        } else {
            UserDefaults.standard.removeObject(forKey: assistKey)
        }
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: unitKey)
        } else {
            UserDefaults.standard.removeObject(forKey: unitKey)
        }
        super.tearDown()
    }

    /// Per-tool needsGPUFeed / needsOverlayFeed live in LiveFeedOrientationTests.
    func testZebraAloneOverlaysIdentityInsteadOfRemakingThePicture() {
        var zebra = MonitorFrameEffects()
        zebra.zebra = true
        XCTAssertFalse(zebra.replacesIdentityFeed)

        var peaking = MonitorFrameEffects()
        peaking.peaking = true
        XCTAssertFalse(peaking.replacesIdentityFeed)

        var both = MonitorFrameEffects()
        both.zebra = true
        both.peaking = true
        XCTAssertTrue(both.needsOverlayFeed)
        XCTAssertFalse(both.replacesIdentityFeed)

        let cube = BuiltInLook.mono.cube()
        var lutAndZebra = MonitorFrameEffects()
        lutAndZebra.zebra = true
        lutAndZebra.lutDimension = cube.size
        lutAndZebra.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        XCTAssertTrue(lutAndZebra.replacesIdentityFeed)
        XCTAssertFalse(lutAndZebra.needsOverlayFeed)

        var lutAndFalseColor = MonitorFrameEffects()
        lutAndFalseColor.falseColor = true
        lutAndFalseColor.lutDimension = cube.size
        lutAndFalseColor.lutRGBA = lutAndZebra.lutRGBA
        XCTAssertTrue(lutAndFalseColor.replacesIdentityFeed)
        XCTAssertFalse(lutAndFalseColor.needsOverlayFeed)

        var falseAndZebra = MonitorFrameEffects()
        falseAndZebra.zebra = true
        falseAndZebra.falseColor = true
        XCTAssertFalse(falseAndZebra.replacesIdentityFeed)
        XCTAssertTrue(falseAndZebra.needsOverlayFeed)
    }

    func testAssistOverlayIsTransparentWhereZebraDoesNotPaint() {
        // D-Log2 18% grey is outside highlight 100 and midtone 55 ± 5.
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 78)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = MonitorFrameEffects()
        fx.zebra = true
        fx.zebraHighlight = true
        fx.zebraMidtone = false
        fx.colorMode = .dLog2
        fx.zebraHighlightIRE = LiveZebra.highlightIRE
        let overlay = LiveMonitorCompositor.assistOverlay(from: source, effects: fx)
        XCTAssertLessThan(
            Self.maxAlpha(overlay), 0.04,
            "zebra overlay must not remake the picture where no stripe lands")
    }

    func testAssistOverlayPaintsHighlightWithAlpha() {
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 255)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = MonitorFrameEffects()
        fx.zebra = true
        fx.zebraHighlight = true
        fx.zebraMidtone = false
        fx.colorMode = .dLog2
        fx.zebraHighlightIRE = LiveZebra.highlightIRE
        fx.zebraHighlightColor = .red
        let overlay = LiveMonitorCompositor.assistOverlay(from: source, effects: fx)
        XCTAssertGreaterThan(
            Self.maxAlpha(overlay), 0.4,
            "clip zebra must land as opaque stripes on a transparent overlay")
        let rgb = Self.sampleRGB(overlay)
        XCTAssertGreaterThan(rgb.0, rgb.1, "highlight fill stays red-dominant")
    }

    /// #136: WAVE's 100 line is the frame's max channel. A hot sky is blue-led,
    /// so its Rec.709 luma sits well under the byte WAVE shows at 100. The
    /// highlight zebra must read the same max channel or it never paints.
    func testHighlightPaintsTintedHotPixelThatWaveShowsAtCeiling() {
        let buffer = ScopeTestBuffers.makeFlatBuffer(red: 170, green: 215, blue: 247)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = MonitorFrameEffects()
        fx.zebra = true
        fx.zebraHighlight = true
        fx.zebraMidtone = false
        fx.colorMode = .dLog2
        fx.zebraHighlightIRE = 100
        let overlay = LiveMonitorCompositor.assistOverlay(from: source, effects: fx)
        XCTAssertGreaterThan(
            Self.maxAlpha(overlay), 0.4,
            "a channel at the live-tap ceiling is clip; luma under it must not hide it")
    }

    @MainActor
    func testFreshAssistUsesDefaultZebraOptions() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.zebraOptions(stores: .app), ZebraAssist.Options.default)
        XCTAssertEqual(ZebraAssist.Options.default.highlightIRE, LiveZebra.highlightIRE)
    }

    @MainActor
    func testZoneTogglesAndColorsRoundTrip() {
        let assist = LiveAssistState()
        var options = assist.zebraOptions(stores: .app)
        options.highlightEnabled = false
        options.midtoneEnabled = false
        options.highlightColor = .red
        options.midtoneColor = .cyan
        options.highlightIRE = 92
        options.midtoneIRE = 48
        assist.setZebraOptions(options, stores: .app)

        XCTAssertFalse(assist.zebraHighlight)
        XCTAssertFalse(assist.zebraMidtone)
        XCTAssertEqual(assist.zebraHighlightColor, .red)
        XCTAssertEqual(assist.zebraMidtoneColor, .cyan)
        XCTAssertEqual(assist.zebraHighlightIRE, 92)
        XCTAssertEqual(assist.zebraMidtoneIRE, 48)

        let overlay = ZebraAssist.overlay(from: assist.effects)
        XCTAssertFalse(overlay.highlightEnabled)
        XCTAssertFalse(overlay.midtoneEnabled)
        XCTAssertEqual(overlay.highlightColor, .red)
        XCTAssertEqual(overlay.midtoneColor, .cyan)
        XCTAssertEqual(overlay.highlightIRE, 92)
        XCTAssertEqual(overlay.midtoneIRE, 48)
        XCTAssertEqual(assist.effects.zebraOptions.unit, .ire)
    }

    @MainActor
    func testUnitPersistsBesideAssistSnapshot() {
        let stores = AssistPanelStores.app
        stores.zebraUnit = .ire
        XCTAssertEqual(stores.zebraUnit, .ire)
        stores.zebraUnit = .native
        XCTAssertEqual(stores.zebraUnit, .native)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: unitKey),
            ZebraAssist.Unit.native.rawValue)

        let assist = LiveAssistState()
        XCTAssertEqual(assist.zebraOptions(stores: stores).unit, .native)
        var options = assist.zebraOptions(stores: stores)
        options.unit = .ire
        assist.setZebraOptions(options, stores: stores)
        XCTAssertEqual(stores.zebraUnit, .ire)
    }

    private static func maxAlpha(_ image: CIImage) -> Float {
        let w = 32
        let h = 32
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(w) / max(image.extent.width, 1),
                y: CGFloat(h) / max(image.extent.height, 1)))
        let context = CIContext(options: MonitorWorkingSpace.contextOptions)
        context.render(
            scaled, toBitmap: &data, rowBytes: w * 4,
            bounds: CGRect(x: 0, y: 0, width: w, height: h),
            format: .RGBA8, colorSpace: nil)
        var best: Float = 0
        for i in stride(from: 3, to: data.count, by: 4) {
            best = max(best, Float(data[i]) / 255)
        }
        return best
    }

    private static func sampleRGB(_ image: CIImage) -> (Float, Float, Float) {
        let context = CIContext(options: MonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) / 255, Float(bytes[1]) / 255, Float(bytes[2]) / 255)
    }
}
