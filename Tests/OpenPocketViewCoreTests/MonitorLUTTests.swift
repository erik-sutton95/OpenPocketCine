import Foundation
import Testing

@testable import OpenPocketViewCore

/// The bundled official cubes this app ships. The LUT choice and resolver are tested in OpenCine.
@Suite struct MonitorLUTTests {

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

    private func officialLUTURL(_ id: OfficialPocketLUT) -> URL {
        OfficialLUTFixtures.url(id)
    }

    private func officialCube(_ id: OfficialPocketLUT) throws -> CubeLUT {
        let text = try String(contentsOf: officialLUTURL(id), encoding: .utf8)
        return try CubeLUT.parse(text)
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
