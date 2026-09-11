import Foundation

/// Current Wi-Fi IPv4 path for cameras joined to the operator's network.
enum SharedWiFiPath {
    static func validAddress(_ value: String) -> Bool {
        var address = in_addr()
        guard inet_pton(AF_INET, value, &address) == 1 else { return false }
        let first = UInt8(truncatingIfNeeded: UInt32(bigEndian: address.s_addr) >> 24)
        return first > 0 && first < 224 && first != 127
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
