import Network

/// Shared-network transport only. Peer-to-peer radio scheduling interrupts the camera feed.
/// All discovery, listeners, and watcher connections use this one configuration.
enum WatcherRelayNetwork {
    static func parameters() -> NWParameters {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = false
        parameters.prohibitedInterfaceTypes = [.cellular]
        parameters.serviceClass = .interactiveVideo
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
            tcp.keepaliveIdle = 10
            tcp.keepaliveInterval = 5
            tcp.keepaliveCount = 3
        }
        return parameters
    }
}
