import SwiftUI

@main
struct OpenPocketCineMacApp: App {
    @State private var session = MacMultiviewSession(
        previewStage: ProcessInfo.processInfo.arguments.contains("--multiview-stage"))

    var body: some Scene {
        WindowGroup {
            MacRootView(session: session)
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultSize(width: 1200, height: 760)
    }
}
