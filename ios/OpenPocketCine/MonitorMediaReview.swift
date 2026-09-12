#if targetEnvironment(simulator)
    import Foundation
    import MonitorPresentation
    import MonitorUI
    import OpenPocketViewCore
    import SwiftUI
    import UIKit

    /// Explicitly opted-in screenshots of the production shared catalog. All data
    /// and thumbnail colors are fixtures; catalog actions do not touch camera I/O.
    @MainActor
    enum MonitorMediaReview {
        static let pathPrefix = "UI-REVIEW/"
        static var isActive: Bool {
            guard let screen = MonitorUIReview.screen else { return false }
            return ["media-fixture", "media-list", "media-selection", "playback"].contains(screen)
        }

        private static let sourceURL: URL? = {
            guard let path = ProcessInfo.processInfo.environment["OPV_SIM_FEED_CLIP"],
                FileManager.default.fileExists(atPath: path)
            else { return nil }
            return URL(fileURLWithPath: path)
        }()

        private static let sourceBytes: UInt64? = {
            guard let sourceURL else { return nil }
            return (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(
                UInt64.init)
        }()

        #if DEBUG
            /// This root is reachable only through the explicit simulator review
            /// environment. Each process owns a fresh temporary namespace.
            static let cacheRoot: URL = {
                let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "OpenPocketCine-UI-Review", isDirectory: true)
                // Interrupted UI test processes cannot run deinit. Reclaim only
                // previous review namespaces in this app's own temporary folder.
                if let stale = try? FileManager.default.contentsOfDirectory(
                    at: parent, includingPropertiesForKeys: nil)
                {
                    for directory in stale { try? FileManager.default.removeItem(at: directory) }
                }
                return parent.appendingPathComponent(UUID().uuidString, isDirectory: true)
            }()

            private static var cachedURLs: [String: URL] = [:]

            @MainActor
            final class CacheLease: ObservableObject {
                private let directory = MonitorMediaReview.cacheRoot

                func prepare(in session: CameraSession) throws {
                    guard MonitorMediaReview.isActive, let source = MonitorMediaReview.sourceURL
                    else {
                        return
                    }
                    for index in 0..<12 {
                        let file = MonitorMediaReview.file(index)
                        let destination = session.cameraMedia.fileCacheURL(
                            cameraID: session.mediaCameraID, file: file)
                        try FileManager.default.createDirectory(
                            at: destination.deletingLastPathComponent(),
                            withIntermediateDirectories: true)
                        if !FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.copyItem(at: source, to: destination)
                        }
                        MonitorMediaReview.cachedURLs[file.path] = destination
                    }
                }

                deinit { try? FileManager.default.removeItem(at: directory) }
            }
        #endif

        static func clipURL(for file: MediaFile) -> URL? {
            guard isActive, file.path.hasPrefix(pathPrefix) else { return nil }
            #if DEBUG
                guard let url = cachedURLs[file.path],
                    FileManager.default.fileExists(atPath: url.path)
                else { return nil }
                return url
            #else
                return sourceURL
            #endif
        }

        static func file(_ index: Int) -> MediaFile {
            MediaFile(
                path: "\(pathPrefix)Review_\(String(format: "%03d", index + 1)).MP4",
                thumbPath: "", sizeBytes: sourceBytes ?? 314_572_800, durationSeconds: 12,
                resolution: "3840x2160", fps: 25)
        }
    }

    struct MonitorMediaReviewView: View {
        @Environment(AppModel.self) private var model
        @Environment(\.monitorWindowGeometry) private var windowGeometry
        @State private var layout: MonitorMediaLayout = .grid
        @State private var size: MonitorThumbnailSize = .medium
        @State private var category = "All"
        @State private var selected: Set<String> = []
        @State private var favorites: Set<String> = [MonitorMediaReview.file(1).id]
        @State private var hidden: Set<String> = []
        @State private var ascending = false
        @State private var playing: MediaFile?
        @State private var delivery: [MediaFile]?
        #if DEBUG
            @StateObject private var cacheLease = MonitorMediaReview.CacheLease()
        #endif
        @State private var cacheError: String?

        private var items: [MonitorMediaItem] {
            var indices = Array(0..<12)
            if ascending { indices.reverse() }
            return indices.compactMap { index in
                let file = MonitorMediaReview.file(index)
                guard !hidden.contains(file.id), category != "Photos",
                    category != "Favorites" || favorites.contains(file.id)
                else { return nil }
                return MonitorMediaItem(
                    id: file.id, filename: file.filename,
                    metadata: "4K 25p · \(index % 3 == 0 ? "D-Log" : "Normal") · 300 MB",
                    format: "4K 25p", color: index % 3 == 0 ? "D-Log" : "Normal", duration: "0:12",
                    date: "2026-09-12",
                    availability: index % 3 == 0 ? .camera : index % 3 == 1 ? .proxy : .original,
                    progress: index == 3 ? 0.62 : nil, favorite: favorites.contains(file.id),
                    photo: false, permissions: [.share, .cache, .favorite, .delete])
            }
        }

        var body: some View {
            GeometryReader { geometry in
                MonitorMediaCatalog(
                    brand: "Review camera",
                    safeArea: OperatorPanelMetrics.resolvedDeviceSafeArea(
                        geometry.safeAreaInsets, window: windowGeometry.safeArea),
                    items: items,
                    categories: [
                        MonitorMediaCategory(id: "All", title: "All", count: 12 - hidden.count),
                        MonitorMediaCategory(
                            id: "Videos", title: "Videos", count: 12 - hidden.count),
                        MonitorMediaCategory(id: "Photos", title: "Photos", count: 0),
                        MonitorMediaCategory(
                            id: "Favorites", title: "Favorites", count: favorites.count),
                    ],
                    category: category, layout: layout, thumbnailSize: size,
                    sortTitle: ascending ? "Oldest" : "Newest", status: "Camera + local cache",
                    selectedIDs: selected, selecting: !selected.isEmpty, refreshing: false,
                    canRefresh: false, tablet: UIDevice.current.userInterfaceIdiom == .pad,
                    action: handle
                ) { item in
                    ZStack {
                        LinearGradient(
                            colors: [
                                .init(red: 0.18, green: 0.23, blue: 0.27),
                                .init(red: 0.08, green: 0.11, blue: 0.14),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                        OpcIcon.mountain.frame(width: 46, height: 46)
                            .foregroundStyle(.white.opacity(0.16))
                    }
                    .accessibilityLabel("Generated review thumbnail for \(item.filename)")
                } empty: {
                    Text("No matching clips").font(MonitorTheme.font(13)).foregroundStyle(
                        MonitorTheme.muted)
                } filters: {
                    EmptyView()
                }
            }
            .ignoresSafeArea().preferredColorScheme(.dark)
            .onAppear {
                #if DEBUG
                    do { try cacheLease.prepare(in: model.session) } catch {
                        cacheError = error.localizedDescription
                    }
                #endif
                if MonitorUIReview.screen == "media-list" { layout = .list }
                if MonitorUIReview.screen == "media-selection" {
                    selected = [MonitorMediaReview.file(0).id, MonitorMediaReview.file(2).id]
                }
                if MonitorUIReview.screen == "playback" { playing = MonitorMediaReview.file(0) }
            }
            .fullScreenCover(item: $playing) { file in
                MediaPlayerView(files: (0..<12).map(MonitorMediaReview.file), startingAt: file)
                    .environment(model)
            }
            .overlay {
                if let delivery {
                    MediaDeliveryPopupOverlay(files: delivery) { self.delivery = nil }
                }
            }
            .overlay(alignment: .bottom) {
                if let cacheError {
                    Text("Review cache could not be prepared: \(cacheError)")
                        .font(MonitorTheme.font(11)).foregroundStyle(MonitorTheme.recording)
                        .accessibilityIdentifier("monitor.review.cacheError")
                }
            }
        }

        private func handle(_ action: MonitorMediaAction) {
            switch action {
            case .back: model.liveOperatorPanel = nil
            case .refresh: break
            case .cycleSort: ascending.toggle()
            case .category(let id): category = id
            case .layout(let value): layout = value
            case .thumbnailSize(let value): size = value
            case .open(let id):
                playing = (0..<12).map(MonitorMediaReview.file).first { $0.id == id }
            case .select(let id): if !selected.insert(id).inserted { selected.remove(id) }
            case .favorite(let id): if !favorites.insert(id).inserted { favorites.remove(id) }
            case .selectAll: selected = Set(items.map(\.id))
            case .clearSelection: selected = []
            case .shareSelection:
                delivery = (0..<12).map(MonitorMediaReview.file).filter { selected.contains($0.id) }
            case .favoriteSelection: favorites.formUnion(selected)
            case .deleteSelection:
                hidden.formUnion(selected)
                selected = []
            case .cacheSelection: break
            }
        }
    }
#endif
