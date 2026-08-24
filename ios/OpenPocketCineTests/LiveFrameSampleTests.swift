import AVFoundation
import CoreImage
import CoreVideo
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// App-layer pipeline: decoder → `LiveAssistEngine` → `LiveFrameSampleBus` →
/// `ScopeAssistBundle`. Curve math itself is covered by the core suite — these
/// tests pin the plumbing, throttle, layer handoff, and effect compositing.
@MainActor
final class LiveFrameSampleTests: XCTestCase {
    func testHandleDecodedFramePublishesScopes() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .rec709 })
        decoder.effects = fx

        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeEdgeBuffer(), effects: fx, transfer: .rec709)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if bus.decodedFrames >= 1, bus.publishedScopes >= 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThanOrEqual(
            bus.decodedFrames, 1, "pixel-buffer callback must increment decodedFrames")
        XCTAssertGreaterThanOrEqual(
            bus.publishedScopes, 1, "scopes must sample the ingested buffer")
        XCTAssertGreaterThanOrEqual(bus.generation, 1, "SwiftUI scopes observe generation")
        XCTAssertNotNil(bus.sourcePixelBuffer, "bus must publish the source buffer")
        XCTAssertEqual(bus.transfer, .rec709)
        XCTAssertEqual(bus.colorMode, .normal)
        XCTAssertEqual(
            bus.bundle.transfer, .rec709, "views read bundle.transfer, never session status")
        XCTAssertFalse(bus.bundle.samples.points.isEmpty, "WAVE needs the shared point bundle")
        XCTAssertFalse(
            bus.bundle.samples.histogramLuma.allSatisfy { $0 == 0 }, "native histogram must fill")
        XCTAssertFalse(
            bus.bundle.histogramDisplay.luma.allSatisfy { $0 == 0 },
            "display histogram must be precomputed")
        XCTAssertGreaterThan(bus.bundle.revision, 0)
    }

    func testHandleDecodedFrameIncrementsGenerationEachCall() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .rec709 })
        decoder.effects = fx

        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeEdgeBuffer(), effects: fx, transfer: .rec709)
        let firstDeadline = Date().addingTimeInterval(2)
        while Date() < firstDeadline {
            if bus.generation >= 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        let first = bus.generation
        XCTAssertGreaterThanOrEqual(first, 1, "first scoped sample must tick generation")

        // Past the 25 Hz gate.
        try? await Task.sleep(for: .milliseconds(50))
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 200), effects: fx, transfer: .rec709)
        let secondDeadline = Date().addingTimeInterval(2)
        while Date() < secondDeadline {
            if bus.generation > first { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThan(
            bus.generation, first, "each scoped sample past the 25 Hz gate must tick generation")
        XCTAssertGreaterThanOrEqual(bus.decodedFrames, 2, "sequential feed drains every frame")
    }

    // MARK: - Layer / feed handoff

    func testLUTOffHandsHEVCBackToDisplayLayerWithoutFlush() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        decoder.effects = fx
        feed.isHidden = false
        decoder.displayLayer.isHidden = true
        XCTAssertTrue(decoder.effects.needsGPUFeed)
        XCTAssertTrue(decoder.effects.needsSample)

        decoder.effects = LiveImageEffects()
        XCTAssertFalse(decoder.effects.needsGPUFeed)
        XCTAssertFalse(decoder.displayLayer.isHidden, "LUT off must show the identity layer")
        XCTAssertTrue(
            feed.isHidden,
            "opaque CIFeedView must not cover Rec.709 / HLG HEVC")
        XCTAssertFalse(decoder.displayedImageRemoved, "toggle must not flushAndRemoveImage")
        XCTAssertFalse(decoder.videoToolboxActive, "no format yet — VT never opened")
        XCTAssertFalse(decoder.awaitingIDR, "LUT off must not hold IDR")
    }

    func testLUTOffAfterDecodedFrameDoesNotFlushOrHoldIDR() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .rec709 })
        decoder.effects = fx
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeEdgeBuffer(), effects: fx, transfer: .rec709)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if bus.decodedFrames >= 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(bus.decodedFrames, 1)

        decoder.effects = LiveImageEffects()
        XCTAssertFalse(
            decoder.displayedImageRemoved, "LUT off after a picture must keep the last frame")
        XCTAssertFalse(decoder.awaitingIDR)
        XCTAssertTrue(feed.isHidden)
        XCTAssertFalse(decoder.displayLayer.isHidden)
        XCTAssertFalse(decoder.videoToolboxActive)
    }

    func testFaceAFKeepsIdentityDisplayLayer() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        feed.isHidden = false
        decoder.displayLayer.isHidden = true

        decoder.effects = LiveImageEffects().withFaceAF(true)
        XCTAssertTrue(decoder.effects.needsSample)
        XCTAssertFalse(decoder.effects.needsGPUFeed)
        XCTAssertFalse(decoder.effects.replacesIdentityFeed)
        XCTAssertFalse(
            decoder.displayLayer.isHidden,
            "Face AF starts VT but the identity picture stays on the display layer")
        XCTAssertTrue(
            feed.isHidden,
            "opaque CIFeedView must not cover the layer while Face AF is reading buffers")
    }

    func testFastUpscalerDoesNotStealIdentityLayer() {
        let previous = FeedUpscaleSwitch.rendererReadsUpscaler
        FeedUpscaleSwitch.rendererReadsUpscaler = .lanczos
        defer { FeedUpscaleSwitch.rendererReadsUpscaler = previous }

        let decoder = HevcDecoder()
        decoder.feedUpscaler = .lanczos
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        feed.isHidden = false
        decoder.displayLayer.isHidden = true

        decoder.effects = LiveImageEffects()
        XCTAssertFalse(decoder.displayLayer.isHidden)
        XCTAssertTrue(feed.isHidden)

        var zebra = LiveImageEffects()
        zebra.zebra = true
        decoder.effects = zebra
        XCTAssertFalse(
            decoder.displayLayer.isHidden,
            "Fast upscale must not remake identity — zebra stays a transparent overlay")
    }

    func testZebraKeepsIdentityDisplayLayer() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        feed.isHidden = true
        decoder.displayLayer.isHidden = false

        var fx = LiveImageEffects()
        fx.zebra = true
        decoder.effects = fx
        XCTAssertTrue(decoder.effects.needsOverlayFeed)
        XCTAssertFalse(decoder.effects.replacesIdentityFeed)
        XCTAssertFalse(
            decoder.displayLayer.isHidden,
            "zebra must not cover Rec.709 / D-Log2 identity with a remade CI picture")
    }

    func testFalseColorKeepsIdentityDisplayLayer() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        feed.isHidden = true
        decoder.displayLayer.isHidden = false

        var fx = LiveImageEffects()
        fx.falseColor = true
        decoder.effects = fx
        XCTAssertTrue(decoder.effects.needsOverlayFeed)
        XCTAssertFalse(decoder.effects.replacesIdentityFeed)
        XCTAssertFalse(
            decoder.displayLayer.isHidden,
            "false colour must not cover Rec.709 / D-Log2 identity with a remade CI picture")
    }

    func testRec709AndHDRWithoutLUTUseDisplayLayer() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        feed.isHidden = false
        decoder.displayLayer.isHidden = true

        decoder.incomingTransfer = .rec709
        decoder.effects = LiveImageEffects()
        XCTAssertFalse(decoder.effects.needsGPUFeed)
        XCTAssertFalse(decoder.displayLayer.isHidden)
        XCTAssertTrue(feed.isHidden)

        decoder.incomingTransfer = .hdr
        decoder.effects = LiveImageEffects()
        XCTAssertFalse(decoder.effects.needsGPUFeed)
        XCTAssertFalse(decoder.displayLayer.isHidden)
        XCTAssertTrue(feed.isHidden)
        XCTAssertFalse(decoder.displayedImageRemoved)
    }

    func testDLog2LUTToRec709HidesOpaqueFeed() {
        let decoder = HevcDecoder()
        let feed = CIFeedView(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        decoder.processedFeed = feed
        let cube = BuiltInLook.mono.cube()
        var logFX = LiveImageEffects()
        logFX.lutDimension = cube.size
        logFX.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        logFX.colorMode = .dLog2
        decoder.incomingTransfer = .dlog2
        decoder.effects = logFX
        feed.isHidden = false
        decoder.displayLayer.isHidden = true

        decoder.incomingTransfer = .rec709
        decoder.effects = LiveImageEffects()
        XCTAssertFalse(decoder.effects.needsGPUFeed)
        XCTAssertFalse(decoder.displayLayer.isHidden)
        XCTAssertTrue(feed.isHidden)
        XCTAssertFalse(decoder.videoToolboxActive)
        XCTAssertFalse(decoder.displayedImageRemoved)
    }

    func testLUTOnlyPresentDoesNotTickScopeGeneration() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .rec709 })
        decoder.effects = fx

        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeEdgeBuffer(), effects: fx, transfer: .rec709)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if bus.decodedFrames >= 1 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThanOrEqual(bus.decodedFrames, 1)
        try? await Task.sleep(for: .milliseconds(80))
        XCTAssertEqual(bus.generation, 0, "LUT present must not invalidate the chrome tree")
        XCTAssertEqual(bus.publishedScopes, 0)
    }

    // MARK: - Transfer plumbing

    func testDLog2TransferRidesWithSample() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .dlog2 })
        decoder.effects = fx
        decoder.incomingTransfer = .dlog2

        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeFlatBuffer(code: 78), effects: fx, transfer: .dlog2)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if bus.publishedScopes >= 1, bus.colorMode == .dLog2 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(bus.transfer, .dlog2, "ColorMode D-Log2 must become MonitorTransfer.dlog2")
        XCTAssertEqual(bus.colorMode, .dLog2)
        XCTAssertNotNil(bus.sourcePixelBuffer)
        XCTAssertEqual(bus.bundle.transfer, .dlog2, "the bundle carries the transfer for the views")
        XCTAssertFalse(bus.bundle.samples.histogramLuma.allSatisfy { $0 == 0 })
    }

    func testTransferResolutionAndColorModeRoundTrip() {
        XCTAssertEqual(MonitorTransfer.resolved(nil, colorMode: nil), .rec709)
        XCTAssertEqual(MonitorTransfer.resolved(nil, colorMode: .dLog2), .dlog2)
        XCTAssertEqual(MonitorTransfer.resolved(.dlog, colorMode: .normal), .dlog, "status wins")
        for transfer in MonitorTransfer.allCases {
            XCTAssertEqual(MonitorTransfer(transfer.colorMode), transfer, "wire round trip")
        }
    }

    func testMissingColorModeKeepsPreviousLogTransfer() {
        XCTAssertEqual(
            MonitorTransfer.resolved(nil, colorMode: nil, previous: .dlog2),
            .dlog2,
            "nil @2 must not drop WAVE back to Rec.709 — that shelves D-Log2 black at ~8")
        XCTAssertEqual(
            MonitorTransfer.resolved(nil, colorMode: nil, previous: .dlog),
            .dlog)
        XCTAssertEqual(
            MonitorTransfer.resolved(.rec709, colorMode: nil, previous: .dlog2),
            .rec709,
            "an explicit Normal reading still wins")
    }

    func testNilStatusTransferDoesNotWipeDecoderLogTransfer() {
        let decoder = HevcDecoder()
        decoder.incomingTransfer = .dlog2
        decoder.adoptIncomingTransfer(nil)
        XCTAssertEqual(
            decoder.incomingTransfer, .dlog2,
            "VideoView.wire used to assign nil and park D-Log2 paper black at ~8 IRE")
        decoder.adoptIncomingTransfer(.rec709)
        XCTAssertEqual(decoder.incomingTransfer, .rec709, "explicit Normal still applies")
    }

    func testDLog2TapSignaturePromotesDefaultRec709Transfer() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .rec709 })
        decoder.effects = fx
        decoder.handleDecodedFrame(
            ScopeTestBuffers.makeBGRA { x, _ in x < 64 ? 16 : 247 },
            effects: fx, transfer: .rec709)

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if bus.publishedScopes >= 1, bus.bundle.transfer == .dlog2 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertEqual(
            bus.bundle.transfer, .dlog2,
            "16/247 tap is D-Log2 paper black + live ceiling; Rec.709 WAVE is the screenshot shelf")
        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        XCTAssertEqual(
            WaveformAxis.traceY(16, transfer: bus.bundle.transfer, plot),
            WaveformAxis.scaleLineY(0, plot),
            accuracy: 0.1)
        XCTAssertEqual(
            WaveformAxis.traceY(247, transfer: bus.bundle.transfer, plot),
            WaveformAxis.scaleLineY(100, plot),
            accuracy: 0.1)
    }

    // MARK: - Throttle constants

    func testScopeTapIntervalTracksTypicalSoftAPRate() {
        XCTAssertEqual(PocketScopeSampler.baseMinInterval, 1.0 / 25.0, accuracy: 1e-9)
        XCTAssertEqual(PocketScopeSampler.denseMinInterval, 1.0 / 10.0, accuracy: 1e-9)
        XCTAssertEqual(
            PocketScopeSampler.minInterval(activeScopeCount: 1, thermalState: .nominal),
            PocketScopeSampler.baseMinInterval)
        XCTAssertEqual(
            PocketScopeSampler.minInterval(activeScopeCount: 2, thermalState: .nominal),
            PocketScopeSampler.baseMinInterval)
        XCTAssertEqual(
            PocketScopeSampler.minInterval(activeScopeCount: 3, thermalState: .nominal),
            PocketScopeSampler.denseMinInterval, "more than two scopes go slower, not faster")
        // Thermal tiers shed the interval, never the sampling density.
        XCTAssertEqual(PocketScopeSampler.thermalMultiplier(.nominal), 1)
        XCTAssertEqual(PocketScopeSampler.thermalMultiplier(.fair), 1)
        XCTAssertEqual(PocketScopeSampler.thermalMultiplier(.serious), 3)
        XCTAssertEqual(PocketScopeSampler.thermalMultiplier(.critical), 5)
        XCTAssertEqual(
            PocketScopeSampler.minInterval(activeScopeCount: 1, thermalState: .serious),
            3.0 / 25.0, accuracy: 1e-9)
        XCTAssertEqual(PocketScopeSampler.maxWidth, 200)
        XCTAssertEqual(PocketScopeSampler.pointStride, 2)
        // 15 Hz next to a 25 fps well is a 2-frame hold. WAVE-only must
        // tap every typical SoftAP picture; dense 3+ stays the 10 Hz back-off.
        XCTAssertEqual(
            scheduledScopeTaps(frames: 25, fps: 25, interval: PocketScopeSampler.baseMinInterval),
            25)
        // 10 Hz on a 40 ms picture clock lands every third frame (deadline skip).
        XCTAssertEqual(
            scheduledScopeTaps(frames: 25, fps: 25, interval: PocketScopeSampler.denseMinInterval),
            9)
    }

    private func scheduledScopeTaps(frames: Int, fps: Double, interval: CFAbsoluteTime) -> Int {
        var next = 0.0
        var taps = 0
        let dt = 1.0 / fps
        for i in 0..<frames {
            let now = Double(i) * dt
            if now + 1e-12 >= next {
                next = now + interval
                taps += 1
            }
        }
        return taps
    }

    // MARK: - Sampler contracts (app layer)

    func testVertexMathMatchesLevelTable() {
        // WAVE / PARADE / HISTO ride ``WaveformAxis`` (0 / paper-IRE / 100).
        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        for transfer in MonitorTransfer.allCases {
            let table = WaveformAxis.levelTable(for: transfer)
            let bytes: [UInt8] = [0, 16, 78, 128, 200, 255]
            let points = bytes.map {
                ScopePoint(xRatio: 0.5, yRatio: 0.5, red: $0, green: $0, blue: $0, luma: $0)
            }
            let capacity = ScopeTraceMetal.maxVertexCount(
                points: points.count, mode: .waveform(.rgb))
            var vertices = [ScopeTraceMetal.Vertex](
                repeating: ScopeTraceMetal.Vertex(position: .zero, size: 0, color: .zero),
                count: capacity)
            let written = vertices.withUnsafeMutableBufferPointer { out in
                ScopeTraceMetal.fillVertices(
                    out, from: 0, points: points, mode: .waveform(.rgb), rect: plot,
                    opacity: 1, levelTable: table)
            }
            XCTAssertEqual(
                written, points.count * 3, "\(transfer) rgb writes one vertex per channel")
            for (index, point) in points.enumerated() {
                let expected = WaveformAxis.vertexPositionY(
                    ire: Double(table[Int(point.luma)]), pointSize: 1, rect: plot)
                for channel in 0..<3 {
                    XCTAssertEqual(
                        Double(vertices[index * 3 + channel].position.y), Double(expected),
                        accuracy: 0.01,
                        "\(transfer) byte \(point.luma) must ride the WAVE 0/100 axis")
                }
            }
            for byte in bytes {
                XCTAssertEqual(
                    WaveformAxis.traceY(byte, transfer: transfer, plot),
                    WaveformAxis.plotY(Double(table[Int(byte)]), plot),
                    accuracy: 0.01)
            }
        }
    }

    func testVectorscopeCubeWalkOnlyRunsWhenVectorscopeIsOn() {
        let code: UInt8 = 78
        var bytes = [UInt8]()
        for _ in 0..<16 {
            bytes.append(contentsOf: [code, code, code, 255])
        }
        let wave = PocketScopeSampler.sample(
            bytes: bytes, width: 16, height: 1, bytesPerRow: 64,
            transfer: .dlog2, includePoints: true, includeVectorPoints: false,
            look: BuiltInLook.mono.cube(), previous: .empty)
        XCTAssertFalse(wave.samples.points.isEmpty)
        XCTAssertTrue(wave.vectorscopePoints.isEmpty, "WAVE/PARADE must not walk the monitor cube")
        XCTAssertEqual(wave.revision, 1)
        let vector = PocketScopeSampler.sample(
            bytes: bytes, width: 16, height: 1, bytesPerRow: 64,
            transfer: .dlog2, includePoints: false, includeVectorPoints: true,
            look: nil, previous: wave)
        XCTAssertTrue(
            vector.samples.points.isEmpty, "points stay out of the bundle when WAVE is off")
        XCTAssertFalse(vector.vectorscopePoints.isEmpty)
        XCTAssertEqual(vector.revision, 2)
        XCTAssertEqual(vector.trailSamples, wave.samples, "previous samples ride as the trail")
    }

    func testScopesIgnoreTheLUTLook() {
        // WAVE / HISTO meter native camera codes regardless of the armed look.
        let code: UInt8 = 78  // legal-scaled D-Log2 grey after the tap
        var bytes = [UInt8]()
        for _ in 0..<16 {
            bytes.append(contentsOf: [code, code, code, 255])
        }
        let plain = PocketScopeSampler.sample(
            bytes: bytes, width: 16, height: 1, bytesPerRow: 64,
            transfer: .dlog2, includePoints: true, look: nil, previous: .empty)
        let looked = PocketScopeSampler.sample(
            bytes: bytes, width: 16, height: 1, bytesPerRow: 64,
            transfer: .dlog2, includePoints: true, look: BuiltInLook.mono.cube(),
            previous: .empty)
        XCTAssertEqual(plain.samples, looked.samples, "the look must not leak into WAVE/HISTO")
        let peak =
            plain.samples.histogramLuma.enumerated()
            .max(by: { $0.element < $1.element })?.offset ?? 0
        XCTAssertEqual(peak, 78, "grey stays the native curve byte")
        XCTAssertEqual(plain.samples.points.first?.luma, 78)
        XCTAssertEqual(plain.samples.points.first?.red, 78)
    }

    func testDLog2LegalBlackLandsOnTheZeroLine() {
        // Legal-scaled black (wire Y10 119 → tap byte 16) → native bin 16,
        // WAVE IRE 0 → display bucket 0.
        let code: UInt8 = 16
        var bytes = [UInt8]()
        for _ in 0..<16 {
            bytes.append(contentsOf: [code, code, code, 255])
        }
        let bundle = PocketScopeSampler.sample(
            bytes: bytes, width: 16, height: 1, bytesPerRow: 64,
            transfer: .dlog2, includePoints: true, look: nil, previous: .empty)
        XCTAssertEqual(
            bundle.samples.histogramLuma[16], bundle.samples.points.count,
            "every sampled pixel lands in native bin 16")
        XCTAssertGreaterThan(bundle.samples.histogramLuma[16], 0)
        let displayPeak =
            bundle.histogramDisplay.luma.enumerated()
            .max(by: { $0.element < $1.element })?.offset ?? 0
        XCTAssertEqual(displayPeak, 0, accuracy: 2, "black anchor sits on the WAVE 0 bucket")
        let plot = WaveformAxis.plotRect(in: CGSize(width: 250, height: 153))
        XCTAssertEqual(
            WaveformAxis.traceY(16, transfer: .dlog2, plot),
            WaveformAxis.scaleLineY(0, plot),
            accuracy: 0.5)
        let histoPlot = HistogramAssist.plotRect(in: ScopePanelSize.histogram)
        XCTAssertEqual(
            HistogramAssist.plotX(Double(displayPeak) / 255 * 100, in: histoPlot),
            HistogramAssist.ireX(0, in: histoPlot),
            accuracy: 1.5,
            "display-bucket 0 sits on the HISTO 0 line")
        XCTAssertTrue(bundle.traffic.anyCrush)
        XCTAssertFalse(bundle.traffic.anyClip)
    }

    // MARK: - GPU effects

    func testPeakingPaintsRedOnEdges() {
        let buffer = ScopeTestBuffers.makeEdgeBuffer(width: 160, height: 90)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = LiveImageEffects()
        fx.peaking = true
        fx.peakingColor = .red
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        let context = CIContext(options: [.cacheIntermediates: false])
        let red = Self.maxRedDelta(output: output, source: source, context: context)
        XCTAssertGreaterThan(red, 0.15, "PEAK must paint red on a hard edge")
    }

    func testDLog2MidGreyDoesNotZebraHighlight() {
        // Legal-scaled grey byte 78 ≈ monitor 25.9% — far from the 100 highlight
        // threshold and outside the default 55 ± 5 midtone band.
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 78)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = LiveImageEffects()
        fx.zebra = true
        fx.zebraHighlight = true
        fx.zebraMidtone = false
        fx.colorMode = .dLog2
        fx.zebraHighlightIRE = LiveZebra.highlightIRE
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        let context = CIContext(options: [.cacheIntermediates: false])
        let delta = Self.maxChannelDelta(output: output, source: source, context: context)
        XCTAssertLessThan(delta, 0.04, "D-Log2 18% grey (monitor ≈ 26%) must not zebra-clip")
    }

    func testDLog2MidGreyDoesNotZebraDefaultMidtone() {
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 78)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = LiveImageEffects()
        fx.zebra = true
        fx.zebraHighlight = false
        fx.zebraMidtone = true
        fx.colorMode = .dLog2
        fx.zebraMidtoneIRE = LiveZebra.midtoneIRE
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        let context = CIContext(options: [.cacheIntermediates: false])
        let delta = Self.maxChannelDelta(output: output, source: source, context: context)
        XCTAssertLessThan(
            delta, 0.04, "grey ≈ 26% is outside the default 55 ± 5 midtone stripe")
    }

    func testDLog2PeakZebrasHighlight() {
        let buffer = ScopeTestBuffers.makeFlatBuffer(code: 255)
        let source = CIImage(cvPixelBuffer: buffer)
        var fx = LiveImageEffects()
        fx.zebra = true
        fx.zebraHighlight = true
        fx.zebraMidtone = false
        fx.colorMode = .dLog2
        fx.zebraHighlightIRE = LiveZebra.highlightIRE
        // White stripes on a white frame are invisible to the delta probe.
        fx.zebraHighlightColor = .red
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        let context = CIContext(options: [.cacheIntermediates: false])
        let delta = Self.maxChannelDelta(output: output, source: source, context: context)
        XCTAssertGreaterThan(delta, 0.08, "D-Log2 curve top (monitor 100) must zebra")
    }

    func testDLog2FalseColorIREPaintsGreyGreenNotClip() {
        let cube = PocketFalseColorMap.cube(scale: .ire, transfer: .dlog2)
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let mapped = cube.map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(
            mapped.green, mapped.red,
            "D-Log2 18% grey is ~42 monitor IRE (41–48 green) on false colour, not the clip band")
        XCTAssertGreaterThan(mapped.green, mapped.blue)
    }

    // MARK: - Real-clip end-to-end (author's machine only)

    func testDLog2ClipPublishesScopeDistribution() async throws {
        let env = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"]
        try XCTSkipIf(
            env == nil || env?.isEmpty == true,
            "set OPV_SIM_FEED_CLIP to a local D-Log2 clip to run this test")
        let url = URL(fileURLWithPath: env!)
        guard let buffer = Self.pullClipFrame(url: url) else {
            XCTFail("AVAssetReader must yield a frame from the D-Log2 clip")
            return
        }
        XCTAssertGreaterThan(CVPixelBufferGetWidth(buffer), 16)
        XCTAssertGreaterThan(CVPixelBufferGetHeight(buffer), 16)
        guard let packed = PocketScopeSampler.copyBGRA(buffer, maxWidth: 160) else {
            XCTFail("clip frame tap must succeed")
            return
        }
        let sampled = PocketScopeSampler.sample(
            bytes: packed.bytes, width: packed.width, height: packed.height,
            bytesPerRow: packed.bytesPerRow, transfer: .dlog2,
            includePoints: true, look: nil, previous: .empty)
        let occupied = sampled.samples.histogramLuma.filter { $0 > 0 }.count
        XCTAssertGreaterThan(occupied, 3, "D-Log2 clip must not be a flat/empty spike")

        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .dlog2 })
        decoder.effects = fx
        decoder.handleDecodedFrame(buffer, effects: fx, transfer: .dlog2)
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if bus.publishedScopes >= 1, !bus.bundle.samples.points.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThanOrEqual(bus.publishedScopes, 1)
        XCTAssertFalse(bus.bundle.samples.points.isEmpty)
        XCTAssertEqual(bus.transfer, .dlog2)
        XCTAssertEqual(bus.bundle.transfer, .dlog2)
    }

    // MARK: - Pipeline coverage across live-like formats

    func testHandleDecodedFramePublishesScopesFrom10BitOrIOSurface() async throws {
        let buffer = try XCTUnwrap(
            Self.makeLiveLikeBuffer(width: 64, height: 48),
            "need a 10-bit / IOSurface / 420v buffer")
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .dlog })
        decoder.effects = fx

        decoder.handleDecodedFrame(buffer, effects: fx, transfer: .dlog)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if bus.publishedScopes >= 1, !bus.bundle.samples.points.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThanOrEqual(bus.publishedScopes, 1)
        XCTAssertFalse(bus.bundle.samples.points.isEmpty)
        let occupied = bus.bundle.samples.histogramLuma.filter { $0 > 0 }.count
        XCTAssertGreaterThan(occupied, 1, "live-like 10-bit/IOSurface tap must occupy bins")
        XCTAssertGreaterThan(bus.bundle.samples.points.map(\.luma).max() ?? 0, 0)
    }

    func testHandleDecodedFramePublishesScopesFrom420v() async {
        let bus = LiveFrameSampleBus()
        let decoder = HevcDecoder()
        var fx = LiveImageEffects()
        fx.histogram = true
        fx.waveform = true
        decoder.attach(sampleBus: bus, effects: { fx }, transfer: { .dlog2 })
        decoder.effects = fx

        decoder.handleDecodedFrame(
            ScopeTestBuffers.make420v(width: 64, height: 48, leftY: 48, rightY: 200),
            effects: fx, transfer: .dlog2)

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if bus.publishedScopes >= 1, !bus.bundle.samples.points.isEmpty { break }
            try? await Task.sleep(for: .milliseconds(20))
        }

        XCTAssertGreaterThanOrEqual(
            bus.publishedScopes, 1, "420v live/HEVC frames must publish a scope bundle")
        XCTAssertFalse(
            bus.bundle.samples.points.isEmpty, "WAVE needs scatter points from the 420v tap")
        let occupied = bus.bundle.samples.histogramLuma.filter { $0 > 0 }.count
        XCTAssertGreaterThan(occupied, 1, "edge frame must not collapse to a single bin")
    }

    // MARK: - Bake / LUT

    func testBakeSizeKeepsSourceAspectAndClampsToDrawable() {
        let fourK = FeedFrameBaker.bakeSize(
            source: CGSize(width: 3840, height: 2160),
            drawable: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(fourK.width, 1920, accuracy: 1)
        XCTAssertEqual(fourK.height, 1080, accuracy: 1)

        let smaller = FeedFrameBaker.bakeSize(
            source: CGSize(width: 1280, height: 720),
            drawable: CGSize(width: 1920, height: 1080))
        XCTAssertEqual(smaller.width, 1280, accuracy: 1)
        XCTAssertEqual(smaller.height, 720, accuracy: 1)
    }

    func testLUTRunsOnLiveFrame() {
        let buffer = ScopeTestBuffers.makeEdgeBuffer()
        let source = CIImage(cvPixelBuffer: buffer)
        let cube = BuiltInLook.mono.cube()
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let output = LiveMonitorCompositor.apply(to: source, effects: fx)
        XCTAssertEqual(output.extent, source.extent)
        XCTAssertTrue(fx.needsGPUFeed)
    }

    // MARK: - Helpers

    private static func pullClipFrame(url: URL) -> CVPixelBuffer? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
            let reader = try? AVAssetReader(asset: asset)
        else { return nil }
        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ])
        output.alwaysCopiesSampleData = true
        reader.add(output)
        guard reader.startReading() else { return nil }
        for _ in 0..<8 {
            if let sample = output.copyNextSampleBuffer(),
                let buffer = CMSampleBufferGetImageBuffer(sample)
            {
                return buffer
            }
        }
        return nil
    }

    /// Prefers legal-scaled 10-bit x420 (black → grey edge), falls back to
    /// IOSurface BGRA, then 8-bit 420v.
    private static func makeLiveLikeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        func usable(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
            PocketScopeSampler.copyBGRA(buffer, maxWidth: 200) == nil ? nil : buffer
        }
        if let ten = ScopeTestBuffers.makeX420(
            width: width, height: height,
            luma10: { x, _ in
                x < width / 2 ? ScopeTestBuffers.dlog2Black10 : ScopeTestBuffers.dlog2Grey10
            })
        {
            if let ten = usable(ten) { return ten }
        }
        let metal = ScopeTestBuffers.makeIOSurfaceBGRA(
            width: width, height: height, left: 40, right: 210)
        if metal.filled, let filled = usable(metal.buffer) { return filled }
        return usable(ScopeTestBuffers.make420v(width: width, height: height, leftY: 48, rightY: 200))
    }

    private static func maxChannelDelta(output: CIImage, source: CIImage, context: CIContext)
        -> Float
    {
        let w = 80
        let h = 40
        func bytes(_ image: CIImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let scaled = image.transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(w) / max(image.extent.width, 1),
                    y: CGFloat(h) / max(image.extent.height, 1)))
            context.render(
                scaled, toBitmap: &data, rowBytes: w * 4,
                bounds: CGRect(x: 0, y: 0, width: w, height: h),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return data
        }
        let a = bytes(output)
        let b = bytes(source)
        var best: Float = 0
        for i in 0..<min(a.count, b.count) {
            best = max(best, abs(Float(a[i]) - Float(b[i])) / 255)
        }
        return best
    }

    private static func maxRedDelta(output: CIImage, source: CIImage, context: CIContext) -> Float {
        let w = 80
        let h = 40
        func bytes(_ image: CIImage) -> [UInt8] {
            var data = [UInt8](repeating: 0, count: w * h * 4)
            let scaled = image.transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(w) / max(image.extent.width, 1),
                    y: CGFloat(h) / max(image.extent.height, 1)))
            context.render(
                scaled, toBitmap: &data, rowBytes: w * 4,
                bounds: CGRect(x: 0, y: 0, width: w, height: h),
                format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
            return data
        }
        let a = bytes(output)
        let b = bytes(source)
        var best: Float = 0
        for i in stride(from: 0, to: a.count, by: 4) {
            let dr = Float(a[i]) - Float(b[i])
            best = max(best, dr / 255)
        }
        return best
    }
}
