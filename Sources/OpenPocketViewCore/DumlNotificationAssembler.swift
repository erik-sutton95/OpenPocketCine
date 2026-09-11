import Foundation

/// One ordered BLE characteristic stream; notification boundaries are not DUML boundaries.
public struct DumlNotificationAssembler {
    private var pending: [UInt8] = []
    public init() {}
    public mutating func append(_ bytes: [UInt8]) -> [Duml.Frame] {
        guard bytes.count <= 4096 else {
            pending.removeAll()
            return []
        }
        if pending.count + bytes.count > 4096 { pending.removeAll() }
        pending.append(contentsOf: bytes)
        var output: [Duml.Frame] = []
        while pending.count >= 4 {
            guard pending[0] == 0x55, pending[2] >> 2 == 1,
                Duml.crc8(Array(pending.prefix(3))) == pending[3]
            else {
                pending.removeFirst()
                continue
            }
            let length = Int(pending[1]) | ((Int(pending[2]) & 3) << 8)
            guard length >= 13 else {
                pending.removeFirst()
                continue
            }
            guard pending.count >= length else { break }
            let checksum = UInt16(pending[length - 2]) | (UInt16(pending[length - 1]) << 8)
            if Duml.crc16(Array(pending.prefix(length - 2))) == checksum,
                let frame = DumlTransport.scanFrames(Array(pending.prefix(length))).first
            {
                output.append(frame)
                pending.removeFirst(length)
            } else {
                pending.removeFirst()
            }
        }
        return output
    }
}
