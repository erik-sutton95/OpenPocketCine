import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
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

enum MediaCategoryTab: String, CaseIterable, Identifiable {
    case all = "All"
    case videos = "Videos"
    case photos = "Photos"
    case favorites = "Favorites"

    var id: String { rawValue }

    var opcIcon: OpcIcon {
        switch self {
        case .all: .layoutGrid
        case .videos: .film
        case .photos: .image
        case .favorites: .star
        }
    }

    var headerTitle: String {
        switch self {
        case .all: "All clips"
        case .videos: "Videos"
        case .photos: "Photos"
        case .favorites: "Favorites"
        }
    }

    var libraryTab: MediaLibraryTab {
        switch self {
        case .all: .all
        case .videos: .videos
        case .photos: .photos
        case .favorites: .favorites
        }
    }
}

enum MediaBrowserLayout: String, CaseIterable {
    case grid
    case list

    var toggleIcon: OpcIcon {
        switch self {
        case .grid: .layoutList
        case .list: .layoutGrid
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .grid: "List view"
        case .list: "Grid view"
        }
    }
}

enum MediaThumbnailSize: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }

    var gridMinimum: CGFloat {
        switch self {
        case .small: 148
        case .medium: 210
        case .large: 280
        }
    }

    var gridMaximum: CGFloat {
        switch self {
        case .small: 200
        case .medium: 300
        case .large: 380
        }
    }

    var gridIconSize: CGFloat {
        switch self {
        case .small: 9
        case .medium: 12
        case .large: 15
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .small: "Small thumbnails"
        case .medium: "Medium thumbnails"
        case .large: "Large thumbnails"
        }
    }
}

enum MediaSortOrder: String, CaseIterable {
    case newest, oldest, name, rating

    var menuLabel: String {
        switch self {
        case .newest: "Newest"
        case .oldest: "Oldest"
        case .name: "Name"
        case .rating: "Rating"
        }
    }

    var next: MediaSortOrder {
        switch self {
        case .newest: .oldest
        case .oldest: .name
        case .name: .rating
        case .rating: .newest
        }
    }

    var librarySort: MediaLibrarySort {
        switch self {
        case .newest: .newest
        case .oldest: .oldest
        case .name: .name
        case .rating: .rating
        }
    }
}

enum MediaClipPresentation {
    static func resolutionLabel(_ resolution: String?) -> String? {
        guard let resolution, !resolution.isEmpty else { return nil }
        let width = resolution.split(separator: "x").first.flatMap { Int($0) }
        if let width {
            if width >= 3840 { return "4K" }
            if width >= 2560 { return "2.7K" }
            if width >= 1920 { return "1080p" }
            if width >= 1280 { return "720p" }
        }
        return resolution
    }

    static func dateLabel(_ dateKey: String) -> String {
        guard dateKey.count == 8 else { return dateKey }
        let year = dateKey.prefix(4)
        let month = dateKey.dropFirst(4).prefix(2)
        let day = dateKey.suffix(2)
        return "\(year)-\(month)-\(day)"
    }

    static func metadataLine(file: MediaFile, durationOverride: String? = nil) -> String {
        var parts: [String] = []
        if let resolution = resolutionLabel(file.resolution) {
            parts.append(resolution)
        }
        let bytes = MediaClipFormatting.byteLabel(file.sizeBytes)
        if !bytes.isEmpty { parts.append(bytes) }
        if file.kind == .video {
            parts.append(
                durationOverride
                    ?? MediaClipFormatting.durationLabel(seconds: file.durationSeconds))
        }
        return parts.joined(separator: " · ")
    }
}

/// Operator-facing media-browser copy. Never name a sister app.
enum MediaLibraryCopy {
    static let filterEmpty = "Nothing in this tab matches the filters."
    static let emptyAll =
        "Nothing on this camera yet. Record a clip, then pull to refresh."
    static let emptyFavorites = "Nothing favorited yet. Star a clip to find it here."
    static let emptyVideos =
        "No videos on this camera yet. Record a clip, then pull to refresh."
    static let emptyPhotos =
        "No photos on this camera yet. Capture a still, then pull to refresh."
    static let disconnected = "Connect the camera to list clips on the body."
    static let disconnectedEmptyCache =
        "Nothing cached on this phone. Connect the camera to list clips on the body."
    static let proxyTag = "Proxy"
    static let proxyHelp = "720p preview. Connect the camera to share the original."
}

struct MediaLibraryView: View {
    /// Host-processed insets (OpenZCine `MediaBrowserView.safeArea`). Do not read
    /// GeometryReader safeAreaInsets here — this surface `ignoresSafeArea()`.
    var safeArea: EdgeInsets = EdgeInsets()
    var onClose: (() -> Void)? = nil

    @Environment(AppModel.self) private var model
    @State private var category: MediaCategoryTab = .all
    @State private var layout: MediaBrowserLayout = .grid
    @State private var thumbnailSize: MediaThumbnailSize = .medium
    @State private var sortOrder: MediaSortOrder = .newest
    @State private var isFilterPopupPresented = false
    @State private var formatFilters: Set<String> = []
    @State private var resolutionFilters: Set<String> = []
    @State private var dateKeyFilter: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isBatchDeleteConfirmPresented = false
    @State private var playingFile: MediaFile?
    @State private var viewingPhoto: MediaFile?
    @State private var deliveryFiles: [MediaFile]?
    @State private var resolvedDurations: [String: String] = [:]

    private var session: CameraSession { model.session }

    private var isLive: Bool {
        if case .live = session.phase { return true }
        return false
    }

    private var localFavorites: Set<String> {
        Set(session.mediaFiles.filter { session.isFavorite($0) }.map(\.path))
    }

    private var libraryFiles: [MediaFile] {
        if isLive { return session.mediaFiles }
        return MediaLibraryQuery.cachedOnly(
            session.mediaFiles,
            cachedPaths: Set(session.mediaFiles.filter(session.isAvailableOffline).map(\.path)))
    }

    private var displayedFiles: [MediaFile] {
        var files = MediaLibraryQuery.filtered(
            libraryFiles,
            tab: category.libraryTab,
            formats: formatFilters,
            resolutions: resolutionFilters,
            dateKey: dateKeyFilter,
            localFavorites: localFavorites
        )
        if category == .favorites {
            files = files.filter { session.isFavorite($0) }
        }
        if sortOrder == .rating {
            return files.sorted { lhs, rhs in
                let left = session.isFavorite(lhs)
                let right = session.isFavorite(rhs)
                if left != right { return left && !right }
                return (lhs.filenameTimestamp ?? "") > (rhs.filenameTimestamp ?? "")
            }
        }
        return MediaLibraryQuery.sorted(files, by: sortOrder.librarySort)
    }

    private var displayedVideos: [MediaFile] {
        displayedFiles.filter { $0.kind == .video }
    }

    private var filterSourceFiles: [MediaFile] {
        var files = MediaLibraryQuery.filtered(
            libraryFiles,
            tab: category.libraryTab,
            localFavorites: localFavorites
        )
        if category == .favorites {
            files = files.filter { session.isFavorite($0) }
        }
        return files
    }

    private var formatOptions: [String] {
        Array(Set(filterSourceFiles.map(\.fileExtension)).filter { !$0.isEmpty }).sorted()
    }

    private var resolutionOptions: [String] {
        Array(Set(filterSourceFiles.compactMap(\.resolution)).filter { !$0.isEmpty }).sorted()
    }

    private var dateOptions: [String] {
        Array(Set(filterSourceFiles.map(\.dateKey)).filter { !$0.isEmpty }).sorted().reversed()
    }

    private var activeFilterCount: Int {
        formatFilters.count + resolutionFilters.count + (dateKeyFilter == nil ? 0 : 1)
    }

    private var hasActiveFilters: Bool { activeFilterCount > 0 }

    private var selectedFiles: [MediaFile] {
        displayedFiles.filter { selectedIDs.contains($0.id) }
    }

    private func mediaPermissions(_ file: MediaFile) -> MonitorMediaPermissions {
        var permissions: MonitorMediaPermissions = [.favorite]
        if isLive || session.isDownloaded(file) { permissions.insert(.share) }
        if isLive && !session.isDownloaded(file) { permissions.insert(.cache) }
        if isLive && file.isDeletable { permissions.insert(.delete) }
        return permissions
    }

    private var catalogItems: [MonitorMediaItem] {
        displayedFiles.map { file in
            let grade = session.cacheGrade(for: file)
            let color = session.shotColor(for: file)?.label ?? ""
            let metadata = MediaClipPresentation.metadataLine(
                file: file, durationOverride: resolvedDurations[file.id])
            return MonitorMediaItem(
                id: file.id, filename: file.filename,
                metadata: color.isEmpty ? metadata : "\(color) · \(metadata)",
                format: file.resolution ?? "", color: color,
                duration: file.kind == .photo
                    ? ""
                    : resolvedDurations[file.id]
                        ?? (file.durationSeconds > 0
                            ? MediaClipFormatting.durationLabel(seconds: file.durationSeconds)
                            : ""),
                date: MediaClipPresentation.dateLabel(file.dateKey),
                availability: grade == .original ? .original : grade.isProxyOnly ? .proxy : .camera,
                progress: session.mediaDownloadProgress[file.path],
                favorite: session.isFavorite(file), photo: file.kind == .photo,
                permissions: mediaPermissions(file)
            )
        }
    }

    private var catalogCategories: [MonitorMediaCategory] {
        MediaCategoryTab.allCases.map { tab in
            MonitorMediaCategory(
                id: tab.rawValue, title: tab.rawValue,
                count: MediaLibraryQuery.filtered(
                    libraryFiles, tab: tab.libraryTab,
                    localFavorites: localFavorites
                ).count)
        }
    }

    var body: some View {
        let filesByID = Dictionary(uniqueKeysWithValues: displayedFiles.map { ($0.id, $0) })
        ZStack(alignment: .topLeading) {
            LiveDesign.background

            MonitorMediaCatalog(
                brand: session.connectedCamera?.name ?? "OpenPocketCine", safeArea: safeArea,
                items: catalogItems, categories: catalogCategories, category: category.rawValue,
                layout: layout == .grid ? .grid : .list,
                thumbnailSize: MonitorThumbnailSize(rawValue: thumbnailSize.rawValue) ?? .medium,
                sortTitle: sortOrder.menuLabel,
                status: isLive ? "Camera + local cache" : "Available on this phone",
                selectedIDs: selectedIDs, selecting: isSelecting,
                refreshing: session.mediaFetchInProgress, canRefresh: isLive,
                tablet: UIDevice.current.userInterfaceIdiom == .pad,
                action: handleCatalogAction
            ) { item in
                if let file = filesByID[item.id] {
                    MediaCatalogThumbnail(
                        file: file, cacheGrade: session.cacheGrade(for: file),
                        localURL: session.localURL(for: file),
                        thumbnailURL: session.thumbnailURL(for: file),
                        onDuration: { resolvedDurations[file.id] = $0 }
                    )
                }
            } empty: {
                if session.mediaFetchInProgress { listingState } else { emptyState }
            } filters: {
                filterButton
            }

            if isFilterPopupPresented {
                filterPopup
            }

            if let state = model.delivery.overlayState {
                VStack {
                    MediaDeliveryOverlay(state: state) {
                        model.delivery.cancel()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    Spacer()
                }
                .allowsHitTesting(true)
            }

        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: thumbnailSize)
        .animation(.easeInOut(duration: 0.2), value: layout)
        .confirmationDialog(
            "Delete \(selectedIDs.count) items from the camera?",
            isPresented: $isBatchDeleteConfirmPresented, titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let files = selectedFiles
                Task {
                    await session.deleteMediaFiles(files)
                    exitSelectionMode()
                }
            }
        }
        .onAppear { session.beginMediaBrowse() }
        .onDisappear { session.endMediaBrowse() }
        .fullScreenCover(item: $playingFile) { file in
            MediaPlayerView(files: displayedVideos, startingAt: file)
                .environment(model)
        }
        .fullScreenCover(item: $viewingPhoto) { file in
            MediaPhotoViewer(file: file)
                .environment(model)
        }
        .overlay {
            if let deliveryFiles {
                MediaDeliveryPopupOverlay(files: deliveryFiles) {
                    self.deliveryFiles = nil
                }
            }
        }
        .sheet(item: Bindable(model.delivery).sharePayload) { payload in
            MediaShareSheet(urls: payload.urls) {
                model.delivery.clearSharePresentation()
            }
        }
    }

    private func dismiss() {
        session.endMediaBrowse()
        if let onClose {
            onClose()
        } else {
            model.homePanel = nil
        }
    }

    // MARK: - Sidebar / strip

    private func handleCatalogAction(_ action: MonitorMediaAction) {
        switch action {
        case .back: dismiss()
        case .refresh: session.refreshMedia()
        case .cycleSort: sortOrder = sortOrder.next
        case .category(let id):
            if let tab = MediaCategoryTab(rawValue: id) { category = tab }
        case .layout(let value): layout = value == .grid ? .grid : .list
        case .thumbnailSize(let size):
            if let value = MediaThumbnailSize(rawValue: size.rawValue) { thumbnailSize = value }
        case .open(let id):
            if let file = displayedFiles.first(where: { $0.id == id }) { open(file) }
        case .select(let id):
            if let file = displayedFiles.first(where: { $0.id == id }) {
                if isSelecting { toggleSelection(file) } else { beginSelection(with: file) }
            }
        case .favorite(let id):
            if let file = displayedFiles.first(where: { $0.id == id }) {
                session.toggleFavorite(file)
            }
        case .selectAll: selectedIDs = Set(displayedFiles.map(\.id))
        case .clearSelection: exitSelectionMode()
        case .shareSelection:
            let files = selectedFiles
            if !files.isEmpty, files.allSatisfy({ mediaPermissions($0).contains(.share) }) {
                Task { await share(files) }
            }
        case .cacheSelection:
            let files = selectedFiles.filter { mediaPermissions($0).contains(.cache) }
            Task { for file in files { await session.download(file: file) } }
        case .favoriteSelection:
            for file in selectedFiles where !session.isFavorite(file) {
                session.toggleFavorite(file)
            }
        case .deleteSelection:
            if !selectedFiles.isEmpty,
                selectedFiles.allSatisfy({ mediaPermissions($0).contains(.delete) })
            {
                isBatchDeleteConfirmPresented = true
            }
        }
    }

    private var filterButton: some View {
        Button {
            isFilterPopupPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                OpcIcon.listFilter
                    .frame(width: 10, height: 10)
                Text("FILTER")
                    .font(MonitorTheme.font(9.5, weight: .bold)).monospacedDigit()
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(MonitorTheme.font(9, weight: .bold)).monospacedDigit()
                        .foregroundStyle(LiveDesign.background)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(LiveDesign.accent, in: Capsule())
                }
            }
            .foregroundStyle(activeFilterCount > 0 ? LiveDesign.accent : LiveDesign.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                (isFilterPopupPresented || activeFilterCount > 0)
                    ? LiveDesign.accentDim : Color.clear,
                in: Capsule()
            )
            .overlay(Capsule().stroke(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
    }

    private var filterPopup: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { isFilterPopupPresented = false }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("FILTER")
                        .font(MonitorTheme.font(10, weight: .bold)).monospacedDigit()
                        .kerning(0.8)
                        .foregroundStyle(LiveDesign.muted)
                    Spacer()
                    CloseButton(action: { isFilterPopupPresented = false }, size: 26)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !formatOptions.isEmpty {
                            filterSection(title: "FORMAT") {
                                filterChipGrid(formatOptions, active: formatFilters) { format in
                                    toggle(format, in: &formatFilters)
                                }
                            }
                        }

                        if !resolutionOptions.isEmpty {
                            filterSection(title: "RESOLUTION") {
                                filterChipGrid(resolutionOptions, active: resolutionFilters) {
                                    resolution in
                                    toggle(resolution, in: &resolutionFilters)
                                }
                            }
                        }

                        if !dateOptions.isEmpty {
                            filterSection(title: "DATE") {
                                let columns = [GridItem(.adaptive(minimum: 150), spacing: 5)]
                                LazyVGrid(columns: columns, spacing: 5) {
                                    ForEach(dateOptions, id: \.self) { key in
                                        MediaFilterChip(
                                            title: MediaClipPresentation.dateLabel(key),
                                            expands: true,
                                            isActive: dateKeyFilter == key
                                        ) {
                                            dateKeyFilter = dateKeyFilter == key ? nil : key
                                        }
                                    }
                                }
                            }
                        }

                        if formatOptions.isEmpty, resolutionOptions.isEmpty, dateOptions.isEmpty {
                            Text("Nothing in this tab to filter by.")
                                .font(LiveType.ui(size: 11))
                                .foregroundStyle(LiveDesign.faint)
                                .padding(.vertical, 2)
                        }

                        if hasActiveFilters {
                            Button("Clear all filters") {
                                formatFilters.removeAll()
                                resolutionFilters.removeAll()
                                dateKeyFilter = nil
                            }
                            .font(MonitorTheme.font(11, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(LiveDesign.accent)
                            .padding(.top, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .frame(width: 320, alignment: .leading)
            .frame(maxHeight: 420, alignment: .top)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .padding(.top, 88)
            .padding(.trailing, 20)
        }
    }

    private func filterSection<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(MonitorTheme.font(9, weight: .bold)).monospacedDigit()
                .foregroundStyle(LiveDesign.muted)
            content()
        }
    }

    private func filterChipGrid(
        _ titles: [String],
        active: Set<String>,
        toggle: @escaping (String) -> Void
    ) -> some View {
        let columns = [GridItem(.adaptive(minimum: 150), spacing: 5)]
        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(titles, id: \.self) { title in
                MediaFilterChip(
                    title: title,
                    expands: true,
                    isActive: active.contains(title),
                    action: { toggle(title) }
                )
            }
        }
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if model.session.mediaFetchInProgress {
                ProgressView()
                    .tint(LiveDesign.accent)
            } else {
                OpcIcon.film
                    .frame(width: 40, height: 40)
                    .foregroundStyle(LiveDesign.faint)
            }
            Text(model.session.mediaFetchInProgress ? "Listing clips" : "No clips yet")
                .font(LiveType.ui(size: 15, weight: .medium))
                .foregroundStyle(LiveDesign.muted)
            Text(model.session.mediaNote ?? emptySubtitle)
                .font(LiveType.ui(size: 12))
                .foregroundStyle(LiveDesign.faint)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var listingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(LiveDesign.muted)
            Text("Listing clips on camera…")
                .font(LiveType.ui(size: 15, weight: .medium))
                .foregroundStyle(LiveDesign.muted)
            Text(
                session.mediaFetchListedCount == 0
                    ? "Querying card storage…"
                    : "\(session.mediaFetchListedCount) clip\(session.mediaFetchListedCount == 1 ? "" : "s") found so far"
            )
            .font(LiveType.ui(size: 12))
            .foregroundStyle(LiveDesign.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptySubtitle: String {
        if !isLive {
            return session.mediaFiles.isEmpty
                ? MediaLibraryCopy.disconnected
                : MediaLibraryCopy.disconnectedEmptyCache
        }
        if hasActiveFilters {
            return MediaLibraryCopy.filterEmpty
        }
        switch category {
        case .favorites: return MediaLibraryCopy.emptyFavorites
        case .videos: return MediaLibraryCopy.emptyVideos
        case .photos: return MediaLibraryCopy.emptyPhotos
        case .all: return MediaLibraryCopy.emptyAll
        }
    }

    private func open(_ file: MediaFile) {
        if isSelecting {
            toggleSelection(file)
            return
        }
        if !isLive, !session.isAvailableOffline(file) { return }
        if file.kind == .photo {
            viewingPhoto = file
        } else {
            playingFile = file
        }
    }

    private func beginSelection(with file: MediaFile) {
        guard !isSelecting else { return }
        isSelecting = true
        selectedIDs = [file.id]
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func toggleSelection(_ file: MediaFile) {
        if selectedIDs.contains(file.id) {
            selectedIDs.remove(file.id)
        } else {
            selectedIDs.insert(file.id)
        }
    }

    private func exitSelectionMode() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func share(_ files: [MediaFile]) async {
        guard !files.isEmpty else { return }
        deliveryFiles = files
    }

    // MARK: - Layout chrome

}

private struct MediaFilterChip: View {
    let title: String
    var expands = false
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(MonitorTheme.font(10, weight: .semibold)).monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.muted)
                .frame(maxWidth: expands ? .infinity : nil)
                .frame(minHeight: 30)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isActive ? LiveDesign.accentDim : LiveDesign.glassBright,
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        isActive ? LiveDesign.accent.opacity(0.45) : LiveDesign.hairline,
                        lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
    }
}

/// The Osmo adapter owns thumbnail acquisition and metadata fallbacks. All card,
/// grid/list and selection rendering lives in MonitorMediaCatalog.
private struct MediaCatalogThumbnail: View {
    let file: MediaFile
    let cacheGrade: MediaCacheGrade
    let localURL: URL?
    let thumbnailURL: URL?
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
                (isPhoto ? OpcIcon.image : OpcIcon.film)
                    .frame(width: 28, height: 28).foregroundStyle(MonitorTheme.faint)
            }
        }
        .clipped()
        .task(id: "\(file.id)#\(thumbnailURL?.path ?? "")") {
            await loadThumbnail()
            await loadDuration()
        }
    }

    private func loadThumbnail() async {
        let cacheKey = "\(file.id)#grid" as NSString
        if let cached = MediaCellThumbnailCache.shared.object(forKey: cacheKey) {
            thumbnail = cached
            return
        }
        func present(_ image: UIImage) {
            MediaCellThumbnailCache.shared.setObject(image, forKey: cacheKey)
            thumbnail = image
        }
        if let thumbnailURL, let data = try? Data(contentsOf: thumbnailURL),
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 640)
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
        await model.session.ensureThumbnail(for: file)
        if let cachedURL = model.session.thumbnailURL(for: file),
            let data = try? Data(contentsOf: cachedURL),
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 640)
        {
            present(image)
            return
        }
        if let remote = MediaHTTP.pathURL(storage: file.storage, path: file.thumbPath),
            let (data, _) = try? await URLSession.shared.data(from: remote),
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 640)
        {
            present(image)
            return
        }
        guard isDownloaded, !isPhoto, let localURL else { return }
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
        guard !isPhoto else { return }
        if file.durationSeconds > 0 {
            onDuration(MediaClipFormatting.durationLabel(seconds: file.durationSeconds))
            return
        }
        guard isDownloaded, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration), duration.isValid, duration.seconds > 0 {
            onDuration(MediaClipFormatting.durationLabel(seconds: Int(duration.seconds)))
        }
    }
}

/// Home overlay host. Live chrome may present `MediaLibraryView` / `SettingsRootView` directly.
struct AppPanelHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry

    var body: some View {
        switch model.homePanel {
        case .settings:
            GeometryReader { proxy in
                SettingsRootView(
                    safeArea: OperatorPanelMetrics.standalonePanelSafeArea(
                        from: OperatorPanelMetrics.resolvedDeviceSafeArea(
                            proxy.safeAreaInsets, window: windowGeometry.safeArea)
                    )
                )
            }
        case .media:
            GeometryReader { proxy in
                MediaLibraryView(
                    safeArea: OperatorPanelMetrics.standalonePanelSafeArea(
                        from: OperatorPanelMetrics.resolvedDeviceSafeArea(
                            proxy.safeAreaInsets, window: windowGeometry.safeArea)
                    )
                )
            }
        case .privacy: LegalDocumentView(kind: .privacy)
        case .terms: LegalDocumentView(kind: .terms)
        case .licenses: LegalDocumentView(kind: .licenses)
        case .notice: LegalDocumentView(kind: .notice)
        case nil: EmptyView()
        }
    }
}

typealias MediaLibraryStubView = MediaLibraryView
