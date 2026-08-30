import Foundation

/// One file from a DUML `0x00/0x27` CompositePack manifest (Osmosis `CameraFile`).
public struct MediaFile: Equatable, Sendable, Identifiable, Hashable, Codable {
    public var path: String
    public var thumbPath: String
    public var handle: UInt32
    public var cmdHandle: UInt32
    public var sizeBytes: UInt64
    public var durationSeconds: Int
    public var isStarred: Bool
    public var resolution: String?
    public var fps: Int?
    public var proxyPath: String?
    public var storage: Int
    public var group: Int
    public var handleShared: Bool
    /// The handle read at the marker's fixed position, before the base+step fit has vouched for it.
    /// Untrusted on its own — see `withCmdHandles`. Zero when the record carries no marker.
    public var handleCandidate: UInt32

    public init(
        path: String,
        thumbPath: String,
        handle: UInt32 = 0,
        cmdHandle: UInt32 = 0,
        sizeBytes: UInt64 = 0,
        durationSeconds: Int = 0,
        isStarred: Bool = false,
        resolution: String? = nil,
        fps: Int? = nil,
        proxyPath: String? = nil,
        storage: Int = 0,
        group: Int = 0,
        handleShared: Bool = false,
        handleCandidate: UInt32 = 0
    ) {
        self.path = path
        self.thumbPath = thumbPath
        self.handle = handle
        self.cmdHandle = cmdHandle
        self.sizeBytes = sizeBytes
        self.durationSeconds = durationSeconds
        self.isStarred = isStarred
        self.resolution = resolution
        self.fps = fps
        self.proxyPath = proxyPath
        self.storage = storage
        self.group = group
        self.handleShared = handleShared
        self.handleCandidate = handleCandidate
    }

    public var id: String { path }
    public var filename: String { (path as NSString).lastPathComponent }
    public var fileExtension: String {
        (filename as NSString).pathExtension.uppercased()
    }

    public var kind: MediaKind {
        MediaKind.from(extension: fileExtension)
    }

    public var isDeletable: Bool { handle != 0 && !handleShared }

    public var favoriteHandle: UInt32 {
        handle != 0 ? handle : cmdHandle
    }

    /// `YYYYMMDDHHmmss` baked into `DJI_20260814125250_0034_D.MP4`.
    public var filenameTimestamp: String? {
        MediaFile.group(MediaFile.timestampRegex, in: filename, at: 1)
    }

    public var captureDate: Date? {
        guard let stamp = filenameTimestamp, stamp.count == 14 else { return nil }
        return MediaFile.timestampFormatter.date(from: stamp)
    }

    public var dateKey: String { filenameTimestamp.map { String($0.prefix(8)) } ?? "" }

    /// `DJI_…_0034_D` sequence used to fit `base + seq × step`.
    public var sequenceNumber: Int {
        MediaFile.group(MediaFile.sequenceRegex, in: filename, at: 1).flatMap(Int.init) ?? 0
    }

    public var burstGroupKey: String? {
        MediaFile.group(MediaFile.burstRegex, in: filename, at: 1)
    }

    public var burstIndex: Int {
        MediaFile.group(MediaFile.burstRegex, in: filename, at: 2).flatMap(Int.init) ?? 0
    }

    public var isBurstLead: Bool { burstGroupKey != nil }

    private static let timestampRegex = try! NSRegularExpression(pattern: #"_(\d{14})_"#)
    private static let sequenceRegex = try! NSRegularExpression(pattern: #"_(\d{4})_D"#)
    private static let burstRegex = try! NSRegularExpression(pattern: #"^(.+)_(\d{3})\.\w+$"#)

    private static func group(_ regex: NSRegularExpression, in string: String, at index: Int)
        -> String?
    {
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
            let captured = Range(match.range(at: index), in: string)
        else { return nil }
        return String(string[captured])
    }
    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()
}

public enum MediaKind: String, Sendable, Codable {
    case video
    case photo

    public static func from(extension ext: String) -> MediaKind {
        switch ext.uppercased() {
        case "JPG", "JPEG", "DNG", "HEIC", "TIF", "TIFF", "PANO":
            return .photo
        default:
            return .video
        }
    }
}

/// What the phone has for a clip. Playback grades the proxy; Share needs the original.
public enum MediaCacheGrade: String, Sendable, Equatable {
    case none
    case proxy
    case original

    public var isPlayableOffline: Bool { self != .none }
    public var isProxyOnly: Bool { self == .proxy }

    public static func resolve(hasOriginal: Bool, hasProxy: Bool) -> MediaCacheGrade {
        if hasOriginal { return .original }
        if hasProxy { return .proxy }
        return .none
    }
}

/// SoftAP HTTP `/v2` paths. Osmosis `PathAddressing` + `StorageRules`.
public enum MediaHTTP {
    public static let host = CameraSoftAP.host
    public static let port = 80

    public static func pathURL(storage: Int, path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/v2"
        components.queryItems = [
            URLQueryItem(name: "storage", value: String(storage)),
            URLQueryItem(name: "path", value: path),
        ]
        return components.url
    }

    /// Guess `/v2?storage=` from the delete handle's `0x40000000` bit.
    /// Internal → 1, SD → 0. Pocket 3 is the single-microSD exception (`0`).
    public static func storageGuess(handle: UInt32, singleSdStorage: Bool) -> Int {
        if singleSdStorage { return 0 }
        return (handle & MediaListCommand.internalBit) != 0 ? 1 : 0
    }

    public static func originalPath(_ file: MediaFile) -> String { file.path }

    /// Clip delivery / export: the original camera file, never the LRF/XRF 720p proxy.
    public static func deliveryPath(_ file: MediaFile) -> String { originalPath(file) }

    public static func thumbnailPath(_ file: MediaFile) -> String { file.thumbPath }

    /// Preview chain: listed proxy, derived `.LRF` (DJI) / `.XRF` (CAM_), then original.
    public static func previewPaths(_ file: MediaFile) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        func add(_ path: String) {
            guard seen.insert(path).inserted else { return }
            paths.append(path)
        }
        if let proxy = file.proxyPath { add(proxy) }
        if let derived = derivedProxyPath(for: file) { add(derived) }
        add(file.path)
        return paths
    }

    /// LRF/XRF sidecars only. Empty for photos and clips with no DJI proxy.
    public static func proxyPaths(_ file: MediaFile) -> [String] {
        previewPaths(file).filter { isProxyPath($0) }
    }

    public static func derivedProxyPath(for file: MediaFile) -> String? {
        guard let ext = derivedProxyExtension(filename: file.filename) else { return nil }
        let base = (file.path as NSString).deletingPathExtension
        return "\(base).\(ext)"
    }

    public static func derivedProxyExtension(filename: String) -> String? {
        if filename.hasPrefix("CAM_") { return "XRF" }
        if filename.hasPrefix("DJI_") { return "LRF" }
        return nil
    }

    /// Ordered `(storage, path)` pairs to try when opening a clip. Winner storage first, then
    /// the other mount; listed/derived proxy first, original last. `/v2` itself has no
    /// extension, so the player must carry [playbackMIMEType] separately.
    public static func playbackCandidates(file: MediaFile, firstStorage: Int) -> [(
        storage: Int, path: String
    )] {
        let stores = firstStorage == 0 ? [0, 1] : [1, 0]
        var out: [(storage: Int, path: String)] = []
        var seen = Set<String>()
        for path in previewPaths(file) {
            for storage in stores {
                let key = "\(storage)\0\(path)"
                if seen.insert(key).inserted {
                    out.append((storage, path))
                }
            }
        }
        return out
    }

    public static func isProxyPath(_ path: String) -> Bool {
        switch (path as NSString).pathExtension.uppercased() {
        case "LRF", "LRV", "XRF": return true
        default: return false
        }
    }

    /// AVPlayer keys off the URL path. Camera `/v2` has none, so pass this as
    /// `AVURLAssetOutOfBandMIMETypeKey`. Sidecar proxies are MP4-in-disguise.
    public static func playbackMIMEType(for path: String) -> String {
        switch (path as NSString).pathExtension.uppercased() {
        case "JPG", "JPEG": return "image/jpeg"
        case "DNG": return "image/x-adobe-dng"
        case "HEIC": return "image/heic"
        default: return "video/mp4"
        }
    }

    /// AVPlayer keys off the file extension. Sidecar `.LRF` / `.XRF` are MP4-in-disguise.
    public static func playbackCacheFileName(_ path: String) -> String {
        let raw = path.replacingOccurrences(of: "/", with: "_")
        switch (raw as NSString).pathExtension.uppercased() {
        case "MP4", "MOV":
            return raw
        default:
            return ((raw as NSString).deletingPathExtension) + ".mp4"
        }
    }
}

/// `0x00/0x26` list payloads. Byte-identical to Osmosis / Mimo.
public enum MediaListCommand {
    public static let pageSize = 45
    public static let newestSD: UInt32 = 0x0000_0001
    public static let newestInternal: UInt32 = 0x4000_0001
    public static let videoHandleBase: UInt32 = 0x4000_0000
    public static let internalBit: UInt32 = 0x4000_0000
    public static let sdCounter: UInt8 = 1
    public static let internalCounter: UInt8 = 2

    public static let listTemplate: [UInt8] = [
        0x4A, 0x00, 0x2A, 0x10,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00,
        0x2D, 0x00, 0x0D, 0x01, 0x00,
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00,
    ]

    public static let triggerPayload: [UInt8] = [
        0x4A, 0x04, 0x0E, 0x10,
        0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x01, 0x00, 0x00, 0x00,
    ]

    public static func listPayload(counter: UInt8, cursor: UInt32) -> [UInt8] {
        var payload = listTemplate
        payload[4] = counter
        payload[10] = UInt8(cursor & 0xFF)
        payload[11] = UInt8((cursor >> 8) & 0xFF)
        payload[12] = UInt8((cursor >> 16) & 0xFF)
        payload[13] = UInt8((cursor >> 24) & 0xFF)
        return payload
    }

    /// Oldest video handle on this page — seeds the next `0x00/0x26` cursor.
    public static func oldestVideoHandle(_ handles: [UInt32]) -> UInt32? {
        handles.filter { $0 >= videoHandleBase }.min()
    }

    /// Oldest video handle strictly older than `cursor`, or nil at the end of the library.
    public static func nextCursor(handles: [UInt32], current: UInt32) -> UInt32? {
        let older = handles.filter { $0 >= videoHandleBase && $0 < current }
        return older.min()
    }

    public static func hasOlderPage(recordCount: Int, cursor: UInt32?) -> Bool {
        guard let cursor, cursor > 0 else { return false }
        return recordCount >= pageSize
    }
}

/// Strip `0x00/0x27` 10-byte sub-headers and concat data chunks in arrival order.
public struct MediaChunkAssembler: Sendable {
    public private(set) var chunksByCounter: [UInt8: [UInt8]] = [:]
    public private(set) var chunkCount = 0
    public private(set) var sawEnd = false

    public init() {}

    public mutating func reset() {
        chunksByCounter = [:]
        chunkCount = 0
        sawEnd = false
    }

    /// Accept a decoded DUML frame. Only `0x00/0x27` contributes.
    @discardableResult
    public mutating func ingest(_ frame: Duml.Frame) -> Bool {
        guard frame.cmdSet == 0x00, frame.cmdId == 0x27 else { return false }
        return ingestPayload(frame.payload)
    }

    @discardableResult
    public mutating func ingestPayload(_ payload: [UInt8]) -> Bool {
        guard payload.count >= 10, payload[0] == 0x4A else { return false }
        let subtype = payload[1]
        if subtype == 0x03 {
            sawEnd = true
            return true
        }
        guard subtype == 0x01, payload.count > 10 else { return false }
        let counter = payload[4]
        chunksByCounter[counter, default: []].append(contentsOf: payload.dropFirst(10))
        chunkCount += 1
        return true
    }

    public func assembled(counter: UInt8) -> [UInt8] {
        chunksByCounter[counter] ?? []
    }

    public func assembledMerged() -> [UInt8] {
        var out: [UInt8] = []
        for key in chunksByCounter.keys.sorted() {
            out.append(contentsOf: chunksByCounter[key] ?? [])
        }
        return out
    }

    public var isEmpty: Bool { chunkCount == 0 }
}

/// CompositePack TLV decode. Port of Osmosis `CameraSession.decodeComposite`.
public enum MediaManifest {
    public static let videoExtensions: Set<String> = [
        "MP4", "MOV", "OSV", "INSV", "LRF", "LRV", "XRF",
    ]
    public static let photoExtensions: Set<String> = [
        "JPG", "JPEG", "DNG", "HEIC", "TIF", "TIFF", "PANO",
    ]

    public static func decode(_ bytes: [UInt8]) -> [MediaFile] {
        let records = decodeComposite(bytes)
        return flagHandleCollisions(withCmdHandles(records))
    }

    public static func decode(_ data: Data) -> [MediaFile] {
        decode([UInt8](data))
    }

    /// Split one collected blob into SD (ctr 1) and internal (ctr 2) when the camera echoed counters.
    public static func decodeStores(assembler: MediaChunkAssembler) -> [MediaFile] {
        let sdBytes = assembler.assembled(counter: MediaListCommand.sdCounter)
        let internalBytes = assembler.assembled(counter: MediaListCommand.internalCounter)
        let sd = sdBytes.isEmpty ? [] : decode(sdBytes)
        let intern = internalBytes.isEmpty ? [] : decode(internalBytes)
        let sdPaths = Set(sd.map(\.path))
        let inPaths = Set(intern.map(\.path))
        if !sd.isEmpty, !intern.isEmpty, sdPaths == inPaths {
            return stampStorage(decode(assembler.assembledMerged()), fallback: true)
        }
        if sd.isEmpty, intern.isEmpty {
            let merged = assembler.assembledMerged()
            return merged.isEmpty ? [] : stampStorage(decode(merged), fallback: true)
        }
        var out: [MediaFile] = []
        out.append(contentsOf: sd.map { stamp($0, storage: 0, group: 0) })
        out.append(contentsOf: intern.map { stamp($0, storage: 1, group: 1) })
        return out
    }

    public static func headerCount(_ bytes: [UInt8]) -> Int {
        guard bytes.count >= 4 else { return 0 }
        return Int(u32(bytes, 0))
    }

    // MARK: - CompositePack

    private struct MediaAnchor {
        var pos: Int
        var end: Int
        var path: String
    }

    private static func decodeComposite(_ bytes: [UInt8]) -> [MediaFile] {
        var medias: [MediaAnchor] = []
        var i = 0
        while i < bytes.count {
            if let field = readPath(bytes, i, sub: 1, prefix: "DCIM/") {
                medias.append(MediaAnchor(pos: i, end: field.end, path: field.value))
                i = field.end
            } else {
                i += 1
            }
        }
        guard !medias.isEmpty else { return [] }

        let boundary = listBoundary(bytes, records: medias.count)
        var byPath: [String: MediaFile] = [:]
        var order: [String] = []
        for (k, media) in medias.enumerated() {
            let lo = k > 0 ? medias[k - 1].end : 0
            let hi = k + 1 < medias.count ? medias[k + 1].pos : bytes.count
            let group = (boundary > 0 && k >= boundary) ? 1 : 0
            if byPath[media.path] == nil {
                var file = resolveRecord(
                    bytes, mediaDir: media.path, selfPos: media.pos, lo: lo, hi: hi)
                file.group = group
                byPath[media.path] = file
                order.append(media.path)
            }
        }
        return order.compactMap { byPath[$0] }
    }

    private struct PathField {
        var value: String
        var end: Int
    }

    private static func readPath(
        _ bytes: [UInt8], _ i: Int, sub: UInt8, prefix: String
    ) -> PathField? {
        guard i + 6 <= bytes.count, bytes[i] == 0x1A else { return nil }
        guard bytes[i + 2] == 0, bytes[i + 3] == 0, bytes[i + 4] == 0 else { return nil }
        guard bytes[i + 5] == sub else { return nil }
        let slen = Int(bytes[i + 1]) - 6
        guard slen >= prefix.utf8.count, i + 6 + slen <= bytes.count else { return nil }
        let raw = bytes[i + 6..<i + 6 + slen]
        guard raw.allSatisfy({ (0x20...0x7E).contains($0) }) else { return nil }
        let value = String(bytes: raw, encoding: .isoLatin1) ?? ""
        guard value.hasPrefix(prefix) else { return nil }
        return PathField(value: value, end: i + 6 + slen)
    }

    private static func listBoundary(_ bytes: [UInt8], records: Int) -> Int {
        guard bytes.count >= 4 else { return -1 }
        let declared = Int(u32(bytes, 0))
        return (declared >= 1 && declared < records) ? declared : -1
    }

    private static func resolveRecord(
        _ bytes: [UInt8], mediaDir: String, selfPos: Int, lo: Int, hi: Int
    ) -> MediaFile {
        let base = (mediaDir as NSString).lastPathComponent
        var thumb: String?
        var t = lo
        while t < hi {
            if let field = readPath(bytes, t, sub: 2, prefix: "MISC/"),
                field.value.hasSuffix(base)
            {
                thumb = field.value
                break
            }
            t += 1
        }

        var ext = ""
        var proxyExt: String?
        var n = lo
        while n < hi - 2 {
            if bytes[n] == 0x0D {
                let len = Int(bytes[n + 1])
                if len > base.utf8.count, n + 2 + len <= bytes.count {
                    let raw = bytes[n + 2..<n + 2 + len]
                    if let value = String(bytes: raw, encoding: .isoLatin1),
                        value.utf8.count > base.utf8.count + 1,
                        value.hasPrefix(base),
                        value.dropFirst(base.count).first == "."
                    {
                        let e = String(value.dropFirst(base.count + 1)).uppercased()
                        if videoExtensions.contains(e) || photoExtensions.contains(e) {
                            ext = e
                        } else if e == "LRF" || e == "LRV" || e == "XRF" {
                            proxyExt = e
                        }
                    }
                }
            }
            n += 1
        }

        var head = -1
        var m = lo
        while m < hi - 4 {
            let kind = bytes[m]
            let star = bytes[m + 1]
            if kind == 0x03 || kind == 0x00,
                star == 0xFF || star == 0xFE,
                bytes[m + 2] == 0x19, bytes[m + 3] == 0x06, m >= 8
            {
                head = m - 8
                break
            }
            m += 1
        }
        let hasMarker = head >= 0
        let isVideo = videoExtensions.contains(ext)

        // The handle at the marker's FIXED position — `u32-LE` at `(19 06) − 10`, the same tag the
        // media type is read from. Unlike the scan above this needs no guard byte to match and
        // cannot run into the next record, so it finds the stills a Pocket 3 writes with `f6`/`c7`
        // guard bytes that the scan walks straight past. Untrusted here: `withCmdHandles` promotes
        // it only where the independent base+step fit agrees. Osmosis `CameraSession.kt` (#22).
        let handleCandidate: UInt32 = {
            guard selfPos >= 17, selfPos <= bytes.count,
                bytes[selfPos - 7] == 0x19, bytes[selfPos - 6] == 0x06
            else { return 0 }
            return u32(bytes, selfPos - 17)
        }()

        var photoSize: UInt64 = 0
        var photoRes: String?
        if !isVideo {
            var q = lo
            while q < hi - 3 {
                if bytes[q] == 0xFF || bytes[q] == 0xFE,
                    bytes[q + 1] == 0x19, bytes[q + 2] == 0x06
                {
                    let mk = q + 1
                    if mk >= 14 { photoSize = UInt64(u32(bytes, mk - 14)) }
                    if base.hasPrefix("DJI_"), mk + 66 <= bytes.count {
                        let w = Int(u32(bytes, mk + 58))
                        let h = Int(u32(bytes, mk + 62))
                        if (1...60_000).contains(w), (1...60_000).contains(h) {
                            photoRes = "\(w)x\(h)"
                        }
                    }
                    break
                }
                q += 1
            }
        }

        let path = ext.isEmpty ? mediaDir : "\(mediaDir).\(ext)"
        let thumbPath =
            (thumb
                ?? mediaDir.replacingOccurrences(of: "DCIM/", with: "MISC/THM/", options: .anchored))
            + ".scr"
        let handle: UInt32 = hasMarker ? u32(bytes, head) : 0
        let size: UInt64 = {
            if isVideo, hasMarker, head >= 4 { return UInt64(u32(bytes, head - 4)) }
            return photoSize
        }()
        let fps = isVideo && hasMarker ? fpsInRange(bytes, start: head, end: hi) : nil
        let duration: Int = {
            guard isVideo, hasMarker, head + 6 <= bytes.count else { return 0 }
            return Int(bytes[head + 4]) | (Int(bytes[head + 5]) << 8)
        }()
        let resolution: String? = {
            if isVideo, hasMarker, head + 7 < bytes.count {
                return resolutionForIndex(Int(bytes[head + 7]))
            }
            return photoRes
        }()
        return MediaFile(
            path: path,
            thumbPath: thumbPath,
            handle: handle,
            sizeBytes: size,
            durationSeconds: duration,
            // Prefer the signature read where the record has one: it is the only thing that works
            // on a body whose stills carry no marker, and it agreed with the marker read
            // everywhere both fired.
            isStarred: starFlagBySignature(bytes, lo: selfPos >= 0 ? selfPos : lo, hi: hi)
                ?? starFlag(bytes, lo: lo, hi: hi),
            resolution: resolution,
            fps: fps,
            proxyPath: proxyExt.map { "\(mediaDir).\($0)" },
            handleCandidate: handleCandidate
        )
    }

    /// The favourite flag as a Pocket 3 writes it: a `00`/`01` byte after a fixed 12-byte
    /// signature that sits *after* the record's own media path, present once per record whatever
    /// the media type.
    ///
    /// `starFlag` cannot work on that body: it anchors on `[ff|fe] 19 06`, and a Pocket 3 still
    /// carries no such marker, so a favourited photo could never show a heart at any offset.
    /// Returns nil where the signature is absent, so the caller can fall back.
    ///
    /// Established in Osmosis by a controlled A/B on one card (2026-08-17): two dumps of the same
    /// nine files differing in exactly three bytes, all three being the favourites changed between
    /// them, across eighteen records agreeing with the camera's own gallery.
    private static func starFlagBySignature(_ bytes: [UInt8], lo: Int, hi: Int) -> Bool? {
        let sig: [UInt8] = [
            0x1B, 0x0A, 0x00, 0x00, 0x00, 0x02, 0x02, 0x01, 0x14, 0x02, 0x15, 0x03,
        ]
        var q = max(0, lo)
        let end = min(hi, bytes.count - sig.count - 1)
        while q <= end {
            var k = 0
            while k < sig.count, bytes[q + k] == sig[k] { k += 1 }
            if k == sig.count { return bytes[q + sig.count] == 1 }
            q += 1
        }
        return nil
    }

    /// Star byte 9 past `[ff|fe] 19 06`. Trust only `== 1` (Nano). 44/48 on Action is a length.
    ///
    /// On an Xtra that offset lands on a *length* byte — its records run `1a <len> 00 00 00 01
    /// DCIM/…` — so anything other than 0 or 1 means this is not the layout the offset was derived
    /// from. Say "not starred" rather than guess: reading a length as a flag would put a heart on
    /// every file at once. Xtra favourites therefore still do not survive a re-list; reading them
    /// needs the camera's own `0x00/0x26` favourites filter, not this decode.
    private static func starFlag(_ bytes: [UInt8], lo: Int, hi: Int) -> Bool {
        var q = lo
        while q < hi - 9 {
            if bytes[q] == 0xFF || bytes[q] == 0xFE,
                bytes[q + 1] == 0x19, bytes[q + 2] == 0x06
            {
                return bytes[q + 9] == 1
            }
            q += 1
        }
        return false
    }

    private static func resolutionForIndex(_ code: Int) -> String? {
        switch code {
        case 10: "1920x1080"  // 0x0A  1080p 16:9 (Xtra-verified)
        case 12: "1920x1440"  // 0x0C  1080p 4:3
        case 16: "3840x2160"  // 0x10  4K 16:9
        case 45: "2688x1512"  // 0x2D  2.7K 16:9
        case 66: "1080x1920"  // 0x42  1080p 9:16 vertical
        case 67: "1512x2688"  // 0x43  2.7K 9:16 vertical
        case 95: "2688x2016"  // 0x5F  2.7K 4:3
        case 103: "3840x2880"  // 0x67  4K 4:3
        case 105: "1080x1080"  // 0x69  1080p 1:1
        case 106: "2160x2160"  // 0x6A  2160p 1:1
        case 107: "3072x3072"  // 0x6B  3K 1:1
        case 108: "1728x3072"  // 0x6C  3K 9:16 vertical
        case 125: "3840x3840"  // 0x7D  4K 1:1, aka OpenGate
        default: nil
        }
    }

    private static func fpsInRange(_ bytes: [UInt8], start: Int, end: Int) -> Int? {
        var fps: Int?
        var i = max(0, start)
        let stop = min(end, bytes.count) - 8
        while i <= stop {
            let den = u32(bytes, i + 4)
            if den == 1000 || den == 1001 {
                let num = u32(bytes, i)
                if (20_000...250_000).contains(num) {
                    fps = Int((Double(num) / Double(den)).rounded())
                }
            }
            i += 1
        }
        return fps
    }

    private static func withCmdHandles(_ files: [MediaFile]) -> [MediaFile] {
        var fits: [Int: (base: UInt32, step: UInt32)] = [:]
        let groups = Dictionary(grouping: files, by: \.group)
        for (group, list) in groups {
            let pts =
                list
                .filter { $0.handle != 0 && $0.sequenceNumber > 0 }
                .map { ($0.sequenceNumber, $0.handle) }
            let unique = Dictionary(pts, uniquingKeysWith: { a, _ in a })
                .map { ($0.key, $0.value) }
                .sorted { $0.0 < $1.0 }
            guard unique.count >= 2 else { continue }
            var stepCounts: [UInt32: Int] = [:]
            for idx in 1..<unique.count {
                let dSeq = unique[idx].0 - unique[idx - 1].0
                guard dSeq > 0 else { continue }
                let dHandle = unique[idx].1 &- unique[idx - 1].1
                if dHandle > 0 {
                    let step = dHandle / UInt32(dSeq)
                    if step > 0 { stepCounts[step, default: 0] += 1 }
                }
            }
            guard let step = stepCounts.max(by: { $0.value < $1.value })?.key else { continue }
            var baseCounts: [UInt32: Int] = [:]
            for (seq, handle) in unique {
                baseCounts[handle &- UInt32(seq) &* step, default: 0] += 1
            }
            guard let base = baseCounts.max(by: { $0.value < $1.value })?.key else { continue }
            fits[group] = (base, step)
        }
        guard !fits.isEmpty else { return files }
        return files.map { file in
            guard let fit = fits[file.group], file.sequenceNumber > 0 else { return file }
            var next = file
            let fitted = fit.base &+ UInt32(file.sequenceNumber) &* fit.step
            next.cmdHandle = fitted
            if file.handle == 0, file.handleCandidate != 0, file.handleCandidate == fitted {
                // Two independent sources agree: the bytes at the record's fixed marker position,
                // and a formula fitted to the handles the OTHER records exposed. That is the bar
                // for a command that destroys a file — and it is how a Pocket 3's stills become
                // deletable without inventing anything, since the handle was always in the record
                // and only the guard-byte scan refused to read it.
                next.handle = file.handleCandidate
            } else if file.handle != 0, file.handle != fitted {
                // The scan produced a handle the fit contradicts. Something is being read out of
                // the wrong place — a record-boundary overrun once handed a photo the neighbouring
                // video's handle — and there is no way to tell which of the two is right. Drop it:
                // losing delete on one file is recoverable, deleting whatever else lives at that
                // handle is not.
                next.handle = 0
            }
            return next
        }
    }

    private static func flagHandleCollisions(_ files: [MediaFile]) -> [MediaFile] {
        var counts: [UInt32: Int] = [:]
        for file in files where file.handle != 0 {
            counts[file.handle, default: 0] += 1
        }
        let shared = Set(counts.compactMap { $0.value > 1 ? $0.key : nil })
        guard !shared.isEmpty else { return files }
        return files.map { file in
            guard shared.contains(file.handle) else { return file }
            var next = file
            next.handleShared = true
            return next
        }
    }

    private static func stampStorage(_ files: [MediaFile], fallback: Bool) -> [MediaFile] {
        files.map { file in
            var next = file
            if fallback {
                next.storage = MediaHTTP.storageGuess(
                    handle: file.handle != 0 ? file.handle : file.cmdHandle, singleSdStorage: false)
            }
            return next
        }
    }

    private static func stamp(_ file: MediaFile, storage: Int, group: Int) -> MediaFile {
        var next = file
        next.storage = storage
        next.group = group
        return next
    }

    private static func u32(_ bytes: [UInt8], _ i: Int) -> UInt32 {
        UInt32(bytes[i])
            | UInt32(bytes[i + 1]) << 8
            | UInt32(bytes[i + 2]) << 16
            | UInt32(bytes[i + 3]) << 24
    }
}

/// Filter / sort helpers shared by the browser (no UI).
public enum MediaLibraryQuery {
    public static func filtered(
        _ files: [MediaFile],
        tab: MediaLibraryTab,
        formats: Set<String> = [],
        resolutions: Set<String> = [],
        dateKey: String? = nil,
        storage: Int? = nil,
        localFavorites: Set<String> = []
    ) -> [MediaFile] {
        files.filter { file in
            switch tab {
            case .all: break
            case .videos: if file.kind != .video { return false }
            case .photos: if file.kind != .photo { return false }
            case .favorites:
                if !(file.isStarred || localFavorites.contains(file.path)) { return false }
            }
            if !formats.isEmpty, !formats.contains(file.fileExtension) { return false }
            if !resolutions.isEmpty {
                let bucket = file.resolution ?? ""
                if !resolutions.contains(bucket) { return false }
            }
            if let dateKey, file.dateKey != dateKey { return false }
            if let storage, file.storage != storage { return false }
            return true
        }
    }

    /// Offline library: keep only files the phone can play without the camera.
    public static func cachedOnly(_ files: [MediaFile], cachedPaths: Set<String>) -> [MediaFile] {
        files.filter { cachedPaths.contains($0.path) }
    }

    public static func sorted(_ files: [MediaFile], by order: MediaLibrarySort) -> [MediaFile] {
        switch order {
        case .newest:
            return files.sorted { lhs, rhs in
                (lhs.filenameTimestamp ?? "") > (rhs.filenameTimestamp ?? "")
            }
        case .oldest:
            return files.sorted { lhs, rhs in
                (lhs.filenameTimestamp ?? "") < (rhs.filenameTimestamp ?? "")
            }
        case .name:
            return files.sorted {
                $0.filename.localizedStandardCompare($1.filename) == .orderedAscending
            }
        case .rating:
            return files.sorted { lhs, rhs in
                if lhs.isStarred != rhs.isStarred { return lhs.isStarred && !rhs.isStarred }
                return (lhs.filenameTimestamp ?? "") > (rhs.filenameTimestamp ?? "")
            }
        }
    }
}

public enum MediaLibraryTab: String, Sendable, CaseIterable {
    case all, videos, photos, favorites
}

public enum MediaLibrarySort: String, Sendable, CaseIterable {
    case newest, oldest, name, rating
}

public enum MediaClipFormatting {
    public static func durationLabel(seconds: Int) -> String {
        guard seconds > 0 else { return "0:00" }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    public static func byteLabel(_ bytes: UInt64) -> String {
        guard bytes > 0 else { return "" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.0f KB", kb) }
        let mb = kb / 1024
        if mb < 1024 { return String(format: "%.1f MB", mb) }
        return String(format: "%.2f GB", mb / 1024)
    }
}
