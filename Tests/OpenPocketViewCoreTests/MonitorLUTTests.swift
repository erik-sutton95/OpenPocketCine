import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct MonitorLUTTests {
    @Test func creativeLooksResolveToGeneratedLooks() {
        #expect(
            LUTResolver.resolve(
                selection: .creativeMono, colorMode: .dLog2, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .creative(.mono))
        #expect(LUTSelection.auto.migratedToDJICatalog == .djiAuto)
        #expect(LUTSelection.officialDLog2.migratedToDJICatalog == .djiDLog2)
    }

    @Test func builtInAndCustomTitlesAreObvious() {
        #expect(
            LUTSelection.djiCases.map(\.title)
                == ["Auto", "D-Log → Rec.709", "D-Log2 → Rec.709", "D-Log M → Rec.709"])
        #expect(
            LUTSelection.creativeCases.map(\.title)
                == ["Mono", "Contrast", "Warm", "Cool"])
        #expect(
            LUTSelection.customCases.map(\.title)
                == ["Custom", "Custom D-Log", "Custom D-Log2"])
        #expect(
            CustomLUTSlot.allCases.map(\.title)
                == ["Custom", "Custom D-Log", "Custom D-Log2"])
        #expect(OfficialPocketLUT.dLogToRec709.fileName == "DJI_Pocket4P_DLog_Rec709_33.cube")
        #expect(OfficialPocketLUT.dLog2ToRec709.fileName == "DJI_Pocket4P_DLog2_Rec709_33.cube")
        #expect(OfficialDJILUT.pocketDLog.fileName == "DJI_Official_Pocket4P_DLog_Rec709_33.cube")
        #expect(OfficialDJILUT.nanoDLogM.title == "D-Log M → Rec.709")
    }

    @Test(.enabled(if: OfficialLUTFixtures.dLog2Present))
    func officialDLog2CubeMovesMidGrey() throws {
        let cube = try officialCube(.dLog2ToRec709)
        #expect(cube.size == 33)
        #expect(cube.rgb.count == 33 * 33 * 33 * 3)
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let out = cube.map(red: g, green: g, blue: g)
        // v1.4 is milder than the old official cube (~0.016 on red); still must not be identity.
        #expect(abs(out.red - g) > 0.01)
        #expect(abs(out.green - g) > 0.01)
        #expect(abs(out.blue - g) > 0.01)
        let black = cube.map(red: 0.0626, green: 0.0626, blue: 0.0626)
        #expect(black.red < 0.04)
        #expect(black.green < 0.04)
        #expect(black.blue < 0.04)
    }

    @Test(.enabled(if: OfficialLUTFixtures.dLogPresent))
    func officialDLogCubeIsNonIdentity() throws {
        let cube = try officialCube(.dLogToRec709)
        #expect(cube.size == 33)
        #expect(cube.rgb.count == 33 * 33 * 33 * 3)
        let g = Float(MonitorTransfer.dlog.middleGrayEncoded)
        let out = cube.map(red: g, green: g, blue: g)
        #expect(abs(out.red - g) > 0.02)
    }

    @Test func autoArmedDLog2SelectsOfficialCube() {
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .dLog2, hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.pocketDLog2))
        #expect(
            LUTResolver.statusLabel(
                enabled: true, selection: .djiAuto, source: .dji(.pocketDLog2))
                == "Auto · D-Log2 → Rec.709")
    }

    private func officialLUTURL(_ id: OfficialPocketLUT) -> URL {
        OfficialLUTFixtures.url(id)
    }

    private func officialCube(_ id: OfficialPocketLUT) throws -> CubeLUT {
        let text = try String(contentsOf: officialLUTURL(id), encoding: .utf8)
        return try CubeLUT.parse(text)
    }

    @Test func autoAppliesOfficialCubeForEachLog() {
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .dLog, hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.pocketDLog))
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .dLog2, hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.pocketDLog2))
    }

    @Test func playbackAutoKeepsLastLogWhenTheFileAndLiveSayRec709() {
        #expect(PlaybackLUTColor.resolve(live: .normal, last: .dLog2) == .dLog2)
        #expect(PlaybackLUTColor.resolve(live: .hdr, last: .dLog) == .dLog)
        #expect(PlaybackLUTColor.resolve(live: nil, last: .dLog2) == .dLog2)
        #expect(PlaybackLUTColor.resolve(live: .dLog2, last: .dLog2) == .dLog2)
        #expect(PlaybackLUTColor.resolve(live: .dLog2, last: .dLog) == .dLog2)
        #expect(PlaybackLUTColor.resolve(live: .normal, last: .normal) == .normal)
        #expect(PlaybackLUTColor.resolve(live: nil, last: nil) == nil)
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto,
                colorMode: PlaybackLUTColor.resolve(live: .normal, last: .dLog2),
                hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.pocketDLog2))
    }

    @Test func autoLeavesRec709AndHLGUnlutedWithoutCustom() {
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .normal, hasCustomDLog: false, hasCustomDLog2: false)
                == .off)
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .hdr, hasCustomDLog: true, hasCustomDLog2: true)
                == .off)
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: nil, hasCustomDLog: false, hasCustomDLog2: false,
                hasCustomRec709: true)
                == .off)
    }

    @Test func builtInAutoIgnoresCustomSlots() {
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .dLog, hasCustomDLog: true, hasCustomDLog2: true)
                == .dji(.pocketDLog))
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .dLog2, hasCustomDLog: true, hasCustomDLog2: true,
                hasCustomRec709: true)
                == .dji(.pocketDLog2))
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .normal, family: .pocket, hasCustomDLog: false,
                hasCustomDLog2: false, hasCustomRec709: true)
                == .off)
    }

    @Test func djiAutoFollowsColorAndBody() {
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .dLog2, family: .pocket, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .dji(.pocketDLog2))
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .dLog, family: .pocket, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .dji(.pocketDLog))
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .dLogM, family: .nano,
                cameraName: "Osmo Nano", hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.nanoDLogM))
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .dLogM, family: .pocket,
                cameraName: "Osmo Pocket 3", hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.nanoDLogM))
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .dLogM, family: .other,
                cameraName: "Osmo Action 6", hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.action6DLogM))
        #expect(
            LUTResolver.resolve(
                selection: .djiDLogM, colorMode: .dLogM, family: .other,
                cameraName: "Osmo Action 6", hasCustomDLog: false, hasCustomDLog2: false)
                == .dji(.action6DLogM))
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: .normal, family: .pocket, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .off)
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .dLog2, family: .nano, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .dji(.nanoDLogM))
        #expect(
            LUTResolver.statusLabel(
                enabled: true, selection: .djiAuto, source: .dji(.pocketDLog2))
                == "Auto · D-Log2 → Rec.709")
    }

    @Test func manualSelectionIgnoresColorMode() {
        #expect(
            LUTResolver.resolve(
                selection: .officialDLog, colorMode: .dLog2, hasCustomDLog: true,
                hasCustomDLog2: true)
                == .dji(.pocketDLog))
        #expect(
            LUTResolver.resolve(
                selection: .officialDLog2, colorMode: .dLog, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .dji(.pocketDLog2))
        #expect(
            LUTResolver.resolve(
                selection: .customDLog, colorMode: .dLog2, hasCustomDLog: true,
                hasCustomDLog2: false)
                == .custom(.dLog))
        #expect(
            LUTResolver.resolve(
                selection: .customDLog2, colorMode: .dLog, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .off)
        #expect(
            LUTResolver.resolve(
                selection: .customRec709, colorMode: .dLog2, hasCustomDLog: true,
                hasCustomDLog2: true,
                hasCustomRec709: true)
                == .custom(.rec709))
        #expect(
            LUTResolver.resolve(
                selection: .customRec709, colorMode: .normal, hasCustomDLog: false,
                hasCustomDLog2: false)
                == .off)
    }

    @Test func autoFollowsTeleDLog2Fallback() {
        let current = ColorMode.dLog2
        let tele = CamFov.colorMode(forZoom: 3, current: current)
        #expect(tele == .dLog)
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: tele, hasCustomDLog: false, hasCustomDLog2: true)
                == .dji(.pocketDLog))
        #expect(
            LUTResolver.resolve(
                selection: .djiAuto, colorMode: tele, family: .pocket, hasCustomDLog: true,
                hasCustomDLog2: true)
                == .dji(.pocketDLog))
        #expect(CamFov.colorMode(forZoom: 1, current: current) == nil)
        #expect(
            LUTResolver.resolve(
                selection: .auto, colorMode: .dLog2, hasCustomDLog: false, hasCustomDLog2: true)
                == .dji(.pocketDLog2))
    }

    @Test func statusLabelDistinguishesAutoFromManual() {
        #expect(
            LUTResolver.statusLabel(
                enabled: true, selection: .auto, source: .official(.dLog2ToRec709))
                == "Auto · D-Log2 → Rec.709")
        #expect(
            LUTResolver.statusLabel(
                enabled: true, selection: .auto, source: .off)
                == "Auto · Off")
        #expect(
            LUTResolver.statusLabel(
                enabled: false, selection: .auto, source: .off)
                == "Off · Auto")
        #expect(
            LUTResolver.statusLabel(
                enabled: true, selection: .djiDLog, source: .dji(.pocketDLog))
                == "D-Log → Rec.709")
        #expect(
            LUTResolver.autoCaption(source: .off)
                == "No matching look for this color / camera")
        #expect(
            LUTResolver.autoCaption(source: .custom(.rec709))
                == "Applying Custom")
    }
}

private enum OfficialLUTFixtures {
    static func url(_ id: OfficialPocketLUT) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ios/OpenPocketCine/Resources/\(id.fileName)")
    }

    static var dLogPresent: Bool {
        FileManager.default.fileExists(atPath: url(.dLogToRec709).path)
    }

    static var dLog2Present: Bool {
        FileManager.default.fileExists(atPath: url(.dLog2ToRec709).path)
    }
}
