import Foundation

/// Camera-reported network names. Keep security/radio fields opaque until verified.
public enum MulticamWiFiScan {
    public static func request(seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: 2, receiver: 0x1b, seq: seq, flags: 0x40,
            cmdSet: 7, cmdId: 0xab, payload: [])
    }

    /// Observed 07/AC report: four-byte header, then length-prefixed records.
    /// Record length includes its length byte, five metadata bytes, and UTF-8 SSID.
    public static func names(_ bytes: [UInt8]) -> [String] {
        guard bytes.count >= 4, bytes[0] == 1, bytes[1] == 0x11 else { return [] }
        var result: [String] = []
        var offset = 4
        while offset < bytes.count {
            let length = Int(bytes[offset])
            guard length >= 6, length <= 38, offset + length <= bytes.count else { return [] }
            let raw = Array(bytes[(offset + 6)..<(offset + length)])
            if !raw.isEmpty, !raw.contains(0), let name = String(bytes: raw, encoding: .utf8),
                !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }
                ),
                !result.contains(name)
            {
                result.append(name)
            }
            offset += length
        }
        return result
    }
}
