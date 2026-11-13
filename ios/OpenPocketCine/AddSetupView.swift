import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCore
import OpenCineDJIApple
import OpenPocketViewCore
import SwiftUI

/// Compatibility host for review callers; production slots return the typed flow directly.
struct AddSetupView: View {
    @Environment(AppModel.self) private var model
    let camera: SavedCamera
    let done: (RouteDraft?) -> Void

    var body: some View {
        AddSetupFlowView(
            flow: PocketAddSetup.flow(
                camera: camera, done: done,
                initialSelection: PocketAddSetup.selection(camera: camera, model: model)))
    }
}

/// Host destinations and actions for the shared setup capability chooser.
@MainActor
enum PocketAddSetup {
    static func flow(
        camera: SavedCamera, done: @escaping (RouteDraft?) -> Void, initialSelection: String? = nil
    ) -> AddSetupFlow {
        AddSetupFlow(
            chooser: StationNetworkSetupRules.setupChooser(context: .camera(camera)),
            onSelect: { _ in },
            destination: { option in
                AnyView(PocketSetupDestination(camera: camera, kind: option.kind, done: done))
            },
            initialSelection: initialSelection, onCancel: { done(nil) })
    }

    static func selection(camera: SavedCamera, model: AppModel) -> String? {
        CamerasMapping.addSetupSelection(
            model.cameras, camera: camera,
            chooser: StationNetworkSetupRules.setupChooser(context: .camera(camera)))
    }
}

/// The integration retains scanning, credential entry, persistence and route provisioning.
private struct PocketSetupDestination: View {
    @Environment(AppModel.self) private var model
    let camera: SavedCamera
    let kind: RouteKind
    let done: (RouteDraft?) -> Void

    var body: some View {
        StationNetworkSetupView(
            context: .camera(camera), brand: PocketStationNetwork.brand,
            services: PocketStationNetwork.services, scan: model.networkScan(camera),
            save: { network in
                done(RouteDraft(
                    kind: network.hotspot ? .phoneHotspot : .infrastructureNetwork,
                    network: network.ssid, secret: network.password))
                return true
            }, close: { done(nil) }, path: path
        )
        .presentationBackground(MonitorTheme.background)
    }

    private var path: [StationNetworkSetupView.Page] {
        if kind == .phoneHotspot { return [.hotspot] }
        if PocketAddSetup.selection(camera: camera, model: model) == "wifi" {
            return [.password(camera.wifiSSID ?? "")]
        }
        return [.networks]
    }
}

/// This app's brand words and DJI services for OpenCine's station-network wizard.
enum PocketStationNetwork {
    static let brand = StationNetworkBrand(
        appName: "OpenPocketCine", cameraFamily: "Osmo", cameraNetworkPrefix: "osmo")

    static var services: StationNetworkServices {
        StationNetworkServices(
            savedNetworks: {
                MultiviewNetworkStore.savedNetworks().map {
                    StationNetwork(ssid: $0.ssid, password: $0.password, hotspot: $0.hotspot)
                }
            },
            currentSSID: { await DjiAppleWiFiJoiner.currentSSID() },
            hotspotActive: { DjiAppleSharedWiFiPath.address(hotspot: true) != nil },
            acceptsJoin: { (try? MulticamCommands.join(ssid: $0, password: $1, seq: 0)) != nil })
    }
}
