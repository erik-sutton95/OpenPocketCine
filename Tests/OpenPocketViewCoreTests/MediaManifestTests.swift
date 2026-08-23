import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct MediaManifestTests {
    private var fixture: Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/nano-manifest.bin")
        return try! Data(contentsOf: url)
    }

    @Test func decodesNanoManifestCountAndNames() {
        let files = MediaManifest.decode(fixture)
        #expect(files.count == 34)
        #expect(MediaManifest.headerCount([UInt8](fixture)) == 34)
        #expect(files.first?.filename == "DJI_20260814125250_0034_D.MP4")
        #expect(files.last?.filename == "DJI_20260404103742_0001_D.MP4")
        #expect(files.allSatisfy { $0.kind == .video })
        #expect(files.allSatisfy { $0.filename.hasSuffix(".MP4") })
    }

    @Test func pairsThumbsHandlesAndDuration() {
        let files = MediaManifest.decode(fixture)
        let first = files[0]
        #expect(first.path == "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4")
        #expect(first.thumbPath == "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr")
        #expect(first.handle == 0x4010_0880)
        #expect(first.durationSeconds == 209)
        #expect(first.fps == 25)
        #expect(first.resolution == "3840x2160")
        #expect(first.isStarred == false)
        #expect(first.sizeBytes > 0)

        let second = files[1]
        #expect(second.filename == "DJI_20260814122657_0033_D.MP4")
        #expect(second.thumbPath.hasSuffix("DJI_20260814122657_0033_D.scr"))
        #expect(second.handle == 0x4010_0840)
        #expect(second.durationSeconds == 1551)
    }

    @Test func handleFitIsNanoGeometry() {
        let files = MediaManifest.decode(fixture)
        let withCmd = files.filter { $0.cmdHandle != 0 }
        #expect(withCmd.count == 34)
        // Nano internal: base 0x40100000, step 0x40. File 0034 → 0x40100000 + 34*0x40 = 0x40100880.
        #expect(files[0].cmdHandle == 0x4010_0880)
        #expect(files[0].cmdHandle == files[0].handle)
        let steps = zip(files.dropLast(), files.dropFirst()).map { $0.handle &- $1.handle }
        #expect(steps.allSatisfy { $0 == 0x40 })
    }

    @Test func httpPathsUseStorageAndScr() {
        let files = MediaManifest.decode(fixture)
        let file = files[0]
        let storage = MediaHTTP.storageGuess(handle: file.handle, singleSdStorage: false)
        #expect(storage == 1)
        let thumb = MediaHTTP.pathURL(storage: storage, path: file.thumbPath)
        #expect(
            thumb?.absoluteString
                == "http://192.168.2.1/v2?storage=1&path=MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr"
        )
        let original = MediaHTTP.pathURL(storage: storage, path: file.path)
        #expect(
            original?.absoluteString.contains("DCIM/DJI_001/DJI_20260814125250_0034_D.MP4") == true)
        #expect(MediaHTTP.previewPaths(file).contains { $0.hasSuffix(".LRF") })
        let play = MediaHTTP.playbackCandidates(file: file, firstStorage: 1)
        #expect(play.map(\.storage) == [1, 0, 1, 0])
        #expect(play.map(\.path).allSatisfy { $0.hasSuffix(".LRF") || $0.hasSuffix(".MP4") })
        #expect(play.first?.path.hasSuffix(".LRF") == true)
        #expect(play.last?.path.hasSuffix(".MP4") == true)
        #expect(MediaHTTP.isProxyPath(play[0].path))
        #expect(!MediaHTTP.isProxyPath(file.path))
        #expect(MediaHTTP.deliveryPath(file) == file.path)
        #expect(!MediaHTTP.isProxyPath(MediaHTTP.deliveryPath(file)))
        #expect(MediaHTTP.previewPaths(file).first != MediaHTTP.deliveryPath(file))
        #expect(MediaHTTP.proxyPaths(file).allSatisfy { MediaHTTP.isProxyPath($0) })
        #expect(!MediaHTTP.proxyPaths(file).contains(file.path))
        #expect(!MediaHTTP.proxyPaths(file).isEmpty)
        #expect(MediaHTTP.playbackMIMEType(for: play[0].path) == "video/mp4")
        #expect(MediaHTTP.playbackMIMEType(for: file.path) == "video/mp4")
        #expect(MediaHTTP.playbackCacheFileName(play[0].path).hasSuffix(".mp4"))
        #expect(MediaHTTP.playbackCacheFileName(file.path).hasSuffix(".MP4"))
        // `/v2` itself has no extension — the player must not key off the URL path.
        #expect(thumb?.pathExtension.isEmpty == true)
    }

    @Test func listPayloadMatchesOsmosis() {
        let newest = MediaListCommand.listPayload(counter: 1, cursor: 1)
        #expect(newest[4] == 1)
        #expect(Array(newest[10...13]) == [0x01, 0x00, 0x00, 0x00])
        #expect(newest[14] == 0x2D)
        let onboard = MediaListCommand.listPayload(
            counter: 2, cursor: MediaListCommand.newestInternal)
        #expect(onboard[4] == 2)
        #expect(Array(onboard[10...13]) == [0x01, 0x00, 0x00, 0x40])
        #expect(Commands.mediaListTrigger().payload == MediaListCommand.triggerPayload)
        #expect(Commands.exitPlayback(seq: 0).payload == [0x01, 0x01, 0x00, 0x00])
        #expect(Commands.enterPlayback(seq: 0).payload == [0x01, 0x01, 0x00, 0x01])
    }

    @Test func deleteAndFavoritePayloadsMatchCapture() {
        // Osmosis: handle 0x40104480, first delete of a session (counter 1).
        let del = Commands.deleteMedia(handle: 0x4010_4480, counter: 1)
        #expect(del.cmdSet == 0x00)
        #expect(del.cmdId == 0x28)
        #expect(
            del.payload == [
                0x01,
                0x80, 0x44, 0x10, 0x40,
                0x01, 0x00, 0x00, 0x00,
                0x00,
                0x01, 0x00, 0x00, 0x00,
                0x01, 0x01, 0x00, 0x00,
            ])
        let fav = Commands.setMediaFavorite(handle: 0x4010_4040, on: true, counter: 1)
        #expect(fav.cmdSet == 0x02)
        #expect(fav.cmdId == 0xBF)
        #expect(
            fav.payload == [
                0x01, 0x01,
                0x40, 0x40, 0x10, 0x40,
                0x01, 0x00, 0x00, 0x00,
                0x00, 0x01, 0x00, 0x00, 0x00,
            ])
    }

    @Test func chunkAssemblerStripsSubheader() {
        var assembler = MediaChunkAssembler()
        var payload: [UInt8] = [0x4A, 0x01, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]
        payload += [0xDE, 0xAD]
        let frame = Duml.Frame(
            sender: 0, receiver: 0, seq: 0, flags: 0,
            cmdSet: 0x00, cmdId: 0x27, payload: payload)
        let accepted = assembler.ingest(frame)
        #expect(accepted)
        #expect(assembler.assembled(counter: 2) == [0xDE, 0xAD])
        let ended = assembler.ingest(
            Duml.Frame(
                sender: 0, receiver: 0, seq: 0, flags: 0,
                cmdSet: 0x00, cmdId: 0x27,
                payload: [0x4A, 0x03, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]))
        #expect(ended)
        #expect(assembler.sawEnd)
    }

    @Test func nextCursorUsesOldestVideoHandle() {
        let files = MediaManifest.decode(fixture)
        let handles = files.map(\.handle)
        let oldest = MediaListCommand.oldestVideoHandle(handles)
        #expect(oldest == handles.min())
        #expect(MediaListCommand.hasOlderPage(recordCount: 34, cursor: oldest) == false)
        #expect(MediaListCommand.hasOlderPage(recordCount: 45, cursor: oldest) == true)
        let older = MediaListCommand.nextCursor(handles: handles, current: files[0].handle)
        #expect(older == files.dropFirst().map(\.handle).min())
    }

    @Test func queryFiltersAndSorts() {
        let files = MediaManifest.decode(fixture)
        let videos = MediaLibraryQuery.filtered(files, tab: .videos)
        #expect(videos.count == 34)
        let photos = MediaLibraryQuery.filtered(files, tab: .photos)
        #expect(photos.isEmpty)
        let oldest = MediaLibraryQuery.sorted(files, by: .oldest)
        #expect(oldest.first?.filename.contains("20260404") == true)
        #expect(MediaClipFormatting.durationLabel(seconds: 209) == "3:29")
    }

    @Test func starByteIsStrictlyOne() {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[0] = 0xFF
        bytes[1] = 0x19
        bytes[2] = 0x06
        bytes[9] = 44
        // Action-family length must not count as starred.
        let files = MediaManifest.decode(bytes)
        #expect(files.isEmpty)
    }
}
