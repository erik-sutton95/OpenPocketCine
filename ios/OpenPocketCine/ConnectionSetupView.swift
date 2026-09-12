import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Osmo bindings for the shared pairing page. Reported session phases advance the
/// rail automatically; the operator never acknowledges synthetic progress.
struct ConnectionSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    let compact: Bool
    @State private var selectedID: UUID?
    @State private var diagnostics: DiagnosticSharePayload?
    @State private var orientation = InterfaceOrientationObserver()

    var body: some View {
        GeometryReader { proxy in
            PairCameraPage(
                presentation: OsmoCameraPageAdapter.pairing(model, selected: selectedID),
                safeArea: OsmoCameraPageAdapter.safeArea(
                    proxy.safeAreaInsets, window: windowGeometry.safeArea,
                    portrait: proxy.size.height > proxy.size.width,
                    orientation: orientation.orientation),
                onSelect: { id in
                    guard !model.isBusy else { return }
                    selectedID = UUID(uuidString: id)
                },
                onPrimary: {
                    guard !model.isBusy else { return }
                    if case .failed = model.session.phase {
                        model.session.startScan()
                    } else if let selectedID,
                        let camera = model.session.found.first(where: { $0.id == selectedID })
                    {
                        model.session.connect(camera)
                    }
                },
                onBack: { model.cancelPairing() },
                onDiagnostics: {
                    if let url = DiagnosticCenter.shared.beginShare(session: model.session) {
                        diagnostics = DiagnosticSharePayload(url: url)
                    }
                },
                onWatchFeed: { model.openWatcherBrowse() })
        }
        .ignoresSafeArea()
        .onAppear { orientation.start() }
        .onDisappear { orientation.stop() }
        .sheet(item: $diagnostics) { payload in DiagnosticActivityShareView(items: [payload.url]) }
        .onChange(of: model.session.phase) { _, phase in
            if phase == .openingDatalink { LocalVPNProbe.noteIfActive() }
        }
    }
}
