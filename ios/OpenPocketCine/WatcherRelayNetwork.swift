import Network

/// Shared-network transport only. Peer-to-peer radio scheduling interrupts the camera feed.
/// All discovery, listeners, and watcher connections use this one configuration.
enum WatcherRelayNetwork {
    /// Do not retain a vanished interface when retrying a Bonjour service after a Wi-Fi change.
    static func rediscoveryEndpoint(_ endpoint: NWEndpoint) -> NWEndpoint {
        if case .service(let name, let type, let domain, _) = endpoint {
            return .service(name: name, type: type, domain: domain, interface: nil)
        }
        return endpoint
    }

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
