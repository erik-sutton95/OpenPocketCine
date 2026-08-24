import Foundation
import OpenPocketViewCore

/// Shell I/O for ``ClipColorProfile`` — read the `moov` tail, not the 4K `mdat`.
enum ClipColorProfileIO {
    static func colorMode(at url: URL) -> ColorMode? {
        guard let data = window(at: url) else { return nil }
        return ClipColorProfile.colorMode(fromMP4: data)
    }

    static func shotColor(at url: URL, path: String) -> ColorMode? {
        guard !MediaHTTP.isProxyPath(path) else { return nil }
        return colorMode(at: url)
    }

    static func window(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let size: UInt64
        do {
            size = try handle.seekToEnd()
        } catch {
            return nil
        }
        guard size > 0 else { return nil }
        let window = UInt64(ClipColorProfile.fileTailBytes)
        let start = size > window ? size - window : 0
        do {
            try handle.seek(toOffset: start)
            return try handle.readToEnd()
        } catch {
            return nil
        }
    }
}
