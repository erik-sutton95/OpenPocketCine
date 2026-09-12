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
                    model.reconnect(camera)
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
                })
        }
        .ignoresSafeArea()
        .onAppear { orientation.start() }
        .onDisappear { orientation.stop() }
        .fullScreenCover(
            isPresented: $showMultiview,
            onDismiss: { model.session.startScan() }, content: { MultiviewView() })
    }

    private func saved(_ id: String) -> SavedCamera? {
        model.savedCameras.first { $0.id.uuidString == id }
    }
}
