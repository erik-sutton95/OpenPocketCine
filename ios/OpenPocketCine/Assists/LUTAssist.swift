import Foundation
import OpenPocketViewCore
import SwiftUI

/// LUT long-press body: DJI / Creative / Custom, then exposure and 50/50.
///
/// DJI Auto follows color with the official Rec.709 cubes. Creative is Mono /
/// Contrast / Warm / Cool. Custom is imported `.cube` files. The assist-bar
/// chip is off. Exposure is input-referred stops before the cube (ETTR pull).
enum LUTAssist {
    /// OpenZCine `assistPanelWidth(for: .lut)`.
    static let longPressPanelWidth: CGFloat = 400
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

/// On-disk custom slots — one `.cube` for Rec.709/HLG, D-Log, and D-Log2.
enum CustomLUTStore {
    private static var cubeCache: [String: CubeLUT] = [:]

    static var root: URL {
        let documents =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return documents.appendingPathComponent("luts/custom", isDirectory: true)
    }

    static func list() -> [StoredCustomLUT] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return CustomLUTIndex.stored(fromFileNames: names)
    }

    static func fileName(for slot: CustomLUTSlot) -> String? {
        OperatorPrefs.customFileName(for: slot)
    }

    static func hasCube(_ slot: CustomLUTSlot) -> Bool {
        guard let name = fileName(for: slot), CustomLUTIndex.isSafeFileName(name) else {
            return false
        }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent(name).path)
    }

    static func displayName(for slot: CustomLUTSlot) -> String? {
        guard let name = fileName(for: slot), hasCube(slot) else { return nil }
        return CustomLUTIndex.displayName(fileName: name)
    }

    static func cube(_ slot: CustomLUTSlot) -> CubeLUT? {
        guard let name = fileName(for: slot) else { return nil }
        return cube(fileName: name)
    }

    @discardableResult
    static func importFile(from source: URL) throws -> StoredCustomLUT {
        let fileName = source.lastPathComponent
        guard CustomLUTIndex.isSafeFileName(fileName) else {
            throw CustomLUTStoreError.invalidFileName
        }
        let text: String
        do {
            text = try String(contentsOf: source, encoding: .utf8)
        } catch {
            throw CustomLUTStoreError.unreadable
        }
        let parsed = try CubeLUT.parse(text)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        cubeCache[fileName] = parsed
        return StoredCustomLUT(fileName: fileName)
    }

    @discardableResult
    static func importFile(from source: URL, into slot: CustomLUTSlot) throws -> StoredCustomLUT {
        let previous = fileName(for: slot)
        let stored = try importFile(from: source)
        OperatorPrefs.setCustomFileName(stored.fileName, for: slot)
        if let previous, previous != stored.fileName, !isShared(previous, excluding: slot) {
            try? remove(StoredCustomLUT(fileName: previous))
        }
        return stored
    }

    static func cube(_ lut: StoredCustomLUT) -> CubeLUT? {
        cube(fileName: lut.fileName)
    }

    static func cube(fileName: String) -> CubeLUT? {
        guard CustomLUTIndex.isSafeFileName(fileName) else { return nil }
        if let cached = cubeCache[fileName] { return cached }
        let url = root.appendingPathComponent(fileName)
        guard let text = try? String(contentsOf: url, encoding: .utf8),
            let parsed = try? CubeLUT.parse(text)
        else { return nil }
        cubeCache[fileName] = parsed
        return parsed
    }

    static func remove(_ lut: StoredCustomLUT) throws {
        guard CustomLUTIndex.isSafeFileName(lut.fileName) else {
            throw CustomLUTStoreError.invalidFileName
        }
        do {
            try FileManager.default.removeItem(at: root.appendingPathComponent(lut.fileName))
            cubeCache[lut.fileName] = nil
        } catch {
            throw CustomLUTStoreError.deletionFailed(lut.displayName)
        }
    }

    static func clear(_ slot: CustomLUTSlot) throws {
        let name = fileName(for: slot)
        OperatorPrefs.setCustomFileName(nil, for: slot)
        if let name, !isShared(name, excluding: slot) {
            try remove(StoredCustomLUT(fileName: name))
        }
    }

    private static func isShared(_ fileName: String, excluding slot: CustomLUTSlot) -> Bool {
        slot.others.contains { OperatorPrefs.customFileName(for: $0) == fileName }
    }
}

enum CustomLUTStoreError: LocalizedError {
    case invalidFileName
    case unreadable
    case deletionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            return "The LUT file name is not valid."
        case .unreadable:
            return "The .cube file could not be read."
        case .deletionFailed(let name):
            return "The LUT “\(name)” could not be deleted."
        }
    }
}
