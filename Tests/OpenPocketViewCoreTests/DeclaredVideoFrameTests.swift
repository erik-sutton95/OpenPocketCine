import Testing

@testable import OpenPocketViewCore

@Suite struct DeclaredVideoFrameTests {
    private func packets(_ slice: [UInt8], group: UInt8 = 255, firstSeq: UInt16 = 65520)
        -> [[UInt8]]
    {
        let n = UInt32(slice.count)
        let header: [UInt8] = [
            0, 0, 1, 255, UInt8(n & 255), UInt8((n >> 8) & 255), UInt8((n >> 16) & 255),
            UInt8(n >> 24), 0x90, 0x11, 0, 0, 0, 0, 0, 0,
        ]
        let bytes = header + slice
        let count = (bytes.count + 63) / 64
        return (0..<count).map { i in
            var p = [UInt8](repeating: 0, count: 20)
            let seq = firstSeq &+ UInt16(i * 8)
            p[4] = UInt8(seq & 255)
            p[5] = UInt8(seq >> 8)
            p[6] = 2
            p[16] = group &+ UInt8(i / 63)
            p[17] = UInt8(min(63, count - (i / 63) * 63)) | UInt8(((i % 63) % 2) << 7)
            p[18] = UInt8((i % 63) / 2)
            return p + Array(bytes[(i * 64)..<min(bytes.count, (i + 1) * 64)])
        }
    }
    private let slice = [UInt8]([0, 0, 1, 0x65]) + [UInt8](repeating: 0xAA, count: 9000)

    @Test func joinsThreeTransportGroupsIntoOnePicture() {
        var dp = HevcDepacketizer()
        var output: [[UInt8]] = []
        for p in packets(slice) { if let au = dp.feed(p) { output.append(au) } }
        #expect(output == [slice])
        #expect(dp.droppedIncomplete == 0)
    }
    @Test func missingContinuationPacketRejectsWholePictureAndNextFrameRecovers() {
        var dp = HevcDepacketizer()
        var output: [[UInt8]] = []
        for (i, p) in packets(slice).enumerated() where i != 64 {
            if let au = dp.feed(p) { output.append(au) }
        }
        #expect(output.isEmpty)
        #expect(dp.droppedIncomplete == 1)
        let small: [UInt8] = [0, 0, 1, 0x65, 0xAA]
        #expect(dp.feed(packets(small, group: 8, firstSeq: 4000)[0]) == small)
    }
    @Test func duplicatePacketsIncludingFinalDoNotEmitTwice() {
        var dp = HevcDepacketizer()
        var output: [[UInt8]] = []
        for p in packets(slice) {
            for _ in 0..<2 { if let au = dp.feed(p) { output.append(au) } }
        }
        #expect(output == [slice])
        #expect(dp.droppedIncomplete == 0)
    }
    @Test func nextMarkerRejectsTruncatedPicture() {
        var dp = HevcDepacketizer()
        for p in packets(slice).prefix(63) { #expect(dp.feed(p) == nil) }
        let small: [UInt8] = [0, 0, 1, 0x41, 0xBB]
        #expect(dp.feed(packets(small, group: 9, firstSeq: 9000)[0]) == small)
        #expect(dp.droppedIncomplete == 1)
    }
    @Test func invalidDeclaredLengthCannotEmitOrPoisonNextPicture() {
        var dp = HevcDepacketizer()
        let small: [UInt8] = [0, 0, 1, 0x65, 0xBB]
        #expect(dp.feed(packets(small)[0]) == small)
        var invalid = packets(small, group: 2, firstSeq: 100)[0]
        invalid.replaceSubrange(24..<28, with: [255, 255, 255, 255])
        #expect(dp.feed(invalid) == nil)
        #expect(dp.feed(packets(small, group: 3, firstSeq: 108)[0]) == small)
    }
    @Test func malformedFirstMarkerNeverFallsBackToGroupEmission() {
        var dp = HevcDepacketizer()
        let small: [UInt8] = [0, 0, 1, 0x65, 0xCC]
        var invalid = packets(small, firstSeq: 100)[0]
        invalid.replaceSubrange(24..<28, with: [255, 255, 255, 255])
        #expect(dp.feed(invalid) == nil)
        var continuation = invalid
        continuation[4] = 108
        continuation[16] = 9
        continuation.replaceSubrange(20..<24, with: [1, 2, 3, 4])
        #expect(dp.feed(continuation) == nil)
        #expect(dp.feed(packets(small, group: 10, firstSeq: 116)[0]) == small)
    }

    @Test func privateNanoMetadataCannotCreateFalseSliceNALs() {
        let sps: [UInt8] = [0x67, 0x42, 0xAA]
        let picture: [UInt8] = [0x65, 0xBB]
        var metadata = [UInt8](repeating: 0x22, count: 25)
        metadata.replaceSubrange(4..<9, with: [0, 0, 1, 0x41, 0xFF])
        let privateSEI: [UInt8] = [0, 0, 1, 6, 0xF0, 25] + metadata + [0x80]
        let au = [0, 0, 0, 1] + sps + privateSEI + [0, 0, 0, 1] + picture
        #expect(Hevc.nalUnits(au) == [sps, picture])
        #expect(Hevc.nalUnits(privateSEI).isEmpty)
        let ordinarySEI: [UInt8] = [6, 5, 1, 0x22, 0x80]
        #expect(Hevc.nalUnits([0, 0, 1] + ordinarySEI) == [ordinarySEI])
    }

}
