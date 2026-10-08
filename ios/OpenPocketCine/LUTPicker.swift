import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// The shared LUT picker on this app's session, copy and palette; the sheet form pins this
/// app's exposure and 50/50 bar under the catalog.
struct LUTPicker: View {
    @Bindable var assist: LiveAssistState
    var embedded = false
    @Environment(AppModel.self) private var model

    var body: some View {
        LUTPickerView(
            assist: assist, embedded: embedded, context: context, copy: .app,
            palette: LiveDesign.self
        ) {
            LUTSplitComparisonBar(assist: assist)
        }
    }

    private var context: LUTPickerContext {
        LUTPickerContext(
            colorMode: model.session.status.colorMode,
            isPhoto: model.session.status.isPhoto,
            inPlayback: model.session.status.inPlayback,
            family: model.session.bodyFamily,
            cameraName: model.session.connectedCamera?.model.name,
            isWatching: model.isWatchingFeed,
            lookProfile: model.session.connectedCamera?.model.captureProfile?.looks ?? assist.monitorLookProfile)
    }
}

/// Existing catalog callers use the common pinned exposure and comparison controls.
struct LUTSplitComparisonBar: View {
    var assist: LiveAssistState
    var body: some View { MonitorOperatorLookComparison(assist: assist, haptics: .app) }
}
