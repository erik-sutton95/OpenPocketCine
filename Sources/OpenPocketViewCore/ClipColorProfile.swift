import Foundation

/// Shot color from a Pocket / Osmo MP4. `colr`/`nclx` is Rec.709 even for
/// D-Log2; Mimo Color Recovery reads QuickTime Keys
/// `com.dji.camera.ColorGammaSxS` instead.
public enum ClipColorProfile: Sendable {
    public static let gammaKey = "com.dji.camera.ColorGammaSxS"
    /// Last 2 MiB covers `moov` (including cover-art `ilst`) on Pocket 4P takes.
    public static let fileTailBytes = 2 * 1024 * 1024

    public static func colorMode(fromGamma gamma: String) -> ColorMode? {
        switch gamma.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "Rec.709": .normal
        case "Rec.2100 HLG": .hdr
        case "D-Log": .dLog
        case "D-Log2": .dLog2
        case "D-Log M", "D-LogM", "DLogM": .dLogM
        default: nil
        }
    }

    public static func colorMode(fromMP4 data: Data) -> ColorMode? {
        guard let gamma = gamma(fromMP4: data) else { return nil }
        return colorMode(fromGamma: gamma)
    }

    /// Shot color for Auto LUT. LRF / XRF / LRV preview sidecars are Rec.709
    /// even when the original take is D-Log or D-Log2 — never treat proxy Keys
    /// as the profile.
    public static func shotColor(fromMP4 data: Data, path: String) -> ColorMode? {
        guard !MediaHTTP.isProxyPath(path) else { return nil }
        return colorMode(fromMP4: data)
    }

    /// HTTP Range for the `moov` tail. Camera `/v2` already answers Range.
    public static func httpRange(fileSize: UInt64) -> String {
        let window = UInt64(fileTailBytes)
        if fileSize > window {
            return "bytes=\(fileSize - window)-\(fileSize - 1)"
        }
        if fileSize > 0 {
            return "bytes=0-\(fileSize - 1)"
        }
        return "bytes=-\(fileTailBytes)"
    }

    public static func gamma(fromMP4 data: Data) -> String? {
        keys(fromMP4: data)[gammaKey]
    }

    public static func keys(fromMP4 data: Data) -> [String: String] {
        var found: [String: String] = [:]
        visit(data, start: 0, end: data.count, depth: 0, found: &found)
        if found[gammaKey] != nil { return found }
        if let moov = findType(data, type: "moov") {
            visit(data, start: moov.payload, end: moov.end, depth: 0, found: &found)
        }
        return found
    }

    private struct Box {
        var type: String
        var payload: Int
        var end: Int
    }

    private static func visit(
        _ data: Data, start: Int, end: Int, depth: Int, found: inout [String: String]
    ) {
        guard depth < 12, found[gammaKey] == nil else { return }
        var offset = start
        var names: [String] = []
        while offset + 8 <= end {
            guard let box = nextBox(data, at: offset, limit: end) else { break }
            switch box.type {
            case "keys":
                names = parseKeys(data, payload: box.payload, end: box.end)
            case "ilst" where box.end - box.payload < 8192:
                let values = parseIlst(data, payload: box.payload, end: box.end)
                for (index, value) in values where index >= 1 && index <= names.count {
                    found[names[index - 1]] = value
                }
            case "moov", "udta":
                visit(data, start: box.payload, end: box.end, depth: depth + 1, found: &found)
            case "meta":
                visit(data, start: box.payload, end: box.end, depth: depth + 1, found: &found)
                if found[gammaKey] == nil, box.payload + 4 < box.end {
                    visit(
                        data, start: box.payload + 4, end: box.end, depth: depth + 1, found: &found)
                }
            default:
                break
            }
            if found[gammaKey] != nil { return }
            offset = box.end
        }
    }

    private static func findType(_ data: Data, type: String) -> Box? {
        let needle = Array(type.utf8)
        guard needle.count == 4, data.count >= 8 else { return nil }
        return data.withUnsafeBytes { raw -> Box? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let count = data.count
            var i = 0
            while i + 8 <= count {
                if base[i + 4] == needle[0], base[i + 5] == needle[1],
                    base[i + 6] == needle[2], base[i + 7] == needle[3]
                {
                    if let box = nextBox(data, at: i, limit: count), box.type == type {
                        return box
                    }
                }
                i += 1
            }
            return nil
        }
    }

    private static func nextBox(_ data: Data, at offset: Int, limit: Int) -> Box? {
        guard offset + 8 <= limit else { return nil }
        let size32 = readU32(data, offset)
        let type = readFourCC(data, offset + 4)
        var header = 8
        var size = Int(size32)
        if size32 == 1 {
            guard offset + 16 <= limit else { return nil }
            let wide = readU64(data, offset + 8)
            guard wide <= UInt64(limit) else { return nil }
            size = Int(wide)
            header = 16
        } else if size32 == 0 {
            size = limit - offset
        }
        guard size >= header, offset + size <= limit else { return nil }
        return Box(type: type, payload: offset + header, end: offset + size)
    }

    private static func parseKeys(_ data: Data, payload: Int, end: Int) -> [String] {
        guard payload + 8 <= end else { return [] }
        let count = Int(readU32(data, payload + 4))
        guard (1...64).contains(count) else { return [] }
        var offset = payload + 8
        var names: [String] = []
        names.reserveCapacity(count)
        for _ in 0..<count {
            guard offset + 8 <= end else { break }
            let size = Int(readU32(data, offset))
            guard size >= 8, offset + size <= end else { break }
            let name = String(
                decoding: data[offset + 8..<offset + size],
                as: UTF8.self)
            names.append(name)
            offset += size
        }
        return names
    }

    private static func parseIlst(_ data: Data, payload: Int, end: Int) -> [Int: String] {
        var values: [Int: String] = [:]
        var offset = payload
        while offset + 8 <= end {
            guard let box = nextBox(data, at: offset, limit: end) else { break }
            let index = Int(readU32(data, box.payload - 4))
            var child = box.payload
            while child + 8 <= box.end {
                guard let dataBox = nextBox(data, at: child, limit: box.end) else { break }
                if dataBox.type == "data", dataBox.end - dataBox.payload >= 8 {
                    let bytes = data[dataBox.payload + 8..<dataBox.end]
                    let trimmed = bytes.prefix { $0 != 0 }
                    values[index] = String(decoding: trimmed, as: UTF8.self)
                    break
                }
                child = dataBox.end
            }
            offset = box.end
        }
        return values
    }

    private static func readU32(_ data: Data, _ offset: Int) -> UInt32 {
        data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian
        }
    }

    private static func readU64(_ data: Data, _ offset: Int) -> UInt64 {
        data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self).bigEndian
        }
    }

    private static func readFourCC(_ data: Data, _ offset: Int) -> String {
        String(decoding: data[offset..<offset + 4], as: UTF8.self)
    }
}
