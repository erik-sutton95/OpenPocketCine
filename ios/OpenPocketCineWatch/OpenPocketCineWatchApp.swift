import SwiftUI

/// OpenPocketCine watchOS companion. Mirrors the iPhone monitor on the wrist: a 16:9
/// preview feed, Record / shutter, timecode, and storage. The iPhone owns the camera
/// radio; this app is a WatchConnectivity remote.
@main
struct OpenPocketCineWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = WatchSessionController()

    var body: some Scene {
        WindowGroup {
            WatchMonitorView()
                .environment(controller)
                .onAppear { controller.activate() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { controller.resume() }
                }
        }
    }
}
