import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import SwiftUI

/// Multiview supplies session ownership to the same wizard used by Add setup.
struct MultiviewNetworkSetup: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: MultiviewSession
    var cancel: () -> Void
    var complete: () -> Void

    var body: some View {
        StationNetworkSetupView(
            context: .multiview, brand: PocketStationNetwork.brand,
            services: PocketStationNetwork.services,
            cameraSSIDs: Set(model.savedCameras.compactMap(\.lastSSID)),
            scan: { try await session.scanNetworks(onFound: $0) },
            save: { network in
                session.selectNetworkSource(hotspot: network.hotspot)
                session.selectNetwork(network.ssid)
                session.password = network.password
                return await session.configureNetwork()
            }, errorMessage: session.networkSetupError,
            close: { if session.networkConfigured { complete() } else { cancel() } },
            lockedNetwork: session.tiles.contains(where: { $0.camera != nil })
                ? StationNetwork(
                    ssid: session.ssid, password: session.password,
                    hotspot: session.usePhoneHotspot)
                : nil,
            complete: complete)
        .font(MonitorTheme.font(15))
        .foregroundStyle(MonitorTheme.text)
        .tint(MonitorTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("multiview.networkSetup")
    }
}
