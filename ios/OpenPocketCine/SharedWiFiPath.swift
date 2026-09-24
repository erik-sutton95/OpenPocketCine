import Foundation
import NetworkExtension

/// Current Wi-Fi IPv4 path for cameras joined to the operator's network.
enum SharedWiFiPath {
    static func validAddress(_ value: String) -> Bool {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return false }
        let first = UInt8(truncatingIfNeeded: UInt32(bigEndian: address.s_addr) >> 24)
        return first > 0 && first < 224 && first != 127
    }

    /// Joins this device to the operator's network and waits for its IPv4 address.
    /// Shared by Multiview and a saved camera's Wi-Fi setup.
    static func joinHost(ssid: String, password: String) async throws -> String? {
        if await WiFiJoiner.currentSSID() != ssid {
            let config =
                password.isEmpty
                ? NEHotspotConfiguration(ssid: ssid)
                : NEHotspotConfiguration(ssid: ssid, passphrase: password, isWEP: false)
            config.joinOnce = false
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                NEHotspotConfigurationManager.shared.apply(config) { error in
                    if let error,
                        (error as NSError).code
                            != NEHotspotConfigurationError.alreadyAssociated.rawValue
                    {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
        // iOS applied the join. It names the network only with location permission (or
        // for networks this app configured); an unnamed Wi-Fi address is accepted too.
        func joined() async -> Bool {
            let current = await WiFiJoiner.currentSSID()
            return current == ssid || (current == nil && address() != nil)
        }
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if await joined(), address() != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard await joined() else { return nil }
        return address()
    }

    static func address(hotspot: Bool = false) -> String? {
        interfaceAddress(netmask: false, hotspot: hotspot)
    }
    static func netmask(hotspot: Bool = false) -> String? {
        interfaceAddress(netmask: true, hotspot: hotspot)
    }

    private static func interfaceAddress(netmask: Bool, hotspot: Bool) -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0 else { return nil }
        defer { freeifaddrs(pointer) }
        var current = pointer
        while let item = current {
            defer { current = item.pointee.ifa_next }
            let name = String(cString: item.pointee.ifa_name)
            let matches =
                hotspot ? (name.hasPrefix("bridge") || name.hasPrefix("ap")) : name == "en0"
            guard matches, item.pointee.ifa_flags & UInt32(IFF_UP) != 0,
                let address = netmask ? item.pointee.ifa_netmask : item.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host,
                socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            {
                return String(cString: host)
            }
        }
        return nil
    }
}
