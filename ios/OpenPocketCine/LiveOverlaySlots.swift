import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Mimo's green (x) on the locked subject box.
struct LiveTrackingCancelButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.session.cancelSubjectTracking()
        } label: {
            MonitorIcon.x
                .frame(width: 11, height: 11)
                .foregroundStyle(LiveDesign.background)
                .frame(
                    width: MonitorTrackingGeometry.cancelSize,
                    height: MonitorTrackingGeometry.cancelSize
                )
                .background(LiveDesign.good, in: Circle())
        }
        .buttonStyle(.monitorTapTarget)
        .accessibilityLabel("Stop subject tracking")
        .accessibilityIdentifier("monitor.system.trackCancel")
    }
}
