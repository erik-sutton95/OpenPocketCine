import OpenCineCameraControls
import SwiftUI

/// Compatibility entry; common watcher chrome owns the full strip and its hold lifetime.
struct LiveAssistBar: View {
    @Environment(AppModel.self) private var model
    var isLocked = false
    var showsAudio = true
    var body: some View {
        MonitorWatcherToolStrip(assist: model.assist, palette: LiveDesign.self, haptics: .app,
            isLocked: isLocked, showsAudio: showsAudio)
    }
}
