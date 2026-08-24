import CoreImage
import CoreVideo
import Foundation
import Observation
import OpenPocketViewCore
import os

extension MonitorTransfer {
    /// Wire ColorMode that selected this transfer (`3F` / `3C` / `17` / `41`).
    var colorMode: ColorMode {
        switch self {
        case .rec709: .normal
        case .hdr: .hdr
        case .dlog: .dLog
        case .dlog2: .dLog2
        }
    }

    /// `CameraStatus.monitorTransfer`, else ColorMode, else the last known
    /// curve. Rec.709 only when nothing has been seen yet — falling back on a
    /// missing `@2` is the WAVE black shelf (D-Log2 paper black at ~8 IRE).
    static func resolved(
        _ status: MonitorTransfer?, colorMode: ColorMode?, previous: MonitorTransfer? = nil
    ) -> MonitorTransfer {
        status ?? colorMode.map(MonitorTransfer.init) ?? previous ?? .rec709
    }
}

/// OpenZCine `ScopePoint` — one sampled pixel for WAVE / PARADE / VECTOR.
/// Channel bytes are **native curve codes** from the tap (`byte/255` = encoded
/// curve fraction). Plot placement happens at draw time via
/// `ScopeDisplayScale.levelTable` — never here.
struct ScopePoint: Equatable, Sendable {
    var xRatio: Double
    var yRatio: Double
    var red: UInt8
    var green: UInt8
    var blue: UInt8
    var luma: UInt8
}

/// OpenZCine `ScopeSamples` — one shared tap product for every scope surface.
/// Histograms are 256-bin **native code** counts (display remap is downstream).
struct ScopeSamples: Equatable, Sendable {
    var histogramLuma: [Int]
    var histogramRed: [Int]
    var histogramGreen: [Int]
    var histogramBlue: [Int]
    var points: [ScopePoint]

    static let empty = ScopeSamples(
        histogramLuma: Array(repeating: 0, count: 256),
        histogramRed: Array(repeating: 0, count: 256),
        histogramGreen: Array(repeating: 0, count: 256),
        histogramBlue: Array(repeating: 0, count: 256),
        points: [])
}

/// Ready-to-draw histogram curves on the WAVE IRE axis: remapped so paper
/// black is bucket 0 and live-tap clip is bucket 255, temporally blended
/// 0.65/0.35, box-blurred (r = 2). The HISTO SwiftUI body only strokes these.
struct ScopeHistogramDisplay: Equatable, Sendable {
    var luma: [Float]
    var red: [Float]
    var green: [Float]
    var blue: [Float]

    static let empty = ScopeHistogramDisplay(
        luma: Array(repeating: 0, count: 256),
        red: Array(repeating: 0, count: 256),
        green: Array(repeating: 0, count: 256),
        blue: Array(repeating: 0, count: 256))
}

/// OpenZCine `ScopeAssistBundle` — published once per throttle tick so SwiftUI/Metal
/// invalidates one value instead of re-reading a recycled `CVPixelBuffer`.
struct ScopeAssistBundle: Equatable, Sendable {
    /// Cheap identity for redraw gating. Compare this, not 5,600 points, on main.
    var revision: UInt64 = 0
    var samples = ScopeSamples.empty
    /// Monitor-domain points for VECTOR (through the operator LUT or the official
    /// DJI display cube — log chroma collapses without it). Empty when hidden.
    var vectorscopePoints: [ScopePoint] = []
    var trailSamples = ScopeSamples.empty
    var trailVectorscopePoints: [ScopePoint] = []
    var traffic = ScopeTrafficLightsReading.none
    var histogramDisplay = ScopeHistogramDisplay.empty
    var transfer: MonitorTransfer = .rec709

    static let empty = ScopeAssistBundle()
}

/// OpenZCine `ScopeAssistSampling` + `ScopeSampler`, Pocket color science.
/// WAVE / PARADE / HISTO / LIGHTS meter the clean source in ONE pass.
/// VECTOR derives monitor-domain points from the same walk's output.
enum PocketScopeSampler {
    /// Known-good OpenZCine width. 128 + extra pack/vImage was slower on device.
    static let maxWidth = 200
    static let pointStride = 2
    /// Typical SoftAP is 25 fps. 1–2 scopes track that picture; a 50 Hz
    /// proxy still skips. Deadline cannot catch up.
    static let baseMinInterval: CFAbsoluteTime = 1.0 / 25.0
    /// More scopes share one tap — go slower, not faster.
    static let denseMinInterval: CFAbsoluteTime = 1.0 / 10.0
    static let denseAssistThreshold = 2

    static func minInterval(
        activeScopeCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> CFAbsoluteTime {
        let base =
            activeScopeCount > denseAssistThreshold ? denseMinInterval : baseMinInterval
        return base * thermalMultiplier(thermalState)
    }

    /// OpenZCine sheds the *interval*, never the sampling density.
    static func thermalMultiplier(_ state: ProcessInfo.ThermalState) -> Double {
        switch state {
        case .serious: 3
        case .critical: 5
        default: 1
        }
    }

    static func copyBGRA(_ buffer: CVPixelBuffer, maxWidth: Int) -> (
        bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
    )? {
        LiveFrameTap.copyBGRA8(buffer, maxWidth: maxWidth)
    }

    /// The one walk. 200-wide tap × stride 2 ≈ 5,600 pixels per tick.
    static func sample(
        bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int,
        transfer: MonitorTransfer, includePoints: Bool, includeVectorPoints: Bool = false,
        look: CubeLUT?,
        trafficThreshold: Double = ScopeTrafficLights.defaultThreshold,
        previous: ScopeAssistBundle
    ) -> ScopeAssistBundle {
        var histY = [Int](repeating: 0, count: 256)
        var histR = [Int](repeating: 0, count: 256)
        var histG = [Int](repeating: 0, count: 256)
        var histB = [Int](repeating: 0, count: 256)
        var points = [ScopePoint]()
        let needsPoints = includePoints || includeVectorPoints
        if needsPoints {
            let columns = (width + pointStride - 1) / pointStride
            let rows = (height + pointStride - 1) / pointStride
            points.reserveCapacity(max(0, columns * rows))
        }
        let widthDivisor = Double(max(width, 1))
        let heightDivisor = Double(max(height, 1))
        let lumaW = LiveColorScience.lumaWeights(transfer)
        var y = 0
        while y < height {
            let rowStart = y * bytesPerRow
            var x = 0
            while x < width {
                let i = rowStart + x * 4
                guard i + 2 < bytes.count else { break }
                let b = bytes[i]
                let g = bytes[i + 1]
                let r = bytes[i + 2]
                // Rounded, not floored — floor pushed pure white off the top bin.
                let lumaValue =
                    lumaW.red * Double(r) + lumaW.green * Double(g) + lumaW.blue * Double(b)
                let luma = UInt8(min(255, max(0, lumaValue.rounded())))
                histY[Int(luma)] += 1
                histR[Int(r)] += 1
                histG[Int(g)] += 1
                histB[Int(b)] += 1
                if needsPoints {
                    points.append(
                        ScopePoint(
                            xRatio: Double(x) / widthDivisor,
                            yRatio: Double(y) / heightDivisor,
                            red: r, green: g, blue: b, luma: luma))
                }
                x += pointStride
            }
            y += pointStride
        }
        let samples = ScopeSamples(
            histogramLuma: histY, histogramRed: histR, histogramGreen: histG,
            histogramBlue: histB, points: includePoints ? points : [])
        let vectorPoints =
            includeVectorPoints ? monitorPoints(points, look: look) : []
        return ScopeAssistBundle(
            revision: previous.revision &+ 1,
            samples: samples,
            vectorscopePoints: vectorPoints,
            trailSamples: previous.samples,
            trailVectorscopePoints: previous.vectorscopePoints,
            traffic: ScopeTrafficLights.reading(
                red: histR, green: histG, blue: histB, luma: histY,
                transfer: transfer, threshold: trafficThreshold,
                previous: previous.traffic),
            histogramDisplay: histogramDisplay(
                samples: samples, previous: previous.histogramDisplay, transfer: transfer),
            transfer: transfer)
    }

    /// VECTOR input: sampled points through the display look (operator LUT if
    /// armed, else the official DJI Rec.709 cube for log, else the codes as-is).
    /// Trilinear `CubeLUT.map` per point is the benchmark-accepted cost — no
    /// transcendental math per pixel anywhere in the analysis path.
    static func monitorPoints(_ points: [ScopePoint], look: CubeLUT?) -> [ScopePoint] {
        guard let look else { return points }
        return points.map { point in
            let mapped = look.map(
                red: Float(point.red) / 255,
                green: Float(point.green) / 255,
                blue: Float(point.blue) / 255)
            let red = Double(mapped.red)
            let green = Double(mapped.green)
            let blue = Double(mapped.blue)
            let luma = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            return ScopePoint(
                xRatio: point.xRatio,
                yRatio: point.yRatio,
                red: displayByte(red),
                green: displayByte(green),
                blue: displayByte(blue),
                luma: displayByte(luma))
        }
    }

    /// Display cube for VECTOR when no operator LUT is armed.
    static func monitorCube(for transfer: MonitorTransfer, effects: LiveImageEffects) -> CubeLUT? {
        if let armed = ScopeMonitorLook.cube(from: effects) { return armed }
        switch transfer {
        case .dlog: return BundledOfficialDJILUT.cube(.pocketDLog)
        case .dlog2: return BundledOfficialDJILUT.cube(.pocketDLog2)
        case .rec709, .hdr: return nil
        }
    }

    private static func displayByte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, (value * 255).rounded())))
    }

    // MARK: - Histogram display pipeline (off-main, once per tick)

    static func histogramDisplay(
        samples: ScopeSamples, previous: ScopeHistogramDisplay, transfer: MonitorTransfer
    ) -> ScopeHistogramDisplay {
        ScopeHistogramDisplay(
            luma: displayChannel(
                samples.histogramLuma, previous: previous.luma, transfer: transfer),
            red: displayChannel(samples.histogramRed, previous: previous.red, transfer: transfer),
            green: displayChannel(
                samples.histogramGreen, previous: previous.green, transfer: transfer),
            blue: displayChannel(samples.histogramBlue, previous: previous.blue, transfer: transfer)
        )
    }

    static func displayChannel(
        _ native: [Int], previous: [Float], transfer: MonitorTransfer
    ) -> [Float] {
        let remapped = WaveformAxis.remapHistogram(native, transfer: transfer)
        var blended = [Float](repeating: 0, count: 256)
        let hasPrevious = previous.count == 256
        for i in 0..<256 {
            let current = Float(remapped[i])
            blended[i] = hasPrevious ? 0.65 * current + 0.35 * previous[i] : current
        }
        return boxBlur(blended, radius: 2)
    }

    static func boxBlur(_ values: [Float], radius: Int) -> [Float] {
        guard radius > 0, values.count > 1 else { return values }
        var out = [Float](repeating: 0, count: values.count)
        for i in 0..<values.count {
            let lo = max(0, i - radius)
            let hi = min(values.count - 1, i + radius)
            var sum: Float = 0
            for j in lo...hi { sum += values[j] }
            out[i] = sum / Float(hi - lo + 1)
        }
        return out
    }
}

/// Operator LUT (armed in effects) as a scope-side cube.
enum ScopeMonitorLook {
    static func cube(from effects: LiveImageEffects) -> CubeLUT? {
        let n = effects.lutDimension
        let expected = n * n * n * 4 * MemoryLayout<Float>.size
        guard n >= 2, effects.lutRGBA.count == expected else { return nil }
        let floats = effects.lutRGBA.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var rgb = [Float]()
        rgb.reserveCapacity(n * n * n * 3)
        var index = 0
        while index + 2 < floats.count {
            rgb.append(floats[index])
            rgb.append(floats[index + 1])
            rgb.append(floats[index + 2])
            index += 4
        }
        return CubeLUT(size: n, rgb: rgb)
    }
}

/// Published live-frame sample. GPU assists render the full decoded frame; scopes read a
/// throttled bundle of the **source** (OpenZCine rule — never the grade).
@MainActor
@Observable
final class LiveFrameSampleBus {
    /// OpenZCine `scopeAssist` — Metal/SwiftUI observe this value, not a recycled pixel buffer.
    var bundle = ScopeAssistBundle.empty
    /// Playback composition tap. Scope overlays prefer this while a clip is open.
    var playbackBundle: ScopeAssistBundle?
    @ObservationIgnored var sourcePixelBuffer: CVPixelBuffer?
    var transfer: MonitorTransfer = .rec709
    var colorMode: ColorMode?
    /// Bumps when a new scope bundle lands (≤25 Hz). Present is not gated on this.
    private(set) var generation = 0
    /// Incremented for every decoded pixel buffer that enters the assist pipeline.
    /// Tests use this to prove the callback ran without hardware HEVC.
    @ObservationIgnored private(set) var decodedFrames = 0
    private(set) var publishedScopes = 0

    func noteDecodedFrame() {
        decodedFrames += 1
    }

    func publish(
        source: CVPixelBuffer,
        transfer: MonitorTransfer,
        colorMode: ColorMode,
        bundle: ScopeAssistBundle?
    ) {
        sourcePixelBuffer = source
        if self.transfer != transfer { self.transfer = transfer }
        if self.colorMode != colorMode { self.colorMode = colorMode }
        if let bundle {
            self.bundle = bundle
            publishedScopes += 1
            generation += 1
        }
    }

    var displayBundle: ScopeAssistBundle { playbackBundle ?? bundle }

    func reset() {
        playbackBundle = nil
        bundle = .empty
        sourcePixelBuffer = nil
        transfer = .rec709
        colorMode = nil
        generation = 0
        decodedFrames = 0
        publishedScopes = 0
    }
}

/// Off-main assist work. Latest-frame-wins so a slow peaking render cannot stall UDP ingest.
/// Pixel buffers are held as Swift properties — ARC retains/releases them. Do not call
/// `CVPixelBufferRetain` / `CVPixelBufferRelease` (unavailable under Swift ARC).
final class LiveAssistEngine: @unchecked Sendable {
    struct Result {
        var output: CIImage
        var identity: CIImage
        var source: CVPixelBuffer
        var needsGPU: Bool
        /// Transparent zebra / peaking paint. The identity layer stays the picture.
        var overlayOnly: Bool
        /// LUT cube product. False for identity fallbacks (NSNull of HEVC is black).
        var unmanagedBake: Bool
        var bundle: ScopeAssistBundle?
        var transfer: MonitorTransfer
        var colorMode: ColorMode
        /// False when this result is a late scope bundle. Present already happened.
        var shouldPresent: Bool
        /// Presentation time for skip-duplicate. `0` means unknown — never skip.
        var timeNs: Int64
    }

    private let queue = DispatchQueue(label: "opv.live-assist", qos: .userInitiated)
    private let log = Logger(subsystem: "com.opencapture.openpocketcine", category: "scope-tap")
    private var pendingBuffer: CVPixelBuffer?
    private var pendingEffects = LiveImageEffects()
    private var pendingTransfer = MonitorTransfer.rec709
    private var pendingTimeNs: Int64 = 0
    private var pendingCompletion: (@Sendable (Result) -> Void)?
    private var busy = false
    private var nextScopeAt: CFAbsoluteTime = 0
    /// Rolling tap maximum for the 10 s `scope max:` journal cadence.
    private var ceilingLogMax: UInt8 = 0
    private var nextCeilingLogAt: CFAbsoluteTime = 0
    private var previousBundle = ScopeAssistBundle.empty
    private var loggedTap = false
    private var tapWindowStart: CFAbsoluteTime = 0
    private var tapsInWindow = 0
    /// Shared tap: 25 Hz, 10 Hz with three or more scopes, shed further by
    /// thermal tier (×3 serious, ×5 critical). Deadline cannot catch up.

    init() {}

    func updatePolicy(effects: LiveImageEffects, transfer: MonitorTransfer) {
        queue.async { [self] in
            var fx = effects
            fx.colorMode = transfer.colorMode
            pendingEffects = fx
            pendingTransfer = transfer
            if fx.falseColor {
                PocketFalseColorMap.warm(
                    scale: fx.falseColorScale, mode: fx.colorMode,
                    hasLUT: fx.lutDimension >= 2)
            }
        }
    }

    func submit(
        _ buffer: CVPixelBuffer,
        effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil,
        timeNs: Int64 = 0,
        completion: @escaping @Sendable (Result) -> Void
    ) {
        queue.async { [self] in
            pendingBuffer = FeedWorkingRaster.prepared(buffer)
            if let effects { pendingEffects = effects }
            if let transfer { pendingTransfer = transfer }
            pendingTimeNs = timeNs
            pendingCompletion = completion
            drain()
        }
    }

    func reset() {
        queue.async { [self] in
            pendingBuffer = nil
            pendingTimeNs = 0
            pendingCompletion = nil
            busy = false
            nextScopeAt = 0
            previousBundle = .empty
            loggedTap = false
            tapWindowStart = 0
            tapsInWindow = 0
            ceilingLogMax = 0
            nextCeilingLogAt = 0
            ScopeExposureCeiling.reset()
        }
    }

    private func logTapOnce(
        buffer: CVPixelBuffer,
        packed: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)?,
        points: Int
    ) {
        guard !loggedTap else { return }
        loggedTap = true
        let fourCC = LiveFrameTap.fourCC(buffer)
        let srcW = CVPixelBufferGetWidth(buffer)
        let srcH = CVPixelBufferGetHeight(buffer)
        let planes = CVPixelBufferGetPlaneCount(buffer)
        let ioSurface = LiveFrameTap.isIOSurfaceBacked(buffer)
        if let packed {
            let maxLuma = LiveFrameTap.maxRGB(packed.bytes)
            log.info(
                "scope tap \(fourCC, privacy: .public) \(srcW)x\(srcH) planes=\(planes) ioSurface=\(ioSurface) -> \(packed.width)x\(packed.height) max=\(maxLuma) points=\(points)"
            )
        } else {
            log.error(
                "scope tap FAILED \(fourCC, privacy: .public) \(srcW)x\(srcH) planes=\(planes) ioSurface=\(ioSurface)"
            )
        }
    }

    private func drain() {
        if busy { return }
        guard let buffer = pendingBuffer, let completion = pendingCompletion else { return }
        pendingBuffer = nil
        var fx = pendingEffects
        var transfer = pendingTransfer
        let timeNs = pendingTimeNs
        fx.colorMode = transfer.colorMode
        busy = true

        // Copy CPU planes before Core Image attaches. WAVE/HISTO read the source
        // buffer; wrapping 10-bit x420 / IOSurface in CIImage first can unmap
        // those planes so the later tap returns nil and scopes stay empty.
        // The histogram walk still runs after present so it cannot hold 25 fps.
        var packed: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int)?
        if fx.needsScopes {
            let now = CFAbsoluteTimeGetCurrent()
            let interval = PocketScopeSampler.minInterval(activeScopeCount: fx.activeScopeCount)
            if now >= nextScopeAt {
                nextScopeAt = now + interval
                packed = PocketScopeSampler.copyBGRA(
                    buffer, maxWidth: PocketScopeSampler.maxWidth)
                if packed == nil {
                    logTapOnce(buffer: buffer, packed: nil, points: 0)
                }
            }
        }

        // Identity keeps Rec.709 / HLG attachments. NSNull is cube-only —
        // AVSampleBufferDisplayLayer and color-managed CI both go black without them.
        // Scopes-only present uses the pixel buffer, not this image, so skip the wrap.
        let identity: CIImage
        let output: CIImage
        let overlayOnly: Bool
        let unmanagedBake: Bool
        if fx.needsGPUFeed {
            identity = CIImage(cvPixelBuffer: buffer)
            let cameraCodes = CIImage(
                cvPixelBuffer: buffer, options: LiveMonitorWorkingSpace.imageOptions)
            // LUT / false colour cubes read encoded camera codes (WAVE/HISTO buffer).
            // Passing identity here when LUT was off made FALSE sample Rec.709-linearized
            // HEVC, so toggling the cube look moved the painted regions.
            let measure = (fx.lutDimension >= 2 || fx.falseColor) ? cameraCodes : identity
            if fx.needsOverlayFeed {
                // Measure the same codes WAVE uses; paint only. The picture stays
                // on the identity layer so zebra cannot Rec.709→sRGB the feed.
                output = LiveMonitorCompositor.assistOverlay(from: cameraCodes, effects: fx)
                overlayOnly = true
                unmanagedBake = false
            } else {
                let product = LiveMonitorCompositor.applyProduct(
                    to: measure, effects: fx, display: identity)
                output = product.image
                overlayOnly = false
                unmanagedBake = product.unmanagedBake
            }
        } else {
            identity = CIImage.empty()
            output = identity
            overlayOnly = false
            unmanagedBake = false
        }

        completion(
            Result(
                output: output,
                identity: identity,
                source: buffer,
                needsGPU: fx.needsGPUFeed,
                overlayOnly: overlayOnly,
                unmanagedBake: unmanagedBake,
                bundle: nil,
                transfer: transfer,
                colorMode: transfer.colorMode,
                shouldPresent: true,
                timeNs: timeNs))

        if let packed {
            let tapMin = LiveFrameTap.minRGB(packed.bytes)
            let tapMax = LiveFrameTap.maxRGB(packed.bytes)
            let inferred = MonitorTransfer.inferred(
                minByte: tapMin, maxByte: tapMax, fallback: transfer)
            if inferred != transfer {
                transfer = inferred
                pendingTransfer = inferred
                fx.colorMode = inferred.colorMode
                ControlLiveLog.line(
                    "scope transfer: inferred \(inferred.rawValue) min=\(tapMin) max=\(tapMax)"
                )
            }
            let sampled = PocketScopeSampler.sample(
                bytes: packed.bytes, width: packed.width, height: packed.height,
                bytesPerRow: packed.bytesPerRow, transfer: transfer,
                includePoints: fx.waveform || fx.parade,
                includeVectorPoints: fx.vectorscope,
                look: fx.vectorscope
                    ? PocketScopeSampler.monitorCube(for: transfer, effects: fx) : nil,
                trafficThreshold: fx.trafficThreshold,
                previous: previousBundle)
            previousBundle = sampled
            let observed = ScopeExposureCeiling.observeTapMax(tapMax, transfer: transfer)
            logTapOnce(buffer: buffer, packed: packed, points: sampled.samples.points.count)
            let tapNow = CFAbsoluteTimeGetCurrent()
            let interval = PocketScopeSampler.minInterval(activeScopeCount: fx.activeScopeCount)
            tapsInWindow += 1
            if tapWindowStart == 0 { tapWindowStart = tapNow }
            let elapsed = tapNow - tapWindowStart
            if elapsed >= 2 {
                let hz = Double(tapsInWindow) / elapsed
                let budget = 1.0 / interval
                ControlLiveLog.line(
                    String(
                        format: "scope tap: %.1fHz budget=%.0fHz scopes=%d", hz, budget,
                        fx.activeScopeCount))
                tapsInWindow = 0
                tapWindowStart = tapNow
            }
            // Ceiling calibration breadcrumb: rolling 10 s tap maximum
            // into the pullable journal (tools/pull-control-log.sh).
            // Point the lens at a blown lamp at each ISO and read the
            // saturation byte straight off these lines.
            ceilingLogMax = max(ceilingLogMax, tapMax)
            let now = CFAbsoluteTimeGetCurrent()
            if now >= nextCeilingLogAt {
                nextCeilingLogAt = now + 10
                ControlLiveLog.line(
                    "scope max: byte=\(ceilingLogMax) clip=\(observed.clip) transfer=\(transfer.rawValue) ei=\(ScopeExposureCeiling.resolvedISO())"
                )
                ceilingLogMax = 0
            }
            completion(
                Result(
                    output: output,
                    identity: identity,
                    source: buffer,
                    needsGPU: false,
                    overlayOnly: false,
                    unmanagedBake: false,
                    bundle: sampled,
                    transfer: transfer,
                    colorMode: transfer.colorMode,
                    shouldPresent: false,
                    timeNs: timeNs))
        }

        queue.async { [self] in
            busy = false
            drain()
        }
    }
}
