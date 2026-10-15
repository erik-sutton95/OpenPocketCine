import Foundation
import OpenPocketViewCore

/// Darwin-safe LUT pack helpers. Kotlin never parses `.cube` text: imported cubes pass the shared
/// `CubeLUT.validatedImport` gate, so the app's LUT library stores nothing it refuses.
public enum LUTLibraryWire {
    public static func packedImportedLUT(
        utf8: [UInt8],
        exposureStops: Double = 0,
        colorModeCode: Int = Int(ColorMode.normal.rawValue)
    ) -> [UInt8]? {
        guard let cube = CubeLUT.validatedImport(utf8) else { return nil }
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
}
