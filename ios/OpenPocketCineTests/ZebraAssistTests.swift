import CoreImage
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine `AssistConfiguration.Zebra` + `AssistQuickSettingsContent.zebraRows`
/// (OperatorPreferences.swift, MonitorPanels.swift, MonitorControls.swift,
/// ImageEffectsCompositor.swift).
final class ZebraAssistTests: XCTestCase {
    private let assistKey = "OpenPocketCine.Assist.v1"
    private var savedAssist: Data?
    private var savedUnit: String?

    override func setUp() {
        super.setUp()
        ScopeExposureCeiling.reset()
        savedAssist = UserDefaults.standard.data(forKey: assistKey)
        savedUnit = UserDefaults.standard.string(forKey: ZebraAssist.unitDefaultsKey)
        UserDefaults.standard.removeObject(forKey: assistKey)
        UserDefaults.standard.removeObject(forKey: ZebraAssist.unitDefaultsKey)
    }

    override func tearDown() {
        if let savedAssist {
            UserDefaults.standard.set(savedAssist, forKey: assistKey)
        } else {
            UserDefaults.standard.removeObject(forKey: assistKey)
        }
        if let savedUnit {
            UserDefaults.standard.set(savedUnit, forKey: ZebraAssist.unitDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: ZebraAssist.unitDefaultsKey)
        }
        super.tearDown()
    }

    func testUnitEditorLabelsRoundTrip() {
        XCTAssertEqual(ZebraAssist.unitOptions, ZebraAssist.Unit.allCases.map(\.editorLabel))
        for unit in ZebraAssist.Unit.allCases {
            XCTAssertEqual(ZebraAssist.Unit.fromEditorLabel(unit.editorLabel), unit, "\(unit)")
        }
    }

    func testIREDisplayIsIdentity() {
        var options = ZebraAssist.Options.default
        options.unit = .ire
        XCTAssertEqual(options.displayValue(for: 100, transfer: .dlog2), 100)
        XCTAssertEqual(options.displayValue(for: 55, transfer: .dlog2), 55)
        options.setHighlight(fromDisplay: 88, transfer: .dlog2)
        XCTAssertEqual(options.highlightIRE, 88)
        options.setMidtone(fromDisplay: 42, transfer: .rec709)
        XCTAssertEqual(options.midtoneIRE, 42)
        options.setHighlight(fromDisplay: 150, transfer: .dlog2)
        XCTAssertEqual(options.highlightIRE, 100)
        options.setMidtone(fromDisplay: -4, transfer: .dlog2)
        XCTAssertEqual(options.midtoneIRE, 0)
    }

    func testNativeDisplayUsesEncodedCode() {
        // Native display: IRE 100 → live-tap ceiling 247, IRE 0 → paper black 16.
        var options = ZebraAssist.Options.default
        options.unit = .native
        XCTAssertEqual(options.editorMaximum, 255)
        XCTAssertEqual(options.displayValue(for: 100, transfer: .dlog2), 247)
        XCTAssertEqual(options.displayValue(for: 0, transfer: .dlog2), 16)
        let midNative = Int(
            (ScopeDisplayScale.signalNative(monitorPercent: 55, transfer: .dlog2) * 255)
                .rounded())
        XCTAssertEqual(options.displayValue(for: 55, transfer: .dlog2), midNative)

        options.setHighlight(fromDisplay: 247, transfer: .dlog2)
        XCTAssertEqual(options.highlightIRE, 100, accuracy: 0.01)
        options.setMidtone(fromDisplay: midNative, transfer: .dlog2)
        XCTAssertEqual(options.midtoneIRE, 55, accuracy: 0.25)

        XCTAssertEqual(options.displayValue(for: 100, transfer: .dlog), 223)
        XCTAssertEqual(options.displayValue(for: 0, transfer: .dlog), 24)
        options.setHighlight(fromDisplay: 223, transfer: .dlog)
        XCTAssertEqual(options.highlightIRE, 100, accuracy: 0.01)
    }

    func testUnitDoesNotChangeOverlayThresholds() {
        var options = ZebraAssist.Options.default
        options.highlightIRE = 88
        options.midtoneIRE = 50
        let ireOverlay = ZebraAssist.overlay(from: options)
        options.unit = .native
        let nativeOverlay = ZebraAssist.overlay(from: options)
        XCTAssertEqual(ireOverlay.highlightIRE, nativeOverlay.highlightIRE)
        XCTAssertEqual(ireOverlay.midtoneIRE, nativeOverlay.midtoneIRE)
        XCTAssertEqual(ireOverlay.highlightIRE, 88)
        XCTAssertTrue(ireOverlay.highlightEnabled)
        XCTAssertTrue(ireOverlay.midtoneEnabled)
    }

    /// Per-tool needsGPUFeed / needsOverlayFeed live in LiveFeedOrientationTests.
    func testZebraAloneOverlaysIdentityInsteadOfRemakingThePicture() {
        var zebra = LiveImageEffects()
        zebra.zebra = true
        XCTAssertFalse(zebra.replacesIdentityFeed)

        var peaking = LiveImageEffects()
        peaking.peaking = true
        XCTAssertFalse(peaking.replacesIdentityFeed)

        var both = LiveImageEffects()
        both.zebra = true
        both.peaking = true
        XCTAssertTrue(both.needsOverlayFeed)
        XCTAssertFalse(both.replacesIdentityFeed)

        let cube = BuiltInLook.mono.cube()
        var lutAndZebra = LiveImageEffects()
        lutAndZebra.zebra = true
        lutAndZebra.lutDimension = cube.size
        lutAndZebra.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        XCTAssertTrue(lutAndZebra.replacesIdentityFeed)
        XCTAssertFalse(lutAndZebra.needsOverlayFeed)

        var lutAndFalseColor = LiveImageEffects()
        lutAndFalseColor.falseColor = true
        lutAndFalseColor.lutDimension = cube.size
        lutAndFalseColor.lutRGBA = lutAndZebra.lutRGBA
        XCTAssertTrue(lutAndFalseColor.replacesIdentityFeed)
        XCTAssertFalse(lutAndFalseColor.needsOverlayFeed)

        var falseAndZebra = LiveImageEffects()
        falseAndZebra.zebra = true
        falseAndZebra.falseColor = true
        XCTAssertFalse(falseAndZebra.replacesIdentityFeed)
        XCTAssertTrue(falseAndZebra.needsOverlayFeed)
    }

    func testAssistOverlayIsTransparentWhereZebraDoesNotPaint() {
        // D-Log2 18% grey is outside highlight 100 and midtone 55 ± 5.
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 78)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = LiveImageEffects()
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
        var fx = LiveImageEffects()
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
        var fx = LiveImageEffects()
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

    func testFreshAssistUsesDefaultZebraOptions() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.zebraOptions, ZebraAssist.Options.default)
        XCTAssertEqual(ZebraAssist.Options.default.highlightIRE, LiveZebra.highlightIRE)
    }

    func testZoneTogglesAndColorsRoundTrip() {
        let assist = LiveAssistState()
        var options = assist.zebraOptions
        options.highlightEnabled = false
        options.midtoneEnabled = false
        options.highlightColor = .red
        options.midtoneColor = .cyan
        options.highlightIRE = 92
        options.midtoneIRE = 48
        assist.zebraOptions = options

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

    func testUnitPersistsBesideAssistSnapshot() {
        ZebraAssist.persistedUnit = .ire
        XCTAssertEqual(ZebraAssist.persistedUnit, .ire)
        ZebraAssist.persistedUnit = .native
        XCTAssertEqual(ZebraAssist.persistedUnit, .native)
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: ZebraAssist.unitDefaultsKey),
            ZebraAssist.Unit.native.rawValue)

        let assist = LiveAssistState()
        XCTAssertEqual(assist.zebraUnit, .native)
        var options = assist.zebraOptions
        options.unit = .ire
        assist.zebraOptions = options
        XCTAssertEqual(ZebraAssist.persistedUnit, .ire)
    }

    private static func maxAlpha(_ image: CIImage) -> Float {
        let w = 32
        let h = 32
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: CGFloat(w) / max(image.extent.width, 1),
                y: CGFloat(h) / max(image.extent.height, 1)))
        let context = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
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
        let context = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: image.extent.midX, y: image.extent.midY, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) / 255, Float(bytes[1]) / 255, Float(bytes[2]) / 255)
    }
}
