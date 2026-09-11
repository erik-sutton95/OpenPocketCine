import Foundation

/// Bounded unicast discovery on the operator's actual IPv4 subnet.
public enum MulticamDiscovery {
    public static func hosts(address: String, mask: String, excluding: Set<String> = [])
        -> [String]?
    {
        func parse(_ string: String) -> UInt32? {
            let parts = string.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count == 4 else { return nil }
            var value: UInt32 = 0
            for part in parts {
                guard let byte = UInt8(part) else { return nil }
                value = (value << 8) | UInt32(byte)
            }
            return value
        }
        guard let ip = parse(address), let netmask = parse(mask) else { return nil }
        let hostBits = ~netmask
        guard hostBits > 1, hostBits <= 1023, hostBits & (hostBits &+ 1) == 0 else { return nil }
        let network = ip & netmask
        return (1..<hostBits).compactMap { offset in
            let value = network | offset
            let host = [24, 16, 8, 0].map { String((value >> $0) & 255) }.joined(separator: ".")
            return value == ip || excluding.contains(host) ? nil : host
        }
    }
}
