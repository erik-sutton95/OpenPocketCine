import AVFoundation
import MonitorPresentation
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class MediaLibraryTests: XCTestCase {
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

        XCTAssertEqual(MediaLibraryQuery.filtered(all, tab: .favorites).count, 1)
        XCTAssertEqual(
            MediaLibraryQuery.filtered(all, tab: .all, formats: ["MP4"]).count, 2)
        XCTAssertEqual(
            MediaLibraryQuery.filtered(all, tab: .all, resolutions: ["3840x2160"]).count, 1)
        XCTAssertEqual(
            MediaLibraryQuery.filtered(all, tab: .all, dateStart: "20260801").map(\.filename),
            ["DJI_20260814125250_0034_D.MP4", "DJI_20260801000000_0002_D.JPG"])
        XCTAssertEqual(
            MediaLibraryQuery.filtered(all, tab: .all, dateEnd: "20260501").map(\.filename),
            ["DJI_20260404103742_0001_D.MP4"])
        XCTAssertEqual(
            MediaLibraryQuery.filtered(
                all, tab: .all, dateStart: "20260801", dateEnd: "20260801"
            ).map(\.filename),
            ["DJI_20260801000000_0002_D.JPG"])
        let newest = MediaLibraryQuery.sorted(videos, by: .newest)
        XCTAssertEqual(newest.first?.filename, "DJI_20260814125250_0034_D.MP4")
    }

    func testCacheGradePrefersOriginalOverProxy() {
        XCTAssertEqual(
            MediaCacheGrade.resolve(hasOriginal: true, hasProxy: true), .original)
        XCTAssertEqual(
            MediaCacheGrade.resolve(hasOriginal: false, hasProxy: true), .proxy)
        XCTAssertEqual(
            MediaCacheGrade.resolve(hasOriginal: false, hasProxy: false), .none)
        XCTAssertTrue(MediaCacheGrade.proxy.isProxyOnly)
        XCTAssertFalse(MediaCacheGrade.original.isProxyOnly)
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

    func testShareFilenameAndExposureMetadata() {
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
        var exposure = MediaDeliveryConfiguration()
        XCTAssertTrue(exposure.bakeLUTExposure)
        let baked = MediaDelivery.metadata(
            for: file, configuration: exposure, lutName: "Auto · D-Log2 → Rec.709",
            cameraName: nil, lutExposureStops: -1)
        XCTAssertEqual(baked?.lutExposureStops, -1)
        XCTAssertNil(baked?.convertLog)
        exposure.bakeLUTExposure = false
        let cubeOnly = MediaDelivery.metadata(
            for: file, configuration: exposure, lutName: "Auto · D-Log2 → Rec.709",
            cameraName: nil, lutExposureStops: -1)
        XCTAssertNil(cubeOnly?.lutExposureStops)
    }

    func testConvertLogExportNamesTheDestinationLog() {
        let file = MediaFile(
            path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath: "MISC/THM/clip.scr")
        var config = MediaDeliveryConfiguration()
        config.bakeLUT = false
        config.convertLog = true
        config.exportFormat = .mov
        XCTAssertEqual(
            MediaDelivery.filename(
                for: file, configuration: config, transform: .dLogToDLog2),
            "DJI_20260814125250_0034_D.dlog2.mov")
        XCTAssertEqual(
            MediaDelivery.filename(
                for: file, configuration: config, transform: .dLog2ToDLog),
            "DJI_20260814125250_0034_D.dlog.mov")
        config.convertLog = false
        XCTAssertEqual(
            MediaDelivery.filename(
                for: file, configuration: config, transform: .dLogToDLog2),
            file.filename)
        var converting = MediaDeliveryConfiguration()
        converting.convertLog = true
        converting.bakeLUT = true
        converting.bakeLUTExposure = true
        let meta = MediaDelivery.metadata(
            for: file, configuration: converting, lutName: "Auto · D-Log2 → Rec.709",
            cameraName: nil, lutExposureStops: -1, convertLog: .dLogToDLog2)
        XCTAssertEqual(meta?.convertLog, "D-Log → D-Log2")
        XCTAssertNil(meta?.lutName)
        XCTAssertNil(meta?.lutExposureStops)
        XCTAssertEqual(MediaDeliveryCopy.convertLog, "Convert log")
        XCTAssertFalse(MediaDeliveryCopy.convertLogHelp.isEmpty)
        XCTAssertFalse(MediaDeliveryCopy.convertLogHelpUnavailable.isEmpty)
        if case .convertLogNotLog(let name) = MediaDeliveryError.convertLogNotLog(file.filename) {
            XCTAssertEqual(name, file.filename)
        } else {
            XCTFail("expected convertLogNotLog")
        }
        XCTAssertEqual(
            MediaDeliveryError.convertLogNotLog(file.filename).errorDescription,
            "DJI_20260814125250_0034_D.MP4 isn't D-Log or D-Log2.")
        let photo = MediaFile(
            path: "DCIM/DJI_001/DJI_20260814125250_0034_D.JPG",
            thumbPath: "MISC/THM/clip.scr")
        XCTAssertFalse(MediaDelivery.convertLogAvailable(files: [photo], shotColors: []))
        XCTAssertTrue(MediaDelivery.convertLogAvailable(files: [file], shotColors: []))
        XCTAssertTrue(MediaDelivery.convertLogAvailable(files: [file], shotColors: [.dLog]))
        XCTAssertFalse(MediaDelivery.convertLogAvailable(files: [file], shotColors: [.normal]))
        XCTAssertTrue(
            MediaDelivery.convertLogAvailable(files: [file, file], shotColors: [.normal, nil]))
        XCTAssertTrue(
            MediaDelivery.convertLogAvailable(files: [file, file], shotColors: [nil, .normal]))
        XCTAssertFalse(
            MediaDelivery.convertLogAvailable(files: [photo, file], shotColors: [nil, .normal]))
        XCTAssertFalse(
            MediaDelivery.convertLogAvailable(files: [file, file], shotColors: [.normal, .hdr]))
        XCTAssertTrue(
            MediaDelivery.convertLogAvailable(files: [file, file], shotColors: [.dLog, .dLog2]))
    }

    func testPlaybackTransportFitsNarrowestPhone() {
        let portrait = MonitorPlaybackLayout(width: 375, height: 667, tablet: false)
        XCTAssertTrue(portrait.portrait)
        XCTAssertLessThanOrEqual(MonitorPlaybackLayout.transportWidth, portrait.contentWidth)
        XCTAssertLessThanOrEqual(MonitorPlaybackLayout.actionsWidth, portrait.contentWidth)
        let landscape = MonitorPlaybackLayout(width: 667, height: 375, tablet: false)
        XCTAssertFalse(landscape.portrait)
        let balancedRow =
            MonitorPlaybackLayout.actionsWidth * 2 + MonitorPlaybackLayout.transportWidth + 20
        XCTAssertLessThanOrEqual(balancedRow, landscape.contentWidth)
    }

    @MainActor
    func testPocket3ResolvedStorageUsesSingleSd() {
        let media = CameraMedia()
        let file = MediaFile(
            path: "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
            thumbPath: "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            handle: 0x4010_0880,
            storage: 1)
        XCTAssertEqual(media.resolvedStorage(for: file, singleSd: true), 0)
        XCTAssertEqual(media.resolvedStorage(for: file, singleSd: false), 1)
        media.rememberStorage(1, for: file.path)
        XCTAssertEqual(media.resolvedStorage(for: file, singleSd: true), 0)
    }
}
