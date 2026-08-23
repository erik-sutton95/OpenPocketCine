import AVFoundation
import ImageIO
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
                .padding(.top, 14)
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
    @State private var isSharePresented = false
    @State private var isPreparingShare = false
    @State private var isDeleteConfirmPresented = false
    @State private var loadTask: Task<Void, Never>?
    @State private var chromeVisible = true
    @State private var assistMode = false
    @State private var zoom = AnchoredPinchZoom()
    @State private var zoomContainerSize: CGSize = .zero
    @State private var videoDisplaySize = CGSize(width: 16, height: 9)
    @State private var suppressNextPlaybackTap = false
    @State private var isFrameScrubbing = false
    @State private var frameScrubOriginTime: Double = 0
    @State private var frameScrubVideoWidth: CGFloat = 0
    @State private var frameScrubPending = false
    @State private var clipSlideEdge: Edge = .trailing
    @State private var toastMessage: String?
    @State private var conformSource = ConformPreview.Source()
    @State private var conformTarget: Double?
    @State private var playerLoadGeneration = 0
    @State private var playbackEffectsBox = MediaLUT.PlaybackEffectsBox()
    @State private var deliveryPresentation: MediaDeliveryPresentation?
    @State private var scopePollTask: Task<Void, Never>?
    @State private var playbackAssistToolbarFrame: CGRect = .zero
    @State private var playbackBarFrame: CGRect = .zero
    @State private var playbackAudioLevels = AudioMeterLevels.silent
    @State private var audioMeterController = PlaybackAudioMeterController()

    private let scrubSeekThrottle: CFAbsoluteTime = 0.075
    private let scrubSeekTolerance = CMTime(seconds: 0.1, preferredTimescale: 600)

    enum PlaybackChrome {
        static let barPaddingH: CGFloat = 10
        static let barPaddingV: CGFloat = 9
        static let transportRowSpacing: CGFloat = 5
        static let scrubberRowSpacing: CGFloat = 5
        static let transportButtonSize = CGSize(width: 38, height: 36)
        static let actionButtonSize = CGSize(width: 32, height: 36)
        static let transportIconSize: CGFloat = 18
        static let primaryTransportIconSize: CGFloat = 22
        static let actionIconSize: CGFloat = 16
        static let narrowestScreenWidth: CGFloat = 375
        static let chromeHorizontalPadding: CGFloat = 16

        static func transportRowWidth(
            transportCount: Int = 3, actionCount: Int = 5, minimumSpacer: CGFloat = 6
        ) -> CGFloat {
            let buttons =
                transportButtonSize.width * CGFloat(transportCount)
                + actionButtonSize.width * CGFloat(actionCount)
            let gaps = transportRowSpacing * CGFloat(transportCount + actionCount - 1)
            return buttons + gaps + barPaddingH * 2 + minimumSpacer
        }
    }

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
                    MediaPlayerLayerView(player: player)
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
                .id(active.id)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: clipSlideEdge),
                        removal: .move(edge: clipSlideEdge == .trailing ? .leading : .trailing)
                    )
                )

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

            VStack {
                if chromeVisible {
                    topBar
                }
                Spacer()
                if chromeVisible, let toastMessage { toastView(toastMessage) }
                if chromeVisible { bottomBar }
                if !chromeVisible {
                    HStack {
                        Spacer()
                        restoreChromeButton
                    }
                }
            }
            .padding(.horizontal, PlaybackChrome.chromeHorizontalPadding)
            .padding(.vertical, 14)
            .allowsHitTesting(true)
            .zIndex(2)
            .animation(.spring(duration: 0.32), value: chromeVisible)
        }
        .animation(.easeInOut(duration: 0.28), value: active.id)
        .statusBarHidden()
        .preferredColorScheme(.dark)
        .onAppear { appear() }
        .onDisappear { disappear() }
        .task(id: active.id) { await loadActiveClip() }
        .onChange(of: session.mediaDownloadProgress[active.path] ?? -1) { _, _ in
            if session.isDownloaded(active), isRemoteStream, isClipReady {
                Task { await loadActiveClip() }
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let url = session.localURL(for: active), session.isDownloaded(active) {
                MediaShareSheet(urls: [url]) { isSharePresented = false }
            }
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
        return hasher.finalize()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                MediaCircleIconButton(icon: .chevronLeft, size: 34)
            }
            .buttonStyle(.zcTapTarget)
            Text(active.filename)
                .font(LiveType.ui(size: 14, weight: .semibold))
                .foregroundStyle(LiveDesign.text)
                .lineLimit(1)
            Spacer()
            Button {
                session.toggleFavorite(active)
            } label: {
                OpcIcon.star.view(filled: session.isFavorite(active))
                    .frame(width: 17, height: 17)
                    .foregroundStyle(
                        session.isFavorite(active) ? LiveDesign.accent : LiveDesign.text
                    )
                    .frame(width: 34, height: 34)
                    .liquidGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.zcTapTarget)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if assistMode {
                assistModeBar
            } else {
                playbackTransportBar
            }
        }
        .padding(.horizontal, PlaybackChrome.barPaddingH)
        .padding(.vertical, PlaybackChrome.barPaddingV)
        .liquidGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous),
            interactive: false
        )
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { playbackBarFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, frame in
                        playbackBarFrame = frame
                    }
            }
        }
        .animation(.spring(duration: 0.32), value: assistMode)
    }

    private var playbackTransportBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: PlaybackChrome.scrubberRowSpacing) {
                Text(conformedLabel(isScrubbing ? scrubTime : currentTime))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiveDesign.muted)
                    .frame(width: 40, alignment: .leading)
                MediaPlaybackScrubber(
                    progress: isScrubbing ? scrubTime : currentTime,
                    duration: duration,
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
                Text(conformedLabel(duration))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(LiveDesign.muted)
                    .frame(width: 40, alignment: .trailing)
            }

            HStack(spacing: PlaybackChrome.transportRowSpacing) {
                transportButton(.skipBack) { seek(by: -15) }
                if reachedEnd {
                    transportButton(
                        .rotateCw,
                        size: PlaybackChrome.primaryTransportIconSize
                    ) {
                        restartPlayback()
                    }
                } else {
                    transportButton(
                        isPlaying ? .pause : .play,
                        size: PlaybackChrome.primaryTransportIconSize
                    ) {
                        togglePlay()
                    }
                }
                transportButton(.skipForward) { seek(by: 15) }

                Spacer(minLength: 6)

                actionToggle(
                    .volumeX, .volume2, on: isMuted
                ) {
                    toggleMute()
                }
                conformButton
                cleanViewButton
                viewAssistButton
                shareTransportButton
            }
        }
    }

    private var downloadOrShareButton: some View {
        let downloaded = session.isDownloaded(active)
        let progress = session.mediaDownloadProgress[active.path]
        return Button {
            if downloaded {
                Task { await share() }
            } else {
                Task { await session.download(file: active) }
            }
        } label: {
            ZStack {
                if let progress, !downloaded {
                    ProgressView(value: progress)
                        .tint(LiveDesign.accent)
                        .frame(width: 22, height: 22)
                } else if isPreparingShare {
                    ProgressView()
                        .tint(LiveDesign.accent)
                        .frame(width: 22, height: 22)
                } else {
                    (downloaded ? OpcIcon.share : OpcIcon.download)
                        .frame(
                            width: PlaybackChrome.actionIconSize,
                            height: PlaybackChrome.actionIconSize
                        )
                        .foregroundStyle(LiveDesign.text)
                }
            }
            .frame(
                width: PlaybackChrome.actionButtonSize.width,
                height: PlaybackChrome.actionButtonSize.height
            )
            .contentShape(
                RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
            )
            .liquidGlass(
                in: RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel(downloaded ? "Share clip" : "Download clip")
    }

    private var deleteButton: some View {
        Button {
            isDeleteConfirmPresented = true
        } label: {
            OpcIcon.trash
                .frame(
                    width: PlaybackChrome.actionIconSize,
                    height: PlaybackChrome.actionIconSize
                )
                .foregroundStyle(LiveDesign.text)
                .frame(
                    width: PlaybackChrome.actionButtonSize.width,
                    height: PlaybackChrome.actionButtonSize.height
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                    interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .confirmationDialog(
            "Delete this clip from the camera?",
            isPresented: $isDeleteConfirmPresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task { await deleteActive() }
            }
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

    private var assistModeBar: some View {
        HStack(spacing: 6) {
            playbackAssistToolbar
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)
            viewAssistButton
                .layoutPriority(1)
        }
    }

    private var playbackAssistToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(
                    Array(LiveAssistTool.playbackToolbarCases.enumerated()),
                    id: \.element.id
                ) { index, tool in
                    if index > 0, index.isMultiple(of: 3) {
                        Rectangle()
                            .fill(LiveDesign.hairlineStrong)
                            .frame(width: 1, height: 22)
                            .padding(.horizontal, 3)
                    }
                    PlaybackAssistToolButton(tool: tool) { tool in
                        presentPlaybackAssistOptions(tool)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { playbackAssistToolbarFrame = proxy.frame(in: .global) }
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
        let clearance = EdgeInsets(top: 56, leading: 0, bottom: 110, trailing: 0)
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

    private func attachPlaybackVideoComposition(to item: AVPlayerItem) {
        audioMeterController.attach(to: item)
        startScopePolling()
        Task { @MainActor in
            _ = try? await item.asset.loadTracks(withMediaType: .video)
            guard player.currentItem === item else { return }
            updatePlaybackEffects()
        }
    }

    private func updatePlaybackEffects() {
        let fx = model.assist.playbackEffects
        playbackEffectsBox.setScopesActive(fx.needsScopes)
        let changed = playbackEffectsBox.set(effects: fx)
        guard let item = player.currentItem else { return }
        let needsComp = fx.needsGPUFeed || fx.needsScopes
        if !needsComp {
            if item.videoComposition != nil {
                item.videoComposition = nil
            }
            return
        }
        if item.videoComposition == nil || (changed && player.rate == 0) {
            item.videoComposition = playbackEffectsBox.makeVideoComposition(for: item.asset)
        }
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

    private func startScopePolling() {
        scopePollTask?.cancel()
        scopePollTask = Task { @MainActor in
            while !Task.isCancelled {
                let snap = playbackEffectsBox.readScopeSnapshot()
                if model.frameSamples.playbackBundle?.revision != snap.revision {
                    model.frameSamples.playbackBundle = snap.bundle
                }
                try? await Task.sleep(for: .milliseconds(84))
            }
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
        let rate = conformSource.captureRate ?? 0
        return Menu {
            Picker(ConformPreview.menuHeader(captureRate: rate), selection: $conformTarget) {
                Text("Real time").tag(Double?.none)
                ForEach(availability.targets, id: \.self) { target in
                    Text(ConformPreview.targetLabel(captureRate: rate, targetRate: target))
                        .tag(Double?.some(target))
                }
            }
            .pickerStyle(.inline)
            if let reason = availability.unavailableReason {
                Section { Text(reason) }
            } else if conformTarget != nil {
                Section { Text(ConformPreview.audioLabel) }
            }
        } label: {
            OpcIcon.timer
                .frame(
                    width: PlaybackChrome.actionIconSize,
                    height: PlaybackChrome.actionIconSize
                )
                .foregroundStyle(
                    conformTarget != nil
                        ? LiveDesign.accent
                        : (availability.isAvailable ? LiveDesign.text : LiveDesign.faint)
                )
                .frame(
                    width: PlaybackChrome.actionButtonSize.width,
                    height: PlaybackChrome.actionButtonSize.height
                )
                .background(
                    conformTarget != nil ? LiveDesign.accentDim : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                    interactive: true)
        }
        .disabled(!availability.isAvailable)
        .accessibilityLabel("Conform preview")
        .onChange(of: conformTarget) { _, _ in
            applyMute()
            if isPlaying { startPlayback() }
        }
    }

    private var cleanViewButton: some View {
        Button {
            withAnimation(.spring(duration: 0.32)) { chromeVisible = false }
        } label: {
            OpcIcon.maximize
                .frame(
                    width: PlaybackChrome.actionIconSize,
                    height: PlaybackChrome.actionIconSize
                )
                .foregroundStyle(LiveDesign.text)
                .frame(
                    width: PlaybackChrome.actionButtonSize.width,
                    height: PlaybackChrome.actionButtonSize.height
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                    interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Hide playback controls")
        .accessibilityHint("A restore control stays in the corner")
    }

    private var restoreChromeButton: some View {
        Button {
            withAnimation(.spring(duration: 0.32)) { chromeVisible = true }
        } label: {
            OpcIcon.minimize
                .frame(
                    width: PlaybackChrome.actionIconSize,
                    height: PlaybackChrome.actionIconSize
                )
                .foregroundStyle(LiveDesign.text.opacity(0.75))
                .frame(
                    width: PlaybackChrome.actionButtonSize.width,
                    height: PlaybackChrome.actionButtonSize.height
                )
                .liquidGlass(in: Circle(), interactive: true)
                .opacity(0.85)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Show playback controls")
    }

    private var viewAssistButton: some View {
        let anyAssistOn = !model.assist.playbackVisibleTools.isEmpty
        let highlighted = assistMode || anyAssistOn
        return Button {
            withAnimation(.spring(duration: 0.32)) { assistMode.toggle() }
        } label: {
            OpcIcon.monitor
                .frame(
                    width: PlaybackChrome.actionIconSize,
                    height: PlaybackChrome.actionIconSize
                )
                .foregroundStyle(highlighted ? LiveDesign.accent : LiveDesign.text)
                .frame(
                    width: PlaybackChrome.actionButtonSize.width,
                    height: PlaybackChrome.actionButtonSize.height
                )
                .background(
                    assistMode ? LiveDesign.accentDim : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                    interactive: true)
        }
        .buttonStyle(.zcTapTarget)
    }

    private var shareTransportButton: some View {
        let downloaded = session.isDownloaded(active)
        return Button {
            if isPlaying {
                player.pause()
                isPlaying = false
            }
            deliveryPresentation = MediaDeliveryPresentation(files: [active])
        } label: {
            if isPreparingShare || session.mediaDownloadProgress[active.path] != nil, !downloaded {
                ProgressView()
                    .tint(LiveDesign.accent)
                    .frame(
                        width: PlaybackChrome.actionButtonSize.width,
                        height: PlaybackChrome.actionButtonSize.height)
            } else {
                OpcIcon.share
                    .frame(
                        width: PlaybackChrome.actionIconSize,
                        height: PlaybackChrome.actionIconSize
                    )
                    .foregroundStyle(downloaded ? LiveDesign.text : LiveDesign.faint)
                    .frame(
                        width: PlaybackChrome.actionButtonSize.width,
                        height: PlaybackChrome.actionButtonSize.height
                    )
                    .contentShape(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                    )
                    .liquidGlass(
                        in: RoundedRectangle(
                            cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                        interactive: true)
            }
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Share clip")
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
        _ icon: OpcIcon,
        size: CGFloat = PlaybackChrome.transportIconSize,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon
                .frame(width: size, height: size)
                .foregroundStyle(LiveDesign.text)
                .frame(
                    width: PlaybackChrome.transportButtonSize.width,
                    height: PlaybackChrome.transportButtonSize.height
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                    interactive: true)
        }
        .buttonStyle(.zcTapTarget)
    }

    private func actionToggle(
        _ onIcon: OpcIcon, _ offIcon: OpcIcon, on: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            (on ? onIcon : offIcon)
                .frame(
                    width: PlaybackChrome.actionIconSize,
                    height: PlaybackChrome.actionIconSize
                )
                .foregroundStyle(on ? LiveDesign.accent : LiveDesign.text)
                .frame(
                    width: PlaybackChrome.actionButtonSize.width,
                    height: PlaybackChrome.actionButtonSize.height
                )
                .contentShape(
                    RoundedRectangle(cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .background(
                    on ? LiveDesign.accentDim : Color.clear,
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous)
                )
                .liquidGlass(
                    in: RoundedRectangle(
                        cornerRadius: DesignTokens.cornerRadius, style: .continuous),
                    interactive: true)
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
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text)
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 2)
                Text("/ \(MediaTimeFormatting.label(duration))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
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

    private func disappear() {
        loadTask?.cancel()
        playbackFlashTask?.cancel()
        scopePollTask?.cancel()
        audioMeterController.stopPolling()
        audioMeterController.detach(from: player.currentItem)
        playbackEffectsBox.invalidateScopeComposition()
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
        player.replaceCurrentItem(with: nil)

        // Never hand AVPlayer a `/v2?path=` URL. That path has no extension, the
        // camera often parks `moov` at the end, and SoftAP has no internet —
        // the item stays `.unknown` and this overlay never clears. Pull the
        // sidecar (same GET as thumbs) and play the local file.
        // Prefer the 720p sidecar even when the 4K original is already cached
        // for export. LUT / false colour grade that proxy, not the raw clip.
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
        player.replaceCurrentItem(with: item)
        applyMute()
        player.automaticallyWaitsToMinimizeStalling = isRemote
        attachPlaybackVideoComposition(to: item)
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
                reachedEnd = true
                isPlaying = false
                currentTime = duration
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
        clipSlideEdge = offset > 0 ? .trailing : .leading
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

    private func share() async {
        guard !isPreparingShare else { return }
        if session.isDownloaded(active) {
            isSharePresented = true
            return
        }
        isPreparingShare = true
        await session.download(file: active)
        isPreparingShare = false
        if session.isDownloaded(active) {
            isSharePresented = true
        }
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

private struct MediaPlaybackScrubber: View {
    let progress: Double
    let duration: Double
    let onScrubbingChanged: (Bool) -> Void
    let onProgressChange: (Double) -> Void
    let onSeek: (Double) -> Void

    @State private var isDragging = false

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, progress / duration))
    }

    var body: some View {
        GeometryReader { geo in
            let trackHeight: CGFloat = 3
            let thumbSize: CGFloat = 12
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LiveDesign.hairline)
                    .frame(height: trackHeight)
                Capsule()
                    .fill(LiveDesign.accent)
                    .frame(width: max(trackHeight, geo.size.width * fraction), height: trackHeight)
                Circle()
                    .fill(LiveDesign.accent)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: max(0, geo.size.width * fraction - thumbSize / 2))
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onScrubbingChanged(true)
                        }
                        let f = fraction(at: value.location.x, width: geo.size.width)
                        onProgressChange(f * duration)
                    }
                    .onEnded { value in
                        let f = fraction(at: value.location.x, width: geo.size.width)
                        onSeek(f * duration)
                        isDragging = false
                        onScrubbingChanged(false)
                    }
            )
        }
        .frame(height: 22)
    }

    private func fraction(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0 }
        return Double(min(1, max(0, x / width)))
    }
}

private struct MediaPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerHostView {
        let view = PlayerHostView()
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerHostView, context: Context) {
        uiView.playerLayer.player = player
    }

    static func dismantleUIView(_ uiView: PlayerHostView, coordinator: ()) {
        uiView.playerLayer.player = nil
    }

    final class PlayerHostView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
