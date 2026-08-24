import AVFoundation
import ImageIO
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

    private let sidebarWidth: CGFloat = 172

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

    private var headerItemCountLabel: String {
        if session.mediaFetchInProgress {
            return session.mediaFetchListedCount == 0
                ? "Scanning…"
                : "Listing… \(session.mediaFetchListedCount) found"
        }
        let count = displayedFiles.count
        return "\(count) item\(count == 1 ? "" : "s")"
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(minimum: thumbnailSize.gridMinimum, maximum: thumbnailSize.gridMaximum),
                spacing: 16
            )
        ]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            LiveDesign.background

            GeometryReader { proxy in
                let portrait = proxy.size.height > proxy.size.width

                Group {
                    if portrait {
                        VStack(alignment: .leading, spacing: 8) {
                            categoryStrip
                            mainHeader
                            gridContent
                                .safeAreaInset(edge: .bottom, spacing: 0) {
                                    portraitGridControlsBand
                                }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 16) {
                            sidebar
                                .frame(width: sidebarWidth)
                            VStack(alignment: .leading, spacing: 6) {
                                mainHeader
                                gridContent
                            }
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, OperatorPanelMetrics.mediaTopPadding(safeArea: safeArea))
                .padding(
                    .leading,
                    OperatorPanelMetrics.mediaLeadingPadding(safeArea: safeArea, portrait: portrait)
                )
                .padding(.trailing, OperatorPanelMetrics.mediaTrailingPadding(safeArea: safeArea))
                .padding(.bottom, OperatorPanelMetrics.mediaBottomPadding(safeArea: safeArea))
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

            if !isSelecting {
                CloseButton(action: dismiss, size: OperatorPanelMetrics.closeSize)
                    .padding(.leading, OperatorPanelMetrics.closeLeading)
                    .padding(.top, OperatorPanelMetrics.closeTopPadding(safeArea: safeArea))
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.2), value: thumbnailSize)
        .animation(.easeInOut(duration: 0.2), value: layout)
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            categoryTabs
            Spacer(minLength: 0)
            sidebarGridControls
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var categoryTabs: some View {
        VStack(spacing: 4) {
            ForEach(MediaCategoryTab.allCases) { tab in
                categoryTabButton(tab)
            }
        }
        .padding(4)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous),
            interactive: false)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(MediaCategoryTab.allCases) { tab in
                    categoryTabButton(tab)
                        .fixedSize()
                }
            }
            .padding(4)
        }
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous),
            interactive: false
        )
        .padding(.leading, 45)
    }

    private func categoryTabButton(_ tab: MediaCategoryTab) -> some View {
        let active = category == tab
        return Button {
            category = tab
        } label: {
            HStack(spacing: 8) {
                tab.opcIcon
                    .frame(width: 12, height: 12)
                    .frame(width: 16)
                Text(tab.rawValue)
                    .font(LiveType.ui(size: 12, weight: active ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? LiveDesign.accent : LiveDesign.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                active ? LiveDesign.accentDim : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
        }
        .buttonStyle(.zcTapTarget)
    }

    // MARK: - Header

    @ViewBuilder
    private var mainHeader: some View {
        if isSelecting {
            selectionHeader
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MULTIMEDIA")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .kerning(0.8)
                            .foregroundStyle(LiveDesign.muted)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(category.headerTitle)
                                .font(LiveType.ui(size: 26, weight: .semibold))
                                .foregroundStyle(LiveDesign.text)
                            Text("·")
                                .font(LiveType.ui(size: 18, weight: .medium))
                                .foregroundStyle(LiveDesign.faint)
                            if session.mediaFetchInProgress {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.small).tint(LiveDesign.muted)
                                    Text(headerItemCountLabel)
                                        .font(LiveType.ui(size: 14, weight: .medium))
                                        .foregroundStyle(LiveDesign.muted)
                                }
                            } else {
                                Text(headerItemCountLabel)
                                    .font(LiveType.ui(size: 14, weight: .medium))
                                    .foregroundStyle(LiveDesign.muted)
                            }
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .center, spacing: 8) {
                        if isLive {
                            refreshButton
                        }
                        filterButton
                        sortButton
                    }
                    .fixedSize()
                }

                if let caching = displayedFiles.first(where: {
                    session.mediaDownloadProgress[$0.path] != nil
                }), let progress = session.mediaDownloadProgress[caching.path] {
                    clipCacheHeaderBar(filename: caching.filename, progress: progress)
                }
            }
        }
    }

    private var selectionHeader: some View {
        HStack(spacing: 12) {
            CloseButton(action: exitSelectionMode, size: 37)
            Text("\(selectedIDs.count) selected")
                .font(LiveType.ui(size: 20, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
            Spacer(minLength: 8)
            Button {
                isBatchDeleteConfirmPresented = true
            } label: {
                Label {
                    Text("Delete")
                } icon: {
                    OpcIcon.trash.frame(width: 14, height: 14)
                }
                .font(LiveType.ui(size: 14, weight: .semibold))
                .foregroundStyle(selectedIDs.isEmpty ? LiveDesign.faint : Color.red)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .overlay(Capsule().stroke(LiveDesign.hairline, lineWidth: 1))
            }
            .buttonStyle(.zcTapTarget)
            .disabled(selectedIDs.isEmpty)
            .confirmationDialog(
                "Delete \(selectedIDs.count) item\(selectedIDs.count == 1 ? "" : "s") from the camera?",
                isPresented: $isBatchDeleteConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    let files = selectedFiles
                    Task {
                        await session.deleteMediaFiles(files)
                        exitSelectionMode()
                    }
                }
            }
            Button {
                Task { await share(selectedFiles) }
            } label: {
                Label {
                    Text("Share")
                } icon: {
                    OpcIcon.share.frame(width: 14, height: 14)
                }
                .font(LiveType.ui(size: 14, weight: .semibold))
                .foregroundStyle(selectedIDs.isEmpty ? LiveDesign.faint : LiveDesign.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    selectedIDs.isEmpty ? Color.clear : LiveDesign.accentDim,
                    in: Capsule()
                )
                .overlay(Capsule().stroke(LiveDesign.hairline, lineWidth: 1))
            }
            .buttonStyle(.zcTapTarget)
            .disabled(selectedIDs.isEmpty)
        }
    }

    private var sortButton: some View {
        MediaActionPill(icon: .chevronsUpDown, title: "SORT", isActive: false) {
            sortOrder = sortOrder.next
        }
        .accessibilityLabel("Sort \(sortOrder.menuLabel)")
    }

    private var refreshButton: some View {
        Button {
            session.refreshMedia()
        } label: {
            HStack(spacing: 6) {
                OpcIcon.refreshCw
                    .frame(width: 10, height: 10)
                Text("REFRESH")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(LiveDesign.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .overlay(Capsule().stroke(LiveDesign.hairline, lineWidth: 1))
            .opacity(session.mediaFetchInProgress ? 0.5 : 1)
        }
        .buttonStyle(.zcTapTarget)
        .disabled(session.mediaFetchInProgress)
        .accessibilityLabel("Refresh camera media")
    }

    private var filterButton: some View {
        Button {
            isFilterPopupPresented.toggle()
        } label: {
            HStack(spacing: 6) {
                OpcIcon.listFilter
                    .frame(width: 10, height: 10)
                Text("FILTER")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                if activeFilterCount > 0 {
                    Text("\(activeFilterCount)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
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
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
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
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                .font(.system(size: 9, weight: .bold, design: .monospaced))
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

    private func clipCacheHeaderBar(filename: String, progress: Double) -> some View {
        HStack(spacing: 10) {
            ProgressView(value: progress)
                .tint(LiveDesign.accent)
                .frame(maxWidth: 120)
            Text("CACHING \(filename) \(Int(progress * 100))%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(LiveDesign.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(in: Capsule(), interactive: false)
    }

    // MARK: - Grid / list

    @ViewBuilder private var gridContent: some View {
        if displayedFiles.isEmpty {
            if session.mediaFetchInProgress {
                listingState
            } else {
                emptyState
            }
        } else if layout == .list {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(displayedFiles) { file in
                        MediaClipListRow(
                            file: file,
                            cacheGrade: session.cacheGrade(for: file),
                            localURL: session.localURL(for: file),
                            thumbnailURL: session.thumbnailURL(for: file),
                            cacheProgress: session.mediaDownloadProgress[file.path],
                            isFavorite: session.isFavorite(file),
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(file.id),
                            onOpen: { open(file) },
                            onBeginSelection: { beginSelection(with: file) },
                            onToggleSelection: { toggleSelection(file) },
                            onToggleFavorite: { session.toggleFavorite(file) }
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await session.refreshMedia() }
        } else {
            ScrollView {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 4) {
                    ForEach(displayedFiles) { file in
                        MediaClipCell(
                            file: file,
                            cacheGrade: session.cacheGrade(for: file),
                            localURL: session.localURL(for: file),
                            thumbnailURL: session.thumbnailURL(for: file),
                            cacheProgress: session.mediaDownloadProgress[file.path],
                            isFavorite: session.isFavorite(file),
                            isSelecting: isSelecting,
                            isSelected: selectedIDs.contains(file.id),
                            onOpen: { open(file) },
                            onBeginSelection: { beginSelection(with: file) },
                            onToggleSelection: { toggleSelection(file) },
                            onToggleFavorite: { session.toggleFavorite(file) }
                        )
                    }
                }
                .padding(.bottom, 24)
            }
            .refreshable { await session.refreshMedia() }
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

    private enum SidebarGridControlMetrics {
        static let buttonSize: CGFloat = 37
        static let buttonSpacing: CGFloat = 4
        static let capsuleHorizontalPadding: CGFloat = 6
        static let capsuleVerticalPadding: CGFloat = 6
        static let toggleIconSize: CGFloat = 14
    }

    private var portraitGridControlsBand: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [LiveDesign.background.opacity(0), LiveDesign.background.opacity(0.94)],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)
            sidebarGridControls
                .padding(.bottom, 4)
        }
        .frame(height: 84)
        .frame(maxWidth: .infinity)
    }

    private var sidebarGridControls: some View {
        HStack(spacing: SidebarGridControlMetrics.buttonSpacing) {
            layoutToggleButton
            ForEach(MediaThumbnailSize.allCases) { size in
                thumbnailSizeButton(size)
            }
        }
        .padding(.horizontal, SidebarGridControlMetrics.capsuleHorizontalPadding)
        .padding(.vertical, SidebarGridControlMetrics.capsuleVerticalPadding)
        .liquidGlass(in: Capsule(), interactive: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Media layout and thumbnail size")
    }

    private var layoutToggleButton: some View {
        Button {
            layout = layout == .grid ? .list : .grid
        } label: {
            layout.toggleIcon
                .frame(
                    width: SidebarGridControlMetrics.toggleIconSize,
                    height: SidebarGridControlMetrics.toggleIconSize
                )
                .foregroundStyle(LiveDesign.muted)
                .frame(
                    width: SidebarGridControlMetrics.buttonSize,
                    height: SidebarGridControlMetrics.buttonSize
                )
                .background(
                    LiveDesign.glassBright,
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(layout.accessibilityLabel)
    }

    private func thumbnailSizeButton(_ size: MediaThumbnailSize) -> some View {
        let active = thumbnailSize == size
        return Button {
            thumbnailSize = size
        } label: {
            OpcIcon.square.view(filled: true)
                .frame(width: size.gridIconSize, height: size.gridIconSize)
                .foregroundStyle(active ? LiveDesign.accent : LiveDesign.muted)
                .frame(
                    width: SidebarGridControlMetrics.buttonSize,
                    height: SidebarGridControlMetrics.buttonSize
                )
                .background(
                    active ? LiveDesign.accentDim : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(size.accessibilityLabel)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

private struct MediaActionPill: View {
    let icon: OpcIcon
    let title: String
    var isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                icon
                    .frame(width: 10, height: 10)
                Text(title)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .lineLimit(1)
            }
            .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? LiveDesign.accentDim : Color.clear, in: Capsule())
            .overlay(Capsule().stroke(LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
    }
}

private struct MediaFilterChip: View {
    let title: String
    var expands = false
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
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

private struct MediaClipFavoriteButton: View {
    let isFavorite: Bool
    var iconSize: CGFloat = 13
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            OpcIcon.star.view(filled: isFavorite)
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(isFavorite ? LiveDesign.accent : LiveDesign.faint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
}

private struct MediaClipListRow: View {
    let file: MediaFile
    let cacheGrade: MediaCacheGrade
    let localURL: URL?
    let thumbnailURL: URL?
    let cacheProgress: Double?
    let isFavorite: Bool
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onOpen: () -> Void
    var onBeginSelection: (() -> Void)?
    var onToggleSelection: (() -> Void)?
    let onToggleFavorite: () -> Void

    @Environment(AppModel.self) private var model
    @State private var thumbnail: UIImage?
    @State private var durationLabel: String?

    private var isPhoto: Bool { file.kind == .photo }

    private var isDownloaded: Bool { cacheGrade == .original }

    private var metadataLine: String {
        let line = MediaClipPresentation.metadataLine(file: file, durationOverride: durationLabel)
        if cacheGrade.isProxyOnly {
            return line.isEmpty
                ? MediaLibraryCopy.proxyTag : "\(line) · \(MediaLibraryCopy.proxyTag)"
        }
        if line.isEmpty {
            return isDownloaded ? "Cached" : "On camera"
        }
        return line
    }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 12) {
                listThumbnail
                    .frame(width: 96, height: 54)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous
                        )
                        .strokeBorder(LiveDesign.hairline, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(file.filename)
                        .font(LiveType.ui(size: 13, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                        .lineLimit(1)
                    Text(metadataLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiveDesign.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if isSelecting {
                    (isSelected ? OpcIcon.circleCheck : OpcIcon.circle)
                        .view(filled: isSelected)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(isSelected ? LiveDesign.accent : Color.white.opacity(0.92))
                }
            }
            .contentShape(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .onTapGesture {
                if isSelecting {
                    onToggleSelection?()
                } else {
                    onOpen()
                }
            }

            if !isSelecting {
                MediaClipFavoriteButton(
                    isFavorite: isFavorite,
                    iconSize: 14,
                    action: onToggleFavorite
                )
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 8)
        .background(
            isSelected ? LiveDesign.accentDim.opacity(0.55) : LiveDesign.surface.opacity(0.45),
            in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                .stroke(
                    isSelected ? LiveDesign.accent.opacity(0.45) : LiveDesign.hairline, lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous))
        .onLongPressGesture(minimumDuration: 0.4) {
            guard !isSelecting else { return }
            onBeginSelection?()
        }
        .task(id: "\(file.id)#list#\(thumbnailURL?.path ?? "")") {
            await loadThumbnail()
            await loadDuration()
        }
        .onDisappear { durationLabel = nil }
    }

    @ViewBuilder private var listThumbnail: some View {
        ZStack {
            LiveDesign.surface
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                (isPhoto ? OpcIcon.image : OpcIcon.film)
                    .frame(width: 20, height: 20)
                    .foregroundStyle(LiveDesign.faint)
            }
            if let cacheProgress {
                ZStack {
                    Color.black.opacity(0.45)
                    Text("\(Int(cacheProgress * 100))%")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(LiveDesign.text)
                }
            } else if cacheGrade == .none {
                ZStack {
                    Color.black.opacity(0.35)
                    (isPhoto ? OpcIcon.image : OpcIcon.circlePlay)
                        .frame(width: 18, height: 18)
                        .foregroundStyle(LiveDesign.text.opacity(0.9))
                }
            } else if cacheGrade.isProxyOnly {
                ZStack {
                    Color.black.opacity(0.28)
                    Text(MediaLibraryCopy.proxyTag)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(LiveDesign.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
            }
        }
    }

    private func loadThumbnail() async {
        let cacheKey = "\(file.id)#list" as NSString
        if let cached = MediaCellThumbnailCache.shared.object(forKey: cacheKey) {
            thumbnail = cached
            return
        }
        func present(_ image: UIImage) {
            MediaCellThumbnailCache.shared.setObject(image, forKey: cacheKey)
            thumbnail = image
        }
        if let thumbnailURL, let data = try? Data(contentsOf: thumbnailURL),
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 480)
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
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 480)
        {
            present(image)
            return
        }
        if let remote = MediaHTTP.pathURL(storage: file.storage, path: file.thumbPath),
            let (data, _) = try? await URLSession.shared.data(from: remote),
            let image = await MediaCellImageLoader.shared.downsampled(data: data, maxPixelSize: 480)
        {
            present(image)
            return
        }
        guard isDownloaded, !isPhoto, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 320, height: 320)
        let time = CMTime(seconds: 0.2, preferredTimescale: 600)
        if let cgImage = try? await generator.image(at: time).image {
            present(UIImage(cgImage: cgImage))
        }
    }

    private func loadDuration() async {
        guard !isPhoto else { return }
        if file.durationSeconds > 0 {
            durationLabel = MediaClipFormatting.durationLabel(seconds: file.durationSeconds)
            return
        }
        guard isDownloaded, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration), duration.isValid, duration.seconds > 0 {
            durationLabel = MediaClipFormatting.durationLabel(seconds: Int(duration.seconds))
        }
    }
}

private struct MediaClipCell: View {
    let file: MediaFile
    let cacheGrade: MediaCacheGrade
    let localURL: URL?
    let thumbnailURL: URL?
    let cacheProgress: Double?
    let isFavorite: Bool
    var isSelecting: Bool = false
    var isSelected: Bool = false
    let onOpen: () -> Void
    var onBeginSelection: (() -> Void)?
    var onToggleSelection: (() -> Void)?
    let onToggleFavorite: () -> Void

    @Environment(AppModel.self) private var model
    @State private var thumbnail: UIImage?
    @State private var durationLabel: String?

    private var isPhoto: Bool { file.kind == .photo }
    private var isDownloaded: Bool { cacheGrade == .original }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .fill(LiveDesign.surface)
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    (isPhoto ? OpcIcon.image : OpcIcon.film)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(LiveDesign.faint)
                }
                overlay
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    .strokeBorder(LiveDesign.hairline, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if cacheGrade.isProxyOnly, cacheProgress == nil, !isSelecting {
                    Text(MediaLibraryCopy.proxyTag)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(LiveDesign.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.58), in: Capsule())
                        .padding(8)
                        .accessibilityLabel(MediaLibraryCopy.proxyHelp)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                let badge = isPhoto ? nil : durationLabel
                if let badge, cacheProgress == nil, !isSelecting {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(LiveDesign.text)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4)
                        )
                        .padding(8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelecting {
                    (isSelected ? OpcIcon.circleCheck : OpcIcon.circle)
                        .view(filled: isSelected)
                        .frame(width: 24, height: 24)
                        .foregroundStyle(isSelected ? LiveDesign.accent : Color.white.opacity(0.92))
                        .padding(8)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 1)
                }
            }
            .contentShape(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .onTapGesture {
                if isSelecting {
                    onToggleSelection?()
                } else {
                    onOpen()
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !isSelecting else { return }
                onBeginSelection?()
            }

            HStack(spacing: 6) {
                Text(file.filename)
                    .font(LiveType.ui(size: 12, weight: .medium))
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                MediaClipFavoriteButton(isFavorite: isFavorite, action: onToggleFavorite)
            }
        }
        .task(id: "\(file.id)#grid#\(thumbnailURL?.path ?? "")") {
            await loadThumbnail()
            await loadDuration()
        }
        .onDisappear { durationLabel = nil }
    }

    @ViewBuilder private var overlay: some View {
        if let cacheProgress {
            ZStack {
                Color.black.opacity(0.45)
                VStack(spacing: 6) {
                    Text("\(Int(cacheProgress * 100))%")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(LiveDesign.text)
                    ProgressView(value: cacheProgress)
                        .tint(LiveDesign.accent)
                        .frame(width: 120)
                }
            }
        } else if cacheGrade == .none {
            ZStack {
                Color.black.opacity(0.35)
                VStack(spacing: 4) {
                    (isPhoto ? OpcIcon.image : OpcIcon.circlePlay)
                        .frame(width: 26, height: 26)
                    Text("On camera")
                        .font(LiveType.ui(size: 10, weight: .semibold))
                }
                .foregroundStyle(LiveDesign.text)
            }
        } else if !isPhoto {
            VStack {
                Spacer()
                HStack {
                    OpcIcon.circlePlay
                        .frame(width: 22, height: 22)
                        .foregroundStyle(LiveDesign.text.opacity(0.9))
                        .padding(8)
                    Spacer()
                }
            }
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
            durationLabel = MediaClipFormatting.durationLabel(seconds: file.durationSeconds)
            return
        }
        guard isDownloaded, let localURL else { return }
        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration), duration.isValid, duration.seconds > 0 {
            durationLabel = MediaClipFormatting.durationLabel(seconds: Int(duration.seconds))
        }
    }
}

/// Home overlay host. Live chrome may present `MediaLibraryView` / `SettingsRootView` directly.
struct AppPanelHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.homePanel {
        case .settings:
            GeometryReader { proxy in
                SettingsRootView(
                    safeArea: OperatorPanelMetrics.standalonePanelSafeArea(
                        from: OperatorPanelMetrics.resolvedDeviceSafeArea(proxy.safeAreaInsets)
                    )
                )
            }
        case .media:
            GeometryReader { proxy in
                MediaLibraryView(
                    safeArea: OperatorPanelMetrics.standalonePanelSafeArea(
                        from: OperatorPanelMetrics.resolvedDeviceSafeArea(proxy.safeAreaInsets)
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
