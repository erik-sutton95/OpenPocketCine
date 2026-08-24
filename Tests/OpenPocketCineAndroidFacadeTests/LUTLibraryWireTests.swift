import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct LUTLibraryWireTests {
    @Test
    func rejectsPathEscapeAndBadNames() {
        #expect(LUTLibraryWire.isSafeStoredFileName("Look.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("../Look.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("dir/Look.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("Look:cube.cube"))
        #expect(!LUTLibraryWire.isSafeStoredFileName("Look.CUBE.bak"))
    }

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
        let record = try #require(LUTLibraryWire.validatedImport(utf8: utf8, fileName: "Look.cube"))
        #expect(record.hasPrefix("1\u{001F}2\u{001F}"))
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

    @Test
    func creativeMonoPacksAGreyscaleCube() throws {
        let packed = try #require(LUTLibraryWire.packedCreativeLook("Mono"))
        #expect(!packed.isEmpty)
        #expect(packed.count % 4 == 0)
    }
}
