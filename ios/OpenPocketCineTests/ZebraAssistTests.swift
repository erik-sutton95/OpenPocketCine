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

    func testPopupStacksUnitsHighlightAndMidtone() {
        // AssistLongPressPanel's ViewThatFits used to unpack Group children as
        // alternatives, so only Units painted. Rows must stay a VStack.
        XCTAssertEqual(
            [ZebraAssist.unitsTitle, ZebraAssist.highlightTitle, ZebraAssist.midtoneTitle],
            ["Units", "Highlight", "Midtone"])
        XCTAssertEqual(ZebraAssist.highlightPalette.map(\.rawValue), ["White", "Amber", "Red"])
        XCTAssertEqual(ZebraAssist.midtonePalette.map(\.rawValue), ["Amber", "Cyan", "Green"])
    }

    func testHighlightFiresAtLiveTapCeiling() {
        let ceiling = ScopeDisplayScale.monitorPercent(247.0 / 255, transfer: .dlog2)
        XCTAssertEqual(ceiling, 100, accuracy: 0.05)
        XCTAssertTrue(LiveColorScience.zebraHighlight(ceiling))
        let grey = ScopeDisplayScale.monitorPercent(
            MonitorTransfer.dlog2.middleGrayEncoded, transfer: .dlog2)
        XCTAssertEqual(grey, 30.50, accuracy: 0.5)
        XCTAssertFalse(LiveColorScience.zebraHighlight(grey))
        let early = ScopeDisplayScale.monitorPercent(188.0 / 255, transfer: .dlog2)
        XCTAssertLessThan(early, 90)
        XCTAssertFalse(LiveColorScience.zebraHighlight(early))

        let dlogCeiling = ScopeDisplayScale.monitorPercent(223.0 / 255, transfer: .dlog)
        XCTAssertEqual(dlogCeiling, 100, accuracy: 0.05)
        XCTAssertTrue(LiveColorScience.zebraHighlight(dlogCeiling))
        let dlogGrey = ScopeDisplayScale.monitorPercent(
            MonitorTransfer.dlog.middleGrayEncoded, transfer: .dlog)
        XCTAssertEqual(dlogGrey, 39.88, accuracy: 0.5)
        XCTAssertFalse(LiveColorScience.zebraHighlight(dlogGrey))
    }

    func testOpenZCineOptionSet() {
        XCTAssertEqual(ZebraAssist.Unit.allCases.map(\.rawValue), ["Native", "IRE"])
        XCTAssertEqual(ZebraAssist.Unit.native.editorLabel, "0-255")
        XCTAssertEqual(ZebraAssist.Unit.ire.editorLabel, "IRE")
        XCTAssertEqual(ZebraAssist.Unit.fromEditorLabel("0-255"), .native)
        XCTAssertEqual(ZebraAssist.Unit.fromEditorLabel("IRE"), .ire)
        XCTAssertEqual(ZebraAssist.unitOptions, ["0-255", "IRE"])

        XCTAssertEqual(
            ZebraAssist.StripeColor.allCases.map(\.rawValue),
            ["White", "Amber", "Red", "Cyan", "Green"])
        XCTAssertEqual(
            ZebraAssist.highlightPalette.map(\.rawValue),
            ["White", "Amber", "Red"])
        XCTAssertEqual(
            ZebraAssist.midtonePalette.map(\.rawValue),
            ["Amber", "Cyan", "Green"])

        let defaults = ZebraAssist.Options.default
        XCTAssertEqual(defaults.unit, .ire)
        XCTAssertTrue(defaults.highlightEnabled)
        XCTAssertTrue(defaults.midtoneEnabled)
        XCTAssertEqual(defaults.highlightIRE, 100)
        XCTAssertEqual(defaults.midtoneIRE, 55)
        XCTAssertEqual(defaults.highlightColor, .white)
        XCTAssertEqual(defaults.midtoneColor, .amber)
        XCTAssertEqual(ZebraAssist.longPressPanelWidth, 400)
        XCTAssertEqual(defaults.editorMaximum, 100)
    }

    func testOpenZCinePopupCopy() {
        XCTAssertEqual(ZebraAssist.unitsTitle, "Units")
        XCTAssertEqual(
            ZebraAssist.unitsHelp,
            "Switch between native 0-255 encoded codes and a 0-100 monitoring IRE scale.")
        XCTAssertEqual(ZebraAssist.highlightTitle, "Highlight")
        XCTAssertEqual(
            ZebraAssist.highlightHelp,
            "High zebra warns when bright detail approaches clipping after the active log curve is compensated."
        )
        XCTAssertEqual(ZebraAssist.midtoneTitle, "Midtone")
        XCTAssertEqual(
            ZebraAssist.midtoneHelp,
            "Midtone zebra gives a curve-compensated reference band for faces or key subject exposure."
        )
    }

    func testStripeLookMatchesOpenZCineCompositor() {
        XCTAssertEqual(ZebraAssist.StripeLook.width, 5)
        XCTAssertEqual(ZebraAssist.StripeLook.sharpness, 1)
        XCTAssertEqual(ZebraAssist.StripeLook.rotation, .pi / 4, accuracy: 1e-12)
    }

    func testStripeFillRGBMatchesOpenZCine() {
        // ImageEffectsCompositor.zebraRGB
        assertRGB(ZebraAssist.StripeColor.white, (1, 1, 1))
        assertRGB(ZebraAssist.StripeColor.amber, (1, 0.72, 0.2))
        assertRGB(ZebraAssist.StripeColor.red, (1, 0.15, 0.15))
        assertRGB(ZebraAssist.StripeColor.cyan, (0, 0.85, 0.9))
        assertRGB(ZebraAssist.StripeColor.green, (0.2, 0.9, 0.35))
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

    func testZebraAloneOverlaysIdentityInsteadOfRemakingThePicture() {
        var zebra = LiveImageEffects()
        zebra.zebra = true
        XCTAssertTrue(zebra.needsGPUFeed)
        XCTAssertTrue(zebra.needsOverlayFeed)
        XCTAssertFalse(zebra.replacesIdentityFeed)

        var peaking = LiveImageEffects()
        peaking.peaking = true
        XCTAssertTrue(peaking.needsOverlayFeed)
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

    func testGPUEffectsReadOverlayHook() {
        var fx = LiveImageEffects()
        fx.zebraHighlight = false
        fx.zebraMidtone = true
        fx.zebraHighlightIRE = 92
        fx.zebraMidtoneIRE = 48
        fx.zebraHighlightColor = .red
        fx.zebraMidtoneColor = .cyan
        let overlay = ZebraAssist.overlay(from: fx)
        XCTAssertFalse(overlay.highlightEnabled)
        XCTAssertTrue(overlay.midtoneEnabled)
        XCTAssertEqual(overlay.highlightIRE, 92)
        XCTAssertEqual(overlay.midtoneIRE, 48)
        XCTAssertEqual(overlay.highlightColor, .red)
        XCTAssertEqual(overlay.midtoneColor, .cyan)
        XCTAssertEqual(fx.zebraOptions.unit, .ire)
    }

    func testFreshAssistDefaultsMatchOpenZCine() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.zebraOptions, ZebraAssist.Options.default)
        XCTAssertTrue(assist.zebraHighlight)
        XCTAssertTrue(assist.zebraMidtone)
        XCTAssertEqual(assist.zebraHighlightIRE, 100)
        XCTAssertEqual(assist.zebraMidtoneIRE, 55)
        XCTAssertEqual(assist.zebraHighlightColor, .white)
        XCTAssertEqual(assist.zebraMidtoneColor, .amber)
        XCTAssertEqual(assist.zebraUnit, .ire)
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

    private func assertRGB(
        _ color: ZebraAssist.StripeColor,
        _ expected: (Double, Double, Double),
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(color.rgb.0, expected.0, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(color.rgb.1, expected.1, accuracy: 1e-12, file: file, line: line)
        XCTAssertEqual(color.rgb.2, expected.2, accuracy: 1e-12, file: file, line: line)
    }
}
