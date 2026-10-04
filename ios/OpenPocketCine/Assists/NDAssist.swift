import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Live-picture ND chip. Suggestion only - the app cannot set a screw-on filter.
/// Parks bottom-leading, just above the view-assist toolbar. Hold 0.3 s then
/// drag to move; L-corner grip scales 0.6…1.6. Same movable contract as LIGHTS.
enum NDAssist {
    static let panelID = "nd-meter"
    static let baseSize = ScopePanelSize.ndMeter
    static let scaleRange: ClosedRange<Double> = 0.6...1.6
    static let defaultScale = 1.0
    static let holdDuration: Double = 0.3
    static let positionGrid: CGFloat = 4
    static let hapticGrid: CGFloat = 22
    static let dragHitPadding: CGFloat = 10
    static let gripHitSize: CGFloat = 56
    static let gripVisualSize: CGFloat = 14
    static let gripExteriorGap: CGFloat = 2
    static let meterTitle = "ND"
    static let accessibilityTitle = "ND Suggestion"
    static let defaultNotation = NDFilterNotation.factor
    static let notationTitle = "Units"
    static let notationHelp =
        "Stops vs middle gray, filter factor (ND16 / ND32 / ND64), or optical density (ND 0.3 = 1 stop)."
    static let helpCopy =
        "Meters the live picture against middle gray and suggests a screw-on ND \u{2014} stops and ND number \u{2014} to balance it. The app cannot set a filter."
    static var notationOptions: [String] { NDFilterNotation.allCases.map(\.editorLabel) }

    static func longPressMenu(assist _: LiveAssistState) -> NDLongPressMenu {
        NDLongPressMenu()
    }

    /// Unplaced tools start at the canvas center; saved/session centers win later.
    static func defaultCenter(
        feed _: CGRect,
        size: CGSize,
        bounds: CGRect,
        chromeClearance _: EdgeInsets,
        gap _: CGFloat = 10
    ) -> CGPoint {
        clamp(
            CGPoint(x: bounds.midX, y: bounds.midY), size: size, in: bounds)
    }

    static func reading(from bundle: ScopeAssistBundle) -> NDFilterSuggestion? {
        NDFilterRecommendation.reading(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)
    }

    typealias StoredCenter = MonitorScopeStoredCenter

    typealias Snapshot = MonitorNDOptions

    static func clampedScale(_ value: Double) -> Double {
        min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
    }

    static func panelSize(scale: Double) -> CGSize {
        let clamped = clampedScale(scale)
        return CGSize(
            width: (baseSize.width * clamped).rounded(),
            height: (baseSize.height * clamped).rounded())
    }

    static func clamp(_ point: CGPoint, size: CGSize, in bounds: CGRect) -> CGPoint {
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
        session: CGPoint? = nil,
        stored: StoredCenter?,
        defaultCenter: CGPoint,
        size: CGSize,
        bounds: CGRect
    ) -> CGPoint {
        if let session { return clamp(session, size: size, in: bounds) }
        let raw = stored?.center(in: bounds) ?? defaultCenter
        return clamp(raw, size: size, in: bounds)
    }

    @MainActor
    static var store: NDAssistStore { NDAssistStore.shared }
}

typealias NDAssistStore = MonitorNDPreferenceStore

struct NDLongPressMenu: View {
    @Bindable var store = NDAssist.store
    var compact: Bool = false

    var body: some View {
        MonitorNDMenu(
            notation: Binding(
                get: { store.notation },
                set: {
                    store.notation = $0; store.persist()
                }), title: NDAssist.notationTitle, notationHelp: NDAssist.notationHelp,
            help: NDAssist.helpCopy, compact: compact,
            selectionFeedback: {
                OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
            })
    }
}

struct NDMeterOverlay: View {
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets

    var body: some View {
        let store = NDAssist.store
        let size = ScopePanelPlacement.size(
            NDAssist.panelSize(scale: store.scale),
            canvas: bounds, clearance: chromeClearance)
        NDMovablePanel(
            store: store,
            size: size,
            defaultCenter: NDAssist.defaultCenter(
                feed: feed, size: size, bounds: bounds, chromeClearance: chromeClearance),
            bounds: bounds,
            placementBounds: ScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        ) {
            NDMeterLiveChip(notation: store.notation)
        }
    }
}

/// Reads the scope bundle in its own scope so the movable panel around the
/// chip does not re-evaluate on every bundle (up to 25 Hz).
private struct NDMeterLiveChip: View {
    @Environment(AppModel.self) private var model
    var notation: NDFilterNotation

    var body: some View {
        NDMeterChip(
            reading: NDAssist.reading(from: model.frameSamples.displayBundle),
            notation: notation)
    }
}

/// App binding keeps the inherited unknown marker content.
struct NDMeterChip: View {
    var reading: NDFilterSuggestion?
    var notation: NDFilterNotation = NDAssist.defaultNotation

    var body: some View {
        MonitorNDFilterChip(
            reading: reading, notation: notation, emptyLabel: NDFilterRecommendation.noneLabel)
    }
}

/// Drag to reposition; drag the corner grip to scale.
struct NDMovablePanel<Content: View>: View {
    @Bindable var store: NDAssistStore
    let size: CGSize
    let defaultCenter: CGPoint
    let bounds: CGRect
    var placementBounds: CGRect? = nil
    @ViewBuilder var content: () -> Content
    @State private var sessionCenter: CGPoint?
    @State private var sessionCenterPortrait: CGPoint?
    var body: some View {
        let movement = placementBounds ?? ScopePanelPlacement.bounds(in: bounds)
        let center = NDAssist.resolvedCenter(
            session: ScopeCanvasSlot.pick(sessionCenter, sessionCenterPortrait, in: bounds),
            stored: ScopeCanvasSlot.pick(store.position, store.positionPortrait, in: bounds),
            defaultCenter: defaultCenter, size: size, bounds: bounds)
        MonitorMovableScopePanel(
            layout: MonitorScopePanelLayout(
                baseSize: NDAssist.baseSize,
                preferredSize: size, center: center, scale: store.scale, canvas: bounds,
                movementBounds: movement),
            resizeLabel: "Resize ND meter",
            onMove: { event in
                switch event {
                case .began: break
                case .cancelled(let retiredCanvas):
                    ScopeCanvasSlot.assign(
                        &sessionCenter, &sessionCenterPortrait, in: retiredCanvas, nil)
                case .changed(let center):
                    ScopeCanvasSlot.assign(
                        &sessionCenter, &sessionCenterPortrait, in: bounds, center)
                case .ended:
                    guard
                        let center = ScopeCanvasSlot.pick(
                            sessionCenter, sessionCenterPortrait, in: bounds)
                    else { return }
                    let stored = NDAssist.StoredCenter(center: center, in: bounds)
                    if ScopeCanvasSlot.forBounds(bounds) == .portrait {
                        store.positionPortrait = stored
                    } else {
                        store.position = stored
                    }
                    store.persist()
                }
            }, onResize: { store.scale = NDAssist.clampedScale($0) },
            onResizeEnded: { store.persist() }, content: content)
    }
}
