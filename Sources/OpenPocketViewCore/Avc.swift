import Foundation

/// H.264 / AVC NAL helpers for Osmo Nano live view. Same UDP 9004 / pktType `0x02`
/// / DJI marker as Pocket HEVC; parameter sets are AVC SPS/PPS (`0x67`/`0x68`),
/// not HEVC VPS/SPS/PPS. Captured 2026-08-18 (`mimo-nano-live-20260818`).
public enum Avc {
    /// AVC NAL unit type: `firstByte & 0x1f`.
    public static func nalType(_ firstByte: UInt8) -> Int { Int(firstByte & 0x1f) }

    public static let nonIdr = 1
    public static let idr = 5
    public static let sei = 6
    public static let sps = 7
    public static let pps = 8
    public static let aud = 9

    public static func isVCL(_ t: Int) -> Bool { (1...5).contains(t) }
    public static func isKeyframeNal(_ t: Int) -> Bool { t == sps || t == pps || t == idr }
}

/// Which live-view codec an Annex-B access unit is. Pocket is HEVC; Nano is AVC.
public enum LiveVideoCodec: Equatable, Sendable {
    case hevc
    case avc
}

public enum LiveVideo {
    /// Classify from a NAL's first byte. Parameter sets are unambiguous;
    /// P-slices and IRAP slices alone are not classified.
    public static func codec(ofNAL firstByte: UInt8) -> LiveVideoCodec? {
        // HEVC param sets are 0x40/0x42/0x44. Nano AVC SPS/PPS are 0x67/0x68
        // (nal_ref_idc=3). Do not use `firstByte & 0x1f` — HEVC IDR_N_LP is 0x28,
        // which is also AVC PPS with nal_ref_idc=1, and that latched Pocket IDRs
        // as AVC (Android then MediaCodec.configure(AVC) threw; WAITING FOR LIVE VIEW).
        // AVC P-slice 0x41 is HEVC type 32 if we only look at `(b>>1)&0x3f`.
        switch firstByte {
        case 0x40, 0x42, 0x44: return .hevc
        case 0x67, 0x68: return .avc
        default: return nil
        }
    }

    public static func detect(nals: [[UInt8]]) -> LiveVideoCodec? {
        for nal in nals {
            guard let first = nal.first, let codec = codec(ofNAL: first) else { continue }
            return codec
        }
        return nil
    }

    public static func detect(annexB: [UInt8]) -> LiveVideoCodec? {
        detect(nals: Hevc.nalUnits(annexB))
    }
}
