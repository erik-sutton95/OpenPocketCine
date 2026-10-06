import OpenCineAppKit
import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

extension NDAssist {
    @MainActor static var store: MonitorNDPreferenceStore { AssistPanelStores.app.nd }
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
