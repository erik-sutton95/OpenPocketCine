import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine vectorscope operator options + `MovablePanel` (id `"vector"`).
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.vectorscopeRows`):
/// * Trace Zoom - 1x / 2x / 4x (graticule stays at unity)
/// * Brightness - 0…200% (default 100; unity baseline, unlike WAVE/PARADE’s /400)
///
/// Always-on plot (no popup toggle in OpenZCine): 75% graticule, 123° I-phase
/// skin line, colour density rendering (log alpha + `traceTint` + 1.1-bin blur
/// + 0.35 crisp core + 0.35 trail).
///
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid);
/// L-corner grip long-press-drags to scale 0.6…1.6. Position persists as a
/// normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum VectorscopeAssist {
    static let panelID = "vector"
    static let baseSize = ScopePanelSize.vectorscope
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let brightnessRange: ClosedRange<Int> = 0...200
    static let defaultBrightness = 100
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2

    /// OpenZCine `AssistConfiguration.Scopes.VectorscopeZoom`.
    typealias Zoom = MonitorVectorscopeZoom

    /// OpenZCine `MovablePanelStoredCenter` - centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Options = MonitorVectorscopeOptions

    /// OpenZCine `Scopes.brightnessMultiplier` - vectorscope keeps the unity baseline.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 100
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = Options.clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    /// OpenZCine `ScopeMini` vectorscope chip - `MON · 1X`.
    static func chip(zoom: Zoom) -> String {
        "MON · \(zoom.rawValue.uppercased())"
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
    static var store: VectorscopeAssistStore { VectorscopeAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.vectorscopeRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> VectorscopeLongPressMenu {
        VectorscopeLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared vectorscope store. `assist` is unused - options live off
    /// `LiveAssistState` so parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> VectorscopeLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> VectorscopeLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> VectorscopeLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel`).
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> VectorscopeMovablePanel<Content> {
        VectorscopeMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance, content: content)
    }
}

typealias VectorscopeAssistStore = MonitorScopePanelStore<MonitorVectorscopeOptions>

/// OpenZCine `AssistQuickSettingsContent.vectorscopeRows`.
struct VectorscopeLongPressMenu: View {
    @Binding var options: VectorscopeAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu.buttonStyle(.zcTapTarget) }

    var assistMenu: MonitorVectorscopeMenu {
        MonitorVectorscopeMenu(
            zoom: Binding(
                get: { options.zoom },
                set: {
                    guard $0 != options.zoom else { return }
                    VectorscopeAssistHaptics.selection(); options.zoom = $0
                }),
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = VectorscopeAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    VectorscopeAssistHaptics.selection(); options.brightness = next
                }),
            zoomHelp:
                "Magnifies only the chroma trace; the graticule stays at unity. The vectorscope reads the monitor image (your active LUT, or the built-in display tone map), where chroma is meaningful.",
            brightnessHelp: "Raise trace intensity when the chroma plot is hard to read.",
            brightnessRange: VectorscopeAssist.brightnessRange, compact: compact,
            zoomFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            })
    }
}

struct VectorscopeMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content
    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: VectorscopeAssistStore { VectorscopeAssist.store }
    var body: some View {
        let bounds = ScopePanelPlacement.bounds(in: canvas, clearance: chromeClearance)
        let scale = store.presentationScale(in: canvas)
        let preferred = VectorscopeAssist.panelSize(scale: scale)
        let size = ScopePanelPlacement.fittedSize(preferred, in: bounds)
        let fallback = VectorscopeAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = VectorscopeAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas), defaultCenter: fallback, size: size,
            bounds: canvas)
        MonitorMovableScopePanel(
            layout: MonitorScopePanelLayout(
                baseSize: VectorscopeAssist.baseSize,
                preferredSize: preferred, center: center, scale: scale, canvas: canvas,
                movementBounds: bounds),
            enabled: !interfaceLocked, resizeLabel: "Resize vectorscope",
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
private enum VectorscopeAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
