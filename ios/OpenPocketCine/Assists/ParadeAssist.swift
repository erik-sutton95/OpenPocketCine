import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import SwiftUI
import UIKit

/// OpenZCine RGB Parade operator options + `MovablePanel` (id `"parade"`).
///
/// Sources: `OperatorPreferences.Scopes.ParadeMode`,
/// `MonitorPanels.AssistQuickSettingsContent.paradeRows`,
/// `MonitorOverlays.LiveParadeScopePanel` / `ParadeScopePlot` / `ScopeMini` chip,
/// `ScopeTraceMetal.Mode.parade`.
///
/// Long-press toolbar rows (`AssistQuickSettingsContent.paradeRows`):
/// * Mode - RGB / YRGB
/// * Brightness - 0…200% (default 100)
/// * Safe Border Clip / Crush / Middle Gray
///
/// Parade Y is the WAVE IRE axis: 0 / 100 on the plot edges, dotted 5 / 95
/// safe borders, middle gray at paper IRE. No 0 / 50 / 100 labels.
///
/// On the panel: 0.3s long-press then drag to reposition (4pt snap, 22pt haptic grid);
/// L-corner grip long-press-drags to scale 0.6…1.6. Position persists as a
/// normalised centre (OpenZCine `MovablePanelStoredCenter`).
enum ParadeAssist {
    static let panelID = "parade"
    static let baseSize = ScopePanelSize.parade
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

    typealias Mode = MonitorParadeMode

    static let brightnessHelp =
        "Raise trace intensity when channel separation is hard to see."

    /// OpenZCine `ScopeMini` chip - mode only (`RGB` / `YRGB`), never the transfer.
    static func chip(_ mode: Mode) -> String { mode.rawValue.uppercased() }

    static func accessibilityLabel(_ mode: Mode) -> String {
        mode == .yrgb ? "YRGB parade" : "RGB parade"
    }

    /// Lane letters in draw order - YRGB prepends luma (OpenZCine `ParadeScopePlot`).
    static func laneLabels(_ mode: Mode) -> [String] {
        mode == .yrgb ? ["Y", "R", "G", "B"] : ["R", "G", "B"]
    }

    /// OpenZCine `rect.width / lanes.count`.
    static func laneWidth(mode: Mode, plot: CGRect) -> CGFloat {
        plot.width / CGFloat(mode.laneCount)
    }

    /// OpenZCine `originX + xRatio * (laneWidth - 1)`.
    static func laneX(xRatio: Double, lane: Int, mode: Mode, plot: CGRect) -> CGFloat {
        let width = laneWidth(mode: mode, plot: plot)
        let originX = plot.minX + CGFloat(lane) * width
        return originX + CGFloat(xRatio) * (width - 1)
    }

    typealias GuideLines = MonitorScopeGuides

    /// OpenZCine `MovablePanelStoredCenter` - centre as a fraction of the overlay bounds.
    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Options = MonitorParadeOptions

    /// Trace opacity at the given brightness. OpenZCine uses `/400` after a calibration
    /// pass; Pocket's shipped parade already reads at unity at 100%, so 100% stays 1.0.
    static func intensity(_ brightness: Int) -> Double {
        Double(Options.clampedBrightness(brightness)) / 100
    }

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
    static var store: ParadeAssistStore { ParadeAssistStore.shared }

    /// OpenZCine `AssistQuickSettingsContent.paradeRows`.
    static func longPressMenu(
        options: Binding<Options>,
        compact: Bool = false
    ) -> ParadeLongPressMenu {
        ParadeLongPressMenu(options: options, compact: compact)
    }

    /// Binds the shared parade store. `assist` is unused - parade options live off
    /// `LiveAssistState` so parallel assist agents do not collide on that blob.
    @MainActor
    static func longPressMenu(
        assist: LiveAssistState,
        compact: Bool = false
    ) -> ParadeLongPressMenu {
        longPressMenu(options: store.optionsBinding, compact: compact)
    }

    @MainActor
    static func longPressMenu(_ assist: LiveAssistState) -> ParadeLongPressMenu {
        longPressMenu(assist: assist)
    }

    @MainActor
    static func longPressMenu() -> ParadeLongPressMenu {
        longPressMenu(options: store.optionsBinding)
    }

    /// Direct drag + L-corner resize wrapper (OpenZCine `MovablePanel` id `"parade"`).
    static func overlay<Content: View>(
        canvas: CGRect,
        feed: CGRect,
        chromeClearance: EdgeInsets = EdgeInsets(),
        @ViewBuilder content: @escaping () -> Content
    ) -> ParadeMovablePanel<Content> {
        ParadeMovablePanel(
            canvas: canvas, feed: feed, chromeClearance: chromeClearance, content: content)
    }
}

typealias ParadeAssistStore = MonitorScopePanelStore<MonitorParadeOptions>

/// OpenZCine `AssistQuickSettingsContent.paradeRows`.
struct ParadeLongPressMenu: View {
    @Binding var options: ParadeAssist.Options
    var compact: Bool = false
    var body: some View { assistMenu.buttonStyle(.zcTapTarget) }

    var assistMenu: MonitorScopeTraceMenu<ParadeAssist.Mode> {
        MonitorScopeTraceMenu(
            modes: ParadeAssist.Mode.allCases, mode: $options.mode,
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = ParadeAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    ParadeAssistHaptics.selection(); options.brightness = next
                }), guides: $options.guides, title: { $0.rawValue },
            brightnessHelp: ParadeAssist.brightnessHelp,
            brightnessRange: ParadeAssist.brightnessRange,
            compact: compact,
            modeFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            }, guideFeedback: { ParadeAssistHaptics.selection() })
    }
}

struct ParadeMovablePanel<Content: View>: View {
    let canvas: CGRect
    let feed: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()
    @ViewBuilder var content: () -> Content
    @Environment(\.interfaceLocked) private var interfaceLocked
    private var store: ParadeAssistStore { ParadeAssist.store }
    var body: some View {
        let bounds = ScopePanelPlacement.bounds(in: canvas, clearance: chromeClearance)
        let scale = store.presentationScale(in: canvas)
        let preferred = ParadeAssist.panelSize(scale: scale)
        let size = ScopePanelPlacement.fittedSize(preferred, in: bounds)
        let fallback = ParadeAssist.defaultCenter(
            feed: feed, size: size, bounds: canvas, chromeClearance: chromeClearance)
        let center = ParadeAssist.resolvedCenter(
            session: store.sessionCenter(in: canvas),
            stored: store.storedCenter(in: canvas), defaultCenter: fallback, size: size,
            bounds: canvas)
        MonitorMovableScopePanel(
            layout: MonitorScopePanelLayout(
                baseSize: ParadeAssist.baseSize,
                preferredSize: preferred, center: center, scale: scale, canvas: canvas,
                movementBounds: bounds),
            enabled: !interfaceLocked, resizeLabel: "Resize parade",
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
private enum ParadeAssistHaptics {
    @MainActor
    static func selection() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }
}
