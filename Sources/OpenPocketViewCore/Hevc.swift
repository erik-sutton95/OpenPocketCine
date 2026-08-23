import Foundation

/// HEVC / H.265 helpers for the Osmo live view: Annex-B NAL splitting, NAL typing, and stripping
/// DJI's per-frame marker. Pure — the VideoToolbox decode lives in the app. See docs/protocol-notes.md.
public enum Hevc {
    /// HEVC NAL unit type from the first byte of the 2-byte NAL header: `(b >> 1) & 0x3f`.
    public static func nalType(_ firstByte: UInt8) -> Int { Int((firstByte >> 1) & 0x3f) }

    // Named types we care about.
    public static let vps = 32, sps = 33, pps = 34
    public static let idr = 20  // IDR_N_LP — the Pocket's keyframe slice
    public static let djiMarker = 63  // DJI's private per-frame marker (`00 00 01 ff …`)
    public static func isVCL(_ t: Int) -> Bool { t <= 31 }  // 0..31 = coded slice NALs
    public static func isKeyframeNal(_ t: Int) -> Bool {
        t == vps || t == sps || t == pps || t == idr
    }

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

    /// Split an Annex-B buffer into raw NAL units (start codes removed). Handles 3- and 4-byte
    /// start codes by trimming a trailing zero that belongs to the next start code.
    public static func nalUnits(_ annexB: [UInt8]) -> [[UInt8]] {
        var starts: [Int] = []
        var i = 0
        while i + 3 <= annexB.count {
            if annexB[i] == 0, annexB[i + 1] == 0, annexB[i + 2] == 1 {
                starts.append(i + 3)
                i += 3
            } else {
                i += 1
            }
        }
        var nals: [[UInt8]] = []
        for (k, s) in starts.enumerated() {
            var e = (k + 1 < starts.count) ? starts[k + 1] - 3 : annexB.count
            while e > s && annexB[e - 1] == 0 { e -= 1 }  // ponytail: drops a genuine trailing 0x00 too; harmless for decode
            if e > s { nals.append(Array(annexB[s..<e])) }
        }
        return nals
    }
}
