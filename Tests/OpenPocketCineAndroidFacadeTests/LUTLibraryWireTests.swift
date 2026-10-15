import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct LUTLibraryWireTests {
    @Test
    func identity2CubePacks32Bytes() throws {
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
        let utf8 = Array(text.utf8)
        let packed = try #require(LUTLibraryWire.packedImportedLUT(utf8: utf8))
        #expect(packed.count == 2 * 2 * 2 * 4)
        // (r=1,g=0,b=1) → dst (g*n² + b*n + r)*4 = (0 + 2 + 1)*4 = 12
        #expect(packed[12] == 255)
        #expect(packed[13] == 0)
        #expect(packed[14] == 255)
        #expect(packed[15] == 255)
    }

    @Test
    func exposurePullRemapsPackedIdentity() throws {
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
        let utf8 = Array(text.utf8)
        let identity = try #require(LUTLibraryWire.packedImportedLUT(utf8: utf8))
        let pulled = try #require(
            LUTLibraryWire.packedImportedLUT(
                utf8: utf8, exposureStops: -1, colorModeCode: Int(ColorMode.dLog2.rawValue)))
        #expect(pulled.count == identity.count)
        #expect(pulled != identity)
    }

    /// A4-27: an import the shared gate (`CubeLUT.validatedImport`) refuses never packs, so the
    /// Android library stores nothing for it.
    @Test(arguments: [
        "not a cube",
        "LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n",
        "LUT_3D_SIZE 2\n1.2 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1\n",
    ])
    func refusesWhatTheImportGateRefuses(text: String) {
        #expect(LUTLibraryWire.packedImportedLUT(utf8: Array(text.utf8)) == nil)
    }

    @Test
    func creativeMonoPacksAGreyscaleCube() throws {
        let packed = try #require(LUTLibraryWire.packedCreativeLook("Mono"))
        #expect(!packed.isEmpty)
        #expect(packed.count % 4 == 0)
    }
}
