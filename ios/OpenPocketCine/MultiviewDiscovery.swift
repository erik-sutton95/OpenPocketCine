import Foundation
import Network
import OpenPocketViewCore

/// Service candidates only. The session must verify BLE identity before starting preview.
@MainActor final class MultiviewDiscovery {
    private var cancelled = false
    func cancel() { cancelled = true }

    func candidates(excluding: Set<String>, hotspot: Bool = false) async throws -> [String] {
        guard let address = SharedWiFiPath.address(hotspot: hotspot),
            let mask = SharedWiFiPath.netmask(hotspot: hotspot),
            let hosts = MulticamDiscovery.hosts(address: address, mask: mask, excluding: excluding)
        else { throw DiscoveryFailure.unsupportedSubnet }
        var found: [String] = []
        for start in stride(from: 0, to: hosts.count, by: 24) {
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            let batch = Array(hosts[start..<min(start + 24, hosts.count)])
            let hits = await withTaskGroup(of: String?.self) { group in
                for host in batch {
                    group.addTask { await self.probe(host, localAddress: address) ? host : nil }
                }
                var results: [String] = []
                for await hit in group { if let hit { results.append(hit) } }
                return results
            }
            found += hits
            if found.count >= 8 { break }
        }
        return Array(found.prefix(8))
    }

    private func probe(_ host: String, localAddress: String) async -> Bool {
        guard !cancelled, !Task.isCancelled else { return false }
        let params = NWParameters.tcp
        params.prohibitedInterfaceTypes = [.cellular]
        params.requiredLocalEndpoint = .hostPort(host: .init(localAddress), port: .any)
        let connection = NWConnection(host: .init(host), port: 7001, using: params)
        connection.start(queue: .global(qos: .utility))
        defer { connection.cancel() }
        let deadline = Date().addingTimeInterval(0.8)
        while Date() < deadline && !cancelled && !Task.isCancelled {
            switch connection.state {
            case .ready: return true
            case .failed, .cancelled: return false
            default: break
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        return false
    }

    enum DiscoveryFailure: LocalizedError {
        case unsupportedSubnet
        var errorDescription: String? {
            "Automatic discovery needs a shared IPv4 network with at most 1,022 device addresses."
        }
    }
}
