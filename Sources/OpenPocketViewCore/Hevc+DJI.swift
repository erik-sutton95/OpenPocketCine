import Foundation

/// DJI live-view framing on top of the shared HEVC/AVC NAL math (OpenCineMedia `Hevc`).
/// See docs/protocol-notes.md.
extension Hevc {
    public static let djiMarker = 63  // DJI's private per-frame marker (`00 00 01 ff …`)

    /// Drop DJI's `00 00 01 ff …` frame marker (NAL type 63): return the buffer from the first
    /// standard NAL onward. If none is found, return the input unchanged.
    public static func stripDjiMarker(_ annexB: [UInt8]) -> [UInt8] {
        var i = 0
        while i + 4 <= annexB.count {
            if annexB[i] == 0, annexB[i + 1] == 0, annexB[i + 2] == 1 {
                let t = nalType(annexB[i + 3])
                if t != djiMarker { return Array(annexB[i...]) }
                i += 3
            } else {
                i += 1
            }
        }
        return annexB
    }
}
