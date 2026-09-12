import MonitorUI
import SwiftUI

@main
struct OpenPocketCineApp: App {
    init() {
        MonitorTheme.prepareResources()
    }

    var body: some Scene {
        WindowGroup {
            AppRoot()
                .observeMonitorWindowGeometry()
                // iPad ignores Info.plist `UIStatusBarHidden` after launch unless
                // the hosting controller prefers it hidden. `~ipad` covers launch.
                .statusBarHidden(true)
        }
    }
}
