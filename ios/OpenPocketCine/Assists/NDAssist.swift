import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// Live-picture ND chip. Suggestion only - the app cannot set a screw-on filter.
/// Parks bottom-leading, just above the view-assist toolbar. Hold 0.3 s then
/// drag to move; L-corner grip scales 0.6…1.6. Same movable contract as LIGHTS.
enum NDAssist {
    static let panelID = "nd-meter"
    static let baseSize = ScopePanelSize.ndMeter
    static let meterTitle = "ND"
    static let accessibilityTitle = "ND Suggestion"
    static let defaultNotation = MonitorNDFilterNotation.factor
    /// No-filter label for the chip and its reading.
    static let noneLabel = "\u{2014}"
    static let notationTitle = "Units"
    static let notationHelp =
        "Stops vs middle gray, filter factor (ND16 / ND32 / ND64), or optical density (ND 0.3 = 1 stop)."
    static let helpCopy =
        "Meters the live picture against middle gray and suggests a screw-on ND \u{2014} stops and ND number \u{2014} to balance it. The app cannot set a filter."
    static var notationOptions: [String] { MonitorNDFilterNotation.allCases.map(\.editorLabel) }

    static func longPressMenu(assist _: LiveAssistState) -> NDLongPressMenu {
        NDLongPressMenu()
    }

    static func reading(from bundle: ScopeAssistBundle) -> MonitorNDFilterSuggestion? {
        MonitorNDFilterRecommendation.reading(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer,
            noneLabel: noneLabel)
    }

    static func panelSize(scale: Double) -> CGSize {
        MonitorScopePanelCentering.panelSize(baseSize, scale: MonitorScopePanelCentering.clampedScale(scale))
    }

    @MainActor
    static var store: MonitorNDPreferenceStore { AssistPanelStores.app.nd }
}

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
        let size = MonitorScopePanelPlacement.size(
            NDAssist.panelSize(scale: store.scale),
            canvas: bounds, clearance: chromeClearance)
        NDMovablePanel(
            store: store,
            size: size,
            defaultCenter: MonitorScopePanelCentering.defaultCenter(size: size, bounds: bounds),
            bounds: bounds,
            placementBounds: MonitorScopePanelPlacement.bounds(in: bounds, clearance: chromeClearance)
        ) {
            NDMeterLiveChip(notation: store.notation)
        }
    }
}

/// Reads the scope bundle in its own scope so the movable panel around the
/// chip does not re-evaluate on every bundle (up to 25 Hz).
private struct NDMeterLiveChip: View {
    @Environment(AppModel.self) private var model
    var notation: MonitorNDFilterNotation

    var body: some View {
        NDMeterChip(
            reading: NDAssist.reading(from: model.frameSamples.displayBundle),
            notation: notation)
    }
}

/// App binding keeps the inherited unknown marker content.
struct NDMeterChip: View {
    var reading: MonitorNDFilterSuggestion?
    var notation: MonitorNDFilterNotation = NDAssist.defaultNotation

    var body: some View {
        MonitorNDFilterChip(
            reading: reading, notation: notation, emptyLabel: NDAssist.noneLabel)
    }
}

/// Drag to reposition; drag the corner grip to scale.
struct NDMovablePanel<Content: View>: View {
    @Bindable var store: MonitorNDPreferenceStore
    let size: CGSize
    let defaultCenter: CGPoint
    let bounds: CGRect
    var placementBounds: CGRect? = nil
    @ViewBuilder var content: () -> Content
    @State private var sessionCenter: CGPoint?
    @State private var sessionCenterPortrait: CGPoint?
    var body: some View {
        let movement = placementBounds ?? MonitorScopePanelPlacement.bounds(in: bounds)
        let center = MonitorScopePanelCentering.resolvedCenter(
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
                    let stored = MonitorScopeStoredCenter(center: center, in: bounds)
                    if ScopeCanvasSlot.forBounds(bounds) == .portrait {
                        store.positionPortrait = stored
                    } else {
                        store.position = stored
                    }
                    store.persist()
                }
            }, onResize: { store.scale = MonitorScopePanelCentering.clampedScale($0) },
            onResizeEnded: { store.persist() }, content: content)
    }
}
