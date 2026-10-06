import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// The zebra menu over the monitored source's transfer and its live ceiling (STATE-01: never a
/// process-wide one).
struct LiveZebraMenu: View {
    var assist: LiveAssistState
    @Environment(AppModel.self) private var model

    var body: some View {
        let transfer =
            model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        ZebraAssist.longPressMenu(
            assist: assist, stores: .app, palette: LiveDesign.self, haptics: .app,
            transfer: transfer,
            clipByte: model.monitorSamples.exposureCeiling.clipByte(transfer: transfer))
    }
}
