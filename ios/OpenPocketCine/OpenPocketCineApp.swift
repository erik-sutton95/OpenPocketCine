import SwiftUI

@main
struct OpenPocketCineApp: App {
    var body: some Scene {
        WindowGroup {
            AppRoot()
                // iPad ignores Info.plist `UIStatusBarHidden` after launch unless
                // the hosting controller prefers it hidden. `~ipad` covers launch.
                .statusBarHidden(true)
        }
    }
}
