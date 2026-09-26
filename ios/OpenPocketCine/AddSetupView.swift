import OpenPocketViewCore
import SwiftUI

/// Saved-camera entry point into the shared station-network wizard.
struct AddSetupView: View {
    typealias Page = StationNetworkSetupView.Page
    let camera: SavedCamera
    var scan: ((@escaping @MainActor (String) -> Void) async throws -> Void)?
    var save: (CameraConnectionSetup, String, String) -> Void
    var close: () -> Void
    var path: [Page] = []

    var body: some View {
        StationNetworkSetupView(
            context: .camera(camera), scan: scan,
            save: { setup, ssid, password in
                save(setup, ssid, password)
                return true
            }, close: close, path: path)
    }
}
