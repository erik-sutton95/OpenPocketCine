import Foundation

/// `camcap_shutter` — legal shutter set the body publishes over `0x00/0x99`.
///
/// Not a `0x02/0x28` GET. SET stays `0x02/0x28`. The table reshapes with fps /
/// rec format / expo (Mimo re-pushes on those changes). Pocket 4 Pro value:
///
/// ```
/// 01 | innerLen:u16-LE | 10 B header | count × 3 B
/// header ends `05 <count>`
/// item = encoded:u16-LE + flag
/// encoded | 0x8000 → 1/N  (same encoding as the shutter SET)
/// encoded without 0x8000 → N seconds (photo); wheel ignores those
/// ```
public enum CamCapShutter {
    public static let subscribeKey = "camcap_shutter"

    /// 1/N denoms in camera order. Empty if the blob is not a shutter table.
    public static func parseDenoms(_ value: [UInt8]) -> [Int] {
        guard let items = parseItems(value) else { return [] }
        var seen = Set<Int>()
        var out: [Int] = []
        for item in items {
            guard case .fraction(let denom) = item else { continue }
            guard (1...16_000).contains(denom), !seen.contains(denom) else { continue }
            seen.insert(denom)
            out.append(denom)
        }
        return out
    }

    /// Wheel options: camera list only. Until a cap push lands, show the live value.
    public static func wheelDenoms(available: [Int], current: Int) -> [Int] {
        if !available.isEmpty { return available }
        return (1...16_000).contains(current) ? [current] : []
    }

    public static func nearestDenom(_ current: Int, in denoms: [Int]) -> Int? {
        guard !denoms.isEmpty else { return nil }
        return denoms.min(by: { abs($0 - current) < abs($1 - current) })
    }

    public static func label(_ denom: Int) -> String { "1/\(denom)" }

    public static func denom(from label: String) -> Int? {
        Int(label.replacingOccurrences(of: "1/", with: ""))
    }

    enum Item: Equatable, Sendable {
        case fraction(Int)
        case seconds(Int)
    }

    static func parseItems(_ value: [UInt8]) -> [Item]? {
        guard value.count >= 13, value[0] == 0x01 else { return nil }
        let inner = Int(value[1]) | (Int(value[2]) << 8)
        guard inner >= 10, 3 + inner <= value.count else { return nil }
        let body = Array(value[3..<(3 + inner)])
        if let items = itemsFromHeader(body) { return items }
        return scanItems(body)
    }

    private static func itemsFromHeader(_ body: [UInt8]) -> [Item]? {
        let count = Int(body[9])
        let payload = Array(body.dropFirst(10))
        guard count > 0, payload.count == count * 3 else { return nil }
        let items = decodeTriplets(payload)
        return items.isEmpty ? nil : items
    }

    /// Firmware that shifts the 10-byte header: take the densest run of 3-byte records.
    private static func scanItems(_ body: [UInt8]) -> [Item]? {
        var best: [Item] = []
        let maxOff = min(16, max(0, body.count - 6))
        for off in 0...maxOff {
            let slice = Array(body[off...])
            let n = slice.count / 3
            guard n >= 2 else { continue }
            let items = decodeTriplets(Array(slice.prefix(n * 3)))
            if fractionCount(items) > fractionCount(best) {
                best = items
            }
        }
        return fractionCount(best) >= 2 ? best : nil
    }

    private static func fractionCount(_ items: [Item]) -> Int {
        items.reduce(0) { count, item in
            if case .fraction = item { return count + 1 }
            return count
        }
    }

    private static func decodeTriplets(_ bytes: [UInt8]) -> [Item] {
        var items: [Item] = []
        var i = 0
        while i + 2 < bytes.count {
            let raw = Int(bytes[i]) | (Int(bytes[i + 1]) << 8)
            if raw & 0x8000 != 0 {
                let denom = raw & 0x7FFF
                if (1...16_000).contains(denom) {
                    items.append(.fraction(denom))
                }
            } else if (1...60).contains(raw) {
                items.append(.seconds(raw))
            }
            i += 3
        }
        return items
    }
}

/// `camcap_iso` — legal ISO indices for the current color / mode.
///
/// ```
/// 01 | innerLen:u16-LE | 00 | count:u8 | count × index
/// ```
/// D-Log2 example: `01 08 00 00 06 03 04 05 06 07 08` → 100…3200.
public enum CamCapIso {
    public static let subscribeKey = "camcap_iso"

    public static func parseIndices(_ value: [UInt8]) -> [IsoIndex] {
        guard value.count >= 5, value[0] == 0x01 else { return [] }
        let inner = Int(value[1]) | (Int(value[2]) << 8)
        guard inner >= 2, 3 + inner <= value.count else { return [] }
        let body = Array(value[3..<(3 + inner)])
        let count = Int(body[1])
        guard body[0] == 0, count >= 1, body.count >= 2 + count else { return [] }
        return body[2..<(2 + count)].compactMap { IsoIndex(rawValue: $0) }
    }

    public static func wheelIndices(available: [IsoIndex], fallback: [IsoIndex]) -> [IsoIndex] {
        available.isEmpty ? fallback : available
    }

    /// Native base ISO for the operator's current transfer. Decoration only —
    /// the wheel list stays `camcap_iso`.
    ///
    /// D-Log = 400, D-Log2 = 1600. Rec.709 / HLG have no published Pocket
    /// native base (OpenZCine stars Nikon 800/6400; do not invent a third).
    /// Uses `CameraStatus.monitorTransfer` (`colorMode` `@2`), not a tele hop SET.
    public static func baseISO(transfer: MonitorTransfer?) -> Int? {
        switch transfer {
        case .dlog: 400
        case .dlog2: 1600
        case .rec709, .hdr, nil: nil
        }
    }

    public static func baseISO(colorMode: ColorMode?) -> Int? {
        switch colorMode {
        case .dLog: 400
        case .dLog2: 1600
        default: nil
        }
    }

    public static func markedLabels(transfer: MonitorTransfer?) -> Set<String> {
        guard let iso = baseISO(transfer: transfer) else { return [] }
        return ["\(iso)"]
    }

    public static func markedLabels(colorMode: ColorMode?) -> Set<String> {
        markedLabels(transfer: colorMode.map(MonitorTransfer.init))
    }

    /// If the operator is still on `from`'s native ISO, hop to `to`'s native.
    /// Off-base or Auto stays put. Rec.709 / HDR have no native — no hop.
    /// `hopEnabled` is the ISO-sheet Native ISO toggle (default on).
    public static func nativeISOHop(
        from: ColorMode?, to: ColorMode, current: IsoIndex?,
        hopEnabled: Bool = true
    ) -> IsoIndex? {
        guard hopEnabled else { return nil }
        guard let from, from != to else { return nil }
        guard let fromBase = baseISO(colorMode: from),
            let toBase = baseISO(colorMode: to)
        else { return nil }
        guard let current, current != .auto, current.isoValue == fromBase else { return nil }
        return to.isoIndices.first { $0.isoValue == toBase }
    }
}

/// Nano `camcap_color_mode` (Mimo 2026-08-18): `01 04 00 03 00 3F 3D`.
/// Pocket never published this table in our takes.
public enum CamCapColorMode {
    public static let subscribeKey = "camcap_color_mode"

    public static func parse(_ value: [UInt8]) -> [ColorMode] {
        guard value.count >= 5, value[0] == 0x01 else { return [] }
        let inner = Int(value[1]) | (Int(value[2]) << 8)
        guard inner >= 2, 3 + inner <= value.count else { return [] }
        let body = Array(value[3..<(3 + inner)])
        let count = Int(body[0])
        guard count >= 1, body.count >= 1 + count else { return [] }
        return body[1..<(1 + count)].compactMap { ColorMode(rawValue: $0) }
    }

    public static func wheel(
        available: [ColorMode], family: CameraBodyFamily
    ) -> [ColorMode] {
        wheel(available: available, order: ColorMode.available(for: family))
    }

    public static func wheel(available: [ColorMode], model: CameraModel) -> [ColorMode] {
        wheel(available: available, order: ColorMode.available(for: model))
    }

    /// Body order is the legal set. `camcap_color_mode` may subset it.
    /// It cannot add D-Log2 (or `0x17` D-Log) to a body that does not have them.
    private static func wheel(available: [ColorMode], order: [ColorMode]) -> [ColorMode] {
        guard !available.isEmpty else { return order }
        let have = Set(available)
        let ranked = order.filter { have.contains($0) }
        return ranked.isEmpty ? order : ranked
    }
}

/// `camcap_video_format` — legal `[res][fps]` pairs for the current shooting mode.
///
/// Mimo live-start 2026-08-28 (Pocket 4 Pro, Video):
/// `01 25 00 0c` then 12× `[res][fps_idx] 00` — 4K 24–60 then 1080p 60–24.
/// Slow-mo 100/120/240 is a different shooting mode; this table is Video only.
public enum CamCapVideoFormat {
    public static let subscribeKey = "camcap_video_format"

    public static func parse(_ value: [UInt8]) -> [VideoFormat] {
        guard value.count >= 5, value[0] == 0x01 else { return [] }
        let inner = Int(value[1]) | (Int(value[2]) << 8)
        guard inner >= 2, 3 + inner <= value.count else { return [] }
        let body = Array(value[3..<(3 + inner)])
        let count = Int(body[0])
        guard count >= 1, body.count >= 1 + count * 3 else { return [] }
        var out: [VideoFormat] = []
        var seen = Set<VideoFormat>()
        var i = 1
        for _ in 0..<count {
            guard i + 2 < body.count else { break }
            if let format = VideoFormat.parseVideoParamV2(Array(body[i..<(i + 2)])),
                seen.insert(format).inserted
            {
                out.append(format)
            }
            i += 3
        }
        return out
    }

    public static func resolutions(
        available: [VideoFormat], current: VideoResolution?
    ) -> [VideoResolution] {
        if available.isEmpty {
            return VideoResolution.allCases
        }
        var seen = Set<VideoResolution>()
        var out: [VideoResolution] = []
        for format in available where seen.insert(format.resolution).inserted {
            out.append(format.resolution)
        }
        if let current, !seen.contains(current) {
            out.insert(current, at: 0)
        }
        return out
    }

    public static func frameRates(
        available: [VideoFormat], resolution: VideoResolution, current: VideoFrameRate?
    ) -> [VideoFrameRate] {
        let rates = available.filter { $0.resolution == resolution }.map(\.frameRate)
        if rates.isEmpty {
            // SlowMo 100/120/240 is not a labeled Video SET. Until camcap
            // republishes that mode, keep the live rate rather than offering 24–60.
            if let current, !VideoFrameRate.labeledVideo.contains(current) {
                return [current]
            }
            return VideoFrameRate.labeledVideo
        }
        return rates
    }
}

/// `camcap_iso_auto_max` — Auto ISO ceiling table + color-mode base.
///
/// ```
/// 02 | innerLen:u16-LE | count | count × IsoLimit | base:u16-LE
/// ```
/// Normal/HDR: `02 0b 00 08 02…09 64 00` → 100 + 200…25600.
/// D-Log: `02 07 00 04 04…07 90 01` → 400 + 800…6400.
/// D-Log2: `01 01 00 00` → no Auto.
///
/// Wheel lists stay on `ColorMode.isoAutoLimits`. This parser pins the capture.
public enum CamCapIsoAutoMax {
    public static let subscribeKey = "camcap_iso_auto_max"

    public static func parse(_ value: [UInt8]) -> (base: Int, limits: [IsoLimit])? {
        guard !value.isEmpty else { return nil }
        if value[0] == 0x01 {
            return (0, [])
        }
        guard value.count >= 6, value[0] == 0x02 else { return nil }
        let inner = Int(value[1]) | (Int(value[2]) << 8)
        guard inner >= 3, 3 + inner <= value.count else { return nil }
        let body = Array(value[3..<(3 + inner)])
        let count = Int(body[0])
        guard count >= 1, body.count >= 1 + count + 2 else { return nil }
        let limits = body[1..<(1 + count)].compactMap { IsoLimit(rawValue: $0) }
        guard limits.count == count else { return nil }
        let baseAt = 1 + count
        let base = Int(UInt16(body[baseAt]) | (UInt16(body[baseAt + 1]) << 8))
        return (base, limits)
    }
}
