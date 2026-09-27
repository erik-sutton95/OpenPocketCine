import UIKit

@testable import OpenPocketCine

/// Synthetic gray 64x64 HEVC, generated with libx265, bframes=0 and a single
/// IDR. Excludes encoder metadata; these are not camera captures.
enum HevcFixture {
    static let keyframe: [UInt8] = [
        "40010c01ffff01600000030090000003000003001eba0240",
        "42010101600000030090000003000003001ea020810596e92930bc05a02000000300200000030321",
        "4401c073c089",
        "2801ac76071c24748e",
    ].flatMap { [UInt8]([0, 0, 0, 1]) + bytes($0) }
    static let pFrame = [UInt8]([0, 0, 0, 1]) + bytes("0201d0097883b0a098")

    /// SoftAP video packet: 20-byte header, video type at byte 6, frame index at byte 16.
    static func packet(_ frame: UInt8, _ accessUnit: [UInt8]) -> [UInt8] {
        var header = [UInt8](repeating: 0, count: 20)
        header[6] = 2
        header[16] = frame
        return header + accessUnit
    }

    private static func bytes(_ hex: String) -> [UInt8] {
        stride(from: 0, to: hex.count, by: 2).map { offset in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        }
    }
}

/// Every display layer host under `view`, depth first.
@MainActor func displayHosts(in view: UIView) -> [DisplayLayerView] {
    (view as? DisplayLayerView).map { [$0] } ?? view.subviews.flatMap { displayHosts(in: $0) }
}
