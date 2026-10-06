import Foundation
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// LUT long-press body: DJI / Creative / Custom, then exposure and 50/50.
///
/// DJI Auto follows color with the official Rec.709 cubes. Creative is Mono /
/// Contrast / Warm / Cool. Custom is imported `.cube` files. The assist-bar
/// chip is off. Exposure is input-referred stops before the cube (ETTR pull).
enum LUTAssist {
    static let exposureTitle = "Exposure"
    static let exposureHelp = "Input stops before the cube. Pull 1–2 after ETTR."

    @ViewBuilder
    static func longPressMenu(assist: LiveAssistState) -> some View {
        LUTPicker(assist: assist, embedded: true)
    }

    @ViewBuilder
    static func longPressMenu(_ assist: LiveAssistState) -> some View {
        LUTPicker(assist: assist, embedded: true)
    }

    /// Pinned under the catalog so landscape never scrolls exposure / 50/50 off-screen.
    @ViewBuilder
    static func longPressFooter(assist: LiveAssistState) -> some View {
        LUTSplitComparisonBar(assist: assist)
    }
}

/// Official Pocket 4P Rec.709 cubes from the app bundle. Parsed once.
enum BundledPocketLUT {
    private static let lock = NSLock()
    private static var cache: [OfficialPocketLUT: CubeLUT] = [:]

    static func cube(_ id: OfficialPocketLUT) -> CubeLUT? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[id] { return cached }
        guard let url = url(for: id),
            let text = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? CubeLUT.parse(text)
        else { return nil }
        cache[id] = parsed
        return parsed
    }

    private static func url(for id: OfficialPocketLUT) -> URL? {
        let name = id.resourceName
        if let url = Bundle.main.url(forResource: name, withExtension: "cube") { return url }
        if let url = Bundle.main.url(
            forResource: name, withExtension: "cube", subdirectory: "Resources")
        {
            return url
        }
        return Bundle.main.url(forResource: id.fileName, withExtension: nil)
    }
}

/// Official DJI Rec.709 cubes from the app bundle. Parsed once.
enum BundledOfficialDJILUT {
    private static let lock = NSLock()
    private static var cache: [OfficialDJILUT: CubeLUT] = [:]

    static func cube(_ id: OfficialDJILUT) -> CubeLUT? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[id] { return cached }
        guard let url = url(for: id),
            let text = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? CubeLUT.parse(text)
        else { return nil }
        cache[id] = parsed
        return parsed
    }

    private static func url(for id: OfficialDJILUT) -> URL? {
        let name = id.resourceName
        if let url = Bundle.main.url(forResource: name, withExtension: "cube") { return url }
        if let url = Bundle.main.url(
            forResource: name, withExtension: "cube", subdirectory: "Resources")
        {
            return url
        }
        return Bundle.main.url(forResource: id.fileName, withExtension: nil)
    }
}

extension OfficialLUTs {
    /// Pocket 4P and DJI Rec.709 cubes from the app bundle. No I-Log cube ships with this app.
    static let app = OfficialLUTs(
        catalog: { isPhotoLive in isPhotoLive ? [.officialAuto] : LUTSelection.djiCases },
        cube: { source in
            switch source {
            case .official(let id): BundledPocketLUT.cube(id)
            case .dji(let id): BundledOfficialDJILUT.cube(id)
            default: nil
            }
        })
}

extension LUTPreferences {
    /// Saved LUT choices under this app's key names (`OpenPocketCine.LUTSelection` and so on).
    static let app = LUTPreferences(storage: .standard, namespace: "OpenPocketCine")
}

extension CustomLUTStore {
    /// Imported `.cube` files in Documents/luts/custom.
    static let app = CustomLUTStore(
        root: (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("luts/custom", isDirectory: true),
        preferences: .app)
}

extension LUTPickerCopy {
    static let app = LUTPickerCopy(
        officialTab: "DJI",
        officialLockedCaption: "Official DJI Rec.709 cube",
        officialCaption: "Official DJI looks for this color / camera",
        customEmptyHint: "Imported looks land here. Auto stays on Built-in or DJI.")
}
