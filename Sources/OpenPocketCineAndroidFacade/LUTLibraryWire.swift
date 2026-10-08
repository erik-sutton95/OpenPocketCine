import Foundation
import OpenPocketViewCore

/// Darwin-safe LUT import/pack helpers (OpenZCine `LUTLibraryWire` pattern).
/// Kotlin never parses `.cube` text; the shared `CubeLUT` parser is the only path.
public enum LUTLibraryWire {
    public static let maximumSourceBytes = 16 * 1024 * 1024

    public static func packedImportedLUT(
        utf8: [UInt8],
        exposureStops: Double = 0,
        colorModeCode: Int = Int(ColorMode.normal.rawValue)
    ) -> [UInt8]? {
        guard utf8.count <= maximumSourceBytes, let cube = cube(from: utf8) else { return nil }
        let transfer = FeedEffectsWire.monitorTransfer(colorModeCode: colorModeCode)
        let graded = cube.colorCube.compensatingExposure(
            stops: exposureStops, transfer: transfer.lutExposureTransfer)
        return packedRGBA(cube: graded)
    }

    public static func packedCreativeLook(
        _ title: String, exposureStops: Double = 0,
        colorModeCode: Int = Int(ColorMode.normal.rawValue)
    ) -> [UInt8]? {
        guard let look = BuiltInLook(rawValue: title) else { return nil }
        let transfer = FeedEffectsWire.monitorTransfer(colorModeCode: colorModeCode)
        let cube = look.cube().colorCube.compensatingExposure(
            stops: exposureStops, transfer: transfer.lutExposureTransfer)
        return packedRGBA(cube: cube)
    }

    /// Packed-2D RGBA8: pixel `(x = b·n + r, y = g)`, alpha 255. GLES-atlas ready.
    public static func packedRGBA(cube: CubeLUT) -> [UInt8] {
        cube.packedRGBA
    }

    public static func isSafeStoredFileName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == name, !trimmed.isEmpty, trimmed.count <= 128 else { return false }
        guard trimmed.lowercased().hasSuffix(".cube") else { return false }
        guard !trimmed.contains(".."), !trimmed.contains("/"), !trimmed.contains("\\") else {
            return false
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func cube(from utf8: [UInt8]) -> CubeLUT? {
        guard let text = String(bytes: utf8, encoding: .utf8) else { return nil }
        return try? CubeLUT.parse(text)
    }
}
