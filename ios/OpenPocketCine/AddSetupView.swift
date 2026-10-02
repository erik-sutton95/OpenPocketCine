import MonitorUI
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

/// The DJI add-route slot (SHELL-02): the station-network wizard for a saved camera. The saved
/// setup becomes a `RouteDraft`; the integration keeps the password and moves the camera.
struct AddSetupView: View {
    @Environment(AppModel.self) private var model
    let camera: SavedCamera
    let done: (RouteDraft?) -> Void

    var body: some View {
        StationNetworkSetupView(
            context: .camera(camera), scan: model.networkScan(camera),
            save: { setup, ssid, password in
                done(
                    RouteDraft(
                        kind: setup == .phoneHotspot ? .phoneHotspot : .infrastructureNetwork, network: ssid,
                        secret: password))
                return true
            }, close: { done(nil) }, path: path
        )
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MonitorTheme.background)
    }

    /// Edit setup reopens the failed setup on its password or hotspot page.
    private var path: [StationNetworkSetupView.Page] {
        guard case .saved(_, let route)? = model.cameras.failures[camera.id]?.target,
            let kind = camera.routes.first(where: { $0.id == route })?.kind
        else { return [] }
        switch kind {
        case .phoneHotspot: return [.hotspot]
        case .infrastructureNetwork: return [.password(camera.wifiSSID ?? "")]
        default: return []
        }
    }
}
