import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Thin Osmo binding for the shared camera home. The existing session owns discovery,
/// reconnect, cancellation, and saved-camera persistence.
struct SavedCamerasView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    let compact: Bool
    @State private var showMultiview = false
    @State private var addSetup: AddSetupTarget?
    /// A hotspot connect waiting for the operator to turn Personal Hotspot on.
    @State private var hotspotPrompt: SavedCamera?
    @State private var hotspotSettingsFor: SavedCamera?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var orientation = InterfaceOrientationObserver()

    private var connectionBusy: Bool { model.isBusy || model.session.isReconnecting }

    var body: some View {
        GeometryReader { proxy in
            CamerasPage(
                brandName: "OpenPocketCine",
                paired: OsmoCameraPageAdapter.paired(model),
                nearby: OsmoCameraPageAdapter.nearby(model),
                scanning: model.isScanning, busy: connectionBusy,
                safeArea: OsmoCameraPageAdapter.safeArea(
                    proxy.safeAreaInsets, window: windowGeometry.safeArea,
                    portrait: proxy.size.height > proxy.size.width,
                    orientation: orientation.orientation),
                onConnect: { id in
                    guard !connectionBusy, let camera = saved(id) else { return }
                    connect(camera, over: camera.preferredSetup)
                },
                onPair: { id in
                    guard !connectionBusy else { return }
                    if let id,
                        let camera = model.session.found.first(where: { $0.id.uuidString == id })
                    {
                        model.isPairingNewCamera = true
                        model.session.connect(camera)
                    } else {
                        model.pairNewCamera()
                    }
                },
                onCancel: { model.cancelPairing() }, onMedia: { model.homePanel = .media },
                onSettings: { model.homePanel = .settings },
                onMultiview: {
                    guard !connectionBusy else { return }
                    model.session.disconnect()
                    showMultiview = true
                },
                onWatchFeed: {
                    guard !connectionBusy else { return }
                    model.openWatcherBrowse()
                },
                onRename: { id, name in
                    guard !connectionBusy, let camera = saved(id) else { return }
                    model.rename(camera, to: name)
                },
                onForget: { id in
                    guard !connectionBusy, let camera = saved(id) else { return }
                    model.forget(camera)
                },
                onConnectSetup: { id, setup in
                    guard !connectionBusy, let camera = saved(id),
                        let setup = CameraConnectionSetup(rawValue: setup)
                    else { return }
                    connect(camera, over: setup)
                },
                onAddSetup: { id in
                    guard !connectionBusy, let camera = saved(id) else { return }
                    addSetup = AddSetupTarget(camera: camera, page: .choose)
                },
                onForgetSetup: { id, setup in
                    guard !connectionBusy, let camera = saved(id),
                        let setup = CameraConnectionSetup(rawValue: setup)
                    else { return }
                    model.forgetSetup(setup, of: camera)
                },
                onFailureAction: { id, action in
                    guard !connectionBusy, let camera = saved(id) else { return }
                    let failed = model.session.connectionSetup
                    switch action {
                    case "edit":
                        let page: AddSetupView.Page =
                            failed == .phoneHotspot
                            ? .hotspot : .password(camera.ssid(for: .wifi) ?? "")
                        addSetup = AddSetupTarget(camera: camera, page: page)
                    case "cameraWiFi": connect(camera, over: .cameraWiFi)
                    default: connect(camera, over: failed)
                    }
                })
        }
        .ignoresSafeArea()
        .onAppear { orientation.start() }
        .onDisappear { orientation.stop() }
        .sheet(item: $addSetup) { target in
            let nearby = model.session.found.contains { $0.id == target.camera.id }
            AddSetupView(
                camera: target.camera,
                scan: nearby
                    ? { onFound in
                        try await model.scanNetworks(with: target.camera, onFound: onFound)
                    }
                    : nil,
                save: { setup, ssid, password in
                    model.addSetup(setup, ssid: ssid, password: password, to: target.camera)
                },
                close: { addSetup = nil }, path: target.page == .choose ? [] : [target.page]
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MonitorTheme.background)
        }
        .alert(
            "Turn on Personal Hotspot",
            isPresented: Binding(
                get: { hotspotPrompt != nil }, set: { if !$0 { hotspotPrompt = nil } }),
            presenting: hotspotPrompt
        ) { camera in
            Button("Open Settings") {
                hotspotSettingsFor = camera
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Connect") { model.reconnect(camera, setup: .phoneHotspot) }
            Button("Cancel", role: .cancel) {}
        } message: { camera in
            Text(
                "\(camera.displayName) joins this iPhone’s hotspot\(camera.hotspotSSID.map { " “\($0)”" } ?? ""). Turn on Personal Hotspot and Allow Others to Join (Settings or Control Center), then tap Connect."
            )
        }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings: offer Connect again rather than guessing it is on.
            guard phase == .active, let camera = hotspotSettingsFor else { return }
            hotspotSettingsFor = nil
            hotspotPrompt = camera
        }
        .fullScreenCover(
            isPresented: $showMultiview,
            onDismiss: { model.session.startScan() }, content: { MultiviewView() })
    }

    /// iOS reports Personal Hotspot only once a device has joined it, so a hotspot connect
    /// without that sign asks first. Without it the camera spends its join retries on a
    /// network that is not there.
    private func connect(_ camera: SavedCamera, over setup: CameraConnectionSetup) {
        if setup == .phoneHotspot, SharedWiFiPath.address(hotspot: true) == nil {
            hotspotPrompt = camera
        } else {
            model.reconnect(camera, setup: setup)
        }
    }

    private func saved(_ id: String) -> SavedCamera? {
        model.savedCameras.first { $0.id.uuidString == id }
    }
}

struct AddSetupTarget: Identifiable {
    let camera: SavedCamera
    let page: AddSetupView.Page
    var id: UUID { camera.id }
}
