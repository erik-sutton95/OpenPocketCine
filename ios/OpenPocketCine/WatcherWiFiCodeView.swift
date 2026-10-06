import OpenCineAppKitApple
import SwiftUI

/// The shared join-code sheet, fed from the live model so it dismisses when the network or live
/// state changes.
struct WatcherWiFiCodeSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        WatcherWiFiCodeView(
            appName: "OpenPocketCine", ssid: model.session.joinedSSID,
            joinCode: model.session.watcherWiFiJoinCode, isLive: model.isLive)
    }
}
