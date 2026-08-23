import OpenPocketViewCore
import SwiftUI

/// OpenZCine `ScopePalette` — additive trace colours shared by WAVE / PARADE / HISTO / VECTOR.
enum ScopePalette {
    struct TraceColor {
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        var color: Color {
            Color(red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha)
        }
    }

    static func rgba(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> Color {
        Color(red: r / 255, green: g / 255, blue: b / 255, opacity: a)
    }

    static func trace(_ r: Double, _ g: Double, _ b: Double, _ a: Double) -> TraceColor {
        TraceColor(red: r, green: g, blue: b, alpha: a)
    }

    static let lumaGhost = trace(182, 190, 186, 0.08)
    static let luma = trace(222, 230, 224, 1.0)
    static let lumaHot = trace(255, 255, 255, 1.0)
    /// RGB overlay waveform — mid alpha so coincident channels add toward white.
    static let overlayRed = trace(255, 64, 54, 0.55)
    static let overlayGreen = trace(70, 240, 110, 0.55)
    static let overlayBlue = trace(72, 148, 255, 0.62)
    static let paradeRed = trace(255, 86, 78, 1.0)
    static let paradeGreen = trace(102, 232, 132, 1.0)
    static let paradeBlue = trace(92, 156, 255, 1.0)
    static let boundary = rgba(220, 235, 225, 0.8)
    static let clip = rgba(255, 150, 142, 0.8)
    static let middle = rgba(246, 241, 226, 0.8)
    /// Faint anchored-scale grid (25 / 50 / 75 lines).
    static let grid = rgba(220, 235, 225, 0.10)
    static let histogramRedFill = rgba(255, 48, 44, 0.17)
    static let histogramGreenFill = rgba(0, 238, 70, 0.15)
    static let histogramBlueFill = rgba(45, 76, 255, 0.19)
    static let panelFill = Color(red: 0.025, green: 0.036, blue: 0.03).opacity(0.72)
}

/// Landscape and portrait keep independent stored centres.
enum ScopeCanvasSlot: String, Sendable {
    case landscape
    case portrait

    static func forBounds(_ bounds: CGRect) -> Self {
        bounds.height > bounds.width ? .portrait : .landscape
    }

    static func pick<T>(_ landscape: T?, _ portrait: T?, in bounds: CGRect) -> T? {
        switch forBounds(bounds) {
        case .portrait: portrait
        case .landscape: landscape
        }
    }

    static func assign<T>(
        _ landscape: inout T?, _ portrait: inout T?, in bounds: CGRect, _ value: T?
    ) {
        switch forBounds(bounds) {
        case .portrait: portrait = value
        case .landscape: landscape = value
        }
    }
}

enum ScopePanelSize {
    static let waveform = CGSize(width: 250, height: 153)
    static let parade = CGSize(width: 250, height: 153)
    static let histogram = CGSize(width: 250, height: 77)
    static let vectorscope = CGSize(width: 190, height: 190)
    static let trafficLights = CGSize(width: 74, height: 168)
}

/// Display level from `ScopeDisplayScale` → y inside `rect`.
///
/// Legacy 4% top/bottom stretch (`crushLevel`…`clipLevel`). WAVE / PARADE /
/// HISTO use ``WaveformAxis`` instead. LIGHTS still sits on this scale.
func scopeLevelY(_ level: Double, _ rect: CGRect) -> CGFloat {
    let lo = ScopeDisplayScale.crushLevel
    let hi = ScopeDisplayScale.clipLevel
    let t = (level - lo) / (hi - lo)
    return rect.maxY - CGFloat(0.04 + t * 0.92) * rect.height
}

/// WAVE plot: same IRE numbers as traffic lights / ``ScopeDisplayScale.monitorPercent``.
/// 0 = paper black, 100 = live-tap EI ceiling, 18% gray stays at paper IRE
/// (D-Log2 = 30.50) — not remapped to 50. The plot uses the full panel under
/// the title so 0 / 100 sit on the min / max edges (the old 8pt chrome pad
/// was the ~5% empty band under the floor).
enum WaveformAxis {
    /// 1pt so the 0 / 100 strokes sit inside the rounded clip.
    static let plotInset: CGFloat = 1
    static let titleHeight: CGFloat = 26
    /// Tight floor — just enough that the 0 stroke is not clipped.
    static let bottomPad: CGFloat = 2
    static let sidePad: CGFloat = 6
    /// Dotted safe-border guides, 5 IRE in from 0 and 100.
    static let bufferIRE = 5.0
    /// Finger jitter that still counts as “hold for options”, not a drag.
    static let optionsDragSlop: CGFloat = 8
    static let crushClipDash: [CGFloat] = [3, 3]

    static func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: sidePad,
            y: titleHeight,
            width: size.width - sidePad * 2,
            height: max(1, size.height - titleHeight - bottomPad))
    }

    /// 0 = paper black, 1 = live-tap clip. Never goes through
    /// ``ScopeDisplayScale.crushLevel`` (that 0.05 is the leftover 5% shelf).
    static func unit(
        _ encoded: Double, transfer: MonitorTransfer, iso: Int? = nil
    ) -> Double {
        ire(encoded, transfer: transfer, iso: iso) / 100.0
    }

    /// IRE 0…100. Paper black is 0, clip is 100, 18% gray is paper IRE.
    static func ire(
        _ encoded: Double, transfer: MonitorTransfer, iso: Int? = nil
    ) -> Double {
        let a = ScopeAnchors.make(transfer: transfer, iso: iso)
        // Byte-round paper black (D-Log2 15.95 → 16) must sit on 0, not 0.02 IRE.
        let blackByte = (a.black * 255).rounded()
        if !encoded.isFinite || encoded * 255 <= blackByte { return 0 }
        if encoded >= a.clip { return 100 }
        let midIRE = LiveColorScience.paperIRE(a.mid)
        if a.mid <= a.black || a.clip <= a.mid {
            return (encoded - a.black) / max(a.clip - a.black, 1e-9) * 100
        }
        if encoded <= a.mid {
            return (encoded - a.black) / (a.mid - a.black) * midIRE
        }
        return midIRE + (encoded - a.mid) / (a.clip - a.mid) * (100 - midIRE)
    }

    /// `ire` is 0…100 (not a 0…1 unit). Passing `crushLevel` 0.05 lands on
    /// the 0 line, not 5% up the plot.
    static func plotY(_ ire: Double, _ rect: CGRect) -> CGFloat {
        let inset = plotInset
        let span = rect.height - 2 * inset
        return rect.maxY - inset - CGFloat(ire / 100.0) * span
    }

    /// Left-to-right twin of ``plotY`` — IRE 0 / 100 sit on the plot edges.
    static func plotX(_ ire: Double, _ rect: CGRect) -> CGFloat {
        let inset = plotInset
        let span = rect.width - 2 * inset
        return rect.minX + inset + CGFloat(ire / 100.0) * span
    }

    /// Native-code histogram counts onto the WAVE IRE axis. Paper black is
    /// bucket 0, live-tap clip is bucket 255. Conserves total count.
    static func remapHistogram(
        _ bins: [Int], transfer: MonitorTransfer, iso: Int? = nil
    ) -> [Int] {
        var out = [Int](repeating: 0, count: 256)
        let table = levelTable(for: transfer, iso: iso)
        for code in 0..<min(bins.count, 256) where bins[code] != 0 {
            let bucket = Int((Double(table[code]) / 100.0 * 255).rounded())
            out[min(255, max(0, bucket))] += bins[code]
        }
        return out
    }

    static func scaleLineY(_ scaleIRE: Double, _ rect: CGRect) -> CGFloat {
        plotY(scaleIRE, rect)
    }

    static func traceY(
        _ byte: UInt8, transfer: MonitorTransfer, iso: Int? = nil, _ rect: CGRect
    ) -> CGFloat {
        plotY(ire(Double(byte) / 255.0, transfer: transfer, iso: iso), rect)
    }

    static func middleGrayIRE(transfer: MonitorTransfer) -> Double {
        transfer.middleGrayPaperIRE
    }

    /// Metal `trace_v` centres a point at `position + size/2`. Offset so the
    /// visual centre lands on the guide, not a half-pixel above it.
    static func vertexPositionY(ire: Double, pointSize: Float, rect: CGRect) -> Float {
        Float(plotY(ire, rect)) - pointSize * 0.5
    }

    /// Visual centre after the Metal `position + size/2` offset.
    static func visualCenterY(ire: Double, pointSize: Float, rect: CGRect) -> Float {
        vertexPositionY(ire: ire, pointSize: pointSize, rect: rect) + pointSize * 0.5
    }

    /// Paper / legal-black code this transfer's tap emits (`encode(0)`).
    static func legalBlackByte(transfer: MonitorTransfer) -> UInt8 {
        UInt8((ScopeAnchors.make(transfer: transfer).black * 255).rounded())
    }

    /// 256 IRE values (0…100). Paper black is 0, not 0.05.
    static func levelTable(for transfer: MonitorTransfer, iso: Int? = nil) -> [Float] {
        let ei = iso ?? ScopeExposureCeiling.resolvedISO()
        return (0...255).map { Float(ire(Double($0) / 255.0, transfer: transfer, iso: ei)) }
    }

    struct GuideStroke: Equatable {
        var ire: Double
        var dashed: Bool
        var usesCrushClipColor: Bool
    }

    /// Solid 0 / 100 on the plot edges. Optional dotted 5 / 95 safe borders.
    /// Middle gray is the log paper IRE, not 50.
    static func guideStrokes(
        clip: Bool, crush: Bool, middle: Bool, transfer: MonitorTransfer
    ) -> [GuideStroke] {
        var strokes = [
            GuideStroke(ire: 0, dashed: false, usesCrushClipColor: false),
            GuideStroke(ire: 100, dashed: false, usesCrushClipColor: false),
        ]
        if crush {
            strokes.append(
                GuideStroke(ire: bufferIRE, dashed: true, usesCrushClipColor: true))
        }
        if clip {
            strokes.append(
                GuideStroke(ire: 100 - bufferIRE, dashed: true, usesCrushClipColor: true))
        }
        if middle {
            strokes.append(
                GuideStroke(
                    ire: middleGrayIRE(transfer: transfer), dashed: false,
                    usesCrushClipColor: false))
        }
        return strokes
    }

    static func shouldPresentOptions(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) <= optionsDragSlop
    }
}

/// Y of a 0…100 scale line (crush/clip anchors after the stretch).
func scopeScaleLineY(_ scaleIRE: Double, _ rect: CGRect) -> CGFloat {
    scopeLevelY(ScopeDisplayScale.level(scaleIRE: scaleIRE), rect)
}

/// WAVE / PARADE tick Y for one native tap byte (`byte/255` = encoded curve
/// fraction) — placed through the transfer's anchored level table. Hot loops
/// hoist `ScopeDisplayScale.levelTable(for:)` once and call ``scopeLevelY``.
func scopeTraceLevelY(_ byte: UInt8, transfer: MonitorTransfer = .rec709, _ rect: CGRect) -> CGFloat
{
    scopeLevelY(Double(ScopeDisplayScale.levelTable(for: transfer)[Int(byte)]), rect)
}

func scopePlotRect(_ size: CGSize, top: CGFloat) -> CGRect {
    CGRect(x: 6, y: top, width: size.width - 12, height: size.height - top - 8)
}

/// OpenZCine `ScopeMini` vectorscope square — centred in `scopePlotRect(..., top: 26)`.
func vectorscopePlotSquare(in size: CGSize) -> CGRect {
    let plot = scopePlotRect(size, top: 26)
    let side = min(plot.width, plot.height)
    return CGRect(
        x: plot.midX - side / 2, y: plot.midY - side / 2, width: side, height: side)
}

/// Full plot plus 2pt so origin-anchored 1–2px ticks on the 0 / 100 lines
/// are not scissored off the line (OpenZCine Metal has no scissor).
func scopeTraceClipRect(_ plot: CGRect) -> CGRect {
    plot.insetBy(dx: 0, dy: -2)
}

extension MonitorTransfer {
    /// Scope panel chip label (OpenZCine `ScopeMini` chrome).
    var scopeChip: String {
        switch self {
        case .rec709: "709"
        case .hdr: "HLG"
        case .dlog: "DLOG"
        case .dlog2: "DL2"
        }
    }
}

/// BT.709 chroma used by BOTH the vectorscope trace binning and the graticule
/// targets — one function so plot and targets can never disagree.
/// OpenZCine `VectorscopeSampler.chroma` / `VectorscopeColor.traceTint`.
enum ScopeChroma {
    static func rec709(red: Double, green: Double, blue: Double) -> (cb: Double, cr: Double) {
        let y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return ((blue - y) / 1.8556, (red - y) / 1.5748)
    }

    static func rec709(red: UInt8, green: UInt8, blue: UInt8) -> (cb: Double, cr: Double) {
        rec709(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }

    /// OpenZCine `VectorscopeColor.traceTint` — neutrals become white; saturated
    /// bins keep hue while the strongest channel rides full ramp brightness.
    static func traceTint(
        red: Double, green: Double, blue: Double
    ) -> (red: Double, green: Double, blue: Double) {
        let low = min(red, green, blue)
        let high = max(red, green, blue)
        let span = high - low
        guard high > 0.000_001, span > 0.000_001 else {
            return (1, 1, 1)
        }
        let saturation = min(1, max(0, span / high))
        func tint(_ component: Double) -> Double {
            let pure = (component - low) / span
            return (1 - saturation) + pure * saturation
        }
        return (tint(red), tint(green), tint(blue))
    }
}

/// OpenZCine `drawVectorscopeGraticule` constants — outer ring, crosshair,
/// I-phase skin line at 123°, six 75% SMPTE boxes. Always on (no popup toggle).
enum VectorscopeGraticule {
    static let skinAngleDegrees = 123.0
    static let skinLength = 0.92
    static let boxSide: CGFloat = 7
    static let labelPush: CGFloat = 10
    static let crossArm: CGFloat = 8
    static let ring = ScopePalette.rgba(220, 235, 225, 0.55)
    static let faint = ScopePalette.rgba(220, 235, 225, 0.30)
    static let box = ScopePalette.rgba(220, 235, 225, 0.6)
    static let label = ScopePalette.rgba(220, 235, 225, 0.55)
    /// 75% bars: 191 = 0.75 × 255. Same codes OpenZCine feeds `VectorscopeSampler.chroma`.
    static let targets: [(label: String, red: UInt8, green: UInt8, blue: UInt8)] = [
        ("R", 191, 0, 0), ("Mg", 191, 0, 191), ("B", 0, 0, 191),
        ("Cy", 0, 191, 191), ("G", 0, 191, 0), ("Yl", 191, 191, 0),
    ]

    static var skinAngleRadians: Double { skinAngleDegrees * .pi / 180 }

    static func skinEnd(in rect: CGRect) -> CGPoint {
        let radius = rect.width / 2
        let angle = skinAngleRadians
        return CGPoint(
            x: rect.midX + CGFloat(cos(angle)) * radius * skinLength,
            y: rect.midY - CGFloat(sin(angle)) * radius * skinLength)
    }

    static func targetCenter(
        red: UInt8, green: UInt8, blue: UInt8, in rect: CGRect
    ) -> CGPoint {
        let chroma = ScopeChroma.rec709(red: red, green: green, blue: blue)
        return CGPoint(
            x: rect.midX + CGFloat(chroma.cb) * rect.width,
            y: rect.midY - CGFloat(chroma.cr) * rect.height)
    }
}

// MARK: - WAVE

struct WaveformOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let assist = model.frameSamples.displayBundle
        let options = WaveformAssist.store.options
        let size = WaveformAssist.panelSize(scale: options.scale)
        let intensity = WaveformAssist.intensity(options.brightness)
        // Transfer rides the bundle — reading session.status here re-rendered
        // every scope on 5 Hz telemetry pushes (DESIGN §2.3).
        let transfer = assist.transfer
        let plot = ScopeMiniChrome(
            title: "Wave", chip: options.mode.rawValue.uppercased(),
            size: size
        ) {
            // Traces first; 0 / 100 and the dotted 5 / 95 buffers sit on top.
            ZStack(alignment: .topLeading) {
                if ScopeTraceMetal.isAvailable {
                    let plot = WaveformAxis.plotRect(in: size)
                    ScopeTraceMetalView(
                        samples: assist.samples, trail: assist.trailSamples,
                        mode: .waveform(options.mode), transfer: transfer,
                        revision: assist.revision, opacity: intensity,
                        layoutSize: plot.size
                    )
                    .frame(width: plot.width, height: plot.height)
                    .offset(x: plot.minX, y: plot.minY)
                } else {
                    WaveformScopePlot(
                        samples: assist.samples, trail: assist.trailSamples,
                        mode: options.mode, transfer: transfer, opacity: intensity
                    )
                    .frame(width: size.width, height: size.height)
                }
                WaveformGuideOverlay(
                    clip: options.guides.clip, crush: options.guides.crush,
                    middle: options.guides.middle, transfer: transfer
                )
                .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityLabel(options.mode == .rgb ? "RGB waveform" : "Luma waveform")
        if canvas.width > 1, canvas.height > 1 {
            WaveformAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance,
                onOpenOptions: { frame in
                    WaveformAssist.presentOptions(anchor: frame, assist: model.assist)
                }
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

private struct WaveformScopePlot: View, Equatable {
    var samples: ScopeSamples
    var trail: ScopeSamples = .empty
    var mode: WaveformAssist.Mode = .rgb
    var transfer: MonitorTransfer = .rec709
    var opacity: Double = 1

    var body: some View {
        Canvas { context, size in
            let rect = WaveformAxis.plotRect(in: size)
            let table = WaveformAxis.levelTable(for: transfer)
            var traces = context
            traces.clip(to: Path(scopeTraceClipRect(rect)))
            drawTrace(
                trail.points, rect: rect, table: table, context: traces,
                opacity: opacity * ScopeTraceMetal.trailDecay)
            drawTrace(
                samples.points, rect: rect, table: table, context: traces, opacity: opacity)
        }
    }

    private func drawTrace(
        _ points: [ScopePoint], rect: CGRect, table: [Float],
        context: GraphicsContext, opacity: Double
    ) {
        guard !points.isEmpty, opacity > 0 else { return }
        var ctx = context
        ctx.opacity = opacity
        ctx.blendMode = .plusLighter
        func y(_ byte: UInt8) -> CGFloat { WaveformAxis.plotY(Double(table[Int(byte)]), rect) }
        switch mode {
        case .luma:
            for (index, point) in points.enumerated() {
                let x = rect.minX + CGFloat(point.xRatio) * rect.width
                let tickY = y(point.luma)
                ctx.fill(
                    Path(CGRect(x: x, y: tickY - 1, width: 2, height: 2)),
                    with: .color(ScopePalette.lumaGhost.color))
                ctx.fill(
                    Path(CGRect(x: x, y: tickY - 0.5, width: 1, height: 1)),
                    with: .color(ScopePalette.luma.color))
                if index % 4 == 0 {
                    ctx.fill(
                        Path(CGRect(x: x, y: tickY - 0.5, width: 1, height: 1)),
                        with: .color(ScopePalette.lumaHot.color))
                }
            }
        case .rgb:
            let channels: [(Color, (ScopePoint) -> UInt8)] = [
                (ScopePalette.overlayRed.color, { $0.red }),
                (ScopePalette.overlayGreen.color, { $0.green }),
                (ScopePalette.overlayBlue.color, { $0.blue }),
            ]
            for point in points {
                let x = rect.minX + CGFloat(point.xRatio) * rect.width
                for channel in channels {
                    ctx.fill(
                        Path(CGRect(x: x, y: y(channel.1(point)) - 0.5, width: 1, height: 1)),
                        with: .color(channel.0))
                }
            }
        }
    }
}

/// Solid 0 / 100 on the plot edges. Dotted 5 / 95 safe borders. Solid middle
/// gray at the log paper IRE (not 50).
private struct WaveformGuideOverlay: View {
    var clip = true
    var crush = true
    var middle = true
    var transfer: MonitorTransfer = .rec709

    var body: some View {
        Canvas { context, size in
            let rect = WaveformAxis.plotRect(in: size)
            func line(_ y: CGFloat, _ color: Color, _ style: StrokeStyle) {
                var path = Path()
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
                context.stroke(path, with: .color(color), style: style)
            }
            let grayIRE = WaveformAxis.middleGrayIRE(transfer: transfer)
            for stroke in WaveformAxis.guideStrokes(
                clip: clip, crush: crush, middle: middle, transfer: transfer)
            {
                let y = WaveformAxis.scaleLineY(stroke.ire, rect)
                let isGray = abs(stroke.ire - grayIRE) < 0.05
                let color: Color =
                    stroke.usesCrushClipColor
                    ? ScopePalette.clip
                    : (isGray ? ScopePalette.middle : ScopePalette.boundary)
                let style =
                    stroke.dashed
                    ? StrokeStyle(lineWidth: 1.25, dash: WaveformAxis.crushClipDash)
                    : StrokeStyle(lineWidth: isGray ? 1 : 1.25)
                line(y, color, style)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - PARADE

struct ParadeOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let assist = model.frameSamples.displayBundle
        let transfer = assist.transfer
        let options = ParadeAssist.store.options
        let size = ParadeAssist.panelSize(scale: options.scale)
        let intensity = ParadeAssist.intensity(options.brightness)
        let plot = ScopeMiniChrome(
            title: "Parade",
            chip: ParadeAssist.chip(options.mode),
            size: size
        ) {
            ZStack(alignment: .topLeading) {
                if ScopeTraceMetal.isAvailable {
                    let plotRect = WaveformAxis.plotRect(in: size)
                    ScopeTraceMetalView(
                        samples: assist.samples, trail: assist.trailSamples,
                        mode: .parade(options.mode), transfer: transfer,
                        revision: assist.revision, opacity: intensity,
                        layoutSize: plotRect.size
                    )
                    .frame(width: plotRect.width, height: plotRect.height)
                    .offset(x: plotRect.minX, y: plotRect.minY)
                } else {
                    ParadeScopePlot(
                        samples: assist.samples, trail: assist.trailSamples,
                        mode: options.mode, transfer: transfer, opacity: intensity
                    )
                    .frame(width: size.width, height: size.height)
                }
                WaveformGuideOverlay(
                    clip: options.guides.clip, crush: options.guides.crush,
                    middle: options.guides.middle, transfer: transfer
                )
                .frame(width: size.width, height: size.height)
            }
        }
        .accessibilityLabel(ParadeAssist.accessibilityLabel(options.mode))
        if canvas.width > 1, canvas.height > 1 {
            ParadeAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

private struct ParadeScopePlot: View, Equatable {
    var samples: ScopeSamples
    var trail: ScopeSamples = .empty
    var mode: ParadeAssist.Mode = .rgb
    var transfer: MonitorTransfer = .rec709
    var opacity: Double = 1

    var body: some View {
        Canvas { context, size in
            let rect = WaveformAxis.plotRect(in: size)
            let table = WaveformAxis.levelTable(for: transfer)
            var traces = context
            traces.clip(to: Path(scopeTraceClipRect(rect)))
            drawLanes(
                trail.points, rect: rect, table: table, context: traces,
                opacity: opacity * ScopeTraceMetal.trailDecay)
            drawLanes(
                samples.points, rect: rect, table: table, context: traces, opacity: opacity)
        }
    }

    private func drawLanes(
        _ points: [ScopePoint], rect: CGRect, table: [Float],
        context: GraphicsContext, opacity: Double
    ) {
        guard !points.isEmpty, opacity > 0 else { return }
        let lumaLane: [(Color, (ScopePoint) -> UInt8)] =
            mode == .yrgb ? [(ScopePalette.luma.color, { $0.luma })] : []
        let lanes: [(Color, (ScopePoint) -> UInt8)] =
            lumaLane + [
                (ScopePalette.paradeRed.color, { $0.red }),
                (ScopePalette.paradeGreen.color, { $0.green }),
                (ScopePalette.paradeBlue.color, { $0.blue }),
            ]
        var ctx = context
        ctx.opacity = opacity
        ctx.blendMode = .plusLighter
        for (index, lane) in lanes.enumerated() {
            for point in points {
                let x = ParadeAssist.laneX(
                    xRatio: point.xRatio, lane: index, mode: mode, plot: rect)
                let y = WaveformAxis.plotY(Double(table[Int(lane.1(point))]), rect)
                ctx.fill(
                    Path(CGRect(x: x, y: y - 0.5, width: 1, height: 1)),
                    with: .color(lane.0))
            }
        }
    }
}

// MARK: - HISTO

struct HistogramOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let assist = model.frameSamples.displayBundle
        let options = HistogramAssist.store.options
        let size = HistogramAssist.panelSize(scale: options.scale)
        let plot = ScopeMiniChrome(
            title: HistogramAssist.panelTitle, chip: HistogramAssist.chip,
            size: size
        ) {
            // Draw-only body: curves arrive remapped / blended / smoothed and
            // the traffic reading pre-metered (DESIGN §3.2) — no math on main.
            HistogramScopePlot(
                display: assist.histogramDisplay,
                traffic: assist.traffic,
                showTrafficLights: options.trafficLights)
        }
        .accessibilityLabel("RGB histogram, scale 0 to 100")
        if canvas.width > 1, canvas.height > 1 {
            HistogramAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

private struct HistogramScopePlot: View, Equatable {
    var display: ScopeHistogramDisplay
    var traffic: ScopeTrafficLightsReading = .none
    var showTrafficLights = true

    var body: some View {
        ZStack {
            Canvas { context, size in
                let rect = HistogramAssist.plotRect(in: size)
                // One shared peak so channel heights stay comparable (floor 1).
                let peak = max(
                    display.red.max() ?? 0, display.green.max() ?? 0,
                    display.blue.max() ?? 0, display.luma.max() ?? 0, 1)
                drawHistogramReferenceGrid(in: context, rect: rect)
                if showTrafficLights, traffic.anyClip {
                    let clipStart = HistogramAssist.ireX(HistogramAssist.clipZoneIRE, in: rect)
                    let clipEnd = HistogramAssist.ireX(100, in: rect)
                    context.fill(
                        Path(
                            CGRect(
                                x: clipStart, y: rect.minY,
                                width: max(0, clipEnd - clipStart), height: rect.height)),
                        with: .color(ScopePalette.clip.opacity(0.14)))
                }
                // Traces first, clipped to 0…100; min/max strokes sit on top.
                var signal = context
                signal.clip(to: Path(histogramSignalRect(in: rect)))
                var additive = signal
                additive.opacity = 0.92
                additive.blendMode = .plusLighter
                drawHistogramChannel(
                    in: additive, bins: display.red, rect: rect, peak: peak,
                    fill: ScopePalette.histogramRedFill,
                    stroke: ScopePalette.rgba(255, 48, 44, 0.96))
                drawHistogramChannel(
                    in: additive, bins: display.green, rect: rect, peak: peak,
                    fill: ScopePalette.histogramGreenFill,
                    stroke: ScopePalette.rgba(0, 238, 70, 0.92))
                drawHistogramChannel(
                    in: additive, bins: display.blue, rect: rect, peak: peak,
                    fill: ScopePalette.histogramBlueFill,
                    stroke: ScopePalette.rgba(45, 76, 255, 0.94))
                var lumaContext = signal
                lumaContext.opacity = 0.58
                drawHistogramLumaStroke(
                    in: lumaContext, bins: display.luma, rect: rect, peak: peak,
                    stroke: ScopePalette.rgba(245, 242, 232, 0.58))
                drawHistogramBoundaries(in: context, rect: rect)
            }
            if showTrafficLights {
                HStack {
                    trafficColumn(
                        red: traffic.red.crush, green: traffic.green.crush,
                        blue: traffic.blue.crush)
                    Spacer()
                    trafficColumn(
                        red: traffic.red.clip, green: traffic.green.clip,
                        blue: traffic.blue.clip)
                }
                .padding(.horizontal, HistogramAssist.trafficHorizontalInset)
                .padding(.top, 12)
            }
        }
    }

    private func trafficColumn(red: Bool, green: Bool, blue: Bool) -> some View {
        VStack(spacing: 3) {
            trafficBlock(ScopePalette.rgba(255, 92, 82, 1), hot: red)
            trafficBlock(ScopePalette.rgba(86, 235, 132, 1), hot: green)
            trafficBlock(ScopePalette.rgba(96, 158, 255, 1), hot: blue)
        }
    }

    private func trafficBlock(_ color: Color, hot: Bool) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(hot ? color : Color.clear)
            .frame(
                width: HistogramAssist.trafficLampWidth,
                height: HistogramAssist.trafficLampHeight
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(color.opacity(hot ? 1 : 0.8), lineWidth: 1.5)
            )
            .shadow(color: hot ? color.opacity(0.45) : .clear, radius: hot ? 5 : 0)
            .animation(.easeOut(duration: 0.15), value: hot)
    }
}

// MARK: - VECTOR

struct VectorscopeOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let assist = model.frameSamples.displayBundle
        let options = VectorscopeAssist.store.options
        let plot = ScopeMiniChrome(
            title: "Vector",
            chip: VectorscopeAssist.chip(zoom: options.zoom),
            size: VectorscopeAssist.panelSize(scale: options.scale)
        ) {
            ZStack {
                if ScopeTraceMetal.isAvailable {
                    Canvas { context, size in
                        drawVectorscopeGraticule(in: context, rect: vectorscopePlotSquare(in: size))
                    }
                    VectorscopeMetalView(
                        points: assist.vectorscopePoints,
                        trailPoints: assist.trailVectorscopePoints,
                        zoom: options.zoom,
                        brightness: options.brightness,
                        revision: assist.revision)
                } else {
                    VectorscopePlot(
                        points: assist.vectorscopePoints,
                        trailPoints: assist.trailVectorscopePoints,
                        zoom: options.zoom,
                        brightness: options.brightness)
                }
            }
        }
        .accessibilityLabel("Vectorscope")
        if canvas.width > 1, canvas.height > 1 {
            VectorscopeAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance
            ) {
                plot
            }
        } else {
            plot
        }
    }
}

private struct VectorscopePlot: View, Equatable {
    var points: [ScopePoint]
    var trailPoints: [ScopePoint] = []
    var zoom: VectorscopeAssist.Zoom = .x1
    var brightness: Int = VectorscopeAssist.defaultBrightness

    nonisolated static func == (lhs: VectorscopePlot, rhs: VectorscopePlot) -> Bool {
        lhs.points == rhs.points && lhs.trailPoints == rhs.trailPoints && lhs.zoom == rhs.zoom
            && lhs.brightness == rhs.brightness
    }

    var body: some View {
        Canvas { context, size in
            let rect = vectorscopePlotSquare(in: size)
            let side = rect.width
            drawVectorscopeGraticule(in: context, rect: rect)
            let intensity = VectorscopeAssist.intensity(brightness)
            if !trailPoints.isEmpty,
                let trail = VectorscopeRaster.image(
                    from: trailPoints, gain: zoom.gain, intensity: intensity)
            {
                var ghost = context
                ghost.blendMode = .plusLighter
                ghost.opacity = ScopeTraceMetal.trailDecay
                ghost.addFilter(.blur(radius: side / CGFloat(VectorscopeRaster.bins) * 1.1))
                ghost.draw(Image(decorative: trail, scale: 1), in: rect)
            }
            if let image = VectorscopeRaster.image(
                from: points, gain: zoom.gain, intensity: intensity)
            {
                // OpenZCine: soft blob ≈ one bin, then a 0.35 crisp core.
                var blur = context
                blur.blendMode = .plusLighter
                blur.addFilter(.blur(radius: side / CGFloat(VectorscopeRaster.bins) * 1.1))
                blur.draw(Image(decorative: image, scale: 1), in: rect)
                var crisp = context
                crisp.blendMode = .plusLighter
                crisp.opacity = 0.35
                crisp.draw(Image(decorative: image, scale: 1), in: rect)
            }
        }
    }
}

/// Shared CbCr density raster for VECTOR. Points are already monitor-domain
/// (through the operator LUT or the official DJI display cube) — the only math
/// here is ``ScopeChroma`` and the density ramp. One binning path feeds both
/// the Metal texture and the Canvas fallback so they can never disagree.
enum VectorscopeRaster {
    /// OpenZCine bin count — 128 EVERYWHERE (Metal and CPU fallback alike).
    static let bins = 128

    /// Storage-row CbCr bin (row 0 = most negative Cr). `nil` when gain
    /// pushes the sample off the plot — OpenZCine drops overshoot, no clamp.
    static func binIndex(
        red: UInt8, green: UInt8, blue: UInt8, gain: Double = 1
    ) -> (column: Int, row: Int)? {
        let chroma = ScopeChroma.rec709(red: red, green: green, blue: blue)
        let x = chroma.cb * gain + 0.5
        let y = chroma.cr * gain + 0.5
        guard x >= 0, x <= 1, y >= 0, y <= 1 else { return nil }
        let scale = Double(bins - 1)
        return (Int((x * scale).rounded()), Int((y * scale).rounded()))
    }

    /// OpenZCine `VectorscopeDensityRasterizer.premultipliedRGBA`: log density
    /// alpha `(0.4 + 0.6·density) × intensity`, `traceTint` colour, +Cr flipped
    /// up. `nil` when nothing lands.
    static func pixels(from points: [ScopePoint], gain: Double, intensity: Double) -> [UInt8]? {
        guard !points.isEmpty else { return nil }
        let n = bins
        var counts = [UInt32](repeating: 0, count: n * n)
        var sumRed = [UInt32](repeating: 0, count: n * n)
        var sumGreen = [UInt32](repeating: 0, count: n * n)
        var sumBlue = [UInt32](repeating: 0, count: n * n)
        for point in points {
            guard
                let bin = binIndex(
                    red: point.red, green: point.green, blue: point.blue, gain: gain)
            else { continue }
            let idx = bin.row * n + bin.column
            counts[idx] &+= 1
            sumRed[idx] &+= UInt32(point.red)
            sumGreen[idx] &+= UInt32(point.green)
            sumBlue[idx] &+= UInt32(point.blue)
        }
        let peak = counts.max() ?? 0
        guard peak > 0 else { return nil }
        let logPeak = log(1 + Double(peak))
        var pixels = [UInt8](repeating: 0, count: n * n * 4)
        for index in 0..<(n * n) where counts[index] > 0 {
            let count = Double(counts[index])
            let density = log(1 + count) / logPeak
            let alpha = min(1, max(0, (0.4 + 0.6 * density) * intensity))
            let tint = ScopeChroma.traceTint(
                red: Double(sumRed[index]) / (count * 255),
                green: Double(sumGreen[index]) / (count * 255),
                blue: Double(sumBlue[index]) / (count * 255))
            let row = n - 1 - index / n
            let column = index % n
            let offset = (row * n + column) * 4
            pixels[offset] = UInt8(255 * tint.red * alpha)
            pixels[offset + 1] = UInt8(255 * tint.green * alpha)
            pixels[offset + 2] = UInt8(255 * tint.blue * alpha)
            pixels[offset + 3] = UInt8(255 * alpha)
        }
        return pixels
    }

    /// CPU-fallback face of ``pixels(from:gain:intensity:)``.
    static func image(from points: [ScopePoint], gain: Double, intensity: Double) -> CGImage? {
        guard let pixels = pixels(from: points, gain: gain, intensity: intensity) else {
            return nil
        }
        let n = bins
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: n * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }
}

// MARK: - LIGHTS

struct TrafficLightsOverlay: View {
    @Environment(AppModel.self) private var model
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets

    var body: some View {
        let store = TrafficLightsAssist.store
        let size = TrafficLightsAssist.panelSize(scale: store.scale)
        TrafficLightsMovablePanel(
            store: store,
            size: size,
            defaultCenter: TrafficLightsAssist.defaultCenter(
                feed: feed, size: size, bounds: bounds, chromeClearance: chromeClearance),
            bounds: bounds
        ) {
            // Metered once in the sampler with the operator threshold riding
            // `LiveImageEffects.trafficThreshold` — render the bundle directly.
            TrafficLightsMeterMini(reading: model.frameSamples.bundle.traffic)
        }
    }
}

/// OpenZCine `TrafficLightsMeterMini` — RED-style RGB goal posts, clip lamps on
/// top, crush lamps on the floor, `TL` title. `fillsWidth` is the portrait
/// full-bleed stack; the landscape floating panel stays the 74-box.
private struct TrafficLightsMeterMini: View {
    let reading: ScopeTrafficLightsReading
    var fillsWidth: Bool = false

    var body: some View {
        GeometryReader { proxy in
            let uiScale = min(
                proxy.size.width / TrafficLightsAssist.baseSize.width,
                proxy.size.height / TrafficLightsAssist.baseSize.height)
            let columnWidth = TrafficLightsAssist.columnWidth(
                fillsWidth: fillsWidth, panelWidth: proxy.size.width, uiScale: uiScale)
            VStack(spacing: TrafficLightsAssist.titleSpacing * uiScale) {
                Text(TrafficLightsAssist.meterTitle)
                    .font(
                        .system(
                            size: TrafficLightsAssist.titleSize * uiScale, weight: .bold,
                            design: .monospaced)
                    )
                    .foregroundStyle(LiveDesign.text.opacity(0.58))
                    .lineLimit(1)
                HStack(alignment: .bottom, spacing: TrafficLightsAssist.columnSpacing * uiScale) {
                    goalPost(
                        color: TrafficLightsAssist.meterColor(TrafficLightsAssist.meterRedRGB),
                        channel: reading.red, uiScale: uiScale, columnWidth: columnWidth)
                    goalPost(
                        color: TrafficLightsAssist.meterColor(TrafficLightsAssist.meterGreenRGB),
                        channel: reading.green, uiScale: uiScale, columnWidth: columnWidth)
                    goalPost(
                        color: TrafficLightsAssist.meterColor(TrafficLightsAssist.meterBlueRGB),
                        channel: reading.blue, uiScale: uiScale, columnWidth: columnWidth)
                }
                .frame(maxWidth: fillsWidth ? .infinity : nil)
            }
            .padding(.horizontal, TrafficLightsAssist.panelPad * uiScale)
            .padding(.vertical, TrafficLightsAssist.panelPad * uiScale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(ScopePalette.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TrafficLightsAssist.accessibilityTitle)
        .accessibilityValue(TrafficLightsAssist.accessibilityValue(for: reading))
    }

    private func goalPost(
        color: Color, channel: ScopeChannelLight, uiScale: CGFloat, columnWidth: CGFloat
    ) -> some View {
        let columnHeight = TrafficLightsAssist.columnHeight * uiScale
        let indicatorSize = TrafficLightsAssist.indicatorSize * uiScale
        let shown = TrafficLightsAssist.channelDisplay(for: channel)
        return VStack(spacing: TrafficLightsAssist.postSpacing * uiScale) {
            trafficIndicator(
                color: color, active: channel.clip, size: indicatorSize, uiScale: uiScale)
            GeometryReader { proxy in
                let height = proxy.size.height
                let centerLineHeight = max(1, uiScale * TrafficLightsAssist.centerLineFactor)
                let halfHeight = (height - centerLineHeight) / 2
                let barHeight = halfHeight * CGFloat(shown.barFill)
                let track = RoundedRectangle(
                    cornerRadius: TrafficLightsAssist.trackCorner * uiScale, style: .continuous
                )
                .fill(LiveDesign.text.opacity(0.08))
                VStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        track
                        if shown.side == .over, barHeight > 0 {
                            goalPostFill(
                                color: color,
                                height: max(TrafficLightsAssist.minBarHeight * uiScale, barHeight),
                                uiScale: uiScale, towardClip: true)
                        }
                    }
                    .frame(height: halfHeight)
                    .clipped()
                    Rectangle()
                        .fill(LiveDesign.text.opacity(0.14))
                        .frame(height: centerLineHeight)
                    ZStack(alignment: .top) {
                        track
                        if shown.side == .under, barHeight > 0 {
                            goalPostFill(
                                color: color,
                                height: max(TrafficLightsAssist.minBarHeight * uiScale, barHeight),
                                uiScale: uiScale, towardClip: false)
                        }
                    }
                    .frame(height: halfHeight)
                    .clipped()
                }
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: TrafficLightsAssist.trackCorner * uiScale, style: .continuous)
                )
                .animation(.easeOut(duration: 0.12), value: shown.barFill)
                .animation(.easeOut(duration: 0.12), value: shown.side)
            }
            .frame(width: columnWidth, height: columnHeight)
            trafficIndicator(
                color: color, active: channel.crush, size: indicatorSize, uiScale: uiScale)
        }
        .frame(maxWidth: .infinity)
    }

    private func goalPostFill(
        color: Color, height: CGFloat, uiScale: CGFloat, towardClip: Bool
    ) -> some View {
        RoundedRectangle(
            cornerRadius: TrafficLightsAssist.trackCorner * uiScale, style: .continuous
        )
        .fill(
            LinearGradient(
                colors: [color.opacity(0.35), color.opacity(0.92)],
                startPoint: towardClip ? .bottom : .top,
                endPoint: towardClip ? .top : .bottom)
        )
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }

    private func trafficIndicator(color: Color, active: Bool, size: CGFloat, uiScale: CGFloat)
        -> some View
    {
        Circle()
            .fill(active ? color : Color.clear)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .strokeBorder(
                        color.opacity(active ? 1 : 0.75), lineWidth: max(1, 1.5 * uiScale))
            )
            .shadow(color: active ? color.opacity(0.45) : .clear, radius: active ? 4 * uiScale : 0)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

// MARK: - Chrome + drawing

private struct ScopeMiniChrome<Content: View>: View {
    let title: String
    let chip: String
    let size: CGSize
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScopePalette.panelFill
            content()
            HStack(spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.66))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Spacer(minLength: 2)
                Text(chip)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 12)
        .allowsHitTesting(false)
    }
}

private func drawHistogramReferenceGrid(in context: GraphicsContext, rect: CGRect) {
    for step in 1..<4 {
        let y = rect.minY + rect.height * CGFloat(step) / 4
        var line = Path()
        line.move(to: CGPoint(x: rect.minX, y: y))
        line.addLine(to: CGPoint(x: rect.maxX, y: y))
        context.stroke(line, with: .color(ScopePalette.rgba(220, 235, 225, 0.06)), lineWidth: 1)
    }
}

private func drawHistogramBoundaries(in context: GraphicsContext, rect: CGRect) {
    for scale in [0.0, 100.0] {
        let x = HistogramAssist.ireX(scale, in: rect)
        var line = Path()
        line.move(to: CGPoint(x: x, y: rect.minY))
        line.addLine(to: CGPoint(x: x, y: rect.maxY))
        context.stroke(line, with: .color(ScopePalette.rgba(220, 235, 225, 0.8)), lineWidth: 1.25)
    }
}

/// The WAVE 0…100 band. Traces clip here so stroke/fill cannot pass min/max.
private func histogramSignalRect(in rect: CGRect) -> CGRect {
    let x0 = HistogramAssist.ireX(0, in: rect)
    let x100 = HistogramAssist.ireX(100, in: rect)
    return CGRect(x: x0, y: rect.minY, width: max(1, x100 - x0), height: rect.height)
}

private func histogramPaths(bins: [Float], rect: CGRect, peak: Float) -> (fill: Path, stroke: Path)
{
    guard bins.count > 1, peak > 0, bins.contains(where: { $0 > 0 }) else {
        return (Path(), Path())
    }
    let last = bins.count - 1
    func point(at index: Int) -> CGPoint {
        let x = HistogramAssist.plotX(Double(index) / Double(last) * 100, in: rect)
        let height = CGFloat(bins[index] / peak) * rect.height
        return CGPoint(x: x, y: rect.maxY - height)
    }
    var fill = Path()
    fill.move(to: CGPoint(x: HistogramAssist.plotX(0, in: rect), y: rect.maxY))
    fill.addLine(to: point(at: 0))
    var stroke = Path()
    stroke.move(to: point(at: 0))
    for index in 1...last {
        let previous = point(at: index - 1)
        let current = point(at: index)
        let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
        fill.addQuadCurve(to: midpoint, control: previous)
        stroke.addQuadCurve(to: midpoint, control: previous)
    }
    fill.addLine(to: CGPoint(x: HistogramAssist.plotX(100, in: rect), y: rect.maxY))
    fill.closeSubpath()
    return (fill, stroke)
}

private func drawHistogramChannel(
    in context: GraphicsContext, bins: [Float], rect: CGRect, peak: Float, fill: Color,
    stroke: Color
) {
    let paths = histogramPaths(bins: bins, rect: rect, peak: peak)
    context.fill(paths.fill, with: .color(fill))
    context.stroke(
        paths.stroke, with: .color(stroke),
        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
}

private func drawHistogramLumaStroke(
    in context: GraphicsContext, bins: [Float], rect: CGRect, peak: Float, stroke: Color
) {
    let paths = histogramPaths(bins: bins, rect: rect, peak: peak)
    context.stroke(
        paths.stroke, with: .color(stroke),
        style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
}

/// OpenZCine `drawVectorscopeGraticule` — ring, crosshair, dashed I-phase
/// skin line, 75% boxes. Geometry lives on ``VectorscopeGraticule`` so the
/// Metal overlay and Canvas fallback cannot drift.
func drawVectorscopeGraticule(in context: GraphicsContext, rect: CGRect) {
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    context.stroke(Path(ellipseIn: rect), with: .color(VectorscopeGraticule.ring), lineWidth: 1.25)
    let arm = VectorscopeGraticule.crossArm
    var cross = Path()
    cross.move(to: CGPoint(x: centre.x - arm, y: centre.y))
    cross.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
    cross.move(to: CGPoint(x: centre.x, y: centre.y - arm))
    cross.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))
    context.stroke(cross, with: .color(VectorscopeGraticule.faint), lineWidth: 1)
    var skin = Path()
    skin.move(to: centre)
    skin.addLine(to: VectorscopeGraticule.skinEnd(in: rect))
    context.stroke(
        skin, with: .color(ScopePalette.middle), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    let boxSide = VectorscopeGraticule.boxSide
    let push = VectorscopeGraticule.labelPush
    for target in VectorscopeGraticule.targets {
        let point = VectorscopeGraticule.targetCenter(
            red: target.red, green: target.green, blue: target.blue, in: rect)
        let box = CGRect(
            x: point.x - boxSide / 2, y: point.y - boxSide / 2, width: boxSide, height: boxSide)
        context.stroke(Path(box), with: .color(VectorscopeGraticule.box), lineWidth: 1)
        let dx = point.x - centre.x
        let dy = point.y - centre.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        context.draw(
            Text(target.label)
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .foregroundStyle(VectorscopeGraticule.label),
            at: CGPoint(x: point.x + dx / length * push, y: point.y + dy / length * push))
    }
}
