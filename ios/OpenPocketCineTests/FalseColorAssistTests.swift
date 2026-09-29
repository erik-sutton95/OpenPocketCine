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

    func testExposureChangeKeepsFalseColorPaintAvailable() throws {
        ScopeExposureCeiling.setISO(1600)
        try warmOverlayCubes(scale: .ire, mode: .dLog2)
        for iso in [125, 200, 400, 800, 1600] {
            let previous = try XCTUnwrap(
                PocketFalseColorMap.overlayPairData(scale: .ire, mode: .dLog2))
            ScopeExposureCeiling.setISO(iso)
            let retained = try XCTUnwrap(
                PocketFalseColorMap.overlayPairData(scale: .ire, mode: .dLog2),
                "Exposure updates must not remove false color while warming")
            XCTAssertEqual(retained.clipByte, previous.clipByte)
            XCTAssertEqual(retained.paint, previous.paint)
            XCTAssertEqual(retained.weight, previous.weight)
            try warmOverlayCubes(scale: .ire, mode: .dLog2)
            XCTAssertEqual(
                PocketFalseColorMap.overlayPairData(scale: .ire, mode: .dLog2)?.clipByte,
                ScopeExposureCeiling.clipByte(transfer: .dlog2))
        }
    }

    func testExposureReturningToCachedMapDiscardsObsoleteBuild() throws {
        ScopeExposureCeiling.setISO(1600)
        try warmOverlayCubes(scale: .limits, mode: .dLog2)
        let original = try XCTUnwrap(
            PocketFalseColorMap.overlayPairData(scale: .limits, mode: .dLog2))
        ScopeExposureCeiling.setISO(125)
        _ = PocketFalseColorMap.overlayPairData(scale: .limits, mode: .dLog2)
        ScopeExposureCeiling.setISO(1600)
        for _ in 0..<50 {
            let maps = try XCTUnwrap(
                PocketFalseColorMap.overlayPairData(scale: .limits, mode: .dLog2))
            XCTAssertEqual(maps.clipByte, original.clipByte)
            XCTAssertEqual(maps.paint, original.paint)
            XCTAssertEqual(maps.weight, original.weight)
            usleep(20_000)
        }
    }

    func testFalseColorExposureSnapshotSurvivesGlobalISOChange() {
        let anchors = ScopeAnchors.make(transfer: .dlog2, clipByte: 200)
        let bands = LiveColorScience.falseColorBands(
            .stops, transfer: .dlog2, clipEncoded: anchors.clip)
        let before = ScopeDisplayScale.waveformLevel(0.7, anchors: anchors)
        ScopeExposureCeiling.setISO(100)
        ScopeExposureCeiling.observeTapMax(170, transfer: .dlog2)
        XCTAssertEqual(ScopeDisplayScale.waveformLevel(0.7, anchors: anchors), before)
        XCTAssertEqual(
            LiveColorScience.falseColorBands(
                .stops, transfer: .dlog2,
                clipEncoded: anchors.clip), bands)
        XCTAssertEqual(anchors.clip, 200.0 / 255.0)
    }

    func testScaleOptionsMatchOpenZCine() {
        XCTAssertEqual(FalseColorAssist.scaleOptions, ["CineStop", "IRE", "Limits"])
        XCTAssertEqual(FalseColorAssist.Options.default.scale, .stops)
        XCTAssertTrue(FalseColorAssist.Options.default.referenceEnabled)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "CineStop"), .stops)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "PStops"), .stops)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "ZC Stops"), .stops)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "IRE"), .ire)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "Limits"), .limits)
        XCTAssertEqual(FalseColorAssist.scale(forMenuLabel: "unknown"), .stops)
        XCTAssertEqual(FalseColorAssist.menuLabel(for: .stops), "CineStop")
        XCTAssertEqual(FalseColorAssist.menuLabel(for: .ire), "IRE")
        XCTAssertEqual(FalseColorAssist.menuLabel(for: .limits), "Limits")
        XCTAssertTrue(FalseColorAssist.scaleHelp.contains("CineStop"))
        XCTAssertEqual(FalseColorScaleKind(rawValue: "ZC Stops") ?? .stops, .stops)
        XCTAssertEqual(LiveImageEffects().falseColorScale, .stops)
    }

    /// Legend copy is pinned once, in core `LiveColorScienceTests`; the shell must
    /// match it band for band (the `zip` in `legendStops` would silently truncate).
    func testLegendLabelsMatchCoreFalseColorBands() {
        for scale in FalseColorScaleKind.allCases {
            let core = PocketFalseColorMap.bands(scale: scale, transfer: .dlog2).map(\.label)
            XCTAssertEqual(FalseColorAssist.legendLabels(scale: scale), core, "\(scale) labels")
            XCTAssertEqual(
                scale.legendStops(transfer: .dlog2).map(\.label), core, "\(scale) legend stops")
        }
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
        FalseColorAssist.selectScale("CineStop", assist: assist)
        XCTAssertEqual(assist.falseColorScale, .stops)
    }

    /// OpenZCine `testFalseColorReferenceUsesCompactProportionalScales`.
    func testReferenceOverlayMatchesOpenZCineChrome() {
        XCTAssertEqual(FalseColorReference.panelSize, CGSize(width: 264, height: 52))
        XCTAssertEqual(FalseColorReferenceChrome.panelSize, FalseColorReference.panelSize)

        let ire = FalseColorReference.segments(scale: .ire, transfer: .dlog2)
        XCTAssertEqual(ire.count, 6)
        XCTAssertEqual(ire[0].lowerFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(ire[0].upperFraction, 0.025, accuracy: 0.0001)
        XCTAssertEqual(ire[2].lowerFraction, 0.38, accuracy: 0.0001)
        XCTAssertEqual(ire[2].upperFraction, 0.42, accuracy: 0.0001)
        XCTAssertEqual(ire[4].lowerFraction, 0.80, accuracy: 0.0001)
        XCTAssertEqual(ire[4].upperFraction, 0.95, accuracy: 0.0001)
        XCTAssertEqual(ire.last?.upperFraction, 1)
        XCTAssertLessThan(ire[1].upperFraction, ire[2].lowerFraction)

        let stops = FalseColorReference.segments(scale: .stops, transfer: .dlog2)
        XCTAssertEqual(stops.count, 9)
        XCTAssertEqual(stops[0].lowerFraction, 0, accuracy: 0.0001)
        XCTAssertEqual(stops[0].upperFraction, 0.05, accuracy: 0.0001)
        XCTAssertEqual(stops[3].lowerFraction, 0.41, accuracy: 0.0001)
        XCTAssertEqual(stops[3].upperFraction, 0.49, accuracy: 0.0001)
        XCTAssertEqual(stops.last?.upperFraction, 1)
        XCTAssertLessThan(stops[2].upperFraction, stops[3].lowerFraction)

        XCTAssertEqual(
            FalseColorReference.axisLabels(scale: .ire),
            ["crush", "18%", "skin", "clip"])
        XCTAssertEqual(
            FalseColorReference.axisLabels(scale: .stops),
            ["crush", "18%", "skin", "clip"])
        XCTAssertEqual(
            FalseColorReference.axisLabels(scale: .limits),
            ["crushed", "midtones untouched", "clipped"])
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

    func testIREOverlayPaintsRec709GreyGreenAndDLog2GreyAsAGap() {
        let rec709Cube = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .rec709)
        let rec709Grey = Float(MonitorTransfer.rec709.middleGrayEncoded)
        let rec709 = rec709Cube.map(red: rec709Grey, green: rec709Grey, blue: rec709Grey)
        XCTAssertGreaterThan(
            rec709.green, rec709.red,
            "Rec.709 18% grey is WAVE ~41 (18%MG green)")

        let cube = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog2)
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let mapped = cube.map(red: g, green: g, blue: g)
        XCTAssertEqual(mapped.red, mapped.green, accuracy: 0.06, "D-Log2 18% is an IRE gap")
        XCTAssertEqual(mapped.green, mapped.blue, accuracy: 0.06)
        let weight = PocketFalseColorMap.overlayWeightCube(scale: .ire, transfer: .dlog2)
            .map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(weight.red, 0.5, "IRE gaps cover the picture, not a hole")
        let clip = Float(ScopeExposureCeiling.clipEncoded(transfer: .dlog2))
        let over = cube.map(red: clip, green: clip, blue: clip)
        XCTAssertGreaterThan(over.red, over.green, "live-tap ceiling is 95%WC red")
        let early = cube.map(red: 188.0 / 255, green: 188.0 / 255, blue: 188.0 / 255)
        XCTAssertLessThan(
            early.red, over.red, "byte 188 is recoverable D-Log2 highlight, not the clip band")

        let dlogC = Float(223) / 255
        let dlogClip = PocketFalseColorMap.overlayPaintCube(scale: .ire, transfer: .dlog)
            .map(red: dlogC, green: dlogC, blue: dlogC)
        XCTAssertGreaterThan(dlogClip.red, dlogClip.green, "D-Log live-tap max 223 is the clip band")
    }

    func testPostLUTCodesAreADifferentIREBand() throws {
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let pre = PocketFalseColorMap.overlayPaintCube(scale: .stops, transfer: .dlog2)
            .map(red: g, green: g, blue: g)
        guard let look = BundledPocketLUT.cube(.dLog2ToRec709) else {
            throw XCTSkip("official D-Log2 cube must load")
        }
        let graded = look.map(red: g, green: g, blue: g)
        let post = PocketFalseColorMap.overlayPaintCube(scale: .stops, transfer: .dlog2)
            .map(red: graded.red, green: graded.green, blue: graded.blue)
        let delta =
            abs(post.red - pre.red) + abs(post.green - pre.green) + abs(post.blue - pre.blue)
        XCTAssertGreaterThan(
            delta, 0.05,
            "log→709 18% is a different D-Log2 code — sampling the cube look must not be how FALSE keys"
        )
    }

    func testCineStopGapsAreGrayscaleAndRec709EighteenIsGreen() {
        let encoded = Float(ScopeDisplayScale.signalNative(monitorPercent: 20, transfer: .dlog2))
        let overlay = PocketFalseColorMap.overlayPaintCube(scale: .stops, transfer: .dlog2)
            .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertEqual(overlay.red, overlay.green, accuracy: 0.04)
        XCTAssertEqual(overlay.green, overlay.blue, accuracy: 0.04)
        XCTAssertGreaterThan(overlay.red, 0.12)

        let grey = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let dlog2 = PocketFalseColorMap.cube(scale: .stops, transfer: .dlog2)
            .map(red: grey, green: grey, blue: grey)
        XCTAssertEqual(dlog2.red, dlog2.green, accuracy: 0.06, "D-Log2 18% is a CineStop gap")
        let rec709Grey = Float(MonitorTransfer.rec709.middleGrayEncoded)
        let rec709 = PocketFalseColorMap.cube(scale: .stops, transfer: .rec709)
            .map(red: rec709Grey, green: rec709Grey, blue: rec709Grey)
        XCTAssertGreaterThan(rec709.green, rec709.red, "Rec.709 18% hits 41–48 green")
        let overlayWeight = PocketFalseColorMap.overlayWeightCube(scale: .stops, transfer: .dlog2)
            .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertGreaterThan(
            overlayWeight.red, 0.9, "CineStop gaps cover the picture, not punch through")
    }

    /// The compositor reads the async-warmed cube bytes (`overlayPaintData` /
    /// `overlayWeightData` return nil until the lattice build lands). Tests
    /// must warm first — the app shows the plain look meanwhile.
    private func warmOverlayCubes(
        scale: FalseColorScaleKind, mode: ColorMode, recordReadinessDuration: Bool = false
    ) throws {
        let started = ProcessInfo.processInfo.systemUptime
        PocketFalseColorMap.warm(scale: scale, mode: mode)
        // This bounds functional setup, not a live-performance benchmark. The
        // two cold 64³ lattices already take about five seconds in unoptimized
        // simulator builds, so normal host contention must not skip pixel checks.
        let deadline = started + 30
        while ProcessInfo.processInfo.systemUptime < deadline {
            let ready =
                PocketFalseColorMap.overlayPairData(scale: scale, mode: mode)?.clipByte
                == ScopeExposureCeiling.clipByte(transfer: MonitorTransfer(mode))
            if ready {
                if recordReadinessDuration {
                    let duration = ProcessInfo.processInfo.systemUptime - started
                    XCTContext.runActivity(named: "Cold false-color cube readiness") { activity in
                        let attachment = XCTAttachment(
                            string: String(
                                format: "Exact exposure map ready after %.3f s", duration))
                        attachment.lifetime = .keepAlways
                        activity.add(attachment)
                    }
                }
                return
            }
            usleep(20_000)
        }
        XCTFail("false-colour cube warm did not finish in time")
        throw NSError(domain: "FalseColorWarm", code: 1)
    }

    func testCompositorFalseColorIgnoresOperatorLUT() throws {
        try warmOverlayCubes(scale: .ire, mode: .normal)
        let g = UInt8(clamping: Int((MonitorTransfer.rec709.middleGrayEncoded * 255).rounded()))
        let codes = Self.solidImage(code: g)
        let identity = codes
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .ire
        fx.colorMode = .normal

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
        XCTAssertGreaterThan(a.1, a.0, "Rec.709 18% IRE band must win over the mono cube look")
        XCTAssertGreaterThan(b.1, b.0)
    }

    func testCompositorStopsPaintsGrayInTheGaps() throws {
        try warmOverlayCubes(scale: .stops, mode: .dLog2)
        // IRE 20 is a CineStop gap (between 12 and 41). WAVE gray, not camera colour.
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
        XCTAssertEqual(rgb.0, rgb.1, accuracy: 0.06, "CineStop gap is WAVE gray")
        XCTAssertEqual(rgb.1, rgb.2, accuracy: 0.06)
        XCTAssertGreaterThan(rgb.0, 0.12, "CineStop gaps must not collapse to black")
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

    func testAssistOverlayPaintsGrayInCineStopGap() throws {
        try warmOverlayCubes(scale: .stops, mode: .dLog2, recordReadinessDuration: true)
        let encoded = UInt8(
            clamping: Int(
                (ScopeDisplayScale.signalNative(monitorPercent: 20, transfer: .dlog2) * 255)
                    .rounded()))
        let codes = Self.solidImage(code: encoded)
        var fx = LiveImageEffects()
        fx.falseColor = true
        fx.falseColorScale = .stops
        fx.colorMode = .dLog2
        let overlay = LiveMonitorCompositor.assistOverlay(from: codes, effects: fx)
        XCTAssertGreaterThan(
            Self.maxAlpha(overlay), 0.85,
            "CineStop gap is WAVE gray over the picture, not a transparent hole")
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
