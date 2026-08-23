import CoreVideo
import Metal
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// Scope plot geometry + tap→sampler behavior on live-like iOS buffers.
/// Curve/axis math is core-tested; this file pins the app-side drawing seams
/// and the end-to-end legal-scaled contract.
final class LiveScopesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        ScopeExposureCeiling.reset()
    }
    // MARK: - Plot geometry

    func testTraceClipCoversAnchoredBandAndScissorFits() {
        let bounds = CGSize(width: 250, height: 153)
        let plot = scopePlotRect(bounds, top: 26)
        let clip = scopeTraceClipRect(plot)
        XCTAssertEqual(clip.minX, plot.minX, accuracy: 0.01)
        XCTAssertEqual(clip.maxX, plot.maxX, accuracy: 0.01)
        XCTAssertEqual(clip.minY, plot.minY - 2, accuracy: 0.01)
        XCTAssertEqual(clip.maxY, plot.maxY + 2, accuracy: 0.01)
        // IRE 0 / 100 sit on the OpenZCine 4% buffer edges — no extra shelf.
        let line0 = scopeScaleLineY(0, plot)
        let line100 = scopeScaleLineY(100, plot)
        XCTAssertEqual(line0, plot.maxY - 0.04 * plot.height, accuracy: 0.01)
        XCTAssertEqual(line100, plot.maxY - 0.96 * plot.height, accuracy: 0.01)
        XCTAssertLessThan(line0, clip.maxY)
        XCTAssertGreaterThan(line100, clip.minY)
        XCTAssertLessThan(line100, line0, "y grows downward")

        let scissor = ScopeTraceMetal.scissor(
            clip: clip, bounds: bounds, drawable: CGSize(width: 750, height: 459))
        XCTAssertNotNil(scissor)
        XCTAssertGreaterThan(scissor?.width ?? 0, 0)
        XCTAssertGreaterThan(scissor?.height ?? 0, 0)
        XCTAssertGreaterThanOrEqual(scissor?.y ?? -1, 0)
        XCTAssertLessThanOrEqual((scissor?.y ?? 0) + (scissor?.height ?? 0), 459)
    }

    func testGreyMarkerSitsAtTheTransferMidLevel() {
        let plot = scopePlotRect(CGSize(width: 250, height: 153), top: 26)
        for transfer in MonitorTransfer.allCases {
            let marker = scopeLevelY(transfer.scopeAnchors.midLevel, plot)
            let greyTick = scopeTraceLevelY(
                UInt8((transfer.scopeAnchors.mid * 255).rounded()), transfer: transfer, plot)
            XCTAssertEqual(
                Double(marker), Double(greyTick), accuracy: 1.0,
                "\(transfer) grey trace must land on the grey guide line")
        }
    }

    // MARK: - The user-facing contract (legal-scaled end to end)

    func testFullDynamicRangeDLog2GradientSpansScaleZeroToHundred() throws {
        let width = 256
        let liveClip10 = ScopeTestBuffers.legal10(247.0 / 255.0)
        let made = ScopeTestBuffers.makeX420(width: width, height: 16) { x, _ in
            ScopeTestBuffers.dlog2Black10
                + (liveClip10 - ScopeTestBuffers.dlog2Black10) * x / (width - 1)
        }
        let buffer = try XCTUnwrap(made, "x420 must be creatable for the live-format contract")
        let packed = try XCTUnwrap(PocketScopeSampler.copyBGRA(buffer, maxWidth: width))
        let bundle = PocketScopeSampler.sample(
            bytes: packed.bytes, width: packed.width, height: packed.height,
            bytesPerRow: packed.bytesPerRow, transfer: .dlog2,
            includePoints: true, look: nil, previous: .empty)
        XCTAssertFalse(bundle.samples.points.isEmpty)
        let table = ScopeDisplayScale.levelTable(for: .dlog2)
        let levels = bundle.samples.points.map { Double(table[Int($0.luma)]) }
        let minLevel = try XCTUnwrap(levels.min())
        let maxLevel = try XCTUnwrap(levels.max())
        XCTAssertEqual(minLevel, 0.05, accuracy: 0.02, "legal black sits on the 0 line")
        XCTAssertEqual(maxLevel, 0.95, accuracy: 0.02, "live-tap EI ceiling sits on the 100 line")
        let overshoot = Double(table[255])
        XCTAssertGreaterThan(
            overshoot, 0.96, "code 255 is above the 100 line, not stretched onto it")

        // Flat grey (wire 331) pins at the transfer's midLevel.
        let greyBuffer = try XCTUnwrap(
            ScopeTestBuffers.makeX420(width: 32, height: 16) { _, _ in
                ScopeTestBuffers.dlog2Grey10
            })
        let greyPacked = try XCTUnwrap(PocketScopeSampler.copyBGRA(greyBuffer, maxWidth: 32))
        let greyBundle = PocketScopeSampler.sample(
            bytes: greyPacked.bytes, width: greyPacked.width, height: greyPacked.height,
            bytesPerRow: greyPacked.bytesPerRow, transfer: .dlog2,
            includePoints: true, look: nil, previous: .empty)
        let greyLevel = Double(table[Int(greyBundle.samples.points.first?.luma ?? 0)])
        XCTAssertEqual(
            greyLevel, MonitorTransfer.dlog2.scopeAnchors.midLevel, accuracy: 0.02,
            "18% grey pinned at paper IRE 30.50")
    }

    // MARK: - Tap format coverage on iOS buffers

    func testTapExpandsX420LegalAnchorsToPaperBytes() throws {
        let made = ScopeTestBuffers.makeX420(width: 48, height: 16) { x, _ in
            x < 16
                ? ScopeTestBuffers.dlog2Black10
                : (x < 32 ? ScopeTestBuffers.dlog2Grey10 : ScopeTestBuffers.clip10)
        }
        let buffer = try XCTUnwrap(made, "10-bit x420 must be creatable on this host")
        let packed = try XCTUnwrap(PocketScopeSampler.copyBGRA(buffer, maxWidth: 48))
        var values = Set<UInt8>()
        for i in stride(from: 1, to: packed.bytes.count, by: 4) {
            values.insert(packed.bytes[i])
        }
        XCTAssertEqual(values, [16, 78, 255], "legal 119/331/940 → curve bytes 16/78/255")
    }

    func testX420PaperBlackRGBSitsOnWaveZeroNotCrushInset() throws {
        let made = ScopeTestBuffers.makeX420(width: 32, height: 16) { _, _ in
            ScopeTestBuffers.dlog2Black10
        }
        let buffer = try XCTUnwrap(made, "x420 paper black must be creatable")
        let packed = try XCTUnwrap(PocketScopeSampler.copyBGRA(buffer, maxWidth: 32))
        var minC = UInt8.max
        var maxC: UInt8 = 0
        for i in stride(from: 0, to: packed.bytes.count - 2, by: 4) {
            minC = min(minC, packed.bytes[i], packed.bytes[i + 1], packed.bytes[i + 2])
            maxC = max(maxC, packed.bytes[i], packed.bytes[i + 1], packed.bytes[i + 2])
        }
        XCTAssertEqual(minC, 16, "x420 Y119 / limited paper black expands to RGB 16, not a lift")
        XCTAssertEqual(maxC, 16)

        let bundle = PocketScopeSampler.sample(
            bytes: packed.bytes, width: packed.width, height: packed.height,
            bytesPerRow: packed.bytesPerRow, transfer: .dlog2,
            includePoints: true, look: nil, previous: .empty)
        let point = try XCTUnwrap(bundle.samples.points.first)
        XCTAssertEqual(point.red, 16)
        XCTAssertEqual(point.green, 16)
        XCTAssertEqual(point.blue, 16)
        XCTAssertEqual(point.luma, 16)

        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        let line0 = WaveformAxis.scaleLineY(0, plot)
        let leftover = scopeLevelY(
            ScopeDisplayScale.crushLevel, scopePlotRect(CGSize(width: 250, height: 153), top: 26))
        let table = WaveformAxis.levelTable(for: .dlog2)
        var vertices = [ScopeTraceMetal.Vertex](
            repeating: ScopeTraceMetal.Vertex(position: .zero, size: 0, color: .zero),
            count: ScopeTraceMetal.maxVertexCount(points: 1, mode: .waveform(.rgb)))
        let written = vertices.withUnsafeMutableBufferPointer { out in
            ScopeTraceMetal.fillVertices(
                out, from: 0, points: [point], mode: .waveform(.rgb), rect: plot,
                opacity: 1, levelTable: table)
        }
        XCTAssertEqual(written, 3)
        for channel in 0..<3 {
            XCTAssertEqual(
                Double(vertices[channel].position.y) + 0.5, Double(line0), accuracy: 0.1,
                "RGB channel \(channel) of paper black must sit on WAVE 0")
            XCTAssertGreaterThan(
                abs(Double(vertices[channel].position.y) + 0.5 - Double(leftover)), 3,
                "must not sit on the leftover 0.05 / 4% crush inset")
        }
    }

    func testLimitedRangeY16RGBDoesNotSitAtFivePercent() {
        let buffer = ScopeTestBuffers.make420v(width: 32, height: 16, leftY: 16, rightY: 16)
        guard let packed = PocketScopeSampler.copyBGRA(buffer, maxWidth: 32) else {
            XCTFail("420v Y16 must tap")
            return
        }
        var maxC: UInt8 = 0
        for i in stride(from: 0, to: packed.bytes.count - 2, by: 4) {
            maxC = max(maxC, packed.bytes[i], packed.bytes[i + 1], packed.bytes[i + 2])
        }
        XCTAssertEqual(maxC, 0, "limited Y=16 expands to curve 0, not a lifted ~20")

        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        let line0 = WaveformAxis.scaleLineY(0, plot)
        let line5 = WaveformAxis.scaleLineY(5, plot)
        let leftover = WaveformAxis.plotY(ScopeDisplayScale.crushLevel, plot)
        let y = WaveformAxis.traceY(0, transfer: .dlog2, plot)
        XCTAssertGreaterThanOrEqual(y, line0 - 0.2, "container legal black is at or below WAVE 0")
        XCTAssertEqual(leftover, line0, accuracy: 0.5, "0.05 is 0.05 IRE, not 5% of the plot")
        XCTAssertGreaterThan(line0 - line5, 4, "the 5 IRE buffer is above 0")
    }

    func testTapExpandsIOSurfaceX420() throws {
        let made = ScopeTestBuffers.makeX420(width: 64, height: 32, ioSurface: true) { _, _ in
            ScopeTestBuffers.dlog2Grey10
        }
        let buffer = try XCTUnwrap(made, "IOSurface x420 must be creatable on this host")
        XCTAssertTrue(LiveFrameTap.isIOSurfaceBacked(buffer))
        let packed = try XCTUnwrap(
            PocketScopeSampler.copyBGRA(buffer, maxWidth: 64),
            "IOSurface-backed planes must tap (the historical zeros bug)")
        XCTAssertGreaterThan(LiveFrameTap.maxRGB(packed.bytes), 0)
        for i in stride(from: 1, to: packed.bytes.count, by: 4) {
            XCTAssertEqual(packed.bytes[i], 78)
        }
    }

    func testTapReads420vEdge() {
        let buffer = ScopeTestBuffers.make420v(width: 64, height: 48, leftY: 16, rightY: 235)
        XCTAssertEqual(
            CVPixelBufferGetPixelFormatType(buffer),
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        guard let packed = PocketScopeSampler.copyBGRA(buffer, maxWidth: 32) else {
            XCTFail("420v must tap via the planar reader")
            return
        }
        var minB = UInt8.max
        var maxB: UInt8 = 0
        for i in stride(from: 1, to: packed.bytes.count, by: 4) {
            minB = min(minB, packed.bytes[i])
            maxB = max(maxB, packed.bytes[i])
        }
        XCTAssertEqual(minB, 0, "legal floor Y16 expands to curve 0")
        XCTAssertEqual(maxB, 255, "legal white Y235 expands to curve 255")
    }

    func testIOSurfaceDLog2BlackTapsToByte16AndCrushes() throws {
        let made = ScopeTestBuffers.makeIOSurfaceBGRA(width: 64, height: 48, left: 16, right: 16)
        try XCTSkipIf(!made.filled, "IOSurface BGRA is not CPU-writable here")
        let packed = try XCTUnwrap(
            PocketScopeSampler.copyBGRA(made.buffer, maxWidth: 32),
            "IOSurface D-Log2 black must tap")
        var sum = 0
        var count = 0
        for i in stride(from: 0, to: packed.bytes.count - 2, by: 4) {
            sum += Int(packed.bytes[i]) + Int(packed.bytes[i + 1]) + Int(packed.bytes[i + 2])
            count += 3
        }
        let mean = count == 0 ? 0 : Double(sum) / Double(count)
        XCTAssertEqual(mean, 16, accuracy: 1, "tap must keep the curve byte, not γ-lift it")

        let bundle = PocketScopeSampler.sample(
            bytes: packed.bytes, width: packed.width, height: packed.height,
            bytesPerRow: packed.bytesPerRow, transfer: .dlog2,
            includePoints: true, look: nil, previous: .empty)
        XCTAssertEqual(
            bundle.samples.histogramLuma[16],
            bundle.samples.points.count, "every sampled pixel lands in native bin 16")
        XCTAssertTrue(bundle.traffic.anyCrush, "a black-only frame is a toe pile-up")
        XCTAssertFalse(bundle.traffic.anyClip)
        // And it draws on the 0 line.
        let plot = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(
            scopeTraceLevelY(16, transfer: .dlog2, plot),
            scopeLevelY(ScopeDisplayScale.crushLevel, plot),
            accuracy: 0.5,
            "legal black sits on the drawn 0 line")
    }

    func testSubBlackNoiseDrawsBelowTheZeroLineAndDoesNotCrush() {
        // Real Pocket 4P floors measured 112/142 — below the paper black
        // prediction. Those dips must stay visible in the sub-black margin and
        // must not light the crush lamp (they are noise, not crushed picture).
        let plot = CGRect(x: 0, y: 0, width: 100, height: 100)
        let noise = scopeTraceLevelY(10, transfer: .dlog2, plot)
        let zero = scopeLevelY(ScopeDisplayScale.crushLevel, plot)
        XCTAssertGreaterThan(noise, zero, "sub-black draws in the margin below the 0 line")
        XCTAssertLessThanOrEqual(noise, scopeLevelY(0, plot) + 0.01, "but inside the clip band")

        var bytes = [UInt8]()
        for _ in 0..<32 {
            bytes.append(contentsOf: [10, 10, 10, 255])
        }
        let bundle = PocketScopeSampler.sample(
            bytes: bytes, width: 32, height: 1, bytesPerRow: 128,
            transfer: .dlog2, includePoints: false, look: nil, previous: .empty)
        XCTAssertFalse(bundle.traffic.anyCrush, "sub-black noise is below the crush floor")
    }

    func testContainerSubBlackSurvivesTheTapAndTrueBlackSitsOnTheZeroLine() throws {
        // The bottom shelf, container-referenced: sub-black sensor noise at
        // container Y 80 must survive the tap's legal expansion (byte 5 — the
        // `max(0, luma − 64)` clamp only bites below container 64), draw
        // strictly BELOW the 0 line, and never light the crush lamp. True
        // D-Log2 black (container 119) → byte 16 → ON the 0 line.
        let made = ScopeTestBuffers.makeX420(width: 32, height: 16) { x, _ in
            x < 16 ? 80 : ScopeTestBuffers.dlog2Black10
        }
        let buffer = try XCTUnwrap(made, "x420 must be creatable")
        let packed = try XCTUnwrap(PocketScopeSampler.copyBGRA(buffer, maxWidth: 32))
        var values = Set<UInt8>()
        for i in stride(from: 1, to: packed.bytes.count, by: 4) {
            values.insert(packed.bytes[i])
        }
        XCTAssertEqual(values, [5, 16], "container 80/119 → curve bytes 5/16, no premature clamp")

        let plot = CGRect(x: 0, y: 0, width: 100, height: 100)
        let zeroLine = scopeLevelY(ScopeDisplayScale.crushLevel, plot)
        XCTAssertGreaterThan(
            scopeTraceLevelY(5, transfer: .dlog2, plot), zeroLine + 1,
            "container-80 noise draws strictly below the 0 line, not crushed onto it")
        XCTAssertEqual(
            Double(scopeTraceLevelY(16, transfer: .dlog2, plot)), Double(zeroLine),
            accuracy: 0.5, "container-119 true black sits on the 0 line")

        // A noise-only frame meters clean: below the crush band, no lights.
        let noiseOnly = try XCTUnwrap(
            ScopeTestBuffers.makeX420(width: 32, height: 16) { _, _ in 80 })
        let noisePacked = try XCTUnwrap(PocketScopeSampler.copyBGRA(noiseOnly, maxWidth: 32))
        let bundle = PocketScopeSampler.sample(
            bytes: noisePacked.bytes, width: noisePacked.width, height: noisePacked.height,
            bytesPerRow: noisePacked.bytesPerRow, transfer: .dlog2,
            includePoints: false, look: nil, previous: .empty)
        XCTAssertFalse(bundle.traffic.anyCrush, "sub-black noise is noise, not crushed picture")
        XCTAssertFalse(bundle.traffic.anyClip)
    }

    // MARK: - Vectorscope raster

    func testVectorscopeNeutralGreyStaysCentredAndZoomExpands() throws {
        let n = VectorscopeRaster.bins
        func peakBin(_ pixels: [UInt8]) -> (x: Int, y: Int) {
            var best = 0
            var bestAlpha: UInt8 = 0
            for i in 0..<(n * n) where pixels[i * 4 + 3] > bestAlpha {
                bestAlpha = pixels[i * 4 + 3]
                best = i
            }
            return (best % n, best / n)
        }
        let grey = ScopePoint(xRatio: 0.5, yRatio: 0.5, red: 128, green: 128, blue: 128, luma: 128)
        let greyPixels = try XCTUnwrap(
            VectorscopeRaster.pixels(from: [grey], gain: 1, intensity: 1))
        let g = peakBin(greyPixels)
        XCTAssertEqual(Double(g.x), Double(n / 2), accuracy: 1.5, "neutral chroma bins at centre")
        XCTAssertEqual(Double(g.y), Double(n / 2), accuracy: 1.5)

        // Moderate saturation: a full-sat red at 2× gain leaves the plot and bins nothing.
        let red = ScopePoint(xRatio: 0.5, yRatio: 0.5, red: 160, green: 80, blue: 80, luma: 100)
        let unity = try XCTUnwrap(VectorscopeRaster.pixels(from: [red], gain: 1, intensity: 1))
        let zoomed = try XCTUnwrap(VectorscopeRaster.pixels(from: [red], gain: 2, intensity: 1))
        let a = peakBin(unity)
        let b = peakBin(zoomed)
        let mid = Double(n / 2)
        let unityRadius = hypot(Double(a.x) - mid, Double(a.y) - mid)
        let zoomedRadius = hypot(Double(b.x) - mid, Double(b.y) - mid)
        XCTAssertGreaterThan(unityRadius, 1, "saturated red must leave the centre")
        XCTAssertGreaterThan(zoomedRadius, unityRadius * 1.4, "2× gain expands the trace")
    }
}
