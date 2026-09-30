import Foundation

/// Chooses the Mac's shared-LAN IPv4. Personal Hotspot bridge names are ignored.
public enum MacLanPath {
    public struct Interface: Equatable, Sendable {
        public var name: String
        public var up: Bool
        public var ipv4: String
        public var netmask: String

        public init(name: String, up: Bool, ipv4: String, netmask: String) {
            self.name = name
            self.up = up
            self.ipv4 = ipv4
            self.netmask = netmask
        }
    }

    public static func validAddress(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
            let first = UInt8(parts[0]),
            let second = UInt8(parts[1]),
            UInt8(parts[2]) != nil,
            UInt8(parts[3]) != nil
        else { return false }
        if first == 0 || first == 127 || first >= 224 { return false }
        if first == 169 && second == 254 { return false }
        return true
    }

    /// Osmo SoftAP. Every camera is `192.168.2.1`, so this subnet cannot hold two cameras.
    public static func isCameraAccessPoint(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "192", parts[1] == "168", parts[2] == "2",
            let host = Int(parts[3])
        else { return false }
        return (2...254).contains(host)
    }

    /// Camera hotspot names. A normal router can also use `192.168.2.x`.
    public static func isOsmoSoftAP(_ ssid: String) -> Bool {
        let name = ssid.lowercased().replacingOccurrences(of: " ", with: "")
        return name.contains("osmo") || name.contains("dji") || name.contains("pocket")
            || name.contains("nano") || name.contains("atto")
    }

    /// Prefers `en0` when it is up. Down interfaces and iOS hotspot bridges are not candidates.
    public static func select(_ interfaces: [Interface]) -> Interface? {
        let usable = interfaces.filter { interface in
            interface.up && validAddress(interface.ipv4) && !isHotspotBridge(interface.name)
        }
        if let wifi = usable.first(where: { $0.name == "en0" }) { return wifi }
        return usable.first { $0.name.hasPrefix("en") } ?? usable.first
    }

    public static func isHotspotBridge(_ name: String) -> Bool {
        name.hasPrefix("bridge") || name.hasPrefix("ap")
    }

    /// The live shared-LAN address, when this Mac has one.
    public static func current() -> Interface? {
        select(interfaces())
    }

    public static func interfaces() -> [Interface] {
        #if canImport(Darwin)
            return darwinInterfaces()
        #else
            return []
        #endif
    }
}

#if canImport(Darwin)
    import Darwin

    extension MacLanPath {
        fileprivate static func darwinInterfaces() -> [Interface] {
            var pointer: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
            defer { freeifaddrs(first) }
            var interfaces: [Interface] = []
            var current = pointer
            while let item = current {
                defer { current = item.pointee.ifa_next }
                guard let address = item.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET)
                else { continue }
                let up = item.pointee.ifa_flags & UInt32(IFF_UP) != 0
                guard let ipv4 = numericHost(address),
                    let maskPointer = item.pointee.ifa_netmask,
                    let netmask = numericHost(maskPointer)
                else { continue }
                interfaces.append(
                    Interface(
                        name: String(cString: item.pointee.ifa_name), up: up, ipv4: ipv4,
                        netmask: netmask))
            }
            return interfaces
        }

        private static func numericHost(_ address: UnsafePointer<sockaddr>) -> String? {
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0,
                NI_NUMERICHOST)
            guard result == 0 else { return nil }
            return String(cString: host)
        }
    }
#endif
