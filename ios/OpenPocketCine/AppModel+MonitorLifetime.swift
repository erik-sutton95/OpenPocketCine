import MonitorUI
import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import SwiftUI
import OpenCineDJIApple

extension AppModel {
    /// A tile lends its native transport and decoder. The shell only returns that loan.
    func borrowMonitor(_ camera: DjiAppleSighting, release: @escaping @MainActor () -> Void) {
        let saved = SavedCamera(id: camera.id.uuidString,
            integration: DJICameraSessionAdapter.integration,
            advertisedName: camera.name, model: camera.model.name)
        shell.borrow(ConnectedCamera(saved: saved, session: session.control), release: release)
    }

    #if targetEnvironment(simulator)
        /// SIMULATED clip preview: no connection approval or writable camera state is invented.
        func presentSimulatorPreview() {
            guard shell.monitor == nil else { return }
            let saved = SavedCamera(id: "simulated-clip-preview",
                integration: DJICameraSessionAdapter.integration,
                advertisedName: "SIMULATED clip preview", model: "SIMULATED")
            shell.borrow(ConnectedCamera(saved: saved, session: session.control), release: {})
        }
    #endif
}

/// Bounded native pages; navigation and the monitor underneath belong to the shared shell.
struct ShellCoverPage: View {
    let cover: ShellModel.Cover
    @Environment(AppModel.self) private var model

    var body: some View {
        MonitorCoverPage { safeArea in
            switch cover {
            case .settings:
                SettingsRootView(safeArea: safeArea, onClose: { model.shell.dismissCover() })
            case .media:
                MediaLibraryView(safeArea: safeArea, onClose: { model.shell.dismissCover() })
            }
        }
    }
}
