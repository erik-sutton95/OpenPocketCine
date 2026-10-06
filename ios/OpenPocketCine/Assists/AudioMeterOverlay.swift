import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// Keeps frequent audio observations inside the meter, not the scope host.
struct LiveAudioMeterOverlay: View {
    @Environment(AppModel.self) private var model
    let bounds: CGRect
    var chromeClearance: EdgeInsets = EdgeInsets()

    var body: some View {
        AudioMeterOverlay(
            stores: .app,
            // ponytail: unknown meters draw as the floor, as before; a distinct "no report" look
            // is a UI change to prove on device first.
            levels: model.session.status.audioMeters ?? .silent,
            sensitivity: model.session.status.audioChannel?.label,
            bounds: bounds, chromeClearance: chromeClearance,
            hapticsEnabled: model.hapticsEnabled,
            onConfigure: { model.assist.configureTool = .audioMeters })
    }
}
