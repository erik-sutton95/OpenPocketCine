import Testing

@testable import OpenPocketViewCore

@Suite struct CubeLUTTests {
    @Test func parsesValidTwoByTwoCube() throws {
        let text = """
            # a comment
            TITLE "demo"
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
        let lut = try CubeLUT.parse(text)
        #expect(lut.size == 2)
        #expect(lut.rgb.count == 2 * 2 * 2 * 3)
        #expect(Array(lut.rgb.prefix(3)) == [0, 0, 0])
        #expect(Array(lut.rgb.suffix(3)) == [1, 1, 1])
    }

    @Test func skipsDomainAndMetadataLines() throws {
        let text = """
            LUT_3D_SIZE 2
            DOMAIN_MIN 0.0 0.0 0.0
            DOMAIN_MAX 1.0 1.0 1.0
            0.0 0.0 0.0
            0.5 0.5 0.5
            0.0 0.0 0.0
            0.0 0.0 0.0
            0.0 0.0 0.0
            0.0 0.0 0.0
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        let lut = try CubeLUT.parse(text)
        #expect(lut.size == 2)
        #expect(Array(lut.rgb[3..<6]) == [0.5, 0.5, 0.5])
    }

    @Test func rejectsNonDefaultInputDomain() {
        let text = """
            LUT_3D_SIZE 2
            DOMAIN_MIN 0.0 0.0 0.0
            DOMAIN_MAX 2.0 2.0 2.0
            0.0 0.0 0.0
            1.0 1.0 1.0
            """
        #expect(throws: CubeLUTParseError.unsupportedDomain) {
            try CubeLUT.parse(text)
        }
    }

    @Test func throwsWhenSizeDeclarationMissing() {
        #expect(throws: CubeLUTParseError.missingSize) {
            try CubeLUT.parse("0 0 0\n1 1 1\n")
        }
    }

    @Test func throwsWhenSampleCountDoesNotMatchSize() {
        let text = """
            LUT_3D_SIZE 2
            0 0 0
            1 1 1
            """
        #expect(throws: CubeLUTParseError.self) {
            try CubeLUT.parse(text)
        }
    }

    @Test func rejectsDegenerateCubeSizeBelowTwo() {
        #expect(throws: CubeLUTParseError.unsupportedSize(1)) {
            try CubeLUT.parse("LUT_3D_SIZE 1\n0 0 0\n")
        }
    }

    @Test func rejectsCubeSizeAboveSupportedMaximum() {
        #expect(throws: CubeLUTParseError.unsupportedSize(66)) {
            try CubeLUT.parse("LUT_3D_SIZE 66\n0 0 0\n")
        }
    }

    @Test func acceptsResolveDefaultSize65Declaration() {
        #expect(CubeLUT.supportedSizeRange.contains(65))
        #expect(throws: CubeLUTParseError.sampleCountMismatch(expected: 65 * 65 * 65 * 3, found: 3))
        {
            try CubeLUT.parse("LUT_3D_SIZE\t65\n0 0 0\n")
        }
    }

    @Test func colorCubeDownsamplesSize65To64() {
        let n = 65
        let denom = Float(n - 1)
        var rgb = [Float]()
        rgb.reserveCapacity(n * n * n * 3)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    rgb.append(Float(r) / denom)
                    rgb.append(Float(g) / denom)
                    rgb.append(Float(b) / denom)
                }
            }
        }
        let lut = CubeLUT(size: n, rgb: rgb)
        let gpu = lut.colorCube
        #expect(gpu.size == CubeLUT.colorCubeMaxDimension)
        #expect(gpu.rgb.count == 64 * 64 * 64 * 3)
        let mid = gpu.map(red: 0.5, green: 0.5, blue: 0.5)
        #expect(abs(mid.red - 0.5) < 0.02)
        #expect(abs(mid.green - 0.5) < 0.02)
        #expect(abs(mid.blue - 0.5) < 0.02)
        #expect(
            CubeLUT(size: 33, rgb: Array(repeating: 0, count: 33 * 33 * 33 * 3)).colorCube.size
                == 33)
    }

    @Test func rejectsAbsurdlyLargeDeclaredSizeWithoutAllocating() {
        #expect(throws: CubeLUTParseError.unsupportedSize(1000)) {
            try CubeLUT.parse("LUT_3D_SIZE 1000\n0 0 0\n")
        }
    }

    @Test func parsesACRLFAuthoredCube() throws {
        let text =
            "# a comment\r\n"
            + "TITLE \"demo\"\r\n"
            + "LUT_3D_SIZE 2\r\n"
            + "DOMAIN_MIN 0.0 0.0 0.0\r\n"
            + "DOMAIN_MAX 1.0 1.0 1.0\r\n"
            + "0 0 0\r\n1 0 0\r\n0 1 0\r\n1 1 0\r\n"
            + "0 0 1\r\n1 0 1\r\n0 1 1\r\n1 1 1\r\n"
        let lut = try CubeLUT.parse(text)
        #expect(lut.size == 2)
        #expect(Array(lut.rgb.suffix(3)) == [1, 1, 1])
    }

    @Test func rgbaComponentsInsertAlpha() throws {
        let lut = try CubeLUT.parse(
            """
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
        )
        let rgba = lut.rgbaComponents
        #expect(rgba.count == 2 * 2 * 2 * 4)
        #expect(rgba[3] == 1)
        #expect(Array(rgba.prefix(4)) == [0, 0, 0, 1])
    }

    @Test func identityMapRoundTrip() {
        let identity = CubeLUT(
            size: 2,
            rgb: [
                0, 0, 0, 1, 0, 0, 0, 1, 0, 1, 1, 0,
                0, 0, 1, 1, 0, 1, 0, 1, 1, 1, 1, 1,
            ])
        let mapped = identity.map(red: 0, green: 0, blue: 0)
        #expect(mapped.red == 0 && mapped.green == 0 && mapped.blue == 0)
        let white = identity.map(red: 1, green: 1, blue: 1)
        #expect(white.red == 1 && white.green == 1 && white.blue == 1)
    }

    @Test func builtInMonoIsGreyscale() {
        let cube = BuiltInLook.mono.cube(size: 5)
        #expect(cube.size == 5)
        let mid = cube.map(red: 1, green: 0, blue: 0)
        #expect(abs(mid.red - mid.green) < 0.001)
        #expect(abs(mid.green - mid.blue) < 0.001)
        #expect(mid.red > 0.2)
    }

    @Test func builtInContrastPullsMids() {
        let contrast = BuiltInLook.contrast.map(red: 0.5, green: 0.5, blue: 0.5)
        #expect(abs(contrast.0 - 0.5) < 0.001)
        let low = BuiltInLook.contrast.map(red: 0.2, green: 0.2, blue: 0.2)
        #expect(low.0 < 0.2)
        let high = BuiltInLook.contrast.map(red: 0.8, green: 0.8, blue: 0.8)
        #expect(high.0 > 0.8)
    }

    @Test func expoParamDoesNotInventWhiteBalance() {
        // WB is `cam_image_effect` `@4–8`, not expo `@41`. `@6` is EV (`0x02/0x2E`). ISO is `@16`, not `@13`.
        var expo = [UInt8](repeating: 0, count: 46)
        expo[13] = 0xE7
        expo[14] = 0x03  // 999 sitting at the old wrong offset
        expo[16] = 0xC8
        expo[17] = 0x00  // ISO 200
        expo[6] = 0x0F
        expo[7] = 0x01
        expo[41] = 0x02
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_expo_param", value: expo), to: &s))
        #expect(s.iso == 200)
        #expect(s.expoMode == .auto)  // @7 == 0x01 is exposure auto, not WB
        #expect(s.evComp == EvComp(thirds: -1))  // @6 == 0x0F
        #expect(s.whiteBalanceKelvin == -1)
        #expect(s.whiteBalance == nil)
        #expect(s.irisLabel == nil)
    }

    @Test func customLUTIndexKeepsOnlyCubesSortedCaseInsensitively() {
        let stored = CustomLUTIndex.stored(fromFileNames: [
            "b.cube", "A.cube", "notes.txt", "C.CUBE", "sub/dir",
        ])
        #expect(stored.map(\.fileName) == ["A.cube", "b.cube", "C.CUBE"])
        #expect(stored[0].displayName == "A")
        #expect(CustomLUTIndex.displayName(fileName: "Bleach.CUBE") == "Bleach")
        #expect(CustomLUTIndex.displayName(fileName: "weird") == "weird")
    }

    @Test func customLUTIndexRejectsPathComponents() {
        #expect(CustomLUTIndex.isSafeFileName("Look.cube"))
        #expect(!CustomLUTIndex.isSafeFileName("../escape.cube"))
        #expect(!CustomLUTIndex.isSafeFileName("sub/Look.cube"))
        #expect(!CustomLUTIndex.isSafeFileName("Look:cube"))
        #expect(!CustomLUTIndex.isSafeFileName(""))
    }
}
