import AVFoundation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class MediaLibraryTests: XCTestCase {
    func testThumbnailGridMatchesOpenZCineMinima() {
        XCTAssertEqual(MediaThumbnailSize.small.gridMinimum, 148)
        XCTAssertEqual(MediaThumbnailSize.medium.gridMinimum, 210)
        XCTAssertEqual(MediaThumbnailSize.large.gridMinimum, 280)
        XCTAssertEqual(MediaThumbnailSize.small.gridMaximum, 200)
        XCTAssertEqual(MediaThumbnailSize.medium.gridMaximum, 300)
        XCTAssertEqual(MediaThumbnailSize.large.gridMaximum, 380)
    }

    func testEmptyCopyDoesNotNameSisterApps() {
        let copy = [
            MediaLibraryCopy.filterEmpty,
            MediaLibraryCopy.emptyAll,
            MediaLibraryCopy.emptyFavorites,
            MediaLibraryCopy.emptyVideos,
            MediaLibraryCopy.emptyPhotos,
            MediaLibraryCopy.disconnected,
            MediaLibraryCopy.disconnectedEmptyCache,
            MediaOperatorCopy.clipNotCached,
        ]
        for text in copy {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("OpenZCine"))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("Nikon"))
            XCTAssertFalse(text.localizedCaseInsensitiveContains("protocol is not"))
        }
    }

    func testFilterAndSortOfManifestFiles() {
        let videos = [
            MediaFile(
                path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
                thumbPath: "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
                handle: 0x4010_0880,
                durationSeconds: 209,
                resolution: "3840x2160"),
            MediaFile(
                path: "DCIM/DJI_001/DJI_20260404103742_0001_D.MP4",
                thumbPath: "MISC/THM/DJI_001/DJI_20260404103742_0001_D.scr",
                handle: 0x4010_0040,
                durationSeconds: 12,
                isStarred: true,
                resolution: "1920x1080"),
        ]
        let photo = MediaFile(
            path: "DCIM/DJI_001/DJI_20260801000000_0002_D.JPG",
            thumbPath: "MISC/THM/DJI_001/DJI_20260801000000_0002_D.scr")
        let all = videos + [photo]

        XCTAssertEqual(MediaLibraryQuery.filtered(all, tab: .videos).count, 2)
        XCTAssertEqual(MediaLibraryQuery.filtered(all, tab: .photos).count, 1)
        XCTAssertEqual(MediaLibraryQuery.filtered(all, tab: .favorites).count, 1)
        XCTAssertEqual(
            MediaLibraryQuery.filtered(all, tab: .all, formats: ["MP4"]).count, 2)
        XCTAssertEqual(
            MediaLibraryQuery.filtered(all, tab: .all, resolutions: ["3840x2160"]).count, 1)

        let oldest = MediaLibraryQuery.sorted(all, by: .oldest)
        XCTAssertEqual(oldest.first?.filename, "DJI_20260404103742_0001_D.MP4")
        let newest = MediaLibraryQuery.sorted(videos, by: .newest)
        XCTAssertEqual(newest.first?.filename, "DJI_20260814125250_0034_D.MP4")
        XCTAssertEqual(MediaClipFormatting.durationLabel(seconds: 209), "3:29")
    }

    func testOfflineLibraryHidesThumbOnlyClips() {
        let cached = MediaFile(
            path: "DCIM/DJI_001/CACHED.MP4",
            thumbPath: "MISC/THM/CACHED.scr")
        let thumbOnly = MediaFile(
            path: "DCIM/DJI_001/THUMB_ONLY.MP4",
            thumbPath: "MISC/THM/THUMB_ONLY.scr")
        let shown = MediaLibraryQuery.cachedOnly(
            [cached, thumbOnly], cachedPaths: [cached.path])
        XCTAssertEqual(shown.map(\.filename), ["CACHED.MP4"])
    }

    func testPlaybackCompositionScalesWorkingSizeBackToTheRaster() {
        let working = CGRect(x: 0, y: 0, width: 1440, height: 810)
        let raster = CGRect(x: 0, y: 0, width: 3840, height: 2160)
        let fitted = working.applying(MediaLUT.transformFitting(working, to: raster))
        XCTAssertEqual(fitted.width, raster.width, accuracy: 0.5)
        XCTAssertEqual(fitted.height, raster.height, accuracy: 0.5)
        XCTAssertEqual(fitted.minX, 0, accuracy: 0.5)
        XCTAssertEqual(fitted.minY, 0, accuracy: 0.5)
        XCTAssertEqual(1440 / 3840.0, 0.375, accuracy: 0.0001)
    }

    func testExportPresetKeepsFourKNot720p() {
        let compatible = [
            AVAssetExportPresetHEVCHighestQuality,
            AVAssetExportPreset1280x720,
            AVAssetExportPresetHighestQuality,
        ]
        XCTAssertEqual(
            MediaLUT.exportPreset(bakingLUT: true, compatible: compatible),
            AVAssetExportPresetHEVCHighestQuality)
        XCTAssertEqual(
            MediaLUT.exportPreset(bakingLUT: false, compatible: compatible),
            AVAssetExportPresetPassthrough)
        XCTAssertNotEqual(
            MediaLUT.exportPreset(bakingLUT: true, compatible: compatible),
            AVAssetExportPreset1280x720)
    }

    func testExportProgressMapsTheSessionBand() {
        XCTAssertEqual(MediaLUT.mappedExportProgress(0), 0.05, accuracy: 0.0001)
        XCTAssertEqual(MediaLUT.mappedExportProgress(0.5), 0.475, accuracy: 0.0001)
        XCTAssertEqual(MediaLUT.mappedExportProgress(1), 0.90, accuracy: 0.0001)
        XCTAssertEqual(MediaLUT.mappedExportProgress(1.4), 0.90, accuracy: 0.0001)
    }

    func testShareOverlaySaysExportingWhileTheSessionTicks() {
        var state = MediaDeliveryOverlayState(
            destination: .nativeShare, totalClips: 1, clipIndex: 1, clipFraction: 0.05)
        XCTAssertEqual(state.statusLine, "Exporting 5%")
        state.clipFraction = 0.5
        XCTAssertEqual(state.statusLine, "Exporting 50%")
        state.clipFraction = 0.95
        XCTAssertEqual(state.statusLine, "Preparing to share 95%")
        state.clipFraction = 1
        XCTAssertEqual(state.statusLine, "Preparing to share 100%")
    }

    func testFiftyFpsClipOffersHalfSpeedConform() {
        let file = MediaFile(
            path: "DCIM/DJI_001/DJI_20260819000000_0050_D.MP4",
            thumbPath: "MISC/THM/DJI_001/DJI_20260819000000_0050_D.scr",
            resolution: "3840x2160",
            fps: 50)
        let source = ConformPreview.probe(listedRate: file.fps.map(Double.init))
        let availability = ConformPreview.availability(for: source)
        XCTAssertEqual(source.captureRate, 50)
        XCTAssertTrue(availability.targets.contains(25))
        XCTAssertEqual(
            ConformPreview.targetLabel(captureRate: 50, targetRate: 25), "25 fps · 50%")
        XCTAssertEqual(
            PlaybackVideoLayout.size(fromResolution: file.resolution),
            CGSize(width: 3840, height: 2160))
    }

    func testMediaFileCatalogRoundTrip() throws {
        let file = MediaFile(
            path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath: "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            handle: 0x4010_0880,
            sizeBytes: 1_024_000,
            durationSeconds: 12,
            resolution: "3840x2160")
        let data = try JSONEncoder().encode([file])
        let decoded = try JSONDecoder().decode([MediaFile].self, from: data)
        XCTAssertEqual(decoded, [file])
    }

    func testPlaybackToolbarUsesLabeledChipsAndAudio() {
        XCTAssertTrue(LiveAssistTool.playbackToolbarCases.contains(.audioMeters))
        XCTAssertTrue(LiveAssistTool.playbackToolbarCases.contains(.falseColor))
        XCTAssertTrue(LiveAssistTool.playbackToolbarCases.contains(.zebra))
        XCTAssertFalse(LiveAssistTool.playbackToolbarCases.contains(.level))
        XCTAssertFalse(LiveAssistTool.playbackToolbarCases.contains(.magnification))
    }

    func testShareDestinationsMatchOpenZCine() {
        XCTAssertEqual(
            MediaDeliveryDestination.allCases.map(\.title),
            ["Share", "Frame.io"])
        XCTAssertEqual(MediaExportFormat.allCases.map(\.label), ["MOV", "MP4"])
        let file = MediaFile(
            path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath: "MISC/THM/clip.scr")
        var config = MediaDeliveryConfiguration()
        config.bakeLUT = true
        config.exportFormat = .mov
        XCTAssertEqual(
            MediaDelivery.filename(for: file, configuration: config),
            "DJI_20260814125250_0034_D.mov")
        config.bakeLUT = false
        XCTAssertEqual(MediaDelivery.filename(for: file, configuration: config), file.filename)
    }

    func testPlaybackCandidatesPreferProxyThenOriginalOnBothStores() {
        let file = MediaFile(
            path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath: "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            handle: 0x4010_0880)
        let paths = MediaHTTP.previewPaths(file)
        XCTAssertEqual(paths.first?.hasSuffix(".LRF"), true)
        XCTAssertEqual(paths.last, file.path)
        XCTAssertEqual(MediaHTTP.deliveryPath(file), file.path)
        XCTAssertFalse(MediaHTTP.isProxyPath(MediaHTTP.deliveryPath(file)))
        XCTAssertTrue(MediaHTTP.proxyPaths(file).allSatisfy { MediaHTTP.isProxyPath($0) })
        XCTAssertFalse(MediaHTTP.proxyPaths(file).contains(file.path))
        XCTAssertFalse(MediaHTTP.proxyPaths(file).isEmpty)

        let first = MediaHTTP.storageGuess(handle: file.handle, singleSdStorage: false)
        XCTAssertEqual(first, 1)
        let candidates = MediaHTTP.playbackCandidates(file: file, firstStorage: first)
        XCTAssertEqual(candidates.count, 4)
        XCTAssertEqual(candidates[0].storage, 1)
        XCTAssertTrue(candidates[0].path.hasSuffix(".LRF"))
        XCTAssertEqual(candidates[1].storage, 0)
        XCTAssertTrue(candidates[1].path.hasSuffix(".LRF"))
        XCTAssertEqual(candidates[2].storage, 1)
        XCTAssertEqual(candidates[2].path, file.path)
        XCTAssertEqual(MediaHTTP.playbackMIMEType(for: "/v2"), "video/mp4")
        XCTAssertEqual(MediaHTTP.playbackMIMEType(for: file.path), "video/mp4")
        XCTAssertEqual(
            MediaHTTP.playbackCacheFileName(paths[0]),
            "DCIM_DJI_001_DJI_20260814125250_0034_D.mp4")
        XCTAssertTrue(MediaHTTP.playbackCacheFileName(file.path).hasSuffix(".MP4"))
    }

    func testPlaybackTransportFitsNarrowestPhone() {
        let needed = MediaPlayerView.PlaybackChrome.transportRowWidth()
        let usable =
            MediaPlayerView.PlaybackChrome.narrowestScreenWidth
            - MediaPlayerView.PlaybackChrome.chromeHorizontalPadding * 2
        XCTAssertLessThanOrEqual(needed, usable)
    }

    func testClipOpenCopyDoesNotNameSisterApps() {
        XCTAssertFalse(
            MediaOperatorCopy.clipOpenFailed.localizedCaseInsensitiveContains("OpenZCine"))
        XCTAssertFalse(MediaOperatorCopy.clipOpenFailed.localizedCaseInsensitiveContains("Nikon"))
        XCTAssertFalse(MediaOperatorCopy.clipOpenFailed.isEmpty)
        XCTAssertFalse(MediaOperatorCopy.clipLoading.localizedCaseInsensitiveContains("OpenZCine"))
    }
}
