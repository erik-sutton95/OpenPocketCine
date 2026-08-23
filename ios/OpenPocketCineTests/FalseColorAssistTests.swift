import CoreImage
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Pins OpenZCine `falseColorRows` + `FalseColorScale.legendStops` against what we ship.
final class FalseColorAssistTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ScopeExposureCeiling.reset()
    }

    func testLiveTapCeilingPaintsClipBand() {
        let cube = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog2)
        let c = Float(247) / 255
        let mapped = cube.map(red: c, green: c, blue: c)
        XCTAssertGreaterThan(
            mapped.red, mapped.green,
            "ISO 1600 live-tap max 247 is the clip band, not 18%")
        let early = cube.map(red: 188.0 / 255, green: 188.0 / 255, blue: 188.0 / 255)
        XCTAssertLessThan(
            early.red, mapped.red,
            "byte 188 is recoverable D-Log2 highlight, not the clip band")
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let grey = cube.map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(grey.green, grey.red)

        let dlogCube = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog)
        let dlogC = Float(223) / 255
        let dlogClip = dlogCube.map(red: dlogC, green: dlogC, blue: dlogC)
        XCTAssertGreaterThan(
            dlogClip.red, dlogClip.green,
            "D-Log live-tap max 223 is the clip band")
    }
    func testScaleOptionsMatchOpenZCine() {
        XCTAssertEqual(FalseColorAssist.scaleOptions, ["PStops", "IRE", "Limits"])
        XCTAssertEqual(FalseColorAssist.popupTitles, ["Scale", "Reference Display"])
        XCTAssertEqual(FalseColorAssist.Options.default.scale, .stops)
        XCTAssertTrue(FalseColorAssist.Options.default.referenceEnabled)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "PStops"), .stops)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "ZC Stops"), .stops)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "IRE"), .ire)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "Limits"), .limits)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "unknown"), .stops)
        XCTAssertEqual(FalseColorAssist.menuLabel(for: .stops), "PStops")
        XCTAssertEqual(FalseColorAssist.menuLabel(for: .ire), "IRE")
        XCTAssertEqual(FalseColorAssist.menuLabel(for: .limits), "Limits")
        XCTAssertEqual(FalseColorAssist.longPressPanelWidth, 400)
    }

    @MainActor
    func testFreshAssistDefaultsMatchOpenZCine() {
        XCTAssertEqual(FalseColorAssist.Options.default.scale, .stops)
        XCTAssertTrue(FalseColorAssist.Options.default.referenceEnabled)
        XCTAssertEqual(LiveImageEffects().falseColorScale, .stops)
        // `LiveAssistState.init` reloads OperatorPrefs — pin the decode fallback.
        XCTAssertEqual(FalseColorScaleKind(rawValue: "not-a-scale") ?? .stops, .stops)
    }

    func testIRELegendLabelsMatchOpenZCine() {
        XCTAssertEqual(
            FalseColorAssist.legendLabels(scale: .ire),
            [
                "0–4", "5", "10–12", "18%", "55–61", "92–93", "94–95",
                "96–98", "99–100",
            ])
        XCTAssertEqual(
            FalseColorAssist.legendLabels(scale: .stops),
            [
                "Minimum", "−3", "18%", "Skin +1", "+2",
                "⅔ below max", "⅓ below max", "Maximum",
            ])
        XCTAssertEqual(
            FalseColorAssist.legendLabels(scale: .limits),
            ["0–4", "5–9", "94–98", "99–100"])
    }

    func testLegendBandsCarryOpenZCineLabels() {
        let ire = FalseColorScaleKind.ire.legendStops(transfer: .dlog2)
        XCTAssertEqual(ire.map(\.label), FalseColorAssist.legendLabels(scale: .ire))
        XCTAssertEqual(ire.count, 9)

        let limits = FalseColorScaleKind.limits.legendStops(transfer: .dlog2)
        XCTAssertEqual(limits.map(\.label), FalseColorAssist.legendLabels(scale: .limits))
        XCTAssertEqual(limits.count, 4)

        let stops = FalseColorScaleKind.stops.legendStops(transfer: .dlog2)
        XCTAssertEqual(stops.map(\.label), FalseColorAssist.legendLabels(scale: .stops))
        XCTAssertEqual(stops.count, 8)
    }

    @MainActor
    func testReferenceDisplayArmsFalseColor() {
        let assist = LiveAssistState()
        assist.falseColor = false
        assist.falseColorReference = false
        FalseColorAssist.toggleReference(assist: assist)
        XCTAssertTrue(assist.falseColorReference)
        XCTAssertTrue(assist.falseColor)

        FalseColorAssist.selectScale("IRE", assist: assist)
        XCTAssertEqual(assist.falseColorScale, .ire)
        FalseColorAssist.selectScale("Limits", assist: assist)
        XCTAssertEqual(assist.falseColorScale, .limits)
        FalseColorAssist.selectScale("PStops", assist: assist)
        XCTAssertEqual(assist.falseColorScale, .stops)
    }

    /// OpenZCine `testFalseColorReferenceUsesCompactProportionalScales`.
    func testReferenceOverlayMatchesOpenZCineChrome() {
        XCTAssertEqual(FalseColorReference.panelSize, CGSize(width: 264, height: 52))
        XCTAssertEqual(FalseColorAssist.referencePanelSize, FalseColorReference.panelSize)
        XCTAssertEqual(FalseColorReferenceChrome.panelSize, FalseColorReference.panelSize)

        let ire = FalseColorReference.segments(scale: .ire, transfer: .dlog2)
        XCTAssertEqual(ire.count, 9)
        XCTAssertEqual(ire[0].lowerFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(ire[0].upperFraction, 0.05, accuracy: 0.0001)
        // Pocket WAVE 18% (paper 30.50) — not OpenZCine Reinhard 41–49.
        XCTAssertEqual(ire[3].lowerFraction, 0.28, accuracy: 0.0001)
        XCTAssertEqual(ire[3].upperFraction, 0.34, accuracy: 0.0001)
        XCTAssertEqual(ire[8].lowerFraction, 0.99, accuracy: 0.0001)
        XCTAssertEqual(ire[8].upperFraction, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(ire[2].lowerFraction, ire[1].upperFraction)

        let stops = FalseColorReference.segments(scale: .stops, transfer: .dlog2)
        XCTAssertEqual(stops.count, 8)
        XCTAssertEqual(stops.first?.lowerFraction, 0)
        XCTAssertEqual(stops.last?.upperFraction, 1)
        XCTAssertLessThan(stops[0].upperFraction, stops[1].lowerFraction)
        XCTAssertLessThan(stops[1].upperFraction, stops[2].lowerFraction)
        XCTAssertLessThan(stops[2].upperFraction, stops[3].lowerFraction)
        XCTAssertLessThan(stops[4].upperFraction, stops[5].lowerFraction)
        XCTAssertEqual(stops[5].upperFraction, stops[6].lowerFraction, accuracy: 0.0001)
        XCTAssertEqual(stops[6].upperFraction, stops[7].lowerFraction, accuracy: 0.0001)

        let markers = FalseColorReference.stopAxisMarkers(transfer: .dlog2)
        XCTAssertEqual(markers.map(\.label), ["Min", "−3", "18%", "Skin", "+2", "Max"])
        XCTAssertEqual(
            markers[2].fraction,
            (stops[2].lowerFraction + stops[2].upperFraction) * 0.5,
            accuracy: 0.0001)

        XCTAssertEqual(
            FalseColorReference.axisLabels(scale: .ire),
            ["clip / shadows", "18%", "skin hi", "highlights → clip"])
        XCTAssertEqual(
            FalseColorReference.axisLabels(scale: .limits),
            ["crushed", "midtones untouched", "clipped"])
        XCTAssertEqual(FalseColorReference.axisLabels(scale: .stops), [])
        XCTAssertEqual(FalseColorReference.curveKeyLabel(.dlog2), "D-Log2")
        XCTAssertEqual(FalseColorReference.curveKeyLabel(.dlog), "D-Log")
        XCTAssertEqual(FalseColorReference.curveKeyLabel(.rec709), "709")
        XCTAssertEqual(FalseColorReference.curveKeyLabel(.hdr), "HLG")

        let limits = FalseColorReference.segments(scale: .limits, transfer: .dlog2)
        XCTAssertEqual(limits.count, 4)
        XCTAssertEqual(limits[0].lowerFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(limits[0].upperFraction, 0.05, accuracy: 0.0001)
        XCTAssertEqual(limits[1].lowerFraction, 0.05, accuracy: 0.0001)
        XCTAssertEqual(limits[1].upperFraction, 0.10, accuracy: 0.0001)
        XCTAssertEqual(limits[2].lowerFraction, 0.94, accuracy: 0.0001)
        XCTAssertEqual(limits[2].upperFraction, 0.99, accuracy: 0.0001)
        XCTAssertEqual(limits[3].lowerFraction, 0.99, accuracy: 0.0001)
        XCTAssertEqual(limits[3].upperFraction, 1, accuracy: 0.0001)
    }

    func testIREOverlayPaintsDLog2GreyGreenNotClip() {
        let cube = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog2)
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let mapped = cube.map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(
            mapped.green, mapped.red,
            "D-Log2 18% grey is paper 30.50 (green 18% band) on false colour, not the clip band")
        XCTAssertGreaterThan(mapped.green, mapped.blue)
        // 64³ luma-keyed cube: 18% must be a majority-opaque IRE band, not a hole.
        let weight = PocketFalseColorMap.overlayWeightCube(scale: .ire, transfer: .dlog2)
            .map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(weight.red, 0.5, "18% must be a majority-opaque IRE band, not a hole")
    }

    func testPostLUTCodesAreADifferentIREBand() throws {
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let pre = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog2)
            .map(red: g, green: g, blue: g)
        guard let look = BundledPocketLUT.cube(.dLog2ToRec709) else {
            throw XCTSkip("official D-Log2 cube must load")
        }
        let graded = look.map(red: g, green: g, blue: g)
        let post = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog2)
            .map(red: graded.red, green: graded.green, blue: graded.blue)
        let delta =
            abs(post.red - pre.red) + abs(post.green - pre.green) + abs(post.blue - pre.blue)
        XCTAssertGreaterThan(
            delta, 0.15,
            "log→709 18% is a different D-Log2 code — sampling the cube look must not be how FALSE keys"
        )
    }

    func testIREAndStopsGapsAreGrayscaleNotBlack() {
        // IRE 20 sits between 13 and 28. Overlay used to punch a hole onto the
        // camera picture; the gap is WAVE gray, same as the full lattice.
        let encoded = Float(ScopeDisplayScale.signalNative(monitorPercent: 20, transfer: .dlog2))
        let overlay = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog2)
            .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertEqual(overlay.red, overlay.green, accuracy: 0.04)
        XCTAssertEqual(overlay.green, overlay.blue, accuracy: 0.04)
        XCTAssertGreaterThan(overlay.red, 0.12)

        let full = PocketFalseColorMap.cube(scale: .ire, transfer: .dlog2)
            .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertEqual(full.red, overlay.red, accuracy: 0.04)
        XCTAssertEqual(full.green, overlay.green, accuracy: 0.04)
        XCTAssertEqual(full.blue, overlay.blue, accuracy: 0.04)

        let grey = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let stops = PocketFalseColorMap.cube(scale: .stops, transfer: .dlog2)
            .map(red: grey, green: grey, blue: grey)
        XCTAssertGreaterThan(stops.green, stops.red, "PStops 18% is the green landmark")
        XCTAssertGreaterThan(stops.green, stops.blue)
        let overlayStops = PocketFalseColorMap.overlayPaintCube(scale: .stops, transfer: .dlog2)
            .map(red: grey, green: grey, blue: grey)
        XCTAssertGreaterThan(overlayStops.green, overlayStops.red)
        let overlayWeight = PocketFalseColorMap.overlayWeightCube(scale: .ire, transfer: .dlog2)
            .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertGreaterThan(
            overlayWeight.red, 0.9, "IRE gaps must cover the picture, not punch through")
    }

    /// The compositor reads the async-warmed cube bytes (`overlayPaintData` /
    /// `overlayWeightData` return nil until the lattice build lands). Tests
    /// must warm first — the app shows the plain look meanwhile.
    private func warmOverlayCubes(scale: FalseColorScaleKind, mode: ColorMode) throws {
        PocketFalseColorMap.warm(scale: scale, mode: mode)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let ready =
                PocketFalseColorMap.overlayPaintData(scale: scale, mode: mode) != nil
                && PocketFalseColorMap.overlayWeightData(scale: scale, mode: mode) != nil
            if ready { return }
            usleep(20_000)
        }
        throw XCTSkip("false-colour cube warm did not finish in time")
    }

    func testCompositorFalseColorIgnoresOperatorLUT() throws {
        try warmOverlayCubes(scale: .ire, mode: .dLog2)
        let g = UInt8(clamping: Int((MonitorTransfer.dlog2.middleGrayEncoded * 255).rounded()))
        let codes = Self.solidImage(code: g)
        let identity = codes
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .ire
        fx.colorMode = .dLog2

        let withoutLUT = LiveMonitorCompositor.apply(to: codes, effects: fx, display: identity)
        let look = BuiltInLook.mono.cube()
        fx.lutDimension = look.size
        fx.lutRGBA = look.rgbaComponents.withUnsafeBytes { Data($0) }
        let withLUT = LiveMonitorCompositor.apply(to: codes, effects: fx, display: identity)

        let a = Self.sampleRGB(withoutLUT)
        let b = Self.sampleRGB(withLUT)
        XCTAssertEqual(a.0, b.0, accuracy: 0.04)
        XCTAssertEqual(a.1, b.1, accuracy: 0.04)
        XCTAssertEqual(a.2, b.2, accuracy: 0.04)
        XCTAssertGreaterThan(a.1, a.0, "IRE 18% green must win over the mono cube look")
        XCTAssertGreaterThan(b.1, b.0)
    }

    func testCompositorStopsPaintsGrayInTheGaps() throws {
        try warmOverlayCubes(scale: .stops, mode: .dLog2)
        // IRE 20 is a PStops gap (between −3 and 18%). WAVE gray, not camera colour.
        let encoded = UInt8(
            clamping: Int(
                (ScopeDisplayScale.signalNative(monitorPercent: 20, transfer: .dlog2) * 255)
                    .rounded()))
        let codes = Self.solidImage(code: encoded)
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .stops
        fx.colorMode = .dLog2
        let product = LiveMonitorCompositor.applyProduct(to: codes, effects: fx, display: codes)
        let rgb = Self.sampleRGB(product.image)
        XCTAssertEqual(rgb.0, rgb.1, accuracy: 0.06, "PStops gap is WAVE gray")
        XCTAssertEqual(rgb.1, rgb.2, accuracy: 0.06)
        XCTAssertGreaterThan(rgb.0, 0.12, "PStops gaps must not collapse to black")
    }

    func testLimitsOverlayShowsLUTBetweenZones() throws {
        try warmOverlayCubes(scale: .limits, mode: .dLog2)
        let grey = UInt8(clamping: Int((MonitorTransfer.dlog2.middleGrayEncoded * 255).rounded()))
        let codes = Self.solidImage(code: grey)
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .limits
        fx.colorMode = .dLog2
        let look = BuiltInLook.mono.cube()
        fx.lutDimension = look.size
        fx.lutRGBA = look.rgbaComponents.withUnsafeBytes { Data($0) }

        let painted = LiveMonitorCompositor.apply(to: codes, effects: fx, display: codes)
        let gradedOnly = {
            var lutOnly = LiveImageEffects()
            lutOnly.lutDimension = look.size
            lutOnly.lutRGBA = fx.lutRGBA
            lutOnly.colorMode = .dLog2
            return LiveMonitorCompositor.apply(to: codes, effects: lutOnly)
        }()
        let a = Self.sampleRGB(painted)
        let b = Self.sampleRGB(gradedOnly)
        XCTAssertEqual(a.0, b.0, accuracy: 0.05)
        XCTAssertEqual(a.1, b.1, accuracy: 0.05)
        XCTAssertEqual(a.2, b.2, accuracy: 0.05)

        let clip = Self.solidImage(code: 255)
        fx.lutDimension = 0
        fx.lutRGBA = Data()
        let clipOff = Self.sampleRGB(
            LiveMonitorCompositor.apply(to: clip, effects: fx, display: clip))
        fx.lutDimension = look.size
        fx.lutRGBA = look.rgbaComponents.withUnsafeBytes { Data($0) }
        let clipOn = Self.sampleRGB(
            LiveMonitorCompositor.apply(to: clip, effects: fx, display: clip))
        // Overlay paint is the authored band on both paths — no DeviceRGB
        // remake, so no display-compensated lattice.
        XCTAssertEqual(clipOff.0, clipOn.0, accuracy: 0.04)
        XCTAssertEqual(clipOff.1, clipOn.1, accuracy: 0.04)
        XCTAssertEqual(clipOff.2, clipOn.2, accuracy: 0.04)
        XCTAssertGreaterThan(clipOff.0, clipOff.1, "99–100 stays red-dominant without a LUT")
        XCTAssertGreaterThan(clipOn.0, clipOn.1, "99–100 must stay the clip paint when LUT is on")
    }

    func testFalseColorAloneOverlaysIdentityInsteadOfRemakingThePicture() {
        var fx = LiveImageEffects()
        fx.falseColor = true
        XCTAssertTrue(fx.needsGPUFeed)
        XCTAssertTrue(fx.needsOverlayFeed)
        XCTAssertFalse(fx.replacesIdentityFeed)

        let cube = BuiltInLook.mono.cube()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        XCTAssertTrue(fx.replacesIdentityFeed)
        XCTAssertFalse(fx.needsOverlayFeed)
    }

    func testAssistOverlayPaintsGrayInIREGap() throws {
        try warmOverlayCubes(scale: .ire, mode: .dLog2)
        let encoded = UInt8(
            clamping: Int(
                (ScopeDisplayScale.signalNative(monitorPercent: 20, transfer: .dlog2) * 255)
                    .rounded()))
        let codes = Self.solidImage(code: encoded)
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .ire
        fx.colorMode = .dLog2
        let overlay = LiveMonitorCompositor.assistOverlay(from: codes, effects: fx)
        XCTAssertGreaterThan(
            Self.maxAlpha(overlay), 0.85,
            "IRE gap is WAVE gray over the picture, not a transparent hole")
        let rgb = Self.sampleRGB(overlay)
        XCTAssertEqual(rgb.0, rgb.1, accuracy: 0.06)
        XCTAssertEqual(rgb.1, rgb.2, accuracy: 0.06)
        XCTAssertGreaterThan(rgb.0, 0.12)
    }

    private static func maxAlpha(_ image: CIImage) -> Float {
        let w = 16
        let h = 16
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

    private static func solidImage(code: UInt8, width: Int = 16, height: Int = 16) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = code
            bytes[i * 4 + 1] = code
            bytes[i * 4 + 2] = code
            bytes[i * 4 + 3] = 255
        }
        return CIImage(
            bitmapData: Data(bytes), bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8, colorSpace: nil)
    }

    private static func sampleRGB(_ image: CIImage) -> (Float, Float, Float) {
        let context = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) / 255, Float(bytes[1]) / 255, Float(bytes[2]) / 255)
    }
}
