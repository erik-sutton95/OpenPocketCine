import CoreImage
import Metal
import OpenPocketViewCore
import UIKit

/// Local GPU monitor tools. Peaking, false colour, and zebra measure **source
/// camera codes** — the same pre-LUT buffer WAVE / HISTO tap. Never the cube look.
/// False colour IRE / Limits use ``LiveColorScience/monitorIRE`` for the active
/// `ColorMode`. LUT and de-squeeze are display-only CI ops. Mirror is a view-space
/// flip (`MirrorAssist.feedScale`) so it never lands in this graph.
struct LiveImageEffects: Equatable, Sendable {
    var peaking = false
    var zebra = false
    var falseColor = false
    var histogram = false
    var waveform = false
    var parade = false
    var vectorscope = false
    var trafficLights = false
    var lutDimension = 0
    var lutRGBA = Data()

    var peakingColor: PeakingPaint = .red
    var peakingSensitivity: PeakingSense = .medium
    var falseColorScale: FalseColorScaleKind = .stops
    var zebraHighlight = true
    var zebraMidtone = true
    var zebraHighlightIRE: Double = LiveZebra.highlightIRE
    var zebraMidtoneIRE: Double = LiveZebra.midtoneIRE
    var zebraHighlightColor: ZebraPaint = .white
    var zebraMidtoneColor: ZebraPaint = .amber
    /// Sibling / session stamps the camera color mode so D-Log2 IRE does not treat mid-grey as clip.
    var colorMode: ColorMode = .normal
    var splitComparison = false
    var splitVertical = true
    /// Left-to-right monitor flip. Applied in `VideoView`, not this compositor.
    var mirror = false
    /// Anamorphic display stretch. `1` is off. Pocket sensors are not squeezed — this is a
    /// preview-only transform matching OpenZCine DE-SQ.
    var desqueezeFactor: Double = 1
    var desqueezeHorizontal = true
    /// Traffic-light pixel-fraction threshold (operator compensation, stops / 10).
    var trafficThreshold: Double = ScopeTrafficLights.defaultThreshold
    /// AF-C face box. Starts VT so Vision can see a `CVPixelBuffer`.
    var faceAF = false

    /// Peaking / false colour / zebra / LUT / display transforms — painted on the video frame.
    var needsGPUFeed: Bool {
        peaking || zebra || falseColor
            || lutDimension >= 2 || desqueezeFactor > 1.001 || splitComparison
    }

    /// LUT / de-squeeze / split remake every pixel. Zebra, peaking, and false
    /// colour only paint — the identity HEVC / VT layer stays so contrast does
    /// not shift. A DeviceRGB bake of the Rec.709 picture is a visible
    /// Rec.709→sRGB re-encode.
    var replacesIdentityFeed: Bool {
        lutDimension >= 2
            || desqueezeFactor > 1.001
            || splitComparison
    }

    /// Transparent stripe / peaking overlay on top of the identity layer.
    var needsOverlayFeed: Bool {
        needsGPUFeed && !replacesIdentityFeed
    }

    /// WAVE / PARADE / HISTO / VECTOR / LIGHTS — OpenZCine `scopesActive`.
    var needsScopes: Bool {
        histogram || waveform || parade || vectorscope || trafficLights
    }

    var needsScopePoints: Bool {
        waveform || parade || vectorscope
    }

    var activeScopeCount: Int {
        [histogram, waveform, parade, vectorscope, trafficLights].filter { $0 }.count
    }

    /// GPU feed, CPU scopes, or AF-C face detect. Any one starts VT for a pixel buffer.
    var needsSample: Bool {
        needsGPUFeed || needsScopes || faceAF
    }

    var needsProcessedFeed: Bool { needsSample }

    func withFaceAF(_ on: Bool) -> LiveImageEffects {
        var fx = self
        fx.faceAF = on
        return fx
    }
}

/// OpenZCine `Peaking.Color` — paint table lives on ``PeakingAssist/Color``.
typealias PeakingPaint = PeakingAssist.Color
/// OpenZCine `Peaking.Sensitivity` — detector steps live on ``PeakingAssist/Sensitivity``.
typealias PeakingSense = PeakingAssist.Sensitivity

enum FalseColorScaleKind: String, CaseIterable, Codable, Sendable {
    case stops = "ZC Stops"
    case ire = "IRE"
    case limits = "Limits"
}

enum ZebraPaint: String, CaseIterable, Codable, Sendable {
    case white = "White"
    case amber = "Amber"
    case red = "Red"
    case cyan = "Cyan"
    case green = "Green"

    /// OpenZCine `ImageEffectsCompositor.zebraRGB`.
    var rgb: (Double, Double, Double) {
        switch self {
        case .white: (1, 1, 1)
        case .amber: (1, 0.72, 0.2)
        case .red: (1, 0.15, 0.15)
        case .cyan: (0, 0.85, 0.9)
        case .green: (0.2, 0.9, 0.35)
        }
    }
}

/// OpenZCine `Peaking` constants used by the Core Image filter-chain detector (no fused kernel).
private enum Peak {
    static let reblurRadius = 1.0
    static let ratioScale = 0.25
    static let antialiasWidth = 0.12
    static let underRampOffset = 0.5
    static let under = (red: 0.04, green: 0.04, blue: 0.05)
    static let gateRampFloor = 0.7
    static let edgeInset = 6.0
    static let maskClosingRadius = 1.0
}

/// Encoded camera codes (D-Log2 on the wire). Default Core Image linearizes a Rec.709
/// tag — or treats an untagged cube result as linear and DeviceRGB-encodes it. Either
/// way the official log→709 cube looks like uncorrected log (lifted blacks, dull reds).
enum LiveMonitorWorkingSpace {
    /// LUT / false-colour cubes on encoded camera codes. Do not use for HEVC identity.
    static var contextOptions: [CIContextOption: Any] {
        [
            .workingFormat: CIFormat.BGRA8,
            .workingColorSpace: NSNull(),
            .outputColorSpace: NSNull(),
            .cacheIntermediates: false,
        ]
    }

    /// Rec.709 / HLG identity present. YUV→RGB needs the buffer's color attachments.
    static var displayContextOptions: [CIContextOption: Any] {
        [
            .workingFormat: CIFormat.BGRA8,
            .cacheIntermediates: false,
        ]
    }

    static var imageOptions: [CIImageOption: Any] {
        [.colorSpace: NSNull()]
    }

    static var displayImageOptions: [CIImageOption: Any] {
        if let rec709 = CGColorSpace(name: CGColorSpace.itur_709) {
            return [.colorSpace: rec709]
        }
        return [.colorSpace: CGColorSpaceCreateDeviceRGB()]
    }

    /// Metal `render(..., colorSpace:)` is non-optional. With the NSNull working
    /// space above, DeviceRGB is a required handle — it does not apply another OETF.
    static let metalDestination = CGColorSpaceCreateDeviceRGB()
}

enum LiveMonitorCompositor {
    /// Working-width cap when the drawable is unknown at this site (the assist engine has
    /// no layer). Peaking / zebra / false colour are display-referred — evaluating their
    /// convolution graphs over the full 4K extent was the top heat source; `FeedFrameBaker`
    /// only downscaled *after* the graph, so ROI pull-back still ran every kernel at 4K.
    private static let maxWorkingWidth: CGFloat = 1440

    /// LUT is the displayed look. False colour / peaking / zebra read unmanaged
    /// camera codes, then composite over that look.
    ///
    /// `source` is encoded camera codes (NSNull). `display` is the Rec.709 / HLG
    /// identity with buffer attachments — used only when no LUT is armed.
    static func apply(to source: CIImage, effects: LiveImageEffects, display: CIImage? = nil)
        -> CIImage
    {
        applyProduct(to: source, effects: effects, display: display).image
    }

    /// Same graph as ``apply(to:effects:display:)``. `unmanagedBake` is true only
    /// when the output is a LUT cube product. Identity fallbacks stay managed —
    /// NSNull of Rec.709 HEVC is a black feed. False colour rides the overlay.
    static func applyProduct(
        to source: CIImage, effects: LiveImageEffects, display: CIImage? = nil
    ) -> (image: CIImage, unmanagedBake: Bool) {
        // Downscale FIRST. The 3D cubes are resolution-independent; peaking and zebra
        // *want* display resolution. `FeedFrameBaker.bake` composes any further drawable
        // fit on the already-small image, so the final on-screen size is unchanged.
        var measure = source
        var displayed = display
        let sourceWidth = source.extent.width
        if sourceWidth > maxWorkingWidth {
            let scale = maxWorkingWidth / sourceWidth
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            measure = source.transformed(by: transform)
            displayed = display?.transformed(by: transform)
        }
        let input = unmanaged(measure)
        let extent = input.extent
        let hasLUT = effects.lutDimension >= 2 && !effects.lutRGBA.isEmpty
        var graded = input
        if hasLUT {
            let lut =
                applyLUT(to: input, dimension: effects.lutDimension, rgba: effects.lutRGBA) ?? input
            graded =
                effects.splitComparison
                ? split(lut, over: input, extent: extent, vertical: effects.splitVertical)
                : lut
        }

        // No cube: keep the caller's YUV→RGB attachments. Unmanaged NSNull is LUT-only —
        // Rec.709 / HLG identity through NSNull presents black on CIFeedView.
        var output = hasLUT ? graded : (displayed ?? measure)
        let cubeProduct = hasLUT
        if effects.falseColor {
            output = applyFalseColor(
                over: output, codes: input, extent: extent, effects: effects)
        }

        if effects.peaking {
            output = applyPeaking(
                over: output, source: input, extent: extent,
                color: effects.peakingColor, sense: effects.peakingSensitivity,
                gateScale: LiveColorScience.peakingGateScale(
                    for: MonitorTransfer(effects.colorMode)))
        }
        if effects.zebra {
            output = applyZebra(
                over: output, source: input, extent: extent,
                zebra: ZebraAssist.overlay(from: effects),
                colorMode: effects.colorMode)
        }
        if effects.desqueezeFactor > 1.001 {
            output = desqueeze(
                output, factor: effects.desqueezeFactor, horizontal: effects.desqueezeHorizontal)
        }
        return (output, cubeProduct)
    }

    /// Stripe / peaking paint only — alpha 0 where the identity picture should show through.
    /// Used when ``LiveImageEffects/needsOverlayFeed`` so the HEVC / VT layer is never remade.
    static func assistOverlay(from source: CIImage, effects: LiveImageEffects) -> CIImage {
        var measure = source
        let sourceWidth = source.extent.width
        if sourceWidth > maxWorkingWidth {
            let scale = maxWorkingWidth / sourceWidth
            measure = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        let input = unmanaged(measure)
        let extent = input.extent
        var output = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0))
            .cropped(to: extent)
        if effects.falseColor {
            output = applyFalseColor(
                over: output, codes: input, extent: extent, effects: effects)
        }
        if effects.peaking {
            output = applyPeaking(
                over: output, source: input, extent: extent,
                color: effects.peakingColor, sense: effects.peakingSensitivity,
                gateScale: LiveColorScience.peakingGateScale(
                    for: MonitorTransfer(effects.colorMode)))
        }
        if effects.zebra {
            output = applyZebra(
                over: output, source: input, extent: extent,
                zebra: ZebraAssist.overlay(from: effects),
                colorMode: effects.colorMode)
        }
        return output
    }

    /// Scale an overlay (often the 1440 working width) onto a full-resolution identity.
    /// Simulator has no HEVC layer, so the overlay is composited over the pixel-buffer picture.
    static func place(_ overlay: CIImage, over base: CIImage) -> CIImage {
        let overlayExtent = overlay.extent
        let baseExtent = base.extent
        guard overlayExtent.width > 1, overlayExtent.height > 1,
            baseExtent.width > 1, baseExtent.height > 1
        else { return overlay.composited(over: base) }
        let scale = min(
            baseExtent.width / overlayExtent.width,
            baseExtent.height / overlayExtent.height)
        let scaled = overlay.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let placedExtent = scaled.extent
        let placed = scaled.transformed(
            by: CGAffineTransform(
                translationX: baseExtent.midX - placedExtent.midX,
                y: baseExtent.midY - placedExtent.midY))
        return placed.composited(over: base.cropped(to: baseExtent))
    }

    /// Encoded camera codes — do not let Core Image sRGB-linearize D-Log2 before the cubes.
    /// OpenZCine `LiveFrameProcessor` marks the same way (`options: [.colorSpace: NSNull()]`).
    private static func unmanaged(_ image: CIImage) -> CIImage {
        image.settingProperties(LiveMonitorWorkingSpace.imageOptions)
    }

    /// Paint from pre-LUT camera codes, composited over the displayed look.
    /// Limits is holes-only (shadow / highlight warnings over the picture).
    /// IRE / PStops paint the full remap — WAVE grayscale in the gaps, not a
    /// hole onto camera colour. Cube data is `nil` while the async lattice
    /// warm runs — show the plain look rather than stall the frame path.
    private static func applyFalseColor(
        over base: CIImage, codes: CIImage, extent: CGRect, effects: LiveImageEffects
    ) -> CIImage {
        guard
            let paintInfo = PocketFalseColorMap.overlayPaintData(
                scale: effects.falseColorScale, mode: effects.colorMode),
            let paint = applyColorCube(
                to: codes, dimension: paintInfo.0, rgba: paintInfo.1),
            let weightInfo = PocketFalseColorMap.overlayWeightData(
                scale: effects.falseColorScale, mode: effects.colorMode),
            let weight = applyColorCube(
                to: codes, dimension: weightInfo.0, rgba: weightInfo.1)
        else { return base }
        return paint.cropped(to: extent).applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: base.cropped(to: extent),
                kCIInputMaskImageKey: weight.cropped(to: extent),
            ])
    }

    private static func applyLUT(to source: CIImage, dimension: Int, rgba: Data) -> CIImage? {
        applyColorCube(to: source, dimension: dimension, rgba: rgba)
    }

    private static func applyColorCube(to source: CIImage, dimension: Int, rgba: Data) -> CIImage? {
        // A fresh CIFilter per apply is graph description only — the cube Data is CoW and
        // the GPU cost lives in the render. The old shared filter + global NSLock made
        // every look serialize through one mutable `setValue`.
        guard
            let filter = CIFilter(
                name: "CIColorCube",
                parameters: [
                    "inputCubeDimension": dimension,
                    "inputCubeData": rgba,
                    kCIInputImageKey: source.clampedToExtent(),
                ])
        else { return nil }
        return filter.outputImage?.cropped(to: source.extent)
    }

    /// OpenZCine 50/50 Log-vs-LUT: graded half composited over the clean source.
    /// Core Image y is up, so the operator's top half is the high-y half.
    private static func split(
        _ graded: CIImage, over source: CIImage, extent: CGRect, vertical: Bool
    ) -> CIImage {
        guard extent.width > 0, extent.height > 0 else { return graded }
        let half =
            vertical
            ? CGRect(x: extent.midX, y: extent.minY, width: extent.width / 2, height: extent.height)
            : CGRect(x: extent.minX, y: extent.minY, width: extent.width, height: extent.height / 2)
        return graded.cropped(to: half).composited(over: source.cropped(to: extent))
    }

    private static func desqueeze(_ image: CIImage, factor: Double, horizontal: Bool) -> CIImage {
        let e = image.extent
        let sx = horizontal ? factor : 1
        let sy = horizontal ? 1 : factor
        let scaled = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
        let s = scaled.extent
        let dx = e.midX - s.midX
        let dy = e.midY - s.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }

    // MARK: - Peaking (OpenZCine fused kernel, filter-chain fallback)

    private static let fusedPeakingKernel: CIKernel? = makeFusedPeakingKernel()

    private static let fusedPeakingCheck: (matches: Bool, note: String) = {
        verifyAgainstChain()
    }()

    static var fusedPeakingAvailable: Bool {
        fusedPeakingKernel != nil && fusedPeakingCheck.matches
    }

    static var fusedPeakingNote: String { fusedPeakingCheck.note }

    private static func verifyAgainstChain() -> (Bool, String) {
        guard let kernel = fusedPeakingKernel else { return (false, "kernel did not compile") }
        let w = 96
        let h = 64
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                var value = 64
                if x % 7 == 3 { value = 210 }
                if y % 9 == 4 { value = 16 }
                for c in 0..<3 { bytes[(y * w + x) * 4 + c] = UInt8(value) }
            }
        }
        let source = CIImage(
            bitmapData: Data(bytes), bytesPerRow: w * 4, size: CGSize(width: w, height: h),
            format: .RGBA8, colorSpace: nil)
        let extent = source.extent
        let context = CIContext(options: [
            .workingFormat: CIFormat.RGBAf,
            .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            .cacheIntermediates: false,
        ])
        func rendered(_ image: CIImage) -> [UInt8] {
            var out = [UInt8](repeating: 0, count: w * h * 4)
            context.render(
                image, toBitmap: &out, rowBytes: w * 4, bounds: extent, format: .BGRA8,
                colorSpace: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB())
            return out
        }
        let chain = rendered(
            applyPeakingFilterChain(
                over: source, source: source, extent: extent,
                color: .red, sense: .medium, gateScale: 1))
        let plain = rendered(source)
        let painted = zip(chain, plain).reduce(0) { $0 + (abs(Int($1.0) - Int($1.1)) > 2 ? 1 : 0) }
        guard painted > 0 else {
            return (false, "chain fallback — probe frame drew no peaking, so nothing was validated")
        }
        guard
            let fusedImage = applyFusedPeaking(
                kernel: kernel, over: source, source: source, extent: extent,
                color: .red, sense: .medium, gateScale: 1)
        else { return (false, "chain fallback — kernel apply returned nil") }
        let fused = rendered(fusedImage)
        var worst = 0
        var differing = 0
        for i in 0..<chain.count {
            let d = abs(Int(chain[i]) - Int(fused[i]))
            worst = max(worst, d)
            if d > 2 { differing += 1 }
        }
        guard worst <= 2 else {
            return (
                false,
                "chain fallback — worst \(worst)/255 over \(differing) channels (chain painted \(painted))"
            )
        }
        return (true, "fused (chain painted \(painted) channels, worst delta \(worst)/255)")
    }

    private static func makeFusedPeakingKernel() -> CIKernel? {
        CIKernel(
            source: """
                float robertsSquared(sampler s, vec2 p) {
                  float a = sample(s, samplerTransform(s, p)).r;
                  float b = sample(s, samplerTransform(s, p + vec2(1.0,  0.0))).r;
                  float c = sample(s, samplerTransform(s, p + vec2(0.0, -1.0))).r;
                  float d = sample(s, samplerTransform(s, p + vec2(1.0, -1.0))).r;
                  float d1 = d - a;
                  float d2 = c - b;
                  return d1 * d1 + d2 * d2;
                }

                kernel vec4 peakingMask(
                    sampler grey, sampler blurred,
                    float ratioScale, float gateGain, float gateBias,
                    float rampGain, float coreBias, float underBias,
                    vec2 lo, vec2 hi) {
                  vec2 p = destCoord();
                  float fine = robertsSquared(grey, p);
                  float coarse = robertsSquared(blurred, p);
                  float ratio = min(fine * ratioScale / max(coarse, 1e-9), 1.0);
                  float gate = clamp(coarse * gateGain + gateBias, 0.0, 1.0);
                  float core = clamp(ratio * rampGain + coreBias, 0.0, 1.0) * gate;
                  float under = clamp(ratio * rampGain + underBias, 0.0, 1.0) * gate;
                  float window = step(lo.x, p.x) * step(lo.y, p.y)
                      * (1.0 - step(hi.x, p.x)) * (1.0 - step(hi.y, p.y));
                  return vec4(core * window, under * window, 0.0, 1.0);
                }
                """)
    }

    static func applyPeaking(
        over base: CIImage, source: CIImage, extent: CGRect,
        color: PeakingPaint, sense: PeakingSense, gateScale: Double = 1
    ) -> CIImage {
        if let kernel = fusedPeakingKernel, fusedPeakingCheck.matches,
            let fused = applyFusedPeaking(
                kernel: kernel, over: base, source: source, extent: extent,
                color: color, sense: sense, gateScale: gateScale)
        {
            return fused
        }
        return applyPeakingFilterChain(
            over: base, source: source, extent: extent,
            color: color, sense: sense, gateScale: gateScale)
    }

    private static func applyFusedPeaking(
        kernel: CIKernel, over base: CIImage, source: CIImage, extent: CGRect,
        color: PeakingPaint, sense: PeakingSense, gateScale: Double
    ) -> CIImage? {
        let cropped = extent.insetBy(dx: Peak.edgeInset, dy: Peak.edgeInset)
        guard cropped.width > 8, cropped.height > 8 else { return nil }
        let grey = greyscale(source).clampedToExtent()
        let blurred = grey.applyingFilter(
            "CIGaussianBlur", parameters: [kCIInputRadiusKey: Peak.reblurRadius])
        let gate = sense.noiseGate * gateScale
        let gateGain = 1.0 / max(gate * (1 - Peak.gateRampFloor), 1e-6)
        let rampGain = 1.0 / max(Peak.antialiasWidth * Peak.ratioScale, 1e-6)
        let threshold = sense.ratioThreshold
        guard
            let mask = kernel.apply(
                extent: cropped.insetBy(dx: -2, dy: -2),
                roiCallback: { _, rect in rect.insetBy(dx: -2, dy: -2) },
                arguments: [
                    grey, blurred,
                    Peak.ratioScale, gateGain, -(gate * Peak.gateRampFloor) * gateGain,
                    rampGain, -(threshold * Peak.ratioScale) * rampGain,
                    -((threshold - Peak.antialiasWidth * Peak.underRampOffset) * Peak.ratioScale)
                        * rampGain,
                    CIVector(x: cropped.minX, y: cropped.minY),
                    CIVector(x: cropped.maxX, y: cropped.maxY),
                ])
        else { return nil }

        var coreMask = mask
        if Peak.maskClosingRadius > 0 {
            coreMask =
                mask
                .applyingFilter(
                    "CIMorphologyMaximum",
                    parameters: [kCIInputRadiusKey: Peak.maskClosingRadius]
                )
                .applyingFilter(
                    "CIMorphologyMinimum",
                    parameters: [kCIInputRadiusKey: Peak.maskClosingRadius]
                )
                .cropped(to: cropped)
        }
        let core = broadcast(.red, of: coreMask)
        let under = broadcast(.green, of: mask)
        return composite(over: base, coreMask: core, underMask: under, color: color, extent: extent)
    }

    private enum MaskChannel { case red, green }

    private static func broadcast(_ channel: MaskChannel, of image: CIImage) -> CIImage {
        let vector =
            channel == .red
            ? CIVector(x: 1, y: 0, z: 0, w: 0) : CIVector(x: 0, y: 1, z: 0, w: 0)
        return image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": vector,
                "inputGVector": vector,
                "inputBVector": vector,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
    }

    static func applyPeakingFilterChain(
        over base: CIImage, source: CIImage, extent: CGRect,
        color: PeakingPaint, sense: PeakingSense, gateScale: Double = 1
    ) -> CIImage {
        let grey = greyscale(source).clampedToExtent()
        let cropped = extent.insetBy(dx: Peak.edgeInset, dy: Peak.edgeInset)
        let fine = grey.applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0]).cropped(
            to: cropped)
        let coarse =
            grey
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: Peak.reblurRadius])
            .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: 1.0])
            .cropped(to: cropped)

        func scale(_ image: CIImage, by factor: Double, bias: Double = 0) -> CIImage {
            image.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: factor, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 1),
                ])
        }

        let ratio =
            (CIFilter(
                name: "CIDivideBlendMode",
                parameters: [
                    kCIInputImageKey: coarse,
                    kCIInputBackgroundImageKey: scale(fine, by: Peak.ratioScale),
                ])?.outputImage ?? coarse)
            .cropped(to: cropped)

        let gate = sense.noiseGate * gateScale
        let gateGain = 1.0 / max(gate * (1 - Peak.gateRampFloor), 1e-6)
        let gateMask = scale(coarse, by: gateGain, bias: -(gate * Peak.gateRampFloor) * gateGain)
            .applyingFilter("CIColorClamp")

        func ramp(from start: Double) -> CIImage {
            let gain = 1.0 / max(Peak.antialiasWidth * Peak.ratioScale, 1e-6)
            let masked = scale(ratio, by: gain, bias: -(start * Peak.ratioScale) * gain)
                .applyingFilter("CIColorClamp")
            return
                (CIFilter(
                    name: "CIMultiplyCompositing",
                    parameters: [kCIInputImageKey: masked, kCIInputBackgroundImageKey: gateMask]
                )?.outputImage ?? masked)
                .cropped(to: cropped)
        }

        var coreMask = ramp(from: sense.ratioThreshold)
        if Peak.maskClosingRadius > 0 {
            coreMask =
                coreMask
                .applyingFilter(
                    "CIMorphologyMaximum", parameters: [kCIInputRadiusKey: Peak.maskClosingRadius]
                )
                .applyingFilter(
                    "CIMorphologyMinimum", parameters: [kCIInputRadiusKey: Peak.maskClosingRadius]
                )
                .cropped(to: cropped)
        }
        let underMask = ramp(
            from: sense.ratioThreshold - Peak.antialiasWidth * Peak.underRampOffset)
        return composite(
            over: base, coreMask: coreMask, underMask: underMask, color: color, extent: extent)
    }

    private static func greyscale(_ source: CIImage) -> CIImage {
        let third = 1.0 / 3.0
        return source.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: third, y: third, z: third, w: 0),
                "inputGVector": CIVector(x: third, y: third, z: third, w: 0),
                "inputBVector": CIVector(x: third, y: third, z: third, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
    }

    private static func composite(
        over base: CIImage, coreMask: CIImage, underMask: CIImage, color: PeakingPaint,
        extent: CGRect
    ) -> CIImage {
        let dark = CIImage(
            color: CIColor(red: Peak.under.red, green: Peak.under.green, blue: Peak.under.blue)
        )
        .cropped(to: extent)
        let rgb = color.rgb
        let tint = CIImage(color: CIColor(red: rgb.0, green: rgb.1, blue: rgb.2)).cropped(
            to: extent)
        let withUnder =
            (CIFilter(
                name: "CIBlendWithMask",
                parameters: [
                    kCIInputImageKey: dark, kCIInputBackgroundImageKey: base,
                    kCIInputMaskImageKey: underMask,
                ])?.outputImage ?? base)
            .cropped(to: extent)
        return
            (CIFilter(
                name: "CIBlendWithMask",
                parameters: [
                    kCIInputImageKey: tint, kCIInputBackgroundImageKey: withUnder,
                    kCIInputMaskImageKey: coreMask,
                ])?.outputImage ?? withUnder)
            .cropped(to: extent)
    }

    // MARK: - Zebra (`ScopeDisplayScale.signalNative` thresholds)

    static func applyZebra(
        over base: CIImage, source: CIImage, extent: CGRect,
        zebra: ZebraAssist.OverlaySpec, colorMode: ColorMode
    ) -> CIImage {
        // Measure **source** encoded luma; monitor-percent thresholds map to curve
        // codes (0 = paper black, 100 = live-tap EI ceiling). The old
        // `encodedValue(ire100:)` ran a 48-step bisection up to 3× per frame.
        // D-Log2 18% grey stays at paper IRE 30.50 — never a highlight zebra.
        // Unit is editor-only (OpenZCine `ZebraSettings.unit`) — both zones read IRE here.
        let transfer = MonitorTransfer(colorMode)
        let luma = source.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        var output = base
        if zebra.highlightEnabled {
            let rgb = zebra.highlightColor.rgb
            let threshold = ScopeDisplayScale.signalNative(
                monitorPercent: zebra.highlightIRE, transfer: transfer)
            output = blendStripedZebra(
                over: output, mask: thresholdMask(luma, above: threshold),
                color: CIColor(red: rgb.0, green: rgb.1, blue: rgb.2), extent: extent)
        }
        if zebra.midtoneEnabled {
            let rgb = zebra.midtoneColor.rgb
            let half = LiveZebra.midtoneHalfWidthIRE
            let lo = ScopeDisplayScale.signalNative(
                monitorPercent: zebra.midtoneIRE - half, transfer: transfer)
            let hi = ScopeDisplayScale.signalNative(
                monitorPercent: zebra.midtoneIRE + half, transfer: transfer)
            let mid = bandMask(luma, centre: (lo + hi) * 0.5, halfWidth: abs(hi - lo) * 0.5)
            output = blendStripedZebra(
                over: output, mask: mid,
                color: CIColor(red: rgb.0, green: rgb.1, blue: rgb.2), extent: extent)
        }
        return output
    }

    private static func thresholdMask(_ luma: CIImage, above threshold: Double) -> CIImage {
        let gain = 40.0
        // Bias +1 so luma == threshold paints (`ire100 >= highlight`), matching LiveZebra.
        return luma.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(
                    x: -threshold * gain + 1, y: -threshold * gain + 1, z: -threshold * gain + 1,
                    w: 1),
            ]
        ).applyingFilter("CIColorClamp")
    }

    private static func bandMask(_ luma: CIImage, centre: Double, halfWidth: Double) -> CIImage {
        let low = thresholdMask(luma, above: centre - halfWidth)
        let high = luma.applyingFilter(
            "CIColorMatrix",
            parameters: {
                let gain = 40.0
                let upper = centre + halfWidth
                return [
                    "inputRVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: -gain, y: 0, z: 0, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                    "inputBiasVector": CIVector(
                        x: upper * gain + 1, y: upper * gain + 1, z: upper * gain + 1, w: 1),
                ]
            }()
        ).applyingFilter("CIColorClamp")
        return low.applyingFilter(
            "CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: high])
    }

    private static func blendStripedZebra(
        over base: CIImage, mask: CIImage, color: CIColor, extent: CGRect
    ) -> CIImage {
        let stripes =
            (CIFilter(
                name: "CIStripesGenerator",
                parameters: [
                    "inputColor0": CIColor(red: 0, green: 0, blue: 0),
                    "inputColor1": CIColor(red: 1, green: 1, blue: 1),
                    "inputWidth": ZebraAssist.StripeLook.width,
                    "inputSharpness": ZebraAssist.StripeLook.sharpness,
                    kCIInputCenterKey: CIVector(x: 0, y: 0),
                ])?.outputImage ?? CIImage(color: CIColor(red: 1, green: 1, blue: 1)))
            .transformed(by: CGAffineTransform(rotationAngle: ZebraAssist.StripeLook.rotation))
            .cropped(to: extent)
        let stripedMask = stripes.applyingFilter(
            "CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
        let tint = CIImage(color: color).cropped(to: extent)
        return
            (CIFilter(
                name: "CIBlendWithMask",
                parameters: [
                    kCIInputImageKey: tint,
                    kCIInputBackgroundImageKey: base,
                    kCIInputMaskImageKey: stripedMask,
                ])?.outputImage ?? base)
            .cropped(to: extent)
    }
}

/// OpenZCine `MetalFeedFrameBaker`: evaluate the look graph at feed/panel size off-main.
/// `CIFeedView` only scales the published texture into the drawable — no `createCGImage`.
final class FeedFrameBaker: @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let lutContext: CIContext
    private let displayContext: CIContext
    private let workQueue = DispatchQueue(label: "opv.metal-feed-bake", qos: .userInitiated)
    private let lock = NSLock()
    private var pending:
        (
            image: CIImage, drawableSize: CGSize, pixelFormat: MTLPixelFormat, unmanaged: Bool,
            overlay: Bool
        )?
    private var pendingDone: (@Sendable () -> Void)?
    private var busy = false
    private var textures: [MTLTexture] = []
    private var nextTexture = 0
    private var retained: [ObjectIdentifier: Int] = [:]
    private var published: (texture: MTLTexture, drawableSize: CGSize, pixelFormat: MTLPixelFormat)?
    private(set) var lastBakeUnmanaged = true
    private(set) var lastBakeOverlay = false
    private static let depth = 3

    init(device: MTLDevice) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.lutContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: LiveMonitorWorkingSpace.contextOptions)
        self.displayContext = CIContext(
            mtlCommandQueue: commandQueue,
            options: LiveMonitorWorkingSpace.displayContextOptions)
    }

    func scheduleBake(
        image: CIImage, drawableSize: CGSize, pixelFormat: MTLPixelFormat,
        unmanaged: Bool = true, overlay: Bool = false,
        onComplete: @escaping @Sendable () -> Void
    ) {
        guard drawableSize.width > 0, drawableSize.height > 0 else { return }
        lock.lock()
        pending = (image, drawableSize, pixelFormat, unmanaged, overlay)
        pendingDone = onComplete
        let start = !busy
        if start { busy = true }
        lock.unlock()
        if start { workQueue.async { [self] in run() } }
    }

    func bakedTexture(for drawableSize: CGSize, pixelFormat: MTLPixelFormat) -> MTLTexture? {
        lock.lock()
        defer { lock.unlock() }
        guard let published,
            published.drawableSize == drawableSize,
            published.pixelFormat == pixelFormat
        else { return nil }
        retained[ObjectIdentifier(published.texture), default: 0] += 1
        return published.texture
    }

    func releaseBakedTexture(_ texture: MTLTexture) {
        let key = ObjectIdentifier(texture)
        lock.lock()
        defer { lock.unlock() }
        guard let count = retained[key] else { return }
        if count <= 1 {
            retained[key] = nil
        } else {
            retained[key] = count - 1
        }
    }

    /// CI bottom-left → Metal/MPS origin. Same four multiplies as OpenZCine's baker.
    static func metalOriginTransform(extent: CGRect, bakeWidth: Int, bakeHeight: Int)
        -> CGAffineTransform
    {
        let sx = CGFloat(bakeWidth) / max(extent.width, 1)
        let sy = CGFloat(bakeHeight) / max(extent.height, 1)
        var transform = CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
        transform = transform.concatenating(CGAffineTransform(scaleX: sx, y: sy))
        transform = transform.concatenating(CGAffineTransform(scaleX: 1, y: -1))
        transform = transform.concatenating(
            CGAffineTransform(translationX: 0, y: CGFloat(bakeHeight)))
        return transform
    }

    /// Source resolution, downscale-bounded by the drawable. OpenZCine `bakeSize`.
    static func bakeSize(source: CGSize, drawable: CGSize) -> CGSize {
        guard source.width.isFinite, source.height.isFinite,
            source.width > 0, source.height > 0,
            source.width <= 16_384, source.height <= 16_384,
            drawable.width > 0, drawable.height > 0
        else { return drawable }
        let scale = min(drawable.width / source.width, drawable.height / source.height, 1)
        let fitted = CGSize(width: source.width * scale, height: source.height * scale)
        guard fitted.width >= 1, fitted.height >= 1 else { return drawable }
        return fitted
    }

    private func run() {
        lock.lock()
        guard let request = pending else {
            busy = false
            lock.unlock()
            return
        }
        pending = nil
        let done = pendingDone
        pendingDone = nil
        lock.unlock()

        bake(
            request.image, drawableSize: request.drawableSize, pixelFormat: request.pixelFormat,
            unmanaged: request.unmanaged, overlay: request.overlay
        ) {
            done?()
            self.workQueue.async { [self] in run() }
        }
    }

    private func bake(
        _ source: CIImage, drawableSize: CGSize, pixelFormat: MTLPixelFormat,
        unmanaged: Bool, overlay: Bool, finished: @escaping () -> Void
    ) {
        autoreleasepool {
            let extent = source.extent
            let size = Self.bakeSize(source: extent.size, drawable: drawableSize)
            let width = max(1, Int(size.width.rounded()))
            let height = max(1, Int(size.height.rounded()))
            // Same origin flip as OpenZCine `MetalFeedFrameBaker`: CI is bottom-left,
            // MPS / Metal treat y=0 as the bottom of the picture. CAMetalLayer blit
            // of an unflipped bake is upright; Fast/Quality go through MPS, so the
            // bake must match that kernel or the picture lands upside down.
            let prepared =
                source
                .transformed(
                    by: CGAffineTransform(translationX: -extent.origin.x, y: -extent.origin.y)
                )
                .transformed(
                    by: CGAffineTransform(
                        scaleX: CGFloat(width) / max(extent.width, 1),
                        y: CGFloat(height) / max(extent.height, 1))
                )
                .transformed(by: CGAffineTransform(scaleX: 1, y: -1))
                .transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(height)))
            guard
                let target = renderTexture(width: width, height: height, pixelFormat: pixelFormat),
                let commandBuffer = commandQueue.makeCommandBuffer()
            else {
                finished()
                return
            }
            let context = unmanaged ? lutContext : displayContext
            context.render(
                prepared, to: target, commandBuffer: commandBuffer,
                bounds: CGRect(x: 0, y: 0, width: width, height: height),
                colorSpace: LiveMonitorWorkingSpace.metalDestination)
            commandBuffer.addCompletedHandler { [self] _ in
                lock.lock()
                published = (target, drawableSize, pixelFormat)
                lastBakeUnmanaged = unmanaged
                lastBakeOverlay = overlay
                lock.unlock()
                finished()
            }
            commandBuffer.commit()
        }
    }

    private func renderTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat) -> MTLTexture?
    {
        lock.lock()
        defer { lock.unlock() }
        let matches =
            textures.count == Self.depth
            && textures.allSatisfy {
                $0.width == width && $0.height == height && $0.pixelFormat == pixelFormat
            }
        if !matches {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
            descriptor.storageMode = .private
            let built = (0..<Self.depth).compactMap { _ in
                device.makeTexture(descriptor: descriptor)
            }
            guard built.count == Self.depth else { return nil }
            textures = built
            nextTexture = 0
            retained = retained.filter { key, _ in
                textures.contains { ObjectIdentifier($0) == key }
            }
        }
        for offset in 0..<textures.count {
            let index = (nextTexture + offset) % textures.count
            let texture = textures[index]
            if retained[ObjectIdentifier(texture)] == nil {
                nextTexture = index + 1
                return texture
            }
        }
        return nil
    }
}

/// Metal-backed presenter. Looks bake off-main; this view only scales into the drawable.
final class CIFeedView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    private let device: MTLDevice?
    private let lutContext: CIContext
    private let displayContext: CIContext
    private let baker: FeedFrameBaker?
    /// Presents commit here and complete on the GPU — never a synchronous render on main.
    private let presentQueue: MTLCommandQueue?
    private let presentScaler: FeedPresentScaler?
    /// First successful present. Until then the VT layer must stay visible —
    /// this view is opaque black and `display` returns before the bake lands.
    private(set) var hasPresentedFrame = false

    override init(frame: CGRect) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        let lutOptions = LiveMonitorWorkingSpace.contextOptions
        let displayOptions = LiveMonitorWorkingSpace.displayContextOptions
        self.lutContext =
            device.map { CIContext(mtlDevice: $0, options: lutOptions) }
            ?? CIContext(options: lutOptions)
        self.displayContext =
            device.map { CIContext(mtlDevice: $0, options: displayOptions) }
            ?? CIContext(options: displayOptions)
        self.baker = device.map { FeedFrameBaker(device: $0) }
        self.presentQueue = device?.makeCommandQueue()
        self.presentScaler = device.map { FeedPresentScaler(device: $0) }
        super.init(frame: frame)
        isOpaque = true
        isHidden = true
        backgroundColor = .black
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.contentsScale = UIScreen.main.scale
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scale = window?.screen.scale ?? UIScreen.main.scale
        let size = bounds.size
        if size.width > 1, size.height > 1 {
            let next = CGSize(width: size.width * scale, height: size.height * scale)
            if metalLayer.drawableSize != next {
                metalLayer.drawableSize = next
            }
        }
    }

    func setOverlayChrome(_ overlay: Bool) {
        isOpaque = !overlay
        backgroundColor = overlay ? .clear : .black
        metalLayer.isOpaque = !overlay
    }

    @discardableResult
    func display(_ image: CIImage, unmanaged: Bool = true, overlay: Bool = false) -> Bool {
        setOverlayChrome(overlay)
        let size = metalLayer.drawableSize
        guard size.width > 1, size.height > 1 else { return false }
        guard image.extent.width > 1, image.extent.height > 1 else { return false }
        if let baker {
            baker.scheduleBake(
                image: image, drawableSize: size, pixelFormat: metalLayer.pixelFormat,
                unmanaged: unmanaged, overlay: overlay
            ) { [weak self] in
                DispatchQueue.main.async { self?.presentLatestBake() }
            }
            return true
        }
        return presentSynchronously(image, unmanaged: unmanaged, overlay: overlay)
    }

    /// One command buffer per present, committed without waiting on main. OpenZCine flips
    /// Y when *baking* a texture it then **blits**; this baker renders in drawable
    /// orientation already, so a texel-for-texel copy stays upright — the old path
    /// re-wrapped the bake as `CIImage(mtlTexture:)` and rendered it a second time
    /// (two cancelling origin flips) with `commandBuffer: nil`, a synchronous GPU
    /// submit on main plus a freshly allocated full-extent black composite every frame.
    private func presentLatestBake() {
        let size = metalLayer.drawableSize
        guard let baker,
            let baked = baker.bakedTexture(for: size, pixelFormat: metalLayer.pixelFormat)
        else { return }
        guard let queue = presentQueue,
            let drawable = metalLayer.nextDrawable(),
            let commandBuffer = queue.makeCommandBuffer(),
            encodePresent(baked, to: drawable.texture, commandBuffer: commandBuffer)
        else {
            baker.releaseBakedTexture(baked)
            return
        }
        commandBuffer.addCompletedHandler { _ in
            // The pool slot stays reserved until the GPU has read it.
            baker.releaseBakedTexture(baked)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        hasPresentedFrame = true
        // Overlay only: identity stays on the HEVC / VT layer. Unhiding an
        // opaque identity bake here is a black plate over a working picture.
        if baker.lastBakeOverlay {
            isHidden = false
        }
    }

    /// Bake is source-sized (`bakeSize` never enlarges). Off / Fast / Quality / AI enlarge
    /// it to the drawable the same way OpenZCine `MetalLiveView` does.
    private func encodePresent(
        _ baked: MTLTexture, to target: MTLTexture, commandBuffer: MTLCommandBuffer
    ) -> Bool {
        let overlay = baker?.lastBakeOverlay ?? false
        if let presentScaler,
            presentScaler.encode(
                from: baked, to: target, commandBuffer: commandBuffer, overlay: overlay)
        {
            return true
        }
        if baked.pixelFormat == target.pixelFormat,
            baked.width <= target.width, baked.height <= target.height,
            baked.width == target.width || baked.height == target.height
        {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = target
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(
                red: 0, green: 0, blue: 0, alpha: overlay ? 0 : 1)
            guard let clear = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
            else { return false }
            clear.endEncoding()
            guard let blit = commandBuffer.makeBlitCommandEncoder() else { return false }
            blit.copy(
                from: baked, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: baked.width, height: baked.height, depth: 1),
                to: target, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: MTLOrigin(
                    x: (target.width - baked.width) / 2,
                    y: (target.height - baked.height) / 2,
                    z: 0))
            blit.endEncoding()
            return true
        }
        let unmanaged = baker?.lastBakeUnmanaged ?? true
        let options =
            unmanaged
            ? LiveMonitorWorkingSpace.imageOptions
            : LiveMonitorWorkingSpace.displayImageOptions
        guard let image = CIImage(mtlTexture: baked, options: options) else { return false }
        let dest = CGRect(
            origin: .zero, size: CGSize(width: target.width, height: target.height))
        let fitted = Self.aspectFit(image, in: dest)
        let backdrop = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: overlay ? 0 : 1))
            .cropped(to: dest)
        let context = unmanaged ? lutContext : displayContext
        context.render(
            fitted.composited(over: backdrop), to: target, commandBuffer: commandBuffer,
            bounds: dest, colorSpace: LiveMonitorWorkingSpace.metalDestination)
        return true
    }

    @discardableResult
    private func presentSynchronously(_ image: CIImage, unmanaged: Bool, overlay: Bool) -> Bool {
        guard let drawable = metalLayer.nextDrawable() else { return false }
        let dest = CGRect(
            origin: .zero,
            size: CGSize(width: drawable.texture.width, height: drawable.texture.height))
        let fitted = Self.aspectFit(image, in: dest)
        let backdrop = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: overlay ? 0 : 1))
            .cropped(to: dest)
        let context = unmanaged ? lutContext : displayContext
        context.render(
            fitted.composited(over: backdrop), to: drawable.texture, commandBuffer: nil,
            bounds: dest, colorSpace: LiveMonitorWorkingSpace.metalDestination)
        drawable.present()
        return true
    }

    private static func aspectFit(_ image: CIImage, in dest: CGRect) -> CIImage {
        let src = image.extent
        guard src.width > 0, src.height > 0 else { return image }
        let scale = min(dest.width / src.width, dest.height / src.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let e = scaled.extent
        let dx = dest.midX - e.midX
        let dy = dest.midY - e.midY
        return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy))
    }
}
