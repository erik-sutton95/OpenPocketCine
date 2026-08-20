import CoreImage
import Metal
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class LUTAssistTests: XCTestCase {
    private let keys = [
        "OpenPocketCine.Assist.v1",
        "OpenPocketCine.LUTSelection",
        "OpenPocketCine.CustomRec709File",
        "OpenPocketCine.CustomDLogFile",
        "OpenPocketCine.CustomDLog2File",
        "OpenPocketCine.SelectedCustomLUTFile",
        "OpenPocketCine.LastLUT",
        "OpenPocketCine.LastCustomLUT",
        "OpenPocketCine.LastLUTWasCustom",
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
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))
    }

    func testFreshInstallDefaultsToAuto() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.lutSelection, .auto)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(LUTAssist.longPressPanelWidth, 400)
        XCTAssertEqual(
            CustomLUTSlot.allCases.map(\.title),
            ["Custom", "Custom D-Log", "Custom D-Log2"])
    }

    func testAutoFollowsColorModeAndTeleZoom() {
        let assist = LiveAssistState()
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))
        XCTAssertEqual(assist.lutStatusLabel, "Auto · D-Log2 → Rec.709")

        let tele = CamFov.colorMode(forZoom: 12, current: .dLog2)
        XCTAssertEqual(tele, .dLog)
        assist.syncLUT(to: tele)
        XCTAssertEqual(assist.lutSelection, .auto)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLogToRec709))

        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))

        assist.syncLUT(to: .normal)
        XCTAssertEqual(assist.resolvedSource(), .off)
        XCTAssertEqual(assist.lutStatusLabel, "Auto · Off")
        XCTAssertTrue(assist.lutEnabled)
    }

    func testManualSelectionDoesNotFollowColor() {
        let assist = LiveAssistState()
        assist.selectLUT(.officialDLog)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.lutSelection, .officialDLog)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLogToRec709))
        XCTAssertEqual(assist.lutStatusLabel, "D-Log → Rec.709")

        assist.selectLUT(.auto)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))
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

        assist.selectLUT(.auto)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))
    }

    func testChipToggleKeepsSelection() {
        let assist = LiveAssistState()
        assist.selectLUT(.officialDLog2)
        assist.toggle(.lut)
        XCTAssertFalse(assist.lutEnabled)
        XCTAssertEqual(assist.lutSelection, .officialDLog2)
        XCTAssertEqual(assist.lutStatusLabel, "Off · D-Log2 → Rec.709")
        XCTAssertEqual(assist.effects.lutDimension, 0)
        XCTAssertFalse(assist.effects.needsGPUFeed, "LUT off with no other GPU assist uses the HEVC layer")
        assist.toggle(.lut)
        XCTAssertTrue(assist.lutEnabled)
        XCTAssertEqual(assist.lutSelection, .officialDLog2)
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
        XCTAssertEqual(assist.lutSelection, .auto)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLogToRec709))
        assist.selectLUT(.customFile)
        OperatorPrefs.selectedCustomFileName = "opc-test-dlog.cube"
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .file("opc-test-dlog.cube"))
        assist.selectLUT(.auto)
        assist.syncLUT(to: .dLog2)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))
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
        XCTAssertEqual(assist.lutStatusLabel, "DJI Auto · D-Log2 → Rec.709")
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
        XCTAssertEqual(assist.lutSelection, .auto)
        XCTAssertEqual(assist.resolvedSource(), .official(.dLog2ToRec709))
        XCTAssertEqual(assist.lutStatusLabel, "Auto · D-Log2 → Rec.709")
        guard BundledPocketLUT.cube(.dLog2ToRec709) != nil else {
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
            let wrapped = CIImage(mtlTexture: texture, options: LiveMonitorWorkingSpace.imageOptions)
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
}
