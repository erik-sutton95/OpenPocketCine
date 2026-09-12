import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

// MARK: - Shared chrome

struct MediaCircleIconButton: View {
    let icon: OpcIcon
    var size: CGFloat = 34

    var body: some View {
        icon
            .frame(width: size * 0.38, height: size * 0.38)
            .foregroundStyle(LiveDesign.text)
            .frame(width: size, height: size)
            .glassCircle(interactive: true)
    }
}

struct MediaShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    var onDismiss: () -> Void = {}

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in
            onDismiss()
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Pinch/pan zoom that stays anchored under the fingers.
struct AnchoredPinchZoom {
    static let maxScale: CGFloat = 4

    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    private var committedScale: CGFloat = 1
    private var committedOffset: CGSize = .zero

    var isZoomed: Bool { scale > 1.001 }

    mutating func pinchChanged(magnification: CGFloat, startAnchor: UnitPoint, size: CGSize) {
        let target = min(Self.maxScale, max(1, committedScale * magnification))
        guard committedScale > 0 else { return }
        let ratio = target / committedScale
        let centroid = CGSize(
            width: (startAnchor.x - 0.5) * size.width,
            height: (startAnchor.y - 0.5) * size.height)
        offset = CGSize(
            width: centroid.width - (centroid.width - committedOffset.width) * ratio,
            height: centroid.height - (centroid.height - committedOffset.height) * ratio)
        scale = target
    }

    mutating func panChanged(translation: CGSize) {
        guard isZoomed else { return }
        offset = CGSize(
            width: committedOffset.width + translation.width,
            height: committedOffset.height + translation.height)
    }

    mutating func endGesture(size: CGSize) {
        if scale < 1.05 {
            reset()
            return
        }
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        offset = CGSize(
            width: min(maxX, max(-maxX, offset.width)),
            height: min(maxY, max(-maxY, offset.height)))
        committedScale = scale
        committedOffset = offset
    }

    mutating func reset() {
        self = AnchoredPinchZoom()
    }
}

enum MediaTimeFormatting {
    static func label(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        return MediaClipFormatting.durationLabel(seconds: Int(seconds.rounded(.down)))
    }
}

// MARK: - Photo viewer

struct MediaPhotoViewer: View {
    let file: MediaFile
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monitorWindowGeometry) private var windowGeometry

    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var zoom = AnchoredPinchZoom()
    @State private var isSharePresented = false
    @State private var isPreparingShare = false
    @State private var isDeleteConfirmPresented = false
    @State private var loadTask: Task<Void, Never>?

    private var session: CameraSession { model.session }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { geo in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(zoom.scale)
                        .offset(zoom.offset)
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                pinchGesture(size: geo.size),
                                panGesture(size: geo.size)))
                }
                .ignoresSafeArea()
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(LiveDesign.accent)
                    Text("Preparing image…")
                        .font(LiveType.ui(size: 14, weight: .medium))
                        .foregroundStyle(LiveDesign.muted)
                }
            }

            VStack {
                HStack(spacing: 10) {
                    Button {
                        dismiss()
                    } label: {
                        MediaCircleIconButton(icon: .x, size: 34)
                    }
                    .buttonStyle(.zcTapTarget)
                    Text(file.filename)
                        .font(LiveType.ui(size: 14, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    deleteButton
                    shareButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 14 + windowGeometry.topControlInset)
                Spacer()
                favoriteButton
                    .padding(.bottom, 18)
            }
        }
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            loadTask = Task { await loadImage() }
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
        .overlay {
            if isSharePresented {
                MediaDeliveryPopupOverlay(files: [file]) {
                    isSharePresented = false
                }
            }
        }
    }

    private var favoriteButton: some View {
        let favorite = session.isFavorite(file)
        return Button {
            session.toggleFavorite(file)
        } label: {
            OpcIcon.star.view(filled: favorite)
                .frame(width: 17, height: 17)
                .foregroundStyle(favorite ? LiveDesign.accent : LiveDesign.text)
                .frame(width: 34, height: 34)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
    }

    private var deleteButton: some View {
        Button {
            isDeleteConfirmPresented = true
        } label: {
            MediaCircleIconButton(icon: .trash, size: 34)
        }
        .buttonStyle(.zcTapTarget)
        .confirmationDialog(
            "Delete this photo from the camera?",
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await session.deleteMediaFiles([file])
                    dismiss()
                }
            }
        }
    }

    private var shareButton: some View {
        Button {
            Task { await share() }
        } label: {
            if isPreparingShare {
                ProgressView()
                    .tint(LiveDesign.accent)
                    .frame(width: 34, height: 34)
            } else {
                MediaCircleIconButton(icon: .share, size: 34)
            }
        }
        .buttonStyle(.zcTapTarget)
        .disabled(isPreparingShare)
        .accessibilityLabel("Share photo")
    }

    private func share() async {
        isSharePresented = true
    }

    private func pinchGesture(size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                zoom.pinchChanged(
                    magnification: value.magnification,
                    startAnchor: value.startAnchor,
                    size: size)
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.2)) { zoom.endGesture(size: size) }
            }
    }

    private func panGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in zoom.panChanged(translation: value.translation) }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.2)) { zoom.endGesture(size: size) }
            }
    }

    private func loadImage() async {
        isLoading = true
        defer { isLoading = false }

        if image == nil, let thumbURL = session.thumbnailURL(for: file),
            let data = try? Data(contentsOf: thumbURL),
            let thumb = UIImage(data: data)
        {
            image = thumb
        }

        if session.isDownloaded(file), let url = session.localURL(for: file),
            let loaded = await MediaCellImageLoader.shared.downsampled(at: url, maxPixelSize: 4096)
        {
            image = loaded
            return
        }

        guard session.canReachCameraMedia else { return }

        if let remote = MediaHTTP.pathURL(storage: file.storage, path: file.path) {
            if let (data, _) = try? await URLSession.shared.data(from: remote),
                let loaded = await MediaCellImageLoader.shared.downsampled(
                    data: data, maxPixelSize: 4096)
            {
                image = loaded
            }
        }
    }
}

// MARK: - Player

struct MediaPlayerView: View {
    let files: [MediaFile]
    @State private var active: MediaFile
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.monitorWindowGeometry) private var windowGeometry

    @State private var player = AVPlayer()
    @State private var isPlaying = true
    @State private var isMuted = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    @State private var wasPlayingBeforeScrub = false
    @State private var lastScrubSeekTime: CFAbsoluteTime = 0
    @State private var isClipReady = false
    @State private var loadError: String?
    @State private var reachedEnd = false
    @State private var isRemoteStream = false
    @State private var timeObserver: Any?
    @State private var endObserver: NSObjectProtocol?
    @State private var playbackFlashIcon: OpcIcon?
    @State private var playbackFlashVisible = false
    @State private var playbackFlashTask: Task<Void, Never>?
    @State private var isDeleteConfirmPresented = false
    @State private var loadTask: Task<Void, Never>?
    @State private var chromeVisible = true
    @State private var assistMode = false
    @State private var isInfoPresented = false
    @State private var isConformPresented = false
    @State private var isLooping = false
    @State private var zoom = AnchoredPinchZoom()
    @State private var zoomContainerSize: CGSize = .zero
    @State private var videoDisplaySize = CGSize(width: 16, height: 9)
    @State private var suppressNextPlaybackTap = false
    @State private var isFrameScrubbing = false
    @State private var frameScrubOriginTime: Double = 0
    @State private var frameScrubVideoWidth: CGFloat = 0
    @State private var frameScrubPending = false
    @State private var toastMessage: String?
    @State private var conformSource = ConformPreview.Source()
    @State private var conformTarget: Double?
    @State private var playerLoadGeneration = 0
    @State private var playbackFeed = PlaybackFeedSession()
    @State private var deliveryPresentation: MediaDeliveryPresentation?
    @State private var playbackAssistToolbarFrame: CGRect = .zero
    @State private var playbackBarFrame: CGRect = .zero
    @State private var playbackAudioLevels = AudioMeterLevels.silent
    @State private var audioMeterController = PlaybackAudioMeterController()

    private let scrubSeekThrottle: CFAbsoluteTime = 0.075
    private let scrubSeekTolerance = CMTime(seconds: 0.1, preferredTimescale: 600)

    private enum FrameScrub {
        static let longPressDuration: Double = 0.35
    }

    private enum PlaybackFlash {
        static let fadeIn: Double = 0.12
        static let hold: Double = 0.55
        static let fadeOut: Double = 0.22
    }

    init(files: [MediaFile], startingAt file: MediaFile) {
        self.files = files
        _active = State(initialValue: file)
    }

    private var session: CameraSession { model.session }

    private var playlist: [MediaFile] {
        files.contains(where: { $0.id == active.id }) ? files : [active]
    }

    private var currentIndex: Int? {
        playlist.firstIndex { $0.id == active.id }
    }

    private var canGoPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private var canGoNext: Bool {
        guard let index = currentIndex else { return false }
        return index < playlist.count - 1
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let container = CGRect(origin: .zero, size: geo.size)
                let videoRect = PlaybackVideoLayout.aspectFitRect(
                    videoSize: videoDisplaySize, in: container)

                ZStack {
                    MediaPlayerLayerView(
                        player: player,
                        session: playbackFeed,
                        effects: model.assist.playbackEffects,
                        transfer: MonitorTransfer(model.assist.monitorColorMode ?? .normal),
                        sampleBus: model.frameSamples
                    )
                    .scaleEffect(
                        x: model.assist.isPlaybackVisible(.mirror) ? -1 : 1,
                        y: 1,
                        anchor: .center
                    )
                    .scaleEffect(zoom.scale)
                    .offset(zoom.offset)
                }
                .frame(width: videoRect.width, height: videoRect.height)
                .clipped()
                .position(x: videoRect.midX, y: videoRect.midY)
                .allowsHitTesting(false)

                FeedAlignedAssists(
                    grid: model.assist.isPlaybackVisible(.grid),
                    crosshair: model.assist.isPlaybackVisible(.crosshair),
                    guides: model.assist.isPlaybackVisible(.guides),
                    guideAspect: model.assist.guideAspect,
                    focusPoint: CGPoint(x: 0.5, y: 0.5),
                    overlay: .focus,
                    sceneFaces: [],
                    showFocusChrome: false,
                    showTapFocusBox: false,
                    feed: videoRect
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .allowsHitTesting(false)

                Color.clear
                    .frame(width: videoRect.width, height: videoRect.height)
                    .position(x: videoRect.midX, y: videoRect.midY)
                    .contentShape(Rectangle())
                    .onAppear {
                        frameScrubVideoWidth = videoRect.width
                        zoomContainerSize = videoRect.size
                    }
                    .onChange(of: videoRect.width) { _, width in
                        frameScrubVideoWidth = width
                        zoomContainerSize = videoRect.size
                    }
                    .gesture(playbackVideoGesture)
                    .simultaneousGesture(playbackFrameTapGesture)
                    .simultaneousGesture(playbackFrameScrubGesture)

                playbackTransportFlashOverlay(in: videoRect)
                playbackFrameScrubOverlay(in: videoRect)

                if playlist.count > 1 {
                    clipNavigationArrows(in: videoRect)
                }

                playbackScopeOverlays(in: geo.size, videoRect: videoRect)
            }
            .ignoresSafeArea()

            if !isClipReady || loadError != nil {
                loadingOverlay
            }

            GeometryReader { geometry in
                let layout = MonitorPlaybackLayout(
                    width: geometry.size.width, height: geometry.size.height,
                    tablet: UIDevice.current.userInterfaceIdiom == .pad)
                let portrait = layout.portrait
                ZStack(alignment: .bottomLeading) {
                    VStack(spacing: 0) {
                        if chromeVisible {
                            topBar(portrait: portrait)
                                .padding(.horizontal, 12)
                                .padding(.top, 10 + windowGeometry.topControlInset)
                                .padding(.bottom, 18)
                                .background(
                                    LinearGradient(
                                        colors: [.black.opacity(0.7), .clear],
                                        startPoint: .top, endPoint: .bottom))
                        }
                        Spacer(minLength: 0)
                        if chromeVisible, let toastMessage { toastView(toastMessage) }
                        if chromeVisible { bottomBar(portrait: portrait) }
                        if !chromeVisible {
                            HStack {
                                Spacer()
                                restoreChromeButton
                            }.padding(12)
                        }
                    }
                    if chromeVisible {
                        playbackAssistPalette(layout: layout)
                            .padding(.leading, 12).padding(.bottom, layout.paletteBottom)
                        if isConformPresented {
                            conformPanel
                                .frame(maxWidth: min(480, geometry.size.width - 24))
                                .padding(.horizontal, 12).padding(.bottom, portrait ? 174 : 116)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    if isInfoPresented {
                        MonitorClipInfoPanel(rows: clipInfoRows) { isInfoPresented = false }
                            .frame(width: layout.inspectorWidth)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: isInfoPresented)
                .animation(.easeInOut(duration: 0.22), value: isConformPresented)
                .animation(.easeInOut(duration: 0.22), value: chromeVisible)
            }
            .zIndex(2)
        }
        .animation(.easeInOut(duration: 0.28), value: active.id)
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear {
            model.assist.gradesClip = true
            appear()
        }
        .onDisappear {
            model.assist.gradesClip = false
            disappear()
        }
        .task(id: active.id) {
            assistMode = false
            await loadActiveClip()
        }
        .onChange(of: isConformPresented) { _, shown in if shown { assistMode = false } }
        .onChange(of: isInfoPresented) { _, shown in if shown { assistMode = false } }
        .onChange(of: deliveryPresentation?.id) { _, shown in if shown != nil { assistMode = false }
        }
        .onChange(of: chromeVisible) { _, shown in if !shown { assistMode = false } }
        .onChange(of: session.mediaDownloadProgress[active.path] ?? -1) { _, _ in
            if session.isDownloaded(active), isRemoteStream, isClipReady {
                Task { await loadActiveClip() }
            }
        }
        .onChange(of: session.isDownloaded(active)) { _, downloaded in
            guard downloaded, isClipReady else { return }
            Task { await adoptPlaybackLUTColor() }
        }
        .overlay {
            if deliveryPresentation != nil {
                MediaDeliveryPopupOverlay(files: [active]) {
                    deliveryPresentation = nil
                    if isPlaying { startPlayback() }
                }
                .zIndex(5)
            }
        }
        .overlay(alignment: .top) {
            if let state = model.delivery.overlayState {
                MediaDeliveryOverlay(state: state) {
                    model.delivery.cancel()
                    if isPlaying { startPlayback() }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .zIndex(50)
            }
        }
        .sheet(item: Bindable(model.delivery).sharePayload) { payload in
            MediaShareSheet(urls: payload.urls) {
                model.delivery.clearSharePresentation()
                if isPlaying { startPlayback() }
            }
        }
        .onChange(of: model.delivery.isActive) { _, active in
            if active {
                player.pause()
            } else if isPlaying {
                startPlayback()
            }
        }
        .onChange(of: model.assist.playbackVisibleTools) { _, _ in
            updatePlaybackEffects()
            syncPlaybackAudioMetering()
        }
        .onChange(of: playbackEffectsSignature) { _, _ in
            updatePlaybackEffects()
        }
        .overlay {
            if let tool = model.assist.configureTool {
                GeometryReader { geo in
                    AssistLongPressOverlay(
                        tool: tool,
                        assist: model.assist,
                        anchor: playbackAssistToolbarFrame,
                        toolbar: playbackBarFrame,
                        viewport: geo.size,
                        onDismiss: { model.assist.configureTool = nil }
                    )
                }
                .ignoresSafeArea()
                .zIndex(6)
            }
        }
    }

    private var playbackEffectsSignature: Int {
        var hasher = Hasher()
        hasher.combine(model.assist.playbackVisibleTools.map(\.rawValue).sorted().joined())
        hasher.combine(model.assist.falseColorScale.rawValue)
        hasher.combine(model.assist.falseColorReference)
        hasher.combine(String(describing: model.assist.peakingColor))
        hasher.combine(String(describing: model.assist.peakingSensitivity))
        hasher.combine(model.assist.zebraHighlight)
        hasher.combine(model.assist.zebraMidtone)
        hasher.combine(model.assist.zebraHighlightIRE)
        hasher.combine(model.assist.zebraMidtoneIRE)
        hasher.combine(model.assist.lutEnabled)
        hasher.combine(model.assist.lutSelection.rawValue)
        hasher.combine(model.assist.splitComparison)
        hasher.combine(model.assist.monitorColorMode?.rawValue)
        return hasher.finalize()
    }

    private func topBar(portrait: Bool) -> some View {
        let arrangement =
            portrait
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return arrangement {
            HStack(alignment: .top, spacing: 10) {
                Button {
                    dismiss()
                } label: {
                    MediaCircleIconButton(icon: .chevronLeft, size: 34)
                }
                .buttonStyle(.zcTapTarget).accessibilityLabel("Back to media")
                VStack(alignment: .leading, spacing: 4) {
                    Text(active.filename).font(MonitorTheme.font(13, weight: .semibold))
                        .foregroundStyle(MonitorTheme.text).lineLimit(1)
                    Text(clipMetadata).font(MonitorTheme.font(9.5)).foregroundStyle(
                        MonitorTheme.muted
                    )
                    .lineLimit(portrait ? 2 : 1)
                    Text(playbackSourceLabel).font(MonitorTheme.font(8, weight: .bold)).tracking(
                        0.5
                    )
                    .foregroundStyle(MonitorTheme.secondary).lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 4)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 5))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 3) {
                Button {
                    session.toggleFavorite(active)
                } label: {
                    MonitorPlaybackChip {
                        OpcIcon.star.view(filled: session.isFavorite(active))
                            .foregroundStyle(
                                session.isFavorite(active)
                                    ? LiveDesign.amber : MonitorTheme.secondary)
                    }
                }
                .buttonStyle(.zcTapTarget).accessibilityLabel("Favorite clip")
                Button {
                    isInfoPresented.toggle()
                } label: {
                    MonitorPlaybackChip(active: isInfoPresented) { OpcIcon.info }
                }
                .buttonStyle(.zcTapTarget).accessibilityLabel("Clip information")
                shareTransportButton
                deleteButton
            }
            .frame(maxWidth: portrait ? .infinity : nil, alignment: .trailing)
            .fixedSize(horizontal: !portrait, vertical: true)
        }
    }

    private var clipMetadata: String {
        [
            active.resolution, active.fps.map { "\($0)p" }, session.shotColor(for: active)?.label,
            MediaClipFormatting.byteLabel(active.sizeBytes),
        ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var playbackSourceLabel: String {
        #if targetEnvironment(simulator)
            if MonitorMediaReview.clipURL(for: active) != nil { return "ORIGINAL · ON PHONE" }
        #endif
        let grade = session.cacheGrade(for: active)
        if grade == .original { return "ORIGINAL · ON PHONE" }
        let source = grade.isProxyOnly ? "PROXY" : "ON CAMERA"
        if let progress = session.mediaDownloadProgress[active.path] {
            return "\(source) · CACHING ORIGINAL \(Int(min(1, max(0, progress)) * 100))%"
        }
        return source
    }

    private var clipInfoRows: [MonitorMetadataRow] {
        var rows = [MonitorMetadataRow("File", active.filename)]
        if let captured = active.captureDate {
            rows.append(
                MonitorMetadataRow(
                    "Captured", captured.formatted(date: .abbreviated, time: .standard)))
        }
        if let resolution = active.resolution {
            rows.append(MonitorMetadataRow("Format", resolution))
        }
        if let fps = active.fps { rows.append(MonitorMetadataRow("Frame rate", "\(fps) fps")) }
        if let color = session.shotColor(for: active) {
            rows.append(MonitorMetadataRow("Colour", color.label))
        }
        rows.append(MonitorMetadataRow("Duration", conformedLabel(duration)))
        rows.append(MonitorMetadataRow("Size", MediaClipFormatting.byteLabel(active.sizeBytes)))
        rows.append(MonitorMetadataRow("Availability", playbackSourceLabel))
        return rows
    }

    private func bottomBar(portrait: Bool) -> some View {
        playbackTransportBar(portrait: portrait)
            .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? 860 : 630)
            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 5)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.78), location: 0),
                        .init(color: .black.opacity(0.4), location: 0.62),
                        .init(color: .clear, location: 1),
                    ], startPoint: .bottom, endPoint: .top)
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.onAppear { playbackBarFrame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, frame in
                            playbackBarFrame = frame
                        }
                }
            }
    }

    private var bufferedDuration: Double {
        player.currentItem?.loadedTimeRanges.map { value in
            let range = value.timeRangeValue
            return CMTimeGetSeconds(CMTimeRangeGetEnd(range))
        }.filter(\.isFinite).max() ?? 0
    }

    private func playbackTransportBar(portrait: Bool) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(conformedLabel(isScrubbing ? scrubTime : currentTime))
                    .font(MonitorTheme.font(11, weight: .bold)).foregroundStyle(MonitorTheme.text)
                Spacer()
                Text(conformedLabel(duration)).font(MonitorTheme.font(11)).foregroundStyle(
                    MonitorTheme.secondary)
            }
            .monospacedDigit().shadow(color: .black, radius: 4)
            MonitorPlaybackScrubber(
                progress: isScrubbing ? scrubTime : currentTime,
                duration: duration,
                bufferedProgress: bufferedDuration,
                onScrubbingChanged: { scrubbing in
                    if scrubbing {
                        if !isScrubbing {
                            wasPlayingBeforeScrub = isPlaying
                            scrubTime = currentTime
                            player.pause()
                        }
                        isScrubbing = true
                    } else {
                        isScrubbing = false
                    }
                },
                onProgressChange: { time in
                    scrubTime = time
                    clearEndStateIfSeeking(to: time)
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - lastScrubSeekTime >= scrubSeekThrottle {
                        lastScrubSeekTime = now
                        player.seek(
                            to: CMTime(seconds: time, preferredTimescale: 600),
                            toleranceBefore: scrubSeekTolerance,
                            toleranceAfter: scrubSeekTolerance)
                    }
                },
                onSeek: { time in
                    player.seek(
                        to: CMTime(seconds: time, preferredTimescale: 600),
                        toleranceBefore: .zero, toleranceAfter: .zero)
                    currentTime = time
                    scrubTime = time
                    isScrubbing = false
                    clearEndStateIfSeeking(to: time)
                    if wasPlayingBeforeScrub {
                        startPlayback()
                    }
                }
            )
            let arrangement =
                portrait
                ? AnyLayout(VStackLayout(spacing: 2))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
            arrangement {
                if !portrait { Color.clear.frame(maxWidth: .infinity, maxHeight: 1) }
                HStack(spacing: 8) {
                    transportButton(.skipBack) { seek(by: -15) }
                        .accessibilityLabel("Back 15 seconds")
                    transportButton(reachedEnd ? .rotateCw : isPlaying ? .pause : .play, size: 26) {
                        if reachedEnd { restartPlayback() } else { togglePlay() }
                    }
                    .accessibilityLabel(reachedEnd ? "Restart clip" : isPlaying ? "Pause" : "Play")
                    transportButton(.skipForward) { seek(by: 15) }
                        .accessibilityLabel("Forward 15 seconds")
                }
                HStack(spacing: 3) {
                    conformButton
                    actionToggle(.volumeX, .volume2, on: isMuted) { toggleMute() }
                        .accessibilityLabel(isMuted ? "Unmute" : "Mute")
                    Button {
                        isLooping.toggle()
                    } label: {
                        MonitorPlaybackChip(active: isLooping) { OpcIcon.repeat }
                    }
                    .buttonStyle(.zcTapTarget).accessibilityLabel("Loop playback")
                    .accessibilityValue(isLooping ? "On" : "Off")
                    cleanViewButton
                }
                .frame(maxWidth: .infinity, alignment: portrait ? .center : .trailing)
            }
        }
    }

    private var deleteButton: some View {
        Button {
            isDeleteConfirmPresented = true
        } label: {
            MonitorPlaybackChip(destructive: true) { OpcIcon.trash }
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Delete clip from camera")
        .confirmationDialog(
            "Delete this clip from the camera?", isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { Task { await deleteActive() } }
        }
    }

    @ViewBuilder
    private func clipNavigationArrows(in videoRect: CGRect) -> some View {
        if canGoPrevious {
            Button {
                goToAdjacent(offset: -1)
            } label: {
                OpcIcon.chevronLeft
                    .frame(width: 13, height: 13)
                    .foregroundStyle(LiveDesign.accent)
                    .frame(width: 32, height: 32)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.zcTapTarget)
            .position(x: videoRect.minX + 22, y: videoRect.midY)
            .accessibilityLabel("Previous clip")
        }
        if canGoNext {
            Button {
                goToAdjacent(offset: 1)
            } label: {
                OpcIcon.chevronRight
                    .frame(width: 13, height: 13)
                    .foregroundStyle(LiveDesign.accent)
                    .frame(width: 32, height: 32)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.zcTapTarget)
            .position(x: videoRect.maxX - 22, y: videoRect.midY)
            .accessibilityLabel("Next clip")
        }
    }

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72)
            VStack(spacing: 12) {
                if loadError == nil {
                    if let progress = session.mediaDownloadProgress[active.path],
                        progress > 0, progress < 1
                    {
                        ProgressView(value: progress)
                            .tint(LiveDesign.accent)
                            .frame(width: 120)
                    } else {
                        ProgressView().tint(LiveDesign.accent)
                    }
                }
                Text(loadError ?? loadingCopy)
                    .font(LiveType.ui(size: 14, weight: .medium))
                    .foregroundStyle(LiveDesign.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius), interactive: false)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var loadingCopy: String {
        if session.mediaDownloadProgress[active.path] != nil {
            return "Buffering from camera…"
        }
        return "Preparing playback…"
    }

    private func playbackAssistPalette(layout: MonitorPlaybackLayout) -> some View {
        let portrait = layout.portrait
        let tools = LiveAssistTool.toolbarCases + [.audioMeters]
        return MonitorAssistPalette(
            tools: tools.map {
                MonitorToolItem(
                    id: $0.rawValue, title: $0.rawValue,
                    enabled: model.assist.isPlaybackVisible($0), hasOptions: $0.hasConfiguration)
            },
            layout: MonitorAssistPaletteLayout(
                portrait: portrait, tablet: UIDevice.current.userInterfaceIdiom == .pad,
                expanded: assistMode, toolCount: tools.count,
                maximumWidth: layout.paletteWidth, maximumHeight: layout.paletteHeight),
            usageSeed: MonitorToolUsage.fieldMonitorSeed, expanded: $assistMode,
            onToggle: { id in
                if let tool = LiveAssistTool(rawValue: id) { model.assist.togglePlayback(tool) }
            },
            onOptions: { id in
                if let tool = LiveAssistTool(rawValue: id) { presentPlaybackAssistOptions(tool) }
            },
            icon: { id in
                if let tool = LiveAssistTool(rawValue: id) {
                    AssistToolIcon(
                        tool: tool, size: UIDevice.current.userInterfaceIdiom == .pad ? 24 : 20)
                }
            }
        )
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { playbackAssistToolbarFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        playbackAssistToolbarFrame = frame
                    }
            }
        }
    }

    private func presentPlaybackAssistOptions(_ tool: LiveAssistTool) {
        model.assist.longPressAnchor = playbackAssistToolbarFrame
        model.assist.configureTool = tool
        if tool == .lut { model.assist.showLUTPicker = false }
    }

    @ViewBuilder
    private func playbackScopeOverlays(in size: CGSize, videoRect: CGRect) -> some View {
        let canvas = CGRect(origin: .zero, size: size)
        let clearance = EdgeInsets(top: 56, leading: 56, bottom: 110, trailing: 56)
        if model.assist.isPlaybackVisible(.waveform) {
            WaveformOverlay(canvas: canvas, feed: videoRect, chromeClearance: clearance)
        }
        if model.assist.isPlaybackVisible(.parade) {
            ParadeOverlay(canvas: canvas, feed: videoRect, chromeClearance: clearance)
        }
        if model.assist.isPlaybackVisible(.vectorscope) {
            VectorscopeOverlay(canvas: canvas, feed: videoRect, chromeClearance: clearance)
        }
        if model.assist.isPlaybackVisible(.histogram) {
            HistogramOverlay(canvas: canvas, feed: videoRect, chromeClearance: clearance)
        }
        if model.assist.isPlaybackVisible(.trafficLights) {
            TrafficLightsOverlay(bounds: canvas, feed: videoRect, chromeClearance: clearance)
        }
        if model.assist.isPlaybackVisible(.ndMeter) {
            NDMeterOverlay(bounds: canvas, feed: videoRect, chromeClearance: clearance)
        }
        if model.assist.isPlaybackVisible(.audioMeters) {
            AudioMetersPanelMini(levels: playbackAudioLevels, sensitivity: nil)
                .position(
                    x: min(videoRect.maxX - 22, canvas.maxX - 28),
                    y: min(videoRect.maxY - 96, canvas.maxY - 120))
        }
        if model.assist.isPlaybackVisible(.falseColor), model.assist.falseColorReference {
            FalseColorAssist.referenceDisplay(
                scale: model.assist.falseColorScale,
                colorMode: model.assist.monitorColorMode ?? .normal
            )
            .position(x: videoRect.minX + 140, y: min(videoRect.maxY - 36, canvas.maxY - 80))
        }
    }

    private func attachPlaybackAssists(to item: AVPlayerItem) {
        audioMeterController.attach(to: item)
        updatePlaybackEffects()
    }

    private func updatePlaybackEffects() {
        let fx = model.assist.playbackEffects
        playbackFeed.setEffects(
            fx,
            transfer: MonitorTransfer(fx.colorMode),
            sampleBus: model.frameSamples)
        syncPlaybackAudioMetering()
    }

    private func syncPlaybackAudioMetering() {
        if model.assist.isPlaybackVisible(.audioMeters) {
            audioMeterController.startPolling { [self] levels in
                playbackAudioLevels = levels
            }
        } else {
            audioMeterController.stopPolling()
            playbackAudioLevels = .silent
        }
    }

    private var conformSpeed: Double {
        guard let target = conformTarget, let rate = conformSource.captureRate else { return 1 }
        return ConformPreview.speed(captureRate: rate, targetRate: target)
    }

    private func conformedLabel(_ seconds: Double) -> String {
        MediaTimeFormatting.label(
            ConformPreview.conformedDuration(sourceSeconds: seconds, speed: conformSpeed))
    }

    private var conformButton: some View {
        let availability = ConformPreview.availability(for: conformSource)
        return Button {
            isConformPresented.toggle()
        } label: {
            MonitorPlaybackChip(active: conformTarget != nil || isConformPresented) {
                OpcIcon.timer
            }
        }
        .buttonStyle(.zcTapTarget).disabled(!availability.isAvailable)
        .accessibilityLabel("Conform preview")
        .onChange(of: conformTarget) { _, _ in
            applyMute()
            if isPlaying { startPlayback() }
        }
    }

    private var conformPanel: some View {
        let availability = ConformPreview.availability(for: conformSource)
        let rate = conformSource.captureRate ?? 0
        let labels =
            ["Real time"]
            + availability.targets.map {
                ConformPreview.targetLabel(captureRate: rate, targetRate: $0)
            }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONFORM PREVIEW").font(MonitorTheme.font(9, weight: .bold)).tracking(1.8)
                    Text(conformTarget == nil ? "As recorded" : "Conformed for slow motion")
                        .font(MonitorTheme.font(9)).foregroundStyle(MonitorTheme.muted)
                }
                Spacer()
                Button {
                    isConformPresented = false
                } label: {
                    OpcIcon.x.frame(width: 12, height: 12).frame(width: 44, height: 44)
                }.buttonStyle(.zcTapTarget).accessibilityLabel("Close conform preview")
            }
            MonitorValueDrum(
                options: labels,
                selection: Binding(
                    get: {
                        conformTarget.map {
                            ConformPreview.targetLabel(captureRate: rate, targetRate: $0)
                        } ?? "Real time"
                    },
                    set: { label in
                        guard let index = labels.firstIndex(of: label) else { return }
                        conformTarget = index == 0 ? nil : availability.targets[index - 1]
                    }), isInteractive: availability.isAvailable, haptics: model.hapticsEnabled)
            if conformTarget != nil {
                Text(ConformPreview.audioLabel).font(MonitorTheme.font(9)).foregroundStyle(
                    MonitorTheme.muted)
            }
        }
        .padding(14).monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .expanded)
    }

    private var cleanViewButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { chromeVisible = false }
        } label: {
            MonitorPlaybackChip { OpcIcon.maximize }
        }
        .buttonStyle(.zcTapTarget).accessibilityLabel("Hide playback controls")
        .accessibilityHint("A restore control stays in the corner")
    }

    private var restoreChromeButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) { chromeVisible = true }
        } label: {
            MonitorPlaybackChip { OpcIcon.minimize }
        }
        .buttonStyle(.zcTapTarget).accessibilityLabel("Show playback controls")
    }

    private var shareTransportButton: some View {
        Button {
            if isPlaying {
                player.pause()
                isPlaying = false
            }
            deliveryPresentation = MediaDeliveryPresentation(files: [active])
        } label: {
            MonitorPlaybackChip(title: "SHARE", active: true) { OpcIcon.share }
        }
        .buttonStyle(.zcTapTarget).accessibilityLabel("Share clip")
    }

    private func toastView(_ message: String) -> some View {
        Text(message)
            .font(LiveType.ui(size: 13, weight: .medium))
            .foregroundStyle(LiveDesign.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .liquidGlass(in: Capsule(), interactive: true)
            .padding(.bottom, 8)
            .transition(.opacity)
    }

    private func transportButton(
        _ icon: OpcIcon, size: CGFloat = 18, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon.frame(width: size, height: size).foregroundStyle(MonitorTheme.text)
                .frame(
                    width: MonitorPlaybackLayout.transportSize,
                    height: MonitorPlaybackLayout.transportSize
                ).contentShape(Circle())
                .shadow(color: .black.opacity(0.9), radius: 5)
        }
        .buttonStyle(.zcTapTarget)
    }

    private func actionToggle(
        _ onIcon: OpcIcon, _ offIcon: OpcIcon, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            MonitorPlaybackChip(active: on) { on ? onIcon : offIcon }
        }
        .buttonStyle(.zcTapTarget)
    }

    private var playbackVideoGesture: some Gesture {
        SimultaneousGesture(
            SimultaneousGesture(playbackMagnificationGesture, playbackPanGesture),
            chromeSwipeGesture
        )
    }

    private var playbackFrameTapGesture: some Gesture {
        TapGesture().onEnded { handleFrameTap() }
    }

    private var playbackFrameScrubGesture: some Gesture {
        LongPressGesture(minimumDuration: FrameScrub.longPressDuration)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard isClipReady else { return }
                guard !zoom.isZoomed else { return }
                switch value {
                case .first(true):
                    frameScrubPending = true
                case .second(true, let drag?):
                    if frameScrubPending {
                        beginFrameScrub()
                        frameScrubPending = false
                    }
                    guard isFrameScrubbing else { return }
                    updateFrameScrub(horizontalDelta: drag.translation.width)
                default:
                    break
                }
            }
            .onEnded { _ in
                frameScrubPending = false
                if isFrameScrubbing { endFrameScrub() }
            }
    }

    private var chromeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28)
            .onEnded { value in
                guard !isFrameScrubbing else { return }
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width) + 8, abs(dy) > 44 else { return }
                if dy < 0 {
                    withAnimation(.spring(duration: 0.32)) { chromeVisible = true }
                } else {
                    withAnimation(.spring(duration: 0.32)) { chromeVisible = false }
                }
            }
    }

    private var playbackMagnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if abs(value.magnification - 1) > 0.02 {
                    suppressNextPlaybackTap = true
                    frameScrubPending = false
                }
                zoom.pinchChanged(
                    magnification: value.magnification,
                    startAnchor: value.startAnchor,
                    size: zoomContainerSize)
            }
            .onEnded { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    zoom.endGesture(size: zoomContainerSize)
                }
            }
    }

    private var playbackPanGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard zoom.isZoomed else { return }
                if hypot(value.translation.width, value.translation.height) > 8 {
                    suppressNextPlaybackTap = true
                    frameScrubPending = false
                }
                zoom.panChanged(translation: value.translation)
            }
            .onEnded { _ in
                guard zoom.isZoomed else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    zoom.endGesture(size: zoomContainerSize)
                }
            }
    }

    @ViewBuilder
    private func playbackTransportFlashOverlay(in videoRect: CGRect) -> some View {
        if let playbackFlashIcon {
            playbackFlashIcon
                .frame(width: 48, height: 48)
                .foregroundStyle(LiveDesign.text)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 3)
                .overlay {
                    playbackFlashIcon
                        .frame(width: 48, height: 48)
                        .foregroundStyle(LiveDesign.accent.opacity(0.28))
                        .blendMode(.overlay)
                }
                .opacity(playbackFlashVisible ? 1 : 0)
                .scaleEffect(playbackFlashVisible ? 1 : 0.86)
                .animation(.easeOut(duration: PlaybackFlash.fadeIn), value: playbackFlashVisible)
                .position(x: videoRect.midX, y: videoRect.midY)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func playbackFrameScrubOverlay(in videoRect: CGRect) -> some View {
        if isFrameScrubbing, duration > 0 {
            let fraction = min(1, max(0, scrubTime / duration))
            let barWidth = max(0, videoRect.width - 32)
            VStack(spacing: 10) {
                Text(MediaTimeFormatting.label(scrubTime))
                    .font(MonitorTheme.font(16, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(LiveDesign.text)
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
                Text("/ \(MediaTimeFormatting.label(duration))")
                    .font(MonitorTheme.font(11, weight: .medium)).monospacedDigit()
                    .foregroundStyle(LiveDesign.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlass(in: Capsule(), interactive: false)
            .position(x: videoRect.midX, y: videoRect.midY)
            .allowsHitTesting(false)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LiveDesign.hairline)
                    .frame(width: barWidth, height: 3)
                Capsule()
                    .fill(LiveDesign.accent)
                    .frame(width: max(3, barWidth * fraction), height: 3)
            }
            .position(x: videoRect.midX, y: videoRect.maxY - 18)
            .allowsHitTesting(false)
        }
    }

    private func appear() {
        MediaPlaybackAudioSession.activateForPlayback()
        syncPlaybackAudioMetering()
    }

    /// Auto LUT needs ColorMode. `colr`/`nclx` is Rec.709 even for D-Log2;
    /// QuickTime Keys `com.dji.camera.ColorGammaSxS` on the **original** is the
    /// shot profile. LRF/XRF sidecars are Rec.709 even for log — do not read them.
    /// Live `@2` is the body's current SET — used only when the original has no Keys.
    private func adoptPlaybackLUTColor(playedPath: String? = nil, playedURL: URL? = nil) async {
        let clip: ColorMode?
        if let original = session.localURL(for: active),
            let mode = ClipColorProfileIO.shotColor(at: original, path: active.path)
        {
            session.rememberShotColor(mode, for: active)
            clip = mode
        } else if let playedPath, let playedURL,
            let mode = ClipColorProfileIO.shotColor(at: playedURL, path: playedPath)
        {
            session.rememberShotColor(mode, for: active)
            clip = mode
        } else if let cached = session.shotColor(for: active) {
            clip = cached
        } else {
            clip = await session.fetchOriginalShotColor(for: active)
        }
        let color = PlaybackLUTColor.resolve(
            clip: clip,
            live: session.status.colorMode,
            last: OperatorPrefs.lastMonitorColorMode ?? model.assist.monitorColorMode)
        guard let color else { return }
        model.assist.adoptPlaybackColor(
            color,
            family: session.bodyFamily != .other
                ? session.bodyFamily : model.assist.monitorFamily,
            cameraName: session.connectedCamera?.model.name)
        if let clip {
            ControlLiveLog.line("media: clip color \(clip.label)")
        } else {
            ControlLiveLog.line(
                "media: clip color fallback \(color.label) (proxy Keys ignored)")
        }
    }

    private func disappear() {
        loadTask?.cancel()
        playbackFlashTask?.cancel()
        audioMeterController.stopPolling()
        audioMeterController.detach(from: player.currentItem)
        playbackFeed.shutdown()
        model.frameSamples.playbackBundle = nil
        model.assist.configureTool = nil
        teardownPlayer()
        MediaPlaybackAudioSession.deactivateAfterPlayback()
    }

    private func loadActiveClip() async {
        isClipReady = false
        loadError = nil
        reachedEnd = false
        currentTime = 0
        duration = Double(active.durationSeconds)
        applyListedClipGeometry()
        teardownPlayerObservers()
        player.pause()

        #if targetEnvironment(simulator)
            if let url = MonitorMediaReview.clipURL(for: active) {
                let source = MediaPlaybackSource(
                    url: url, mimeType: "video/mp4", isRemote: false, path: active.path)
                _ = await playSource(source, timeout: .seconds(8))
                return
            }
        #endif

        // Never hand AVPlayer a `/v2?path=` URL. That path has no extension, the
        // camera often parks `moov` at the end, and SoftAP has no internet —
        // the item stays `.unknown` and this overlay never clears. Pull the
        // sidecar (same GET as thumbs) and play the local file.
        // Prefer the 720p sidecar even when the 4K original is already cached
        // for export (`FeedPresentPolicy.preferProxyForMonitorGrade`). LUT /
        // false colour grade that proxy, not the raw clip.
        if let proxy = session.localProxySource(for: active) {
            isRemoteStream = false
            if await playSource(proxy, timeout: .seconds(8)) { return }
        }

        if session.canReachCameraMedia {
            for path in MediaHTTP.proxyPaths(active) {
                if Task.isCancelled { return }
                isRemoteStream = true
                do {
                    let local = try await session.cachePlaybackFile(file: active, path: path)
                    let source = MediaPlaybackSource(
                        url: local,
                        mimeType: MediaHTTP.playbackMIMEType(for: path),
                        isRemote: false,
                        path: path)
                    isRemoteStream = false
                    if await playSource(source, timeout: .seconds(8)) { return }
                } catch {
                    ControlLiveLog.line(
                        "media: play download failed \(path) \(error.localizedDescription)")
                }
            }
        }

        if let cached = session.localPlaybackSource(for: active) {
            isRemoteStream = false
            if await playSource(cached, timeout: .seconds(8)) { return }
        }

        guard session.canReachCameraMedia else {
            loadError = MediaOperatorCopy.clipNotCached
            return
        }

        let original = MediaHTTP.deliveryPath(active)
        isRemoteStream = true
        do {
            let local = try await session.cachePlaybackFile(file: active, path: original)
            let source = MediaPlaybackSource(
                url: local,
                mimeType: MediaHTTP.playbackMIMEType(for: original),
                isRemote: false,
                path: original)
            isRemoteStream = false
            if await playSource(source, timeout: .seconds(8)) { return }
        } catch {
            ControlLiveLog.line(
                "media: play download failed \(original) \(error.localizedDescription)")
        }

        isRemoteStream = false
        if !Task.isCancelled {
            loadError = MediaOperatorCopy.clipOpenFailed
        }
    }

    private func playSource(_ source: MediaPlaybackSource, timeout: Duration) async -> Bool {
        teardownPlayerObservers()
        let item = attachItem(url: source.url, mimeType: source.mimeType, isRemote: source.isRemote)
        let ready = await waitUntilReady(item, timeout: timeout)
        if ready {
            let seconds = item.duration.seconds
            if seconds.isFinite, seconds > 0 { duration = seconds }
            isClipReady = true
            loadError = nil
            if isPlaying { startPlayback() }
            playbackFeed.noteItemReady()
            await adoptPlaybackLUTColor(playedPath: source.path, playedURL: source.url)
            if OperatorPrefs.cacheFullResolution, !session.isDownloaded(active) {
                Task { await session.download(file: active) }
            }
            Task { await probeConformAndSize(from: item.asset) }
            ControlLiveLog.line("media: play ready \(source.path) remote=\(source.isRemote)")
            return true
        }
        let err = item.error?.localizedDescription ?? "status=\(item.status.rawValue)"
        ControlLiveLog.line("media: play skip \(source.path) \(err)")
        teardownPlayerObservers()
        player.replaceCurrentItem(with: nil)
        return false
    }

    private func attachItem(url: URL, mimeType: String, isRemote: Bool) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetOutOfBandMIMETypeKey": mimeType,
                AVURLAssetAllowsCellularAccessKey: false,
                "AVURLAssetHTTPHeaderFieldsKey": ["Accept": "*/*"],
            ])
        let item = AVPlayerItem(asset: asset)
        playbackFeed.prepare(item)
        player.replaceCurrentItem(with: item)
        applyMute()
        player.automaticallyWaitsToMinimizeStalling = isRemote
        attachPlaybackAssists(to: item)
        observePlaybackEnd(for: item)
        attachTimeObserver()
        return item
    }

    private func waitUntilReady(_ item: AVPlayerItem, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !Task.isCancelled, clock.now < deadline {
            if item.status == .readyToPlay { return true }
            if item.status == .failed { return false }
            try? await Task.sleep(for: .milliseconds(80))
        }
        return item.status == .readyToPlay
    }

    private func uniquePaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    private func attachTimeObserver() {
        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { time in
            Task { @MainActor in
                guard !isScrubbing else { return }
                currentTime = time.seconds
                if let dur = player.currentItem?.duration.seconds, dur.isFinite, dur > 0 {
                    duration = dur
                }
            }
        }
    }

    private func observePlaybackEnd(for item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            Task { @MainActor in
                if isLooping {
                    restartPlayback()
                } else {
                    reachedEnd = true
                    isPlaying = false
                    currentTime = duration
                }
            }
        }
    }

    private func teardownPlayerObservers() {
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func teardownPlayer() {
        teardownPlayerObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func handleFrameTap() {
        guard isClipReady else { return }
        guard !isFrameScrubbing else { return }
        if suppressNextPlaybackTap {
            suppressNextPlaybackTap = false
            return
        }
        switch PlaybackFrameTap.action(chromeVisible: chromeVisible, reachedEnd: reachedEnd) {
        case .restartPlayback:
            restartPlayback()
            flash(.play)
        case .toggleTransport:
            let willPlay = !isPlaying
            togglePlay()
            flash(willPlay ? .play : .pause)
        case .ignore:
            break
        }
    }

    private func flash(_ icon: OpcIcon) {
        playbackFlashTask?.cancel()
        playbackFlashIcon = icon
        playbackFlashVisible = false
        playbackFlashTask = Task {
            await MainActor.run { playbackFlashVisible = true }
            try? await Task.sleep(for: .seconds(PlaybackFlash.hold))
            guard !Task.isCancelled else { return }
            await MainActor.run { playbackFlashVisible = false }
            try? await Task.sleep(for: .seconds(PlaybackFlash.fadeOut))
            guard !Task.isCancelled else { return }
            await MainActor.run { playbackFlashIcon = nil }
        }
    }

    private func togglePlay() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            startPlayback()
        }
    }

    private func startPlayback() {
        reachedEnd = false
        player.rate = Float(conformSpeed)
        isPlaying = true
        playbackFeed.noteItemReady()
    }

    private func applyMute() {
        player.isMuted = isMuted || conformTarget != nil
    }

    private func restartPlayback() {
        player.seek(to: .zero)
        currentTime = 0
        startPlayback()
    }

    private func seek(by delta: Double) {
        let target = min(max(0, currentTime + delta), duration)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        clearEndStateIfSeeking(to: target)
    }

    private func clearEndStateIfSeeking(to time: Double) {
        if reachedEnd, time + 0.05 < duration {
            reachedEnd = false
        }
    }

    private func toggleMute() {
        isMuted.toggle()
        applyMute()
    }

    private func goToAdjacent(offset: Int) {
        guard let index = currentIndex else { return }
        let next = index + offset
        guard playlist.indices.contains(next) else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        player.pause()
        isPlaying = true
        reachedEnd = false
        isClipReady = false
        zoom.reset()
        withAnimation(.easeInOut(duration: 0.28)) {
            active = playlist[next]
        }
    }

    private func beginFrameScrub() {
        wasPlayingBeforeScrub = isPlaying
        frameScrubOriginTime = currentTime
        scrubTime = currentTime
        isScrubbing = true
        isFrameScrubbing = true
        player.pause()
        isPlaying = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateFrameScrub(horizontalDelta: CGFloat) {
        guard duration > 0, frameScrubVideoWidth > 0 else { return }
        let deltaTime = Double(horizontalDelta / frameScrubVideoWidth) * duration
        let time = max(0, min(duration, frameScrubOriginTime + deltaTime))
        scrubTime = time
        clearEndStateIfSeeking(to: time)
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastScrubSeekTime >= scrubSeekThrottle {
            lastScrubSeekTime = now
            player.seek(
                to: CMTime(seconds: time, preferredTimescale: 600),
                toleranceBefore: scrubSeekTolerance,
                toleranceAfter: scrubSeekTolerance)
        }
    }

    private func endFrameScrub() {
        guard isFrameScrubbing else { return }
        player.seek(
            to: CMTime(seconds: scrubTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero)
        currentTime = scrubTime
        isScrubbing = false
        isFrameScrubbing = false
        clearEndStateIfSeeking(to: scrubTime)
        if wasPlayingBeforeScrub { startPlayback() }
        suppressNextPlaybackTap = true
    }

    private func applyListedClipGeometry() {
        videoDisplaySize =
            PlaybackVideoLayout.size(fromResolution: active.resolution)
            ?? CGSize(width: 16, height: 9)
        conformTarget = nil
        if let fps = active.fps, fps > 0 {
            conformSource = ConformPreview.probe(listedRate: Double(fps))
        } else {
            conformSource = ConformPreview.Source()
        }
    }

    private func probeConformAndSize(from asset: AVAsset) async {
        playerLoadGeneration += 1
        let generation = playerLoadGeneration
        if let urlAsset = asset as? AVURLAsset {
            if let size = await loadVideoDisplaySize(from: urlAsset) {
                guard generation == playerLoadGeneration else { return }
                videoDisplaySize = size
            }
            let probed = await loadConformSource(from: urlAsset)
            guard generation == playerLoadGeneration else { return }
            conformSource = probed
            if let target = conformTarget, let rate = probed.captureRate,
                target >= rate * ConformPreview.conformFloor
            {
                conformTarget = nil
            }
        }
    }

    private func loadVideoDisplaySize(from asset: AVURLAsset) async -> CGSize? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return nil
        }
        guard let size = try? await track.load(.naturalSize) else { return nil }
        let transform = (try? await track.load(.preferredTransform)) ?? .identity
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        let fitted = CGSize(width: abs(rect.width), height: abs(rect.height))
        guard fitted.width > 1, fitted.height > 1 else { return nil }
        return fitted
    }

    private func loadConformSource(from asset: AVURLAsset) async -> ConformPreview.Source {
        let listed = active.fps.map { Double($0) }
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return ConformPreview.probe(listedRate: listed)
        }
        let nominal = try? await track.load(.nominalFrameRate)
        let minimum = try? await track.load(.minFrameDuration)
        return ConformPreview.probe(
            nominalFrameRate: nominal.map { Double($0) },
            minFrameDurationSeconds: (minimum?.isValid == true) ? minimum?.seconds : nil,
            listedRate: listed)
    }

    private func deleteActive() async {
        let dying = active
        await session.deleteMediaFiles([dying])
        if canGoNext {
            goToAdjacent(offset: 1)
        } else if canGoPrevious {
            goToAdjacent(offset: -1)
        } else {
            dismiss()
        }
    }
}
