import MonitorUI
import OpenPocketViewCore
import OpenCineMedia
import SwiftUI

/// Landscape and portrait keep independent stored centres.
typealias ScopeCanvasSlot = MonitorScopeCanvasSlot

typealias ScopePanelSize = MonitorScopePanelSize

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
/// (D-Log2 = 30.50) - not remapped to 50. The plot uses the full panel under
/// the title so 0 / 100 sit on the min / max edges (the old 8pt chrome pad
/// was the ~5% empty band under the floor).
typealias WaveformAxis = MonitorUI.MonitorWaveformAxis

/// Y of a 0…100 scale line (crush/clip anchors after the stretch).
func scopeScaleLineY(_ scaleIRE: Double, _ rect: CGRect) -> CGFloat {
    scopeLevelY(ScopeDisplayScale.level(scaleIRE: scaleIRE), rect)
}

/// WAVE / PARADE tick Y for one native tap byte (`byte/255` = encoded curve
/// fraction), placed through the transfer's anchored level table on the source's
/// `clipByte`. Hot loops hoist `ScopeDisplayScale.levelTable(for:clipByte:)` once and
/// call ``scopeLevelY``.
func scopeTraceLevelY(
    _ byte: UInt8, transfer: MonitorTransfer = .rec709, clipByte: Int, _ rect: CGRect
) -> CGFloat {
    scopeLevelY(
        Double(ScopeDisplayScale.levelTable(for: transfer, clipByte: clipByte)[Int(byte)]), rect)
}

func scopePlotRect(_ size: CGSize, top: CGFloat) -> CGRect {
    CGRect(x: 6, y: top, width: size.width - 12, height: size.height - top - 8)
}

/// OpenZCine `ScopeMini` vectorscope square - centred in `scopePlotRect(..., top: 26)`.
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
        case .dlogm: "DLM ≈"
        case .dlog2: "DL2"
        case .ilog: "ILOG"
        }
    }
}

// MARK: - WAVE

struct WaveformOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = WaveformAssist.store.options
        let size = MonitorScopePanelPlacement.size(
            WaveformAssist.panelSize(scale: WaveformAssist.store.presentationScale(in: canvas)),
            canvas: canvas, clearance: chromeClearance)
        let intensity = WaveformAssist.intensity(options.brightness)
        let plot = MonitorScopePanelPlate(
            title: "Wave", chip: options.mode.rawValue.uppercased(),
            size: size
        ) {
            ScopeBundleScope { assist in
                // Transfer rides the bundle - reading session.status here re-rendered
                // every scope on 5 Hz telemetry pushes (DESIGN §2.3).
                let transfer = assist.transfer
                // Traces first; 0 / 100 and the dotted 5 / 95 buffers sit on top.
                MonitorWaveformScopePlot(
                    samples: assist.samples, trail: assist.trailSamples,
                    mode: .waveform(options.mode), transfer: transfer, clipByte: assist.clipByte,
                    revision: assist.revision, intensity: intensity,
                    guides: MonitorScopeGuides(
                        clip: options.guides.clip, crush: options.guides.crush,
                        middle: options.guides.middle), size: size, configureDisplay: scopeDisplay)
            }
        }
        .accessibilityLabel(options.mode == .rgb ? "RGB waveform" : "Luma waveform")
        if canvas.width > 1, canvas.height > 1 {
            WaveformAssist.overlay(
                canvas: canvas, feed: feed, chromeClearance: chromeClearance,
                onOpenOptions: { frame in
                    WaveformAssist.presentOptions(anchor: frame, assist: model.assist)
                }, content: { plot })
        } else {
            plot
        }
    }
}

/// Solid 0 / 100 on the plot edges. Dotted 5 / 95 safe borders. Solid middle
/// gray at the log paper IRE (not 50).


// MARK: - PARADE

struct ParadeOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = ParadeAssist.store.options
        let size = MonitorScopePanelPlacement.size(
            ParadeAssist.panelSize(scale: ParadeAssist.store.presentationScale(in: canvas)),
            canvas: canvas, clearance: chromeClearance)
        let intensity = ParadeAssist.intensity(options.brightness)
        let plot = MonitorScopePanelPlate(
            title: "Parade",
            chip: ParadeAssist.chip(options.mode),
            size: size
        ) {
            ScopeBundleScope { assist in
                let transfer = assist.transfer
                MonitorWaveformScopePlot(
                    samples: assist.samples, trail: assist.trailSamples,
                    mode: .parade(options.mode), transfer: transfer, clipByte: assist.clipByte,
                    revision: assist.revision, intensity: intensity,
                    guides: MonitorScopeGuides(
                        clip: options.guides.clip, crush: options.guides.crush,
                        middle: options.guides.middle), size: size, configureDisplay: scopeDisplay)
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

// MARK: - HISTO

struct HistogramOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = HistogramAssist.store.options
        let size = MonitorScopePanelPlacement.size(
            HistogramAssist.panelSize(scale: HistogramAssist.store.presentationScale(in: canvas)),
            canvas: canvas, clearance: chromeClearance)
        let plot = MonitorScopePanelPlate(
            title: HistogramAssist.panelTitle, chip: HistogramAssist.chip,
            size: size
        ) {
            // Draw-only body: curves arrive remapped / blended / smoothed and
            // the traffic reading pre-metered (DESIGN §3.2) - no math on main.
            ScopeBundleScope { assist in
                MonitorHistogramScopePlot(
                    display: assist.histogramDisplay,
                    traffic: assist.traffic,
                    showTrafficLights: options.trafficLights)
            }
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

// MARK: - VECTOR

struct VectorscopeOverlay: View {
    @Environment(AppModel.self) private var model
    var canvas: CGRect = .zero
    var feed: CGRect = .zero
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        let options = VectorscopeAssist.store.options
        let plot = MonitorScopePanelPlate(
            title: "Vector",
            chip: VectorscopeAssist.chip(zoom: options.zoom),
            size: MonitorScopePanelPlacement.size(
                VectorscopeAssist.panelSize(
                    scale: VectorscopeAssist.store.presentationScale(in: canvas)),
                canvas: canvas, clearance: chromeClearance)
        ) {
            ScopeBundleScope { assist in
                MonitorVectorscopeScopePlot(
                    points: assist.vectorscopePoints,
                    trail: assist.trailVectorscopePoints, zoom: options.zoom,
                    brightness: options.brightness, revision: assist.revision,
                    configureDisplay: scopeDisplay)
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

// MARK: - LIGHTS

struct TrafficLightsOverlay: View {
    @Environment(AppModel.self) private var model
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets

    var body: some View {
        let store = TrafficLightsAssist.store
        let size = MonitorScopePanelPlacement.size(
            TrafficLightsAssist.panelSize(scale: store.scale),
            canvas: bounds, clearance: chromeClearance)
        TrafficLightsMovablePanel(
            store: store,
            size: size,
            defaultCenter: MonitorScopePanelCentering.defaultCenter(size: size, bounds: bounds),
            bounds: bounds,
            placementBounds: MonitorScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        ) {
            // Metered once in the sampler with the operator threshold riding
            // `LiveImageEffects.trafficThreshold` - render the bundle directly.
            ScopeBundleScope { _ in
                TrafficLightsMeterMini(reading: model.monitorSamples.bundle.traffic)
            }
        }
    }
}

/// OpenZCine `TrafficLightsMeterMini` - RED-style RGB goal posts, clip lamps on
/// top, crush lamps on the floor, `TL` title. `fillsWidth` is the portrait
/// full-bleed stack; the landscape floating panel stays the 74-box.
typealias TrafficLightsMeterMini = MonitorTrafficLightsMeter

// MARK: - Chrome + drawing

/// Reads the scope bundle in its own observation scope. Read in an overlay
/// body, every bundle (up to 25 Hz) re-evaluated the movable panel wrapper
/// (gestures, shadow, placement) around the plot as well.
private struct ScopeBundleScope<Content: View>: View {
    @Environment(AppModel.self) private var model
    @ViewBuilder let content: (ScopeAssistBundle) -> Content

    var body: some View { content(model.monitorSamples.displayBundle) }
}

/// OpenZCine `drawVectorscopeGraticule` - ring, crosshair, dashed I-phase
/// skin line, 75% boxes. Geometry lives on ``MonitorVectorscopeGraticule`` so the
/// Metal overlay and Canvas fallback cannot drift.
