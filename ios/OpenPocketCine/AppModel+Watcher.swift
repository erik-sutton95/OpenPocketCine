import OpenCineCameraControls
import OpenPocketViewCore

typealias WatcherBrowseView = WatcherBrowse<AppModel>

extension AppModel: WatcherBrowseHost {
    var watcherJoinStatus: WatcherJoinStatus {
        switch relayClient.status {
        case .idle: .idle
        case .connecting: .connecting
        case .reconnecting(let attempt):
            .reconnecting(attempt: attempt, maximum: WatcherRelayRecovery.maximumRetries)
        case .needsPasscode: .needsPasscode
        case .live: .live
        case .failed(let message): .failed(message)
        }
    }

    var watcherFeeds: [WatcherFeedRow] {
        relayBrowser.hosts.map {
            WatcherFeedRow(id: $0.id, name: $0.name, cameraName: $0.cameraName)
        }
    }

    var watcherBrowseError: String? { relayBrowser.browseError }

    func joinWatcherFeed(id: String) {
        guard let feed = relayBrowser.hosts.first(where: { $0.id == id }) else { return }
        joinWatcher(feed)
    }
}
