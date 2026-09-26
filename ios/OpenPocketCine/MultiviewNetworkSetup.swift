import MonitorUI
import SwiftUI

/// Multiview supplies session ownership to the same wizard used by Add setup.
struct MultiviewNetworkSetup: View {
    @Environment(AppModel.self) private var model
    @Bindable var session: MultiviewSession
    var cancel: () -> Void
    var complete: () -> Void

    var body: some View {
        Group {
            if session.tiles.contains(where: { $0.camera != nil }) {
                NavigationStack {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 10) {
                            MonitorIcon.wifi.frame(width: 20, height: 20)
                            Text(session.ssid)
                        }
                        Text("Cameras are using this network. Remove them before changing it.")
                            .foregroundStyle(MonitorTheme.muted)
                        Spacer()
                    }
                    .padding(24)
                    .navigationTitle("Shared Wi-Fi")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done", action: complete)
                        }
                    }
                }
            } else {
                StationNetworkSetupView(
                    context: .multiview,
                    cameraSSIDs: Set(model.savedCameras.compactMap(\.lastSSID)),
                    scan: { try await session.scanNetworks(onFound: $0) },
                    save: { setup, ssid, password in
                        session.selectNetworkSource(hotspot: setup == .phoneHotspot)
                        session.selectNetwork(ssid)
                        session.password = password
                        return await session.configureNetwork()
                    }, errorMessage: session.networkSetupError,
                    close: { if session.networkConfigured { complete() } else { cancel() } })
            }
        }
        .font(MonitorTheme.font(15))
        .foregroundStyle(MonitorTheme.text)
        .tint(MonitorTheme.accent)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("multiview.networkSetup")
    }
}
