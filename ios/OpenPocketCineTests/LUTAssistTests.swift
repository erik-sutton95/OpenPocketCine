import CoreImage
import Metal
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class LUTAssistTests: XCTestCase {
    private let keys = [
        "OpenPocketCine.Assist.v1",
        "OpenPocketCine.PlaybackAssists.v1",
        "OpenPocketCine.LUTSelection",
        "OpenPocketCine.CustomRec709File",
        "OpenPocketCine.CustomDLogFile",
        "OpenPocketCine.CustomDLog2File",
        "OpenPocketCine.SelectedCustomLUTFile",
        "OpenPocketCine.LastLUT",
        "OpenPocketCine.LastCustomLUT",
        "OpenPocketCine.LastLUTWasCustom",
        "OpenPocketCine.LastMonitorColorMode",
        "OpenPocketCine.CacheFullResolution",
    ]
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        for key in keys {
            saved[key] = defaults.object(forKey: key)
            defaults.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        let defaults = UserDefaults.standard
        for key in keys {
            if let value = saved[key] {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        saved.removeAll()
        super.tearDown()
    }

    func testAutoRec709AndHDRDoNotBindACube() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .normal)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(assist.effects.lutDimension, 0)
        XCTAssertFalse(assist.effects.needsGPUFeed)

        assist.syncLUT(to: .hdr)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertFalse(assist.effects.needsGPUFeed)

        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testAutoLUTFollowsPersistedLiveColorWhenOffline() {
        let live = LiveAssistState()
        live.syncLUT(to: .dLog2)
        XCTAssertEqual(OperatorPrefs.lastMonitorColorMode, .dLog2)

        let offline = LiveAssistState()
        XCTAssertEqual(offline.monitorColorMode, .dLog2)
        XCTAssertEqual(offline.resolvedSource(), .dji(.pocketDLog2))
        offline.togglePlayback(.lut)
        XCTAssertGreaterThanOrEqual(offline.playbackEffects.lutDimension, 2)
        XCTAssertTrue(offline.playbackEffects.needsGPUFeed)
    }

    func testPlaybackAutoDoesNotDropLogWhenLiveReportsRec709() {
        XCTAssertEqual(PlaybackLUTColor.resolve(live: .normal, last: .dLog2), .dLog2)
        let color = PlaybackLUTColor.resolve(live: .normal, last: .dLog2)
        let assist = LiveAssistState()
        assist.syncLUT(to: color)
        assist.togglePlayback(.lut)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertGreaterThanOrEqual(assist.playbackEffects.lutDimension, 2)
    }

    func testClipColorGammaWinsAndDoesNotPersistOverLastLive() {
        XCTAssertEqual(
            PlaybackLUTColor.resolve(clip: .dLog2, live: .normal, last: .dLog), .dLog2)
        XCTAssertEqual(
            PlaybackLUTColor.resolve(clip: .normal, live: .dLog2, last: .dLog2), .normal)
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(OperatorPrefs.lastMonitorColorMode, .dLog2)
        assist.adoptPlaybackColor(.normal)
        XCTAssertEqual(assist.monitorColorMode, .normal)
        XCTAssertEqual(
            OperatorPrefs.lastMonitorColorMode, .dLog2,
            "a Rec.709 clip must not overwrite last live log")
        assist.adoptPlaybackColor(.dLog2)
        assist.togglePlayback(.lut)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testLUTPickerAppearDoesNotReplaceClipAutoWithLiveSet() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(OperatorPrefs.lastMonitorColorMode, .dLog2)
        assist.adoptPlaybackColor(.dLog)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        assist.bindLUTPicker(live: .dLog2, inPlayback: true)
        XCTAssertEqual(assist.monitorColorMode, .dLog)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        XCTAssertEqual(
            OperatorPrefs.lastMonitorColorMode, .dLog2,
            "opening LUT in playback must not persist the live SET over the clip")
        assist.bindLUTPicker(live: .dLog2, inPlayback: false)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testDisconnectedMediaLUTPickerKeepsClipAuto() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .normal)
        assist.adoptPlaybackColor(.dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        assist.gradesClip = true
        assist.bindLUTPicker(live: nil, inPlayback: false)
        XCTAssertEqual(assist.monitorColorMode, .dLog2)
        XCTAssertEqual(
            assist.resolvedSource(), .dji(.pocketDLog2),
            "disconnected library has no camera inPlayback; clip color must still drive Auto")
        assist.gradesClip = false
        assist.bindLUTPicker(live: .normal, inPlayback: false)
        XCTAssertEqual(assist.resolvedSource(), .off)
    }

    func testClipColorProfileIOReadsColorGammaFromFileTail() throws {
        let mp4 = Self.colorGammaMP4(gamma: "D-Log2", padMdat: 4096)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("opc-clip-color-\(UUID().uuidString).mp4")
        try mp4.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(ClipColorProfileIO.colorMode(at: url), .dLog2)
        XCTAssertNil(
            ClipColorProfileIO.shotColor(at: url, path: "DCIM/DJI_001/clip.LRF"),
            "LRF Rec.709 must not drive Auto")
        XCTAssertEqual(
            ClipColorProfileIO.shotColor(at: url, path: "DCIM/DJI_001/clip.MP4"), .dLog2)
    }

    func testClipColorProfileIOReadsMimoExportsIfPresent() throws {
        guard let dir = ProcessInfo.processInfo.environment["OPC_CLIP_DIR"], !dir.isEmpty else {
            return
        }
        let expected: [(String, ColorMode)] = [
            ("_video_Normal.MP4", .normal),
            ("_video_HDR.MP4", .hdr),
            ("_video_Dlog.MP4", .dLog),
            ("_video_Dlog2.MP4", .dLog2),
        ]
        let files = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)
        for (suffix, mode) in expected {
            guard let url = files.first(where: { $0.lastPathComponent.hasSuffix(suffix) }) else {
                XCTFail("missing *\(suffix) in OPC_CLIP_DIR")
                continue
            }
            XCTAssertEqual(ClipColorProfileIO.colorMode(at: url), mode, url.lastPathComponent)
        }
    }

    func testCreativeLooksBindGeneratedCubes() {
        let assist = LiveAssistState()
        assist.selectLUT(.creativeMono)
        XCTAssertEqual(assist.resolvedSource(), .creative(.mono))
        XCTAssertEqual(assist.lutStatusLabel, "Mono")
        XCTAssertGreaterThanOrEqual(assist.effects.lutDimension, 2)
        XCTAssertFalse(assist.effects.lutRGBA.isEmpty)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .creativeMono)
    }

    func testFreshInstallDefaultsToAuto() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.lutSelection, .djiAuto)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(assist.lutExposureStops, 0)
        XCTAssertEqual(LUTAssist.longPressPanelWidth, 400)
        XCTAssertEqual(LUTAssist.exposureTitle, "Exposure")
        XCTAssertFalse(LUTAssist.exposureHelp.isEmpty)
        XCTAssertEqual(
            CustomLUTSlot.allCases.map(\.title),
            ["Custom", "Custom D-Log", "Custom D-Log2"])
    }

    func testLUTExposureNudgeSnapsAndRebuildsTheCube() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        guard BundledOfficialDJILUT.cube(.pocketDLog2) != nil else {
            XCTFail("official D-Log2 cube must load from the app bundle")
            return
        }
        let nominal = assist.effects.lutRGBA
        XCTAssertFalse(nominal.isEmpty)
        assist.nudgeLUTExposure(-1)
        XCTAssertEqual(assist.lutExposureStops, -1)
        XCTAssertNotEqual(assist.effects.lutRGBA, nominal, "pull must remap cube inputs")
        assist.nudgeLUTExposure(-0.5)
        XCTAssertEqual(assist.lutExposureStops, -1.5)
        assist.nudgeLUTExposure(0.5)
        XCTAssertEqual(assist.lutExposureStops, -1)
        while LUTExposureCompensation.canStep(assist.lutExposureStops, by: -0.5) {
            assist.nudgeLUTExposure(-0.5)
        }
        XCTAssertEqual(assist.lutExposureStops, -3)
        assist.nudgeLUTExposure(-0.5)
        XCTAssertEqual(assist.lutExposureStops, -3)
    }

    func testExportCubeBakesExposureOnlyWhenAsked() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        guard BundledOfficialDJILUT.cube(.pocketDLog2) != nil else {
            XCTFail("official D-Log2 cube must load from the app bundle")
            return
        }
        assist.nudgeLUTExposure(-1)
        let nominal = assist.exportLUTCube(bakeExposure: false)
        let pulled = assist.exportLUTCube(bakeExposure: true)
        XCTAssertNotNil(nominal)
        XCTAssertNotNil(pulled)
        XCTAssertNotEqual(
            nominal, pulled, "Bake exposure must remap cube inputs the same way as the monitor")
        XCTAssertEqual(assist.exportLUTCube(bakeExposure: true), pulled)
        assist.nudgeLUTExposure(1)
        XCTAssertEqual(
            assist.exportLUTCube(bakeExposure: true),
            assist.exportLUTCube(bakeExposure: false),
            "0.0 stops is the cube as shipped")
    }

    func testLUTExposurePersistsAcrossAssistReload() {
        let assist = LiveAssistState()
        assist.nudgeLUTExposure(-2)
        XCTAssertEqual(assist.lutExposureStops, -2)
        let restored = LiveAssistState()
        XCTAssertEqual(restored.lutExposureStops, -2)
    }

    func testAutoFollowsColorModeAndTeleZoom() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertEqual(assist.lutStatusLabel, "Auto · D-Log2 → Rec.709")

        let tele = CamFov.colorMode(forZoom: 12, current: .dLog2)
        XCTAssertEqual(tele, .dLog)
        assist.syncLUT(to: tele)
        XCTAssertEqual(assist.lutSelection, .djiAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))

        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))

        assist.syncLUT(to: .normal)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(assist.lutStatusLabel, "Auto · Off")
        XCTAssertTrue(assist.lutEnabled)
    }

    func testManualSelectionDoesNotFollowColor() {
        let assist = LiveAssistState()
        assist.selectLUT(.djiDLog)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .djiDLog)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        XCTAssertEqual(assist.lutStatusLabel, "D-Log → Rec.709")

        assist.selectLUT(.djiAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testManualCustomRec709SticksUntilAuto() throws {
        let cube = try writeTempCube(named: "opc-test-manual-rec709.cube")
        defer { try? CustomLUTStore.clear(.rec709) }
        _ = try CustomLUTStore.importFile(from: cube, into: .rec709)

        let assist = LiveAssistState()
        assist.selectLUT(.customRec709)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .customRec709)
        XCTAssertEqual(assist.resolvedSource(), .custom(.rec709))

        assist.selectLUT(.djiAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
    }

    func testChipToggleKeepsSelection() {
        let assist = LiveAssistState()
        assist.selectLUT(.djiDLog2)
        assist.toggle(.lut)
        XCTAssertFalse(assist.lutEnabled)
        XCTAssertEqual(assist.lutSelection, .djiDLog2)
        XCTAssertEqual(assist.lutStatusLabel, "Off · D-Log2 → Rec.709")
        XCTAssertEqual(assist.effects.lutDimension, 0)
        XCTAssertFalse(
            assist.effects.needsGPUFeed, "LUT off with no other GPU assist uses the HEVC layer")
        assist.toggle(.lut)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(assist.lutSelection, .djiDLog2)
    }

    func testCustomSlotsAreIndependentAndAutoUsesThem() throws {
        let rec709 = try writeTempCube(named: "opc-test-rec709.cube")
        let dlog = try writeTempCube(named: "opc-test-dlog.cube")
        let dlog2 = try writeTempCube(named: "opc-test-dlog2.cube")
        defer {
            try? CustomLUTStore.clear(.rec709)
            try? CustomLUTStore.clear(.dLog)
            try? CustomLUTStore.clear(.dLog2)
        }
        _ = try CustomLUTStore.importFile(from: rec709, into: .rec709)
        _ = try CustomLUTStore.importFile(from: dlog, into: .dLog)
        _ = try CustomLUTStore.importFile(from: dlog2, into: .dLog2)
        XCTAssertTrue(CustomLUTStore.hasCube(.rec709))
        XCTAssertTrue(CustomLUTStore.hasCube(.dLog))
        XCTAssertTrue(CustomLUTStore.hasCube(.dLog2))
        XCTAssertEqual(OperatorPrefs.customFileName(for: .rec709), "opc-test-rec709.cube")

        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog)
        XCTAssertEqual(assist.lutSelection, .djiAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog))
        assist.selectLUT(.customFile)
        OperatorPrefs.selectedCustomFileName = "opc-test-dlog.cube"
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .file("opc-test-dlog.cube"))
        assist.selectLUT(.djiAuto)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        assist.syncLUT(to: .normal)
        XCTAssertEqual(assist.resolvedSource(), .off)
    }

    func testOfficialCubesParseAsSize33() throws {
        for lut in OfficialPocketLUT.allCases {
            let url = officialCubeURL(lut.fileName)
            let text = try String(contentsOf: url, encoding: .utf8)
            let cube = try CubeLUT.parse(text)
            XCTAssertEqual(cube.size, 33, lut.fileName)
            XCTAssertEqual(cube.rgb.count, 33 * 33 * 33 * 3, lut.fileName)
        }
        for lut in OfficialDJILUT.allCases {
            XCTAssertNotNil(
                Bundle.main.url(forResource: lut.resourceName, withExtension: "cube"),
                "\(lut.fileName) must ship in the app bundle")
            let url = officialCubeURL(lut.fileName)
            let text = try String(contentsOf: url, encoding: .utf8)
            let cube = try CubeLUT.parse(text)
            XCTAssertEqual(cube.size, 33, lut.fileName)
            XCTAssertEqual(cube.rgb.count, 33 * 33 * 33 * 3, lut.fileName)
            XCTAssertNotNil(BundledOfficialDJILUT.cube(lut), lut.fileName)
        }
    }

    func testArmedDJIAutoDLog2BindsOfficialCube() {
        let assist = LiveAssistState()
        assist.selectLUT(.djiAuto)
        assist.syncLUT(to: .dLog2, family: .pocket, cameraName: "Osmo Pocket 4 Pro")
        XCTAssertEqual(assist.lutSelection, .djiAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertEqual(assist.lutStatusLabel, "Auto · D-Log2 → Rec.709")
        guard BundledOfficialDJILUT.cube(.pocketDLog2) != nil else {
            XCTFail("official DJI D-Log2 cube must load from the app bundle")
            return
        }
        XCTAssertEqual(assist.effects.lutDimension, 33)
        XCTAssertFalse(assist.effects.lutRGBA.isEmpty)
        XCTAssertTrue(assist.effects.needsGPUFeed)
    }

    func testOfficialDLog2CubeMovesMidGrey() throws {
        let cube = try officialCube(.dLog2ToRec709)
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let out = cube.map(red: g, green: g, blue: g)
        XCTAssertGreaterThan(abs(out.red - g), 0.01, "18% D-Log2 must not be identity")
        XCTAssertGreaterThan(abs(out.green - g), 0.01)
        XCTAssertGreaterThan(abs(out.blue - g), 0.01)
        let black = cube.map(red: 0.0626, green: 0.0626, blue: 0.0626)
        XCTAssertLessThan(black.red, 0.04, "log black must become a real Rec.709 black")
    }

    func testArmedAutoDLog2BindsOfficialCube() {
        let assist = LiveAssistState()
        XCTAssertTrue(assist.lutEnabled)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .djiAuto)
        XCTAssertEqual(assist.resolvedSource(), .dji(.pocketDLog2))
        XCTAssertEqual(assist.lutStatusLabel, "Auto · D-Log2 → Rec.709")
        guard BundledOfficialDJILUT.cube(.pocketDLog2) != nil else {
            XCTFail("official D-Log2 cube must load from the app bundle")
            return
        }
        XCTAssertEqual(assist.effects.lutDimension, 33)
        XCTAssertFalse(assist.effects.lutRGBA.isEmpty)
        XCTAssertTrue(assist.effects.needsGPUFeed)
    }

    func testOfficialDLog2BakeKeepsRec709Codes() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal required")
        }
        let cube = try officialCube(.dLog2ToRec709)
        let g = Float(MonitorTransfer.dlog2.middleGrayEncoded)
        let expected = cube.map(red: g, green: g, blue: g)
        let code = UInt8(clamping: Int((Double(g) * 255).rounded()))
        let source = Self.solidImage(code: code)
        var fx = LiveImageEffects()
        fx.lutDimension = cube.size
        fx.lutRGBA = cube.rgbaComponents.withUnsafeBytes { Data($0) }
        let graded = LiveMonitorCompositor.apply(to: source, effects: fx)

        let baker = FeedFrameBaker(device: device)
        let drawable = CGSize(width: 32, height: 32)
        let done = expectation(description: "bake")
        baker.scheduleBake(
            image: graded, drawableSize: drawable, pixelFormat: .bgra8Unorm
        ) {
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
        guard let texture = baker.bakedTexture(for: drawable, pixelFormat: .bgra8Unorm) else {
            XCTFail("baker must publish the LUT texture")
            return
        }
        defer { baker.releaseBakedTexture(texture) }
        guard
            let wrapped = CIImage(
                mtlTexture: texture, options: LiveMonitorWorkingSpace.imageOptions)
        else {
            XCTFail("CIImage(mtlTexture:) must wrap the bake")
            return
        }
        let sample = Self.sampleRGB(wrapped)
        XCTAssertEqual(sample.0, expected.red, accuracy: 0.06)
        XCTAssertEqual(sample.1, expected.green, accuracy: 0.06)
        XCTAssertEqual(sample.2, expected.blue, accuracy: 0.06)
        XCTAssertGreaterThan(
            abs(sample.0 - 0.64), 0.12,
            "DeviceRGB re-encode of the cube output looks like uncorrected log")
    }

    private func writeTempCube(named fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let text = """
            LUT_3D_SIZE 2
            0 0 0
            1 0 0
            0 1 0
            1 1 0
            0 0 1
            1 0 1
            0 1 1
            1 1 1
            """
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func officialCube(_ lut: OfficialPocketLUT) throws -> CubeLUT {
        try CubeLUT.parse(String(contentsOf: officialCubeURL(lut.fileName), encoding: .utf8))
    }

    private func officialCubeURL(_ fileName: String) -> URL {
        let resource = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        if let bundled = Bundle.main.url(forResource: resource, withExtension: "cube") {
            return bundled
        }
        if let nested = Bundle.main.url(
            forResource: resource, withExtension: "cube", subdirectory: "Resources")
        {
            return nested
        }
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("OpenPocketCine/Resources/\(fileName)")
    }

    private static func solidImage(code: UInt8, width: Int = 16, height: Int = 16) -> CIImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            bytes[i * 4] = code
            bytes[i * 4 + 1] = code
            bytes[i * 4 + 2] = code
            bytes[i * 4 + 3] = 255
        }
        return CIImage(
            bitmapData: Data(bytes), bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8, colorSpace: nil)
    }

    private static func sampleRGB(_ image: CIImage) -> (Float, Float, Float) {
        let context = CIContext(options: LiveMonitorWorkingSpace.contextOptions)
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image, toBitmap: &bytes, rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8, colorSpace: nil)
        return (Float(bytes[0]) / 255, Float(bytes[1]) / 255, Float(bytes[2]) / 255)
    }

    /// `ftyp` + optional `mdat` pad + `moov/meta/{keys,ilst}` like Pocket 4P.
    private static func colorGammaMP4(gamma: String, padMdat: Int = 0) -> Data {
        var keysPayload = Data()
        keysPayload.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1])
        let name = Data("com.dji.camera.ColorGammaSxS".utf8)
        var entry = Data()
        entry.append(Self.be32(UInt32(8 + name.count)))
        entry.append(contentsOf: Array("mdta".utf8))
        entry.append(name)
        keysPayload.append(entry)
        let keys = box("keys", keysPayload)

        var dataPayload = Data()
        dataPayload.append(Self.be32(1))
        dataPayload.append(Self.be32(0))
        dataPayload.append(contentsOf: Array(gamma.utf8))
        let dataBox = box("data", dataPayload)
        let child = box(fourCC: 1, dataBox)
        let ilst = box("ilst", child)
        let meta = box("meta", keys + ilst)
        let moov = box("moov", meta)
        var file = box("ftyp", Data("isomisom".utf8))
        if padMdat > 0 {
            file.append(box("mdat", Data(repeating: 0xAB, count: padMdat)))
        }
        file.append(moov)
        return file
    }

    private static func box(_ type: String, _ payload: Data) -> Data {
        var out = Data()
        out.append(Self.be32(UInt32(8 + payload.count)))
        out.append(contentsOf: Array(type.utf8))
        out.append(payload)
        return out
    }

    private static func box(fourCC: UInt32, _ payload: Data) -> Data {
        var out = Data()
        out.append(Self.be32(UInt32(8 + payload.count)))
        out.append(Self.be32(fourCC))
        out.append(payload)
        return out
    }

    private static func be32(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 4)
    }
}
