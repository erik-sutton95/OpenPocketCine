import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct ClipColorProfileTests {
    @Test func gammaMapsToColorMode() {
        #expect(ClipColorProfile.colorMode(fromGamma: "Rec.709") == .normal)
        #expect(ClipColorProfile.colorMode(fromGamma: "Rec.2100 HLG") == .hdr)
        #expect(ClipColorProfile.colorMode(fromGamma: "D-Log") == .dLog)
        #expect(ClipColorProfile.colorMode(fromGamma: "D-Log2") == .dLog2)
        #expect(ClipColorProfile.colorMode(fromGamma: "D-Log M") == .dLogM)
        #expect(ClipColorProfile.colorMode(fromGamma: "  D-Log2  ") == .dLog2)
        #expect(ClipColorProfile.colorMode(fromGamma: "Rec.2020") == nil)
        #expect(ClipColorProfile.colorMode(fromGamma: "") == nil)
    }

    @Test func clipKeysWinOverLastLiveLog() {
        #expect(
            PlaybackLUTColor.resolve(clip: .dLog2, live: .normal, last: .dLog) == .dLog2)
        #expect(
            PlaybackLUTColor.resolve(clip: .normal, live: .dLog2, last: .dLog2) == .normal,
            "a Rec.709 clip must not keep last live log")
        #expect(
            PlaybackLUTColor.resolve(clip: .hdr, live: .normal, last: .dLog2) == .hdr)
        #expect(
            PlaybackLUTColor.resolve(clip: nil, live: .normal, last: .dLog2) == .dLog2,
            "no Keys atom — keep last log so Auto still binds")
        #expect(PlaybackLUTColor.resolve(clip: nil, live: nil, last: nil) == nil)
    }

    @Test func parsesColorGammaFromQuickTimeKeys() {
        for (gamma, mode) in [
            ("Rec.709", ColorMode.normal),
            ("Rec.2100 HLG", .hdr),
            ("D-Log", .dLog),
            ("D-Log2", .dLog2),
        ] {
            let mp4 = Self.mp4(gamma: gamma)
            #expect(ClipColorProfile.gamma(fromMP4: mp4) == gamma)
            #expect(ClipColorProfile.colorMode(fromMP4: mp4) == mode)
        }
    }

    @Test func findsKeysWhenOnlyTheMoovTailIsPresent() {
        let full = Self.mp4(gamma: "D-Log2", padMdat: 4096)
        let tail = full.suffix(2048)
        #expect(ClipColorProfile.colorMode(fromMP4: Data(tail)) == .dLog2)
    }

    @Test func missingKeysIsNotAColor() {
        let empty = Self.box("ftyp", Data("isomisom".utf8))
        #expect(ClipColorProfile.colorMode(fromMP4: empty) == nil)
        #expect(ClipColorProfile.gamma(fromMP4: empty) == nil)
    }

    @Test func proxyRec709IsNotShotColor() {
        let rec709 = Self.mp4(gamma: "Rec.709")
        #expect(ClipColorProfile.colorMode(fromMP4: rec709) == .normal)
        #expect(
            ClipColorProfile.shotColor(
                fromMP4: rec709, path: "DCIM/DJI_001/DJI_20260824085921_0008_D.LRF") == nil,
            "LRF ColorGammaSxS is Rec.709 even on a D-Log2 take")
        #expect(
            ClipColorProfile.shotColor(
                fromMP4: rec709, path: "DCIM/CAM_001/clip.XRF") == nil)
        let log = Self.mp4(gamma: "D-Log2")
        #expect(
            ClipColorProfile.shotColor(fromMP4: log, path: "DCIM/DJI_001/DJI_x_D.MP4") == .dLog2)
        #expect(
            PlaybackLUTColor.resolve(clip: nil, live: .normal, last: .dLog2) == .dLog2,
            "ignored proxy Rec.709 must keep last live log")
    }

    @Test func httpRangeCoversTheMoovTail() {
        #expect(
            ClipColorProfile.httpRange(fileSize: 0) == "bytes=-\(ClipColorProfile.fileTailBytes)")
        #expect(ClipColorProfile.httpRange(fileSize: 100) == "bytes=0-99")
        let size = UInt64(ClipColorProfile.fileTailBytes) + 50
        #expect(
            ClipColorProfile.httpRange(fileSize: size)
                == "bytes=50-\(size - 1)")
    }

    @Test func realMimoExportsIfPresent() throws {
        let dir = ProcessInfo.processInfo.environment["OPC_CLIP_DIR"]
        guard let dir, !dir.isEmpty else { return }
        let expected: [(String, ColorMode)] = [
            ("_video_Normal.MP4", .normal),
            ("_video_HDR.MP4", .hdr),
            ("_video_Dlog.MP4", .dLog),
            ("_video_Dlog2.MP4", .dLog2),
        ]
        let root = URL(fileURLWithPath: dir)
        let files = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil)
        for (suffix, mode) in expected {
            guard let url = files.first(where: { $0.lastPathComponent.hasSuffix(suffix) })
            else {
                Issue.record("missing *\(suffix) in OPC_CLIP_DIR")
                continue
            }
            let data = try Data(contentsOf: url)
            #expect(ClipColorProfile.colorMode(fromMP4: data) == mode)
            let tail = data.suffix(ClipColorProfile.fileTailBytes)
            #expect(ClipColorProfile.colorMode(fromMP4: Data(tail)) == mode)
        }
    }

    @Test func realLrfProxiesAreNotShotColorIfPresent() throws {
        let dir = ProcessInfo.processInfo.environment["OPC_LRF_DIR"]
        guard let dir, !dir.isEmpty else { return }
        let files = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil)
        let lrf = files.filter {
            $0.pathExtension.lowercased() == "mp4" || $0.pathExtension.lowercased() == "lrf"
        }
        #expect(!lrf.isEmpty, "OPC_LRF_DIR has no proxy files")
        for url in lrf {
            let data = try Data(contentsOf: url)
            #expect(
                ClipColorProfile.colorMode(fromMP4: data) == .normal,
                "\(url.lastPathComponent) should parse as Rec.709")
            #expect(
                ClipColorProfile.shotColor(
                    fromMP4: data, path: "DCIM/DJI_001/\(url.lastPathComponent).LRF")
                    == nil,
                "\(url.lastPathComponent) must not drive Auto")
        }
    }

    /// `ftyp` + optional `mdat` pad + `moov/meta/{keys,ilst}` like Pocket 4P.
    private static func mp4(gamma: String, padMdat: Int = 0) -> Data {
        var keysPayload = Data()
        keysPayload.append(contentsOf: [0, 0, 0, 0, 0, 0, 0, 1])
        let name = Data("com.dji.camera.ColorGammaSxS".utf8)
        var entry = Data()
        entry.append(u32(UInt32(8 + name.count)))
        entry.append(contentsOf: Array("mdta".utf8))
        entry.append(name)
        keysPayload.append(entry)
        let keys = box("keys", keysPayload)

        var dataPayload = Data()
        dataPayload.append(u32(1))
        dataPayload.append(u32(0))
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
        out.append(u32(UInt32(8 + payload.count)))
        out.append(contentsOf: Array(type.utf8))
        out.append(payload)
        return out
    }

    private static func box(fourCC: UInt32, _ payload: Data) -> Data {
        var out = Data()
        out.append(u32(UInt32(8 + payload.count)))
        out.append(u32(fourCC))
        out.append(payload)
        return out
    }

    private static func u32(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 4)
    }
}
