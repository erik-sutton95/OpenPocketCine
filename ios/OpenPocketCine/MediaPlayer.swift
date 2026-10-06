import AVFoundation
import ImageIO
import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenPocketViewCore
import OpenCineAppKit
import OpenCineApple
import OpenCineMedia
import SwiftUI
import UIKit

// MARK: - Shared chrome

struct MediaCircleIconButton: View {
    let icon: MonitorIcon
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
    @State private var desqueezeOptions = false
    @State private var desqueezeHelp = false

    private var session: CameraSession { model.session }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image {
                GeometryReader { geo in
                    let rect = DesqueezeAssist.presentationRect(
                        sourceSize: image.size, in: CGRect(origin: .zero, size: geo.size),
                        effects: photoEffects)
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: rect.width, height: rect.height)
                        .scaleEffect(zoom.scale)
                        .offset(zoom.offset)
                        .frame(width: rect.width, height: rect.height)
                        .clipped()
                        .contentShape(Rectangle())
                        .gesture(
                            SimultaneousGesture(
                                pinchGesture(size: rect.size),
                                panGesture(size: rect.size))
                        )
                        .onChange(of: rect.size) { _, size in zoom.endGesture(size: size) }
                        .position(x: rect.midX, y: rect.midY)
                }
                .ignoresSafeArea()
            } else if isLoading {
                VStack(spacing: 12) {
                    ProgressView().tint(LiveDesign.accent)
                    Text("Preparing image…")
                        .font(MonitorTheme.font(14, weight: .medium))
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
                    .buttonStyle(.monitorTapTarget)
                    Text(file.filename)
                        .font(MonitorTheme.font(14, weight: .semibold))
                        .foregroundStyle(LiveDesign.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    deleteButton
                    shareButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 14 + windowGeometry.topControlInset)
                Spacer()
                HStack(spacing: 20) {
                    photoDesqueezeButton
                    favoriteButton
                }
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
        .overlay {
            if desqueezeOptions { photoDesqueezeOptions }
        }
    }

    private var photoEffects: MonitorFrameEffects {
        var effects = MonitorFrameEffects()
        effects.desqueezeFactor =
            model.assist.isPlaybackVisible(.desqueeze)
            ? model.assist.desqueezeFactor : 1
        effects.desqueezeHorizontal = model.assist.desqueezeHorizontal
        return effects
    }

    private var photoDesqueezeButton: some View {
        AssistToolChip(
            tool: .desqueeze, isOn: model.assist.isPlaybackVisible(.desqueeze), compact: true
        )
        .contentShape(Rectangle())
        .minTapTarget()
        .gesture(
            LongPressGesture(minimumDuration: 0.25).exclusively(before: TapGesture())
                .onEnded { value in
                    switch value {
                    case .first: desqueezeOptions = true
                    case .second: model.assist.togglePlayback(.desqueeze)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.assist.togglePlayback(.desqueeze) }
        .accessibilityLabel("Anamorphic Desqueeze")
        .accessibilityValue(model.assist.isPlaybackVisible(.desqueeze) ? "On" : "Off")
        .accessibilityAction(named: "Options") { desqueezeOptions = true }
        .accessibilityIdentifier("photo.desqueeze")
    }

    private var photoDesqueezeOptions: some View {
        GeometryReader { geo in
            MonitorInspector(
                title: MonitorAssistSelection.desqueeze.title, viewport: geo.size,
                safeArea: LiveMonitorLayout.resolvedSafeArea(
                    geo.safeAreaInsets, scene: windowGeometry.safeArea),
                helpVisible: $desqueezeHelp,
                onClose: { desqueezeOptions = false }
            ) {
                EmptyView()
            } content: {
                if let image {
                    Image(uiImage: image).resizable()
                        .aspectRatio(
                            image.size.width / image.size.height
                                * (model.assist.desqueezeHorizontal
                                    ? model.assist.desqueezeFactor
                                    : 1 / model.assist.desqueezeFactor),
                            contentMode: .fit
                        )
                        .frame(maxHeight: 160)
                }
                MonitorInspectorCard {
                    DesqueezeLongPressMenu(assist: model.assist, haptics: .app)
                }
                .environment(\.monitorInspectorHelp, desqueezeHelp)
            } footer: {
                EmptyView()
            }
            .environment(\.monitorSegmentedAppearance, .inspector)
        }
        .ignoresSafeArea()
    }

    private var favoriteButton: some View {
        let favorite = session.isFavorite(file)
        return Button {
            session.toggleFavorite(file)
        } label: {
            MonitorIcon.star.view(filled: favorite)
                .frame(width: 17, height: 17)
                .foregroundStyle(favorite ? LiveDesign.accent : LiveDesign.text)
                .frame(width: 34, height: 34)
                .liquidGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.monitorTapTarget)
        .accessibilityLabel(favorite ? "Remove from favorites" : "Add to favorites")
    }

    private var deleteButton: some View {
        Button {
            isDeleteConfirmPresented = true
        } label: {
            MediaCircleIconButton(icon: .trash, size: 34)
        }
        .buttonStyle(.monitorTapTarget)
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
        .buttonStyle(.monitorTapTarget)
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
    @Environment(\.scenePhase) private var scenePhase

    @State private var nativePlayback: MonitorApplePlaybackOwner
    @State private var playback: PocketPlaybackModel?
    @State private var playerVisible = false
    @State private var pictureGeometry: MonitorPlaybackPictureGeometry?
    @State private var toastMessage: String?
    @State private var deliveryPresentation: MediaDeliveryPresentation?
    @State private var playbackAssistToolbarFrame: CGRect = .zero
    @State private var playbackBarFrame: CGRect = .zero
    @State private var playbackAudioLevels: AudioMeterLevels?
    @State private var audioMeterController = MediaPlaybackAudioSession.makeMeter()

    private var player: AVPlayer { nativePlayback.player }
    private var playbackFeed: MonitorPlaybackFeedSession { nativePlayback.feed }
    private var isPlaying: Bool {
        (playback?.reportedPlaying ?? playback?.playRequested ?? true) && !isScrubbing
    }
    private var isMuted: Bool { playback?.muted ?? false }
    private var currentTime: Double { playback?.position ?? 0 }
    private var duration: Double { playback?.duration ?? Double(active.durationSeconds) }
    private var isScrubbing: Bool { playback?.scrubbing ?? false }
    private var scrubTime: Double { playback?.scrubPosition ?? currentTime }
    private var isClipReady: Bool { playback?.ready ?? false }
    private var loadError: String? { playback?.closed == true ? MediaOperatorCopy.clipNotCached : playback?.error }
    private var reachedEnd: Bool { playback?.reachedEnd ?? false }
    private var isLooping: Bool {
        get { playback?.looping ?? false }
        nonmutating set { playback?.setLooping(newValue) }
    }
    private var conformSource: MonitorConformPreview.Source { playback?.metadata.conform ?? .init() }
    private var conformTarget: Double? {
        get { playback?.conformTarget }
        nonmutating set { playback?.setConformTarget(newValue) }
    }
    private var playerLoadGeneration: Int { Int(truncatingIfNeeded: playback?.token.revision ?? 0) }
    private var videoDisplaySize: CGSize {
        if let width = playback?.metadata.width, let height = playback?.metadata.height {
            return CGSize(width: width, height: height)
        }
        return PlaybackVideoLayout.size(fromResolution: active.resolution)
            ?? CGSize(width: 16, height: 9)
    }

    init(files: [MediaFile], startingAt file: MediaFile) {
        self.files = files
        _active = State(initialValue: file)
        _nativePlayback = State(
            initialValue: MonitorApplePlaybackOwner(feed: PlaybackFeedSession()))
    }

    private var session: CameraSession { model.session }

    private var playlist: [MediaFile] {
        files.contains(where: { $0.id == active.id }) ? files : [active]
    }

    private var canGoPrevious: Bool { playback?.canGoPrevious ?? false }
    private var canGoNext: Bool { playback?.canGoNext ?? false }

    private var playerContent: some View {
        MonitorPlaybackScreen(
            value: playerPresentation, actions: playerActions,
            coverPresented: deliveryPresentation != nil,
            onGeometry: { geometry in
                guard geometry.item == playback?.token else { return }
                pictureGeometry = geometry
            }, onBarFrame: { playbackBarFrame = $0 },
            picture: {
                MediaPlayerLayerView(
                    player: player, session: playbackFeed,
                    effects: model.assist.playbackEffects,
                    transfer: MonitorTransfer(model.assist.monitorColorMode ?? .normal),
                    sampleBus: model.frameSamples)
            },
            feedAssists: { rect in
                FeedAlignedAssists(
                    grid: model.assist.isPlaybackVisible(.grid),
                    crosshair: model.assist.isPlaybackVisible(.crosshair),
                    guides: model.assist.isPlaybackVisible(.guides),
                    guideAspect: model.assist.guideAspect,
                    focusPoint: CGPoint(x: 0.5, y: 0.5), overlay: .focus, sceneFaces: [],
                    showFocusChrome: false, showTapFocusBox: false, feed: rect)
            }, canvasAssists: { size, rect in playbackScopeOverlays(in: size, videoRect: rect) },
            tools: { context in
                playbackAssistPalette(
                    presentation: context.presentation,
                    safeTop: context.safeTop, expanded: context.expanded)
            }
        )
        .monitorVideoBackdrop(
            renderer: model.playbackBackdrop,
            configuration: [
                MonitorVideoBackdropConfiguration(
                    source: ObjectIdentifier(playbackFeed), generation: playerLoadGeneration,
                    effects: model.assist.playbackEffects,
                    geometry: [
                        videoDisplaySize.width, videoDisplaySize.height,
                        (pictureGeometry?.zoom.scale ?? 1),
                        (pictureGeometry?.zoom.offset.width ?? 0),
                        (pictureGeometry?.zoom.offset.height ?? 0),
                    ])
            ],
            enabled: playerVisible && isClipReady, surroundRGB: 0x000000
        ) { size in
            guard let buffer = playbackFeed.backdropSource() else { return [] }
            let rect = DesqueezeAssist.presentationRect(
                sourceSize: videoDisplaySize, in: CGRect(origin: .zero, size: size),
                effects: model.assist.playbackEffects)
            var effects = model.assist.playbackEffects
            effects.clipByte = model.frameSamples.exposureCeiling.clipByte(
                transfer: MonitorTransfer(effects.colorMode))
            return [
                MonitorVideoBackdropSource(
                    buffer: buffer, effects: effects,
                    frame: MonitorVideoBackdropSource.displayedFrame(
                        sourceAspect: videoDisplaySize.width / max(1, videoDisplaySize.height),
                        effects: effects,
                        in: rect, zoom: (pictureGeometry?.zoom.scale ?? 1),
                        offset: (pictureGeometry?.zoom.offset ?? .zero)),
                    clip: rect)
            ]
        }
    }

    private var playerPresentation: MonitorPlaybackPresentation {
        let effects = model.assist.playbackEffects
        let rect = DesqueezeAssist.presentationRect(
            sourceSize: videoDisplaySize,
            in: CGRect(x: 0, y: 0, width: 1000, height: 1000), effects: effects)
        return .init(
            item: playback?.token, title: active.filename, subtitle: clipMetadata,
            source: playbackSourceLabel, metadata: clipInfoRows,
            aspect: Double(rect.width / max(1, rect.height)),
            mirrorHorizontal: effects.mirror, mirrorVertical: effects.mirrorVertical,
            ready: isClipReady, error: loadError,
            progress: session.mediaDownloadProgress[active.path],
            position: isScrubbing ? scrubTime : currentTime, duration: duration,
            buffered: bufferedDuration,
            positionLabel: conformedLabel(isScrubbing ? scrubTime : currentTime),
            durationLabel: conformedLabel(duration),
            playing: isPlaying, reachedEnd: reachedEnd, scrubbing: isScrubbing, muted: isMuted,
            looping: isLooping, previous: canGoPrevious, next: canGoNext,
            favorite: session.isFavorite(active),
            conform: conformSource, conformTarget: conformTarget, haptics: model.hapticsEnabled,
            toast: toastMessage)
    }

    private func withCurrentItem(
        _ token: MonitorPlaybackItemToken, _ action: (PocketPlaybackModel) -> Void
    ) {
        guard let playback, playback.isActive, playback.token == token else { return }
        action(playback)
    }
    private var playerActions: MonitorPlaybackActions {
        .init(
            back: dismissPlayback,
            play: { token, playing in withCurrentItem(token) { $0.setPlaying(playing) } },
            restart: { token in withCurrentItem(token) { $0.restart() } },
            seekBy: { token, delta in withCurrentItem(token) { $0.seek(by: delta) } },
            mute: { token, muted in withCurrentItem(token) { $0.setMuted(muted) } },
            loop: { token, looping in withCurrentItem(token) { $0.setLooping(looping) } },
            conform: { token, target in
                withCurrentItem(token) { owner in
                    owner.setConformTarget(target)
                }
            },
            adjacent: { token, offset in
                withCurrentItem(token) { _ in goToAdjacent(offset: offset) }
            },
            favorite: { token in withCurrentItem(token) { _ in session.toggleFavorite(active) } },
            share: { token in
                withCurrentItem(token) { owner in
                    owner.setPresentationActive(false)
                    deliveryPresentation = MediaDeliveryPresentation(files: [active])
                }
            },
            delete: { token in
                withCurrentItem(token) { _ in
                    let dying = active
                    Task { await deleteActive(dying, admitted: token) }
                }
            },
            beginScrub: { token in
                guard let playback, playback.isActive, playback.token == token else { return nil }
                return playback.beginScrub()
            }, updateScrub: { edit, time in playback?.updateScrub(seconds: time, admitted: edit) },
            updateFrameScrub: { edit, delta, width in
                playback?.updateFrameScrub(delta: delta, width: width, admitted: edit)
            },
            commitScrub: { edit in playback?.commitScrub(admitted: edit) },
            cancelScrub: { edit, reason in
                playback?.cancelScrub(interrupted: reason == .interrupted, admitted: edit)
            })
    }

    private var playerLifecycle: some View {
        playerContent
            .statusBarHidden()
            .preferredColorScheme(.dark)
            .onAppear {
                model.assist.gradesClip = true
                playerVisible = true
                appear()
            }
            .onDisappear {
                playerVisible = false
                playback?.setPresentationActive(false)
                model.assist.gradesClip = false
                disappear()
            }
            .task(id: session.mediaPlaybackRecord(for: active)?.asset.id) {
                loadActiveClip()
            }
            .onChange(of: session.isDownloaded(active)) { _, downloaded in
                if downloaded, isClipReady { playback?.refreshTransfer() }
            }
            .onChange(of: scenePhase) { _, phase in playback?.setSceneActive(phase == .active) }
            .onChange(of: playback?.ready) { _, ready in
                if ready == true, playback?.isActive == true, playback?.ready == true,
                    playback?.active?.payload == active,
                    OperatorPrefs.cacheFullResolution, !session.isDownloaded(active)
                {
                    let file = active
                    Task { await session.download(file: file) }
                }
            }
            .onChange(of: playback?.look?.source) { _, look in
                guard let look, playback?.isActive == true, playback?.look?.source == look else {
                    return
                }
                if let shot = look.shotColor {
                    session.rememberShotColor(
                        shot, for: look.file, operation: look.authority.operation)
                }
                guard playback?.isActive == true, playback?.look?.source == look else { return }
                model.assist.adoptPlaybackColor(
                    look.color,
                    family: look.family != .other ? look.family : model.assist.monitorFamily,
                    cameraName: look.cameraName)
            }
    }

    var body: some View {
        playerLifecycle
            .overlay {
                if deliveryPresentation != nil {
                    MediaDeliveryPopupOverlay(files: [active]) {
                        deliveryPresentation = nil
                        playback?.setPresentationActive(playerVisible && !model.delivery.isActive)
                    }
                    .zIndex(5)
                }
            }
            .overlay(alignment: .top) {
                if let state = model.delivery.overlayState {
                    MediaDeliveryOverlay(state: state) {
                        model.delivery.cancel()
                        playback?.setPresentationActive(playerVisible && !model.delivery.isActive)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .zIndex(50)
                }
            }
            .sheet(item: model.delivery.sharePresentation) { payload in
                MediaShareSheet(urls: payload.urls) {
                    if model.delivery.completeSharePresentation(id: payload.id) {
                        playback?.setPresentationActive(playerVisible && !model.delivery.isActive)
                    }
                }
            }
            .onChange(of: model.delivery.isActive) { _, active in
                playback?.setPresentationActive(
                    !active && playerVisible && deliveryPresentation == nil)
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
                            safeArea: LiveMonitorLayout.resolvedSafeArea(
                                geo.safeAreaInsets, scene: windowGeometry.safeArea),
                            onDismiss: { model.assist.configureTool = nil }
                        )
                        .environment(\.audioInspectorLevels, playbackAudioLevels)
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
        hasher.combine(model.assist.desqueezeFactor)
        hasher.combine(model.assist.desqueezeHorizontal)
        hasher.combine(model.assist.splitComparison)
        hasher.combine(model.assist.monitorColorMode?.rawValue)
        return hasher.finalize()
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

    private var bufferedDuration: Double {
        player.currentItem?.loadedTimeRanges.map { value in
            let range = value.timeRangeValue
            return CMTimeGetSeconds(CMTimeRangeGetEnd(range))
        }.filter(\.isFinite).max() ?? 0
    }

    private func playbackAssistPalette(
        presentation: FieldMonitorLayout, safeTop: CGFloat, expanded: Binding<Bool>
    )
        -> some View
    {
        @Bindable var model = model
        let tools = MonitorAssistSelection.toolbarCases + [.audioMeters]
        let (metrics, frame) = MonitorAssistPaletteLayout.fieldMonitor(
            presentation, toolCount: tools.count, safeTop: safeTop)
        return MonitorAssistPalette(
            tools: tools.map {
                MonitorToolItem(
                    id: $0.rawValue, title: $0.rawValue,
                    enabled: model.assist.isPlaybackVisible($0), hasOptions: $0.hasConfiguration)
            },
            layout: metrics, usageSeed: MonitorToolUsage.fieldMonitorSeed,
            usage: $model.assistToolUsage, expanded: expanded,
            onToggle: { id in
                if let tool = MonitorAssistSelection(rawValue: id) { model.assist.togglePlayback(tool) }
            },
            onOptions: { id in
                if let tool = MonitorAssistSelection(rawValue: id) { presentPlaybackAssistOptions(tool) }
            },
            icon: { id in
                if let tool = MonitorAssistSelection(rawValue: id) {
                    AssistToolIcon(tool: tool, size: nil)
                }
            }
        )
        .background {
            GeometryReader { proxy in
                Color.clear.onAppear { playbackAssistToolbarFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { _, next in
                        playbackAssistToolbarFrame = next
                    }
            }
        }
        .position(x: frame.midX, y: frame.midY)
        .frame(
            width: presentation.viewport.width, height: presentation.viewport.height,
            alignment: .topLeading
        )
        .onAppear {
            playbackAssistToolbarFrame = frame.cgRect
        }
    }

    private func presentPlaybackAssistOptions(_ tool: MonitorAssistSelection) {
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
            NDMeterOverlay(
                stores: .app, bounds: canvas, feed: videoRect, chromeClearance: clearance,
                reading: { [model] in NDAssist.reading(from: model.frameSamples.displayBundle) })
        }
        if model.assist.isPlaybackVisible(.audioMeters), let playbackAudioLevels {
            AudioMeterOverlay(
                stores: .app, levels: playbackAudioLevels, sensitivity: nil,
                bounds: canvas, chromeClearance: clearance,
                hapticsEnabled: model.hapticsEnabled,
                onConfigure: { presentPlaybackAssistOptions(.audioMeters) })
        }
        if model.assist.isPlaybackVisible(.falseColor), model.assist.falseColorReference {
            let transfer =
                model.monitorTransfer ?? MonitorTransfer(model.assist.monitorColorMode ?? .normal)
            FalseColorReferenceOverlay(
                stores: .app, looks: .app,
                scale: model.assist.falseColorScale,
                transfer: transfer,
                rec709: model.assist.falseColorRec709,
                clipByte: model.frameSamples.exposureCeiling.clipByte(transfer: transfer),
                bounds: canvas, chromeClearance: clearance, hapticsEnabled: model.hapticsEnabled,
                onConfigure: { presentPlaybackAssistOptions(.falseColor) })
        }
    }

    private func attachPlaybackAssists(to item: AVPlayerItem) {
        playbackAudioLevels = nil
        audioMeterController.attach(to: item)
        updatePlaybackEffects()
    }

    private func updatePlaybackEffects() {
        let fx = model.assist.playbackEffects
        playbackFeed.setEffects(
            fx.playbackFrameEffects,
            transfer: MonitorTransfer(fx.colorMode),
            sampleBus: model.frameSamples)
        syncPlaybackAudioMetering()
    }

    private func syncPlaybackAudioMetering() {
        if model.assist.isPlaybackVisible(.audioMeters) {
            audioMeterController.startPolling { [self] levels in
                playbackAudioLevels = levels.map(AudioMeterLevels.init)
            }
        } else {
            audioMeterController.stopPolling()
            playbackAudioLevels = nil
        }
    }

    private var conformSpeed: Double {
        guard let target = conformTarget, let rate = conformSource.captureRate else { return 1 }
        return MonitorConformPreview.speed(captureRate: rate, targetRate: target)
    }

    private func conformedLabel(_ seconds: Double) -> String {
        MediaTimeFormatting.label(
            MonitorConformPreview.conformedDuration(sourceSeconds: seconds, speed: conformSpeed))
    }

    private func appear() {
        MediaPlaybackAudioSession.activateForPlayback()
        syncPlaybackAudioMetering()
    }

    private func disappear() {
        audioMeterController.stopPolling()
        audioMeterController.detach(from: player.currentItem)
        nativePlayback.onItemChanged = nil
        playback?.close()
        audioMeterController.close()
        model.assist.configureTool = nil
        MediaPlaybackAudioSession.deactivateAfterPlayback()
    }

    private func loadActiveClip() {
        guard let record = session.mediaPlaybackRecord(for: active) else {
            playback?.close()
            return
        }
        if playback?.closed == true {
            nativePlayback.onItemChanged = nil
            nativePlayback = MonitorApplePlaybackOwner(feed: PlaybackFeedSession())
            playback = nil
        }
        if playback == nil {
            let owner = session.makeMediaPlayback(
                native: nativePlayback, previousColor: { model.assist.monitorColorMode })
            playback = owner
            nativePlayback.onItemChanged = { item in
                audioMeterController.detach(from: nil)
                if let item { attachPlaybackAssists(to: item) }
            }
        }
        if playback?.active?.asset.id != record.asset.id {
            playback?.load(
                record, playlist: playlist.compactMap { session.mediaPlaybackRecord(for: $0) })
        }
        playback?.setSceneActive(scenePhase == .active)
        playback?.setPresentationActive(
            playerVisible && !model.delivery.isActive && deliveryPresentation == nil)
    }

    private func goToAdjacent(offset: Int) {
        guard let playback else { return }
        guard offset < 0 ? playback.canGoPrevious : playback.canGoNext else {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            return
        }
        playback.setPresentationActive(false)
        playback.goToAdjacent(offset)
        guard let next = playback.active?.payload else { return }
        withAnimation(.easeInOut(duration: 0.28)) {
            active = next
        }
    }

    private func dismissPlayback() {
        playerVisible = false
        playback?.setPresentationActive(false)
        dismiss()
    }

    private func deleteActive(_ dying: MediaFile, admitted token: MonitorPlaybackItemToken) async {
        guard let owner = playback, owner.token == token, owner.isActive,
            let index = owner.playlist.firstIndex(where: { $0.asset.id == owner.active?.asset.id })
        else { return }
        let adjacent =
            owner.playlist.indices.contains(index + 1)
            ? owner.playlist[index + 1].payload
            : (owner.playlist.indices.contains(index - 1) ? owner.playlist[index - 1].payload : nil)
        await session.deleteMediaFiles([dying])
        // Confirmed removal can retire this item while the native delete awaits. A successor
        // page or a dismissed host must still reject this outgoing completion.
        guard playback === owner, active == dying, playerVisible,
            owner.token == token || owner.closed
        else { return }
        if let adjacent {
            withAnimation(.easeInOut(duration: 0.28)) { active = adjacent }
        } else {
            dismissPlayback()
        }
    }
}
