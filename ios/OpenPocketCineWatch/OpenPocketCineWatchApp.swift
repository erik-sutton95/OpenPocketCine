import OpenCineWatch
import OpenPocketViewCore
import SwiftUI

/// OpenPocketCine watchOS companion. Mirrors the iPhone monitor on the wrist: a 16:9
/// preview feed, Record / shutter, timecode, and storage. The iPhone owns the camera
/// radio; this app is a WatchConnectivity remote.
@main
struct OpenPocketCineWatchApp: App {
    var body: some Scene {
        WatchCompanionScene(openOnIPhone: WatchRelayCopy.openOnIPhone)
    }
}
