import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineDJIApple
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Decodes cell images downsampled to a bounded pixel size, off the main actor.
actor MediaCellImageLoader {
    static let shared = MediaCellImageLoader()

    func downsampled(
        at url: URL, maxPixelSize: Int, fallbackOrientation: Int? = nil
    ) -> UIImage? {
        autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
                return nil
            }
            return Self.downsampled(
                source: source, maxPixelSize: maxPixelSize,
                fallbackOrientation: fallbackOrientation)
        }
    }

    func downsampled(
        data: Data, maxPixelSize: Int, fallbackOrientation: Int? = nil
    ) -> UIImage? {
        autoreleasepool {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
                return nil
            }
            return Self.downsampled(
                source: source, maxPixelSize: maxPixelSize,
                fallbackOrientation: fallbackOrientation)
        }
    }

    private nonisolated static func exifOrientation(source: CGImageSource) -> Int? {
        guard
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any]
        else { return nil }
        return (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue
    }

    private static func downsampled(
        source: CGImageSource, maxPixelSize: Int, fallbackOrientation: Int?
    ) -> UIImage? {
        let thumbnailOptions =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            ] as [CFString: Any] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
        else { return nil }
        if let fallbackOrientation, fallbackOrientation != 1,
            exifOrientation(source: source) == nil,
            let exif = CGImagePropertyOrientation(rawValue: UInt32(fallbackOrientation))
        {
            return UIImage(cgImage: cgImage, scale: 1, orientation: UIImage.Orientation(exif))
        }
        return UIImage(cgImage: cgImage)
    }
}

@MainActor
enum MediaCellThumbnailCache {
    static let shared: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 150
        return cache
    }()
}

extension UIImage.Orientation {
    fileprivate init(_ exif: CGImagePropertyOrientation) {
        switch exif {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}

enum MediaClipPresentation {
    static let resolutionLevels = MonitorMediaResolutionLevel.standard.filter { $0.minimumWidth <= 3840 && $0.minimumWidth != 2880 }
}

typealias MediaLibraryCopy = MonitorMediaGalleryCopy

struct MediaLibraryView: View {
    var safeArea: EdgeInsets = .init()
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model
    @State private var presented: MonitorMediaGalleryOpen<MediaFile>?
    @State private var deliveryFiles: [MediaFile]?
    private var session: CameraSession { model.session }
    private var library: MonitorMediaLibraryModel<MediaFile> { session.mediaLibrary }
    private var isLive: Bool { if case .live = session.phase { return true }; return false }
    private var operations: MonitorMediaGalleryOperations<MediaFile> {
        if isLive {
            return .init(download: { record in await session.download(file: record.payload) },
                delete: { record in await session.deleteMedia(record.payload) },
                favorite: { record in session.toggleFavorite(record.payload) })
        }
        return .init(favorite: { record in session.toggleFavorite(record.payload) })
    }
    var body: some View {
        MonitorOperatorCatalogScreen(library: library,
            brand: session.connectedCamera?.name ?? "OpenPocketCine", safeArea: safeArea,
            sourceAvailable: isLive, operations: operations,
            colorChoices: ColorMode.allCases.map { .init(id: String($0.rawValue), label: $0.label) },
            resolutionLevels: MediaClipPresentation.resolutionLevels,
            facts: { record in
                let file = session.libraryFile(record)
                return .init(resolution: file.resolution, byteCount: file.sizeBytes,
                    durationSeconds: file.durationSeconds, dateKey: file.dateKey,
                    colorLabel: record.facts.color.flatMap(UInt8.init).flatMap { ColorMode(rawValue: $0) }?.label, progress: session.mediaDownloadProgress[file.path])
            }, begin: { session.beginMediaBrowse() }, refresh: { session.refreshMedia() }, close: dismiss,
            open: { presented = $0 }, share: { records, token in
                guard library.isCurrent(token) else { return }
                deliveryFiles = records.map { record in session.libraryFile(record) }
            }, thumbnail: { context in
                let record = context.record
                let file = session.libraryFile(record)
                let grade = MediaCacheGrade.resolve(hasOriginal: context.cached?.originalURL != nil,
                    hasProxy: context.cached?.proxyURL != nil)
                MediaCatalogThumbnail(cameraID: session.mediaCameraID, file: file,
                    cacheGrade: grade, localURL: context.cached?.originalURL, thumbnailURL: context.cached?.thumbnailURL,
                    isCurrent: context.isCurrent, onDuration: context.duration)
            })
            .fullScreenCover(item: $presented) { request in
                if (request.record.facts.presentationKind ?? request.record.asset.kind) == .photo {
                    MediaPhotoViewer(opening: request, library: library, session: session).environment(model)
                } else {
                    MediaPlayerView(opening: request).environment(model)
                }
            }
            .overlay { MonitorOperatorDeliveryChrome(model: model.delivery.lifetime, scope: .surface, remoteDisplayName: "Frame.io") }
            .overlay {
                if let deliveryFiles {
                    MediaDeliveryPopupOverlay(files: deliveryFiles) { self.deliveryFiles = nil }
                }
            }
            .onChange(of: library.lifetimeToken) { _, _ in deliveryFiles = nil }
            #if DEBUG && targetEnvironment(simulator)
                .task(id: library.displayedRecords.first?.asset.id) {
                    // `ReviewLaunch(screen: .playback)`: open the first staged clip as a tap would.
                    guard MonitorUIReview.opensFirstClip, let record = library.displayedRecords.first else { return }
                    MonitorUIReview.opensFirstClip = false
                    presented = .init(record: record, playlist: library.displayedRecords, admission: library.actionToken)
                }
            #endif
    }
    private func dismiss() {
        if let onClose { onClose() } else { model.homePanel = nil }
    }
}

/// Bounded native image decoding/metadata adapter; the common catalog owns its admission.
private struct MediaCatalogThumbnail: View {
    let cameraID: String
    let file: MediaFile
    let cacheGrade: MediaCacheGrade
    let localURL: URL?
    let thumbnailURL: URL?
    let isCurrent: () -> Bool
    let onDuration: (String) -> Void
    @Environment(AppModel.self) private var model
    @State private var thumbnail: UIImage?

    private var isPhoto: Bool { file.kind == .photo }
    private var isDownloaded: Bool { cacheGrade == .original }

    var body: some View {
        ZStack {
            MonitorTheme.surface
            if let thumbnail {
                Image(uiImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                (isPhoto ? MonitorIcon.image : MonitorIcon.film)
                    .frame(width: 28, height: 28).foregroundStyle(MonitorTheme.faint)
            }
        }
        .clipped()
        .task(
            id:
                "\(cameraID)#\(DjiAppleMediaAssets.asset(for: file).id.rawValue)#\(thumbnailURL?.path ?? "")#\(localURL?.path ?? "")#\(cacheGrade.rawValue)"
        ) {
            thumbnail = nil
            await loadThumbnail()
            await loadDuration()
        }
    }

    private func loadThumbnail() async {
        let cacheKey = "\(cameraID)#\(DjiAppleMediaAssets.asset(for: file).id.rawValue)#grid" as NSString
        guard isCurrent(), !Task.isCancelled else { return }
        if let cached = MediaCellThumbnailCache.shared.object(forKey: cacheKey) {
            thumbnail = cached
            return
        }
        func present(_ image: UIImage) {
            guard isCurrent(), !Task.isCancelled else { return }
            MediaCellThumbnailCache.shared.setObject(image, forKey: cacheKey)
            thumbnail = image
        }
        if let thumbnailURL,
            let image = await MediaCellImageLoader.shared.downsampled(
                at: thumbnailURL, maxPixelSize: 640)
        {
            present(image)
            return
        }
        if isPhoto, isDownloaded, let localURL,
            let image = await MediaCellImageLoader.shared.downsampled(
                at: localURL, maxPixelSize: 640)
        {
            present(image)
            return
        }
        guard isCurrent(), !Task.isCancelled else { return }
        await model.session.ensureThumbnail(for: file)
        guard isCurrent(), !Task.isCancelled else { return }
        if let cachedURL = model.session.thumbnailURL(for: file),
            let image = await MediaCellImageLoader.shared.downsampled(
                at: cachedURL, maxPixelSize: 640)
        {
            present(image)
            return
        }
        guard isCurrent(), !Task.isCancelled else { return }
        if let data = await model.session.thumbnailBytes(for: file),
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 640)
        {
            present(image)
            return
        }
        guard isCurrent(), !Task.isCancelled, isDownloaded, !isPhoto, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let cgImage = try? await generator.image(at: time).image {
            present(UIImage(cgImage: cgImage))
        }
    }

    private func loadDuration() async {
        guard isCurrent(), !Task.isCancelled, !isPhoto else { return }
        if file.durationSeconds > 0 {
            onDuration(MediaClipFormatting.durationLabel(seconds: file.durationSeconds))
            return
        }
        guard isDownloaded, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration), !Task.isCancelled, duration.isNumeric,
            duration.seconds > 0
        {
            onDuration(MediaClipFormatting.durationLabel(seconds: Int(duration.seconds)))
        }
    }
}

/// Legal documents over home, shown only while one is open. Settings and media are the
/// shell's own covers.
struct AppPanelHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.homePanel {
        case .privacy: LegalDocumentView(kind: .privacy)
        case .terms: LegalDocumentView(kind: .terms)
        case .licenses: LegalDocumentView(kind: .licenses)
        case .notice: LegalDocumentView(kind: .notice)
        case .settings, .media, nil: EmptyView()
        }
    }
}
