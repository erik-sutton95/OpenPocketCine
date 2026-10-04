import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine histogram operator options + `MovablePanel` (id `"histo"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.histogramRows`):
/// * Traffic Lights - RGB crush/clip edge blocks
/// * Crush/Clip Compensation - 0…1 stop, shared with the goal-post meter
///
/// Plot geometry is WAVE’s `WaveformAxis` - IRE 0 / 100 on the plot edges,
/// same paper-black / live-tap clip mapping as WAVE / PARADE. Crush / clip
/// lamps sit outside those strokes. No 0 / 50 / 100 labels. On the panel:
/// 0.3s long-press then drag to reposition (4pt snap,
/// 22pt haptic grid); L-corner grip long-press-drags to scale 0.6…1.6.
/// Position persists as a normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum HistogramAssist {
    static let panelID = "histo"
    static let baseSize = ScopePanelSize.histogram
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2
    /// OpenZCine `ScopeMini` title / chip (`"Histo"` → HISTO, `"RGBL"`).
    static let panelTitle = "Histo"
    static let chip = "RGBL"
    static let plotTop: CGFloat = WaveformAxis.titleHeight
    /// OpenZCine `histogramReferenceX(95)` clip band - on WAVE’s IRE axis.
    static let clipZoneIRE = MonitorUI.MonitorHistogramGeometry.clipZoneIRE
    /// Crush / clip lamp size - must match ``HistogramScopePlot`` blocks.
    static let trafficLampWidth: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficLampWidth
    static let trafficLampHeight: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficLampHeight
    /// Inset from the panel edge so the top lamp clears the rounded corner.
    static let trafficOuterPad: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficOuterPad
    /// Gap between a lamp column and the 0 / 100 stroke.
    static let trafficLineGap: CGFloat = MonitorUI.MonitorHistogramGeometry.trafficLineGap

    static let trafficLightsTitle = "Traffic Lights"
    static let trafficLightsHelp =
        "Show small RGB edge blocks for crushed and clipped channels. Clip lights from about a third of a stop under the camera's clip, the same point zebra 100% and CineStop use."
    static let compensationTitle = "Crush/Clip Compensation"
    static let compensationHelp =
        "Stops of crush/clip tolerance before a traffic light glows. Shared with the goal-post meter."

    /// Side gutter that holds a lamp column outside the 0 / 100 strokes.
    static var trafficGutter: CGFloat {
        trafficOuterPad + trafficLampWidth + trafficLineGap
    }

    /// WAVE title / floor, with extra side chrome so crush sits left of 0
    /// and clip sits right of 100. IRE mapping inside the plot is ``WaveformAxis``.
    static func plotRect(in size: CGSize) -> CGRect {
        MonitorUI.MonitorHistogramGeometry.plotRect(in: size)
    }

    /// Left-to-right twin of ``WaveformAxis.plotY``.
    static func plotX(_ ire: Double, in rect: CGRect) -> CGFloat {
        WaveformAxis.plotX(ire, rect)
    }

    static func ireX(_ scaleIRE: Double, in rect: CGRect) -> CGFloat {
        WaveformAxis.plotX(scaleIRE, rect)
    }

    /// Panel-edge inset for the crush / clip columns (outside 0 / 100).
    static var trafficHorizontalInset: CGFloat { trafficOuterPad }

    typealias CrushClipCompensation = MonitorCrushClipCompensation

    /// OpenZCine `MovablePanelStoredCenter` - centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Options = MonitorHistogramOptions

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// Unplaced tools start at the canvas center; saved/session centers win later.
    static func defaultCenter(
        feed _: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance _: EdgeInsets = EdgeInsets(),
        gap _: CGFloat = 10
    ) -> CGPoint {
        clamp(
            CGPoint(x: bounds.midX, y: bounds.midY), size: size, bounds: bounds)
    }

    static func clamp(_ point: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        return CGPoint(
            x: min(max(bounds.minX + halfWidth, point.x), bounds.maxX - halfWidth),
            y: min(max(bounds.minY + halfHeight, point.y), bounds.maxY - halfHeight))
    }

    static func snap(_ point: CGPoint, grid: CGFloat = positionGrid) -> CGPoint {
        CGPoint(
            x: (point.x / grid).rounded() * grid,
            y: (point.y / grid).rounded() * grid)
    }

    static func hapticCell(_ point: CGPoint, grid: CGFloat = hapticGrid) -> Int {
        Int((point.x / grid).rounded()) &* 100_000
            &+ Int((point.y / grid).rounded())
    }

    static func resolvedCenter(
        session: CGPoint?,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, bounds: bounds) }
        if let stored { return clamp(stored.center(in: bounds), size: size, bounds: bounds) }
        return clamp(defaultCenter, size: size, bounds: bounds)
    }

    @MainActor
    static var store: HistogramAssistStore { HistogramAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.histogramRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> HistogramLongPressMenu {
        HistogramLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared histogram store. Crush/clip compensation is also written to
    /// `LiveAssistState` so LIGHTS stays on the same OpenZCine value.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> HistogramLongPressMenu {
        longPressMenu(
            options: Binding(
                get: { store.options },
                set: { next in
                    store.options = next
                    if let shared = TrafficLightsAssist.CrushClipCompensation(
                        rawValue: next.crushClipCompensation.rawValue)
                    {
                        assist.crushClipCompensation = shared
                    }
                }
            ),
            compact: compact
        )
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> HistogramLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> HistogramLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> HistogramMovablePanel<Content> {
        HistogramMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance, content: content)
    }
}

typealias HistogramAssistStore = MonitorScopePanelStore<MonitorHistogramOptions>

/// OpenZCine `AssistQuickSettingsContent.histogramRows`.
struct HistogramLongPressMenu: View {
    @Binding var options: HistogramAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu }

    var assistMenu: MonitorHistogramMenu {
        MonitorHistogramMenu(
            trafficLights: $options.trafficLights,
            compensation: Binding(
                get: { options.crushClipCompensation },
                set: {
                    guard $0 != options.crushClipCompensation else { return }
                    HistogramAssistHaptics.selection(); options.crushClipCompensation = $0
                }), trafficHelp: HistogramAssist.trafficLightsHelp,
            compensationHelp: HistogramAssist.compensationHelp, compact: compact,
            trafficFeedback: { HistogramAssistHaptics.selection() })
    }
}

struct HistogramMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content
    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: HistogramAssistStore { HistogramAssist.store }
    var body: some View {
        let bounds = ScopePanelPlacement.bounds(in: canvas, clearance: chromeClearance)
        let scale = store.presentationScale(in: canvas)
        let preferred = HistogramAssist.panelSize(scale: scale)
        let size = ScopePanelPlacement.fittedSize(preferred, in: bounds)
        let fallback = HistogramAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = HistogramAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas), defaultCenter: fallback, size: size,
            bounds: canvas)
        MonitorMovableScopePanel(
            layout: MonitorScopePanelLayout(
                baseSize: HistogramAssist.baseSize,
                preferredSize: preferred, center: center, scale: scale, canvas: canvas,
                movementBounds: bounds),
            enabled: !interfaceLocked, resizeLabel: "Resize histogram",
            onMove: { event in
                switch event {
                case .began(let center): store.beginDrag(center: center, in: canvas)
                case .changed(let center): store.drag(to: center, in: canvas)
                case .ended: store.endDrag(bounds: canvas)
                case .cancelled(let retiredCanvas): store.cancelDrag(bounds: retiredCanvas)
                }
            }, onResize: { store.setScale($0) }, content: content)
    }
}



/// OpenZCine `OperatorSettingsHaptics.selection`.
private enum HistogramAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
