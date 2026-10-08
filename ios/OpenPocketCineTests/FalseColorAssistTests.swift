import CoreImage
import OpenCineCameraVocabulary
import OpenPocketViewCore
import OpenCineCameraControls
import XCTest
import OpenCineApple
import OpenCineMedia

@testable import OpenPocketCine

/// Pins OpenZCine `falseColorRows` + `FalseColorScale.legendStops` against what we ship.
final class FalseColorAssistTests: XCTestCase {
    /// This test's monitored source (XCTest makes a fresh one per test).
    private let ceiling = DJIScopeExposureCeiling()

    func testExposureChangeKeepsFalseColorPaintAvailable() throws {
        ceiling.setISO(1600)
        try warmOverlayCubes(scale: .ire, mode: .dLog2)
        for iso in [125, 200, 400, 800, 1600] {
            let previous = try XCTUnwrap(
                PocketFalseColorMap.overlayPairData(
                    scale: .ire, mode: .dLog2, rec709: false,
                    clipByte: ceiling.clipByte(transfer: .dlog2)))
            ceiling.setISO(iso)
            let retained = try XCTUnwrap(
                PocketFalseColorMap.overlayPairData(
                    scale: .ire, mode: .dLog2, rec709: false,
                    clipByte: ceiling.clipByte(transfer: .dlog2)),
                "Exposure updates must not remove false color while warming")
            XCTAssertEqual(retained.clipByte, previous.clipByte)
            XCTAssertEqual(retained.paint, previous.paint)
            XCTAssertEqual(retained.weight, previous.weight)
            try warmOverlayCubes(scale: .ire, mode: .dLog2)
            XCTAssertEqual(
                PocketFalseColorMap.overlayPairData(
                    scale: .ire, mode: .dLog2, rec709: false,
                    clipByte: ceiling.clipByte(transfer: .dlog2))?.clipByte,
                ceiling.clipByte(transfer: .dlog2))
        }
    }

    func testExposureReturningToCachedMapDiscardsObsoleteBuild() throws {
        ceiling.setISO(1600)
        try warmOverlayCubes(scale: .limits, mode: .dLog2)
        let original = try XCTUnwrap(
            PocketFalseColorMap.overlayPairData(
                scale: .limits, mode: .dLog2, rec709: false,
                clipByte: ceiling.clipByte(transfer: .dlog2)))
        ceiling.setISO(125)
        _ = PocketFalseColorMap.overlayPairData(
            scale: .limits, mode: .dLog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2))
        ceiling.setISO(1600)
        for _ in 0..<50 {
            let maps = try XCTUnwrap(
                PocketFalseColorMap.overlayPairData(
                    scale: .limits, mode: .dLog2, rec709: false,
                    clipByte: ceiling.clipByte(transfer: .dlog2)))
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
        ceiling.setISO(100)
        ceiling.observeTapMax(170, transfer: .dlog2)
        XCTAssertEqual(ScopeDisplayScale.waveformLevel(0.7, anchors: anchors), before)
        XCTAssertEqual(
            LiveColorScience.falseColorBands(
                .stops, transfer: .dlog2,
                clipEncoded: anchors.clip), bands)
        XCTAssertEqual(anchors.clip, 200.0 / 255.0)
    }

    /// Legend copy is pinned once, in core `LiveColorScienceTests`; the shell must
    /// match it band for band (the `zip` in `legendStops` would silently truncate).
    func testLegendLabelsMatchCoreFalseColorBands() {
        for scale in MonitorFalseColorSelection.allCases where !scale.liveScale.usesSceneStops {
            let core = PocketFalseColorMap.bands(
                scale: scale, transfer: .dlog2, rec709: false,
                clipByte: ceiling.clipByte(transfer: .dlog2)
            ).map(\.label)
            XCTAssertEqual(FalseColorAssist.legendLabels(scale: scale), core, "\(scale) labels")
            XCTAssertEqual(
                scale.legendStops(
                    transfer: .dlog2, rec709: false, clipByte: ceiling.clipByte(transfer: .dlog2)
                ).map(\.label), core, "\(scale) legend stops")
        }
    }

    /// The scale help names this app's scales, and its legend chrome is the shared ruler's size.
    func testScaleHelpAndReferenceChromeFollowTheSharedReference() {
        XCTAssertTrue(FalseColorLooks.app.scaleHelp.contains("CineStop"))
        XCTAssertTrue(FalseColorLooks.app.scaleHelp.contains("Video"))
        XCTAssertEqual(FalseColorReferenceChrome.panelSize, FalseColorReference.panelSize)
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
        FalseColorAssist.selectScale("Video", assist: assist)
        XCTAssertEqual(assist.falseColorScale, .stops)
        FalseColorAssist.selectScale("CineStop", assist: assist)
        XCTAssertEqual(assist.falseColorScale, .sceneStops)
    }

    func testCineStopPaintsEveryStopFlat() {
        let cube = PocketFalseColorMap.overlayPaintCube(
            scale: .sceneStops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2))
        func sample(stops: Double) -> (red: Float, green: Float, blue: Float) {
            let code = Float(LiveColorScience.encode(0.18 * pow(2, stops), transfer: .dlog2))
            let rgb = cube.map(red: code, green: code, blue: code)
            return (rgb.red, rgb.green, rgb.blue)
        }
        let gray = sample(stops: 0)
        XCTAssertEqual(gray.red, 127.0 / 255, accuracy: 0.03, "0 stops is gray")
        XCTAssertEqual(gray.red, gray.green, accuracy: 0.01)
        XCTAssertEqual(gray.green, gray.blue, accuracy: 0.01)
        let upper = sample(stops: 2)
        XCTAssertEqual(upper.red, 252.0 / 255, accuracy: 0.04, "+2 is soft yellow")
        XCTAssertEqual(upper.green, 232.0 / 255, accuracy: 0.04)
        let shadows = sample(stops: -4)
        XCTAssertEqual(shadows.red, 102.0 / 255, accuracy: 0.03, "−4 stops is flat dark gray")
        XCTAssertEqual(shadows.red, shadows.blue, accuracy: 0.01)
        let highlights = sample(stops: 5)
        XCTAssertEqual(highlights.red, 179.0 / 255, accuracy: 0.03, "+5 stops is flat light gray")
        let over = cube.map(red: 1, green: 1, blue: 1)
        XCTAssertGreaterThan(over.red, 0.8, "past the live-tap ceiling is clip red")
        XCTAssertLessThan(over.green, 0.3)
        let weight = PocketFalseColorMap.overlayWeightCube(
            scale: .sceneStops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: 0.5, green: 0.5, blue: 0.5)
        XCTAssertGreaterThan(weight.red, 0.9, "CineStop covers the picture, not a hole")
    }

    /// OpenZCine `testFalseColorReferenceUsesCompactProportionalScales`.

    func testIREOverlayPaintsRec709GreyGreenAndDLog2GreyAsAGap() {
        let rec709Cube = PocketFalseColorMap.overlayPaintCube(
            scale: .ire, transfer: .rec709, rec709: false,
            clipByte: ceiling.clipByte(transfer: .rec709))
        let rec709Grey = Float(MonitorTransfer.rec709.middleGrayEncoded)
        let rec709 = rec709Cube.map(red: rec709Grey, green: rec709Grey, blue: rec709Grey)
        XCTAssertGreaterThan(
            rec709.green, rec709.red,
            "Rec.709 18% grey is WAVE ~41 (18%MG green)")

        let cube = PocketFalseColorMap.overlayPaintCube(
            scale: .ire, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2))
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let mapped = cube.map(red: g, green: g, blue: g)
        XCTAssertEqual(mapped.red, mapped.green, accuracy: 0.06, "D-Log2 18% is an IRE gap")
        XCTAssertEqual(mapped.green, mapped.blue, accuracy: 0.06)
        let weight = PocketFalseColorMap.overlayWeightCube(
            scale: .ire, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(weight.red, 0.5, "IRE gaps cover the picture, not a hole")
        let clip = Float(ceiling.clipEncoded(transfer: .dlog2))
        let over = cube.map(red: clip, green: clip, blue: clip)
        XCTAssertGreaterThan(over.red, over.green, "live-tap ceiling is 95%WC red")
        let early = cube.map(red: 188.0 / 255, green: 188.0 / 255, blue: 188.0 / 255)
        XCTAssertLessThan(
            early.red, over.red, "byte 188 is recoverable D-Log2 highlight, not the clip band")

        let dlogC = Float(223) / 255
        let dlogClip = PocketFalseColorMap.overlayPaintCube(
            scale: .ire, transfer: .dlog, rec709: false, clipByte: ceiling.clipByte(transfer: .dlog)
        )
        .map(red: dlogC, green: dlogC, blue: dlogC)
        XCTAssertGreaterThan(
            dlogClip.red, dlogClip.green, "D-Log live-tap max 223 is the clip band")
    }

    func testPostLUTCodesAreADifferentIREBand() throws {
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let pre = PocketFalseColorMap.overlayPaintCube(
            scale: .stops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: g, green: g, blue: g)
        guard let look = BundledPocketLUT.cube(.dLog2ToRec709) else {
            throw XCTSkip("official D-Log2 cube must load")
        }
        let graded = look.map(red: g, green: g, blue: g)
        let post = PocketFalseColorMap.overlayPaintCube(
            scale: .stops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: graded.red, green: graded.green, blue: graded.blue)
        let delta =
            abs(post.red - pre.red) + abs(post.green - pre.green) + abs(post.blue - pre.blue)
        XCTAssertGreaterThan(
            delta, 0.05,
            "log→709 18% is a different D-Log2 code — sampling the cube look must not be how FALSE keys"
        )
    }

    func testVideoGapsAreGrayscaleAndRec709EighteenIsGreen() {
        let encoded = Float(
            ScopeDisplayScale.signalNative(
                monitorPercent: 20, transfer: .dlog2, clipByte: ceiling.clipByte(transfer: .dlog2)))
        let overlay = PocketFalseColorMap.overlayPaintCube(
            scale: .stops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertEqual(overlay.red, overlay.green, accuracy: 0.04)
        XCTAssertEqual(overlay.green, overlay.blue, accuracy: 0.04)
        XCTAssertGreaterThan(overlay.red, 0.12)

        let grey = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let dlog2 = PocketFalseColorMap.cube(
            scale: .stops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: grey, green: grey, blue: grey)
        XCTAssertEqual(dlog2.red, dlog2.green, accuracy: 0.06, "D-Log2 18% is a Video gap")
        let rec709Grey = Float(MonitorTransfer.rec709.middleGrayEncoded)
        let rec709 = PocketFalseColorMap.cube(
            scale: .stops, transfer: .rec709, rec709: false,
            clipByte: ceiling.clipByte(transfer: .rec709)
        )
        .map(red: rec709Grey, green: rec709Grey, blue: rec709Grey)
        XCTAssertGreaterThan(rec709.green, rec709.red, "Rec.709 18% hits 41–48 green")
        let overlayWeight = PocketFalseColorMap.overlayWeightCube(
            scale: .stops, transfer: .dlog2, rec709: false,
            clipByte: ceiling.clipByte(transfer: .dlog2)
        )
        .map(red: encoded, green: encoded, blue: encoded)
        XCTAssertGreaterThan(
            overlayWeight.red, 0.9, "Video gaps cover the picture, not punch through")
    }

    /// The compositor reads the async-warmed cube bytes (`overlayPaintData` /
    /// `overlayWeightData` return nil until the lattice build lands). Tests
    /// must warm first — the app shows the plain look meanwhile.
    private func warmOverlayCubes(
        scale: MonitorFalseColorSelection, mode: ColorMode, recordReadinessDuration: Bool = false
    ) throws {
        let started = ProcessInfo.processInfo.systemUptime
        let clip = ceiling.clipByte(transfer: MonitorTransfer(mode))
        PocketFalseColorMap.warm(scale: scale, mode: mode, rec709: false, clipByte: clip)
        // This bounds functional setup, not a live-performance benchmark. The
        // two cold 64³ lattices already take about five seconds in unoptimized
        // simulator builds, so normal host contention must not skip pixel checks.
        let deadline = started + 30
        while ProcessInfo.processInfo.systemUptime < deadline {
            let ready =
                PocketFalseColorMap.overlayPairData(
                    scale: scale, mode: mode, rec709: false, clipByte: clip)?.clipByte == clip
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
        var fx = MonitorFrameEffects()
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
        // IRE 20 is a Video gap (between 12 and 41). WAVE gray, not camera colour.
        let encoded = UInt8(
            clamping: Int(
                (ScopeDisplayScale.signalNative(
                    monitorPercent: 20, transfer: .dlog2,
                    clipByte: ceiling.clipByte(transfer: .dlog2)) * 255)
                    .rounded()))
        let codes = Self.solidImage(code: encoded)
        var fx = MonitorFrameEffects()
        fx.falseColor = true
        fx.falseColorScale = .stops
        fx.colorMode = .dLog2
        let product = LiveMonitorCompositor.applyProduct(to: codes, effects: fx, display: codes)
        let rgb = Self.sampleRGB(product.image)
        XCTAssertEqual(rgb.0, rgb.1, accuracy: 0.06, "Video gap is WAVE gray")
        XCTAssertEqual(rgb.1, rgb.2, accuracy: 0.06)
        XCTAssertGreaterThan(rgb.0, 0.12, "Video gaps must not collapse to black")
    }

    func testLimitsOverlayShowsLUTBetweenZones() throws {
        try warmOverlayCubes(scale: .limits, mode: .dLog2)
        let grey = UInt8(clamping: Int((MonitorTransfer.dlog2.middleGrayEncoded * 255).rounded()))
        let codes = Self.solidImage(code: grey)
        var fx = MonitorFrameEffects()
        fx.falseColor = true
        fx.falseColorScale = .limits
        fx.colorMode = .dLog2
        let look = BuiltInLook.mono.cube()
        fx.lutDimension = look.size
        fx.lutRGBA = look.rgbaComponents.withUnsafeBytes { Data($0) }

        let painted = LiveMonitorCompositor.apply(to: codes, effects: fx, display: codes)
        let gradedOnly = {
            var lutOnly = MonitorFrameEffects()
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

    func testAssistOverlayPaintsGrayInVideoGap() throws {
        try warmOverlayCubes(scale: .stops, mode: .dLog2, recordReadinessDuration: true)
        let encoded = UInt8(
            clamping: Int(
                (ScopeDisplayScale.signalNative(
                    monitorPercent: 20, transfer: .dlog2,
                    clipByte: ceiling.clipByte(transfer: .dlog2)) * 255)
                    .rounded()))
        let codes = Self.solidImage(code: encoded)
        var fx = MonitorFrameEffects()
        fx.falseColor = true
        fx.falseColorScale = .stops
        fx.colorMode = .dLog2
        let overlay = LiveMonitorCompositor.assistOverlay(from: codes, effects: fx)
        XCTAssertGreaterThan(
            Self.maxAlpha(overlay), 0.85,
            "Video gap is WAVE gray over the picture, not a transparent hole")
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
        let context = CIContext(options: MonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) / 255, Float(bytes[1]) / 255, Float(bytes[2]) / 255)
    }
}
