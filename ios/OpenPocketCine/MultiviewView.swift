import OpenCineAppKitApple
import AVFoundation
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI
import OpenCineDJIApple

/// SwiftUI may construct discarded view values; only the retained owner opens camera resources.
@MainActor
private final class MultiviewSessionOwner {
    private var retained: MultiviewSession?
    private var make: (() -> MultiviewSession)?
    init(make: @escaping () -> MultiviewSession) { self.make = make }
    var session: MultiviewSession {
        if let retained { return retained }
        guard let make else { preconditionFailure("Missing retained Multiview constructor") }
        let created = make()
        retained = created
        self.make = nil
        return created
    }
}

struct MultiviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var owner: MultiviewSessionOwner
    private var session: MultiviewSession { owner.session }
    private let startsSession: Bool
    private let reviewPictures: Bool
    @State private var adding: MultiviewSession.Tile?
    @State private var showNetwork = false
    @State private var selectedCamera: DjiAppleSighting?
    @State private var showLeave = false
    @State private var liveTile: MultiviewSession.Tile?
    @State private var settingsTile: MultiviewSession.Tile?
    @State private var stageGeometry = MultiviewStageGeometry()

    init(session: MultiviewSession? = nil, startsSession: Bool = true, reviewPictures: Bool = false,
        makeSession: @escaping @MainActor () -> MultiviewSession = { MultiviewSession() })
    {
        #if DEBUG
            let usesReviewFixture = session == nil && MultiviewUIReview.isActive
        #else
            let usesReviewFixture = false
        #endif
        _owner = State(initialValue: MultiviewSessionOwner {
            if let session { return session }
            #if DEBUG
                if usesReviewFixture, let fixture = MultiviewUIReview.sessionFromEnvironment() {
                    return fixture
                }
            #endif
            let stage = makeSession()
            let store = MultiviewStagePreferencesStore(
                storage: .standard, key: "multiview.presentation")
            stage.presentation.attachPersistence(load: store.load, save: store.save)
            return stage
        })
        self.startsSession = usesReviewFixture ? false : startsSession
        self.reviewPictures = usesReviewFixture ? true : reviewPictures
    }

    var body: some View {
        NavigationStack {
            MultiviewStageSurface(
                arrangement: session.presentation.layout.arrangement, selected: session.focusedIndex
            ) { viewport in
                stageContent(viewport: viewport)
                    .toolbar(.hidden, for: .navigationBar)
                    .statusBarHidden(true)

                    .allowsHitTesting(!showNetwork && adding == nil && !session.closing)
                    .overlay {
                        if session.closing {
                            ProgressView("Returning cameras to their Wi-Fi…").padding().background(
                                .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        }
                    }
                    .accessibilityHidden(showNetwork || adding != nil)
                    .overlay {
                        if let tile = adding {
                            cameraPicker(tile)
                        }
                    }
                    .fullScreenCover(item: $liveTile, onDismiss: { session.closeLiveView() }) {
                        tile in
                        if let model = tile.liveModel {
                            LiveViewScreen().environment(model)
                                .onAppear {
                                    model.multiviewExit = {
                                        model.shell.close()
                                        liveTile = nil
                                    }
                                }
                        }
                    }
                    .alert(
                        "Multiview",
                        isPresented: Binding(
                            get: { session.error != nil }, set: { if !$0 { session.error = nil } })
                    ) {
                        Button("OK") { session.error = nil }
                        if session.hasPendingCleanup {
                            Button("Close anyway") { dismiss() }
                        }
                    } message: {
                        Text(session.error ?? "")
                    }
                    .confirmationDialog(
                        MultiviewNetworkRestore.cameraNetworks.closeQuestion,
                        isPresented: $showLeave, titleVisibility: .visible
                    ) {
                        Button(MultiviewNetworkRestore.closeAction) {
                            Task { if await session.closeStage() { dismiss() } }
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        if startsSession { session.setApplicationActive(phase == .active) }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIApplication.willResignActiveNotification)
                    ) { _ in
                        if startsSession { session.setApplicationActive(false) }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIApplication.didBecomeActiveNotification)
                    ) { _ in
                        if startsSession { session.setApplicationActive(true) }
                    }
                    .onChange(of: session.layout) { _, _ in session.persistStage() }
                    .onChange(of: session.focusedIndex) { _, _ in session.persistStage() }
                    .onAppear {
                        if startsSession { session.start() }
                        showNetwork = !session.networkConfigured
                    }
            }
            .ignoresSafeArea(.container)
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showNetwork) {
            MultiviewNetworkSetup(
                session: session,
                cancel: {
                    showNetwork = false
                    Task { if await session.closeStage() { dismiss() } }
                }, complete: { showNetwork = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MonitorTheme.background)
            .interactiveDismissDisabled()
        }
    }

    private func stageContent(viewport: MultiviewStageViewport) -> some View {
        let safe = viewport.safeArea
        let layout = viewport.layout
        let program = session.tiles[min(3, max(0, session.focusedIndex))]
        return MultiviewStage(
            tiles: session.tiles.indices.map(session.stageTile), layout: layout,
            viewport: viewport.size, safeArea: safe,
            arrangement: Binding(
                get: { session.layout == .grid ? .grid : .centerStage },
                set: { session.layout = $0 == .grid ? .grid : .centerStage }),
            selected: Binding(get: { session.focusedIndex }, set: { session.focusedIndex = $0 }),
            fill: Binding(
                get: { session.feedAspect == .fill },
                set: {
                    session.feedAspect = $0 ? .fill : .fit16x9
                    session.persistStage()
                }),
            tools: [.layout, .camera, .fit, .lut],
            readouts: program.camera == nil
                ? nil : MultiviewTelemetryPresentation(
                    settings: program.settings, power: program.control.current.power).readouts,
            lut: session.tiles.contains { $0.camera != nil && $0.lutEnabled },
            recording: session.anyRecording, busy: session.busy,
            groupBusy: session.groupRecordingBusy,
            confirmsRecord: model.recordConfirmationEnabled,
            network: MultiviewStageButton(
                title: "Shared Wi-Fi", value: session.ssid, icon: .wifi,
                enabled: !(session.busy || session.connectingCameras || !startsSession),
                identifier: "multiview.network"
            ) { showNetwork = true },
            geometry: stageGeometry,
            actions: MultiviewStageActions(
                openLiveView: openLiveView, add: add, perform: perform, toggleLUT: toggleLUT,
                openSettings: { settingsTile = session.tiles[$0] }, close: close,
                recordContext: session.recordContext(slot:),
                record: { plan, slot in await session.record(plan, together: slot == nil) },
                popupsClosed: closePopups),
            picture: picture,
            backdrop: MultiviewBackdrop(
                session: session, layout: layout, geometry: stageGeometry,
                enabled: liveTile == nil && !showNetwork && adding == nil && !session.closing)
        )
        .multiviewStageState(session.presentation)
        .multiviewStageServices(toolServices)
        .multiviewStageVisible(liveTile == nil)
        .overlay { settingsPanel(viewport: viewport.size, safe: safe) }
    }

    /// Every assigned tile has both working adapters: the per-tile settings panel (which opens
    /// that tile's controls once its link is available and says so otherwise) and its own
    /// decoder's Auto LUT render plan.
    private var toolServices: MultiviewStageServices {
        let assigned = Set(session.tiles.indices.filter { session.tiles[$0].camera != nil })
        return MultiviewStageServices(
            availability: MultiviewToolAvailability(
                cameraSettingsSlots: assigned, pictureLUTSlots: assigned),
            automaticLUT: true)
    }

    private func closePopups() {
        settingsTile = nil
        session.closeCameraSettings()
    }

    @ViewBuilder
    private func settingsPanel(viewport: CGSize, safe: EdgeInsets) -> some View {
        if let tile = settingsTile {
            // Same trailing side panel as Live View's gimbal controls.
            MultiviewCameraSettings(
                session: session, initialTile: tile, viewport: viewport, safeArea: safe,
                close: closePopups
            )
            .accessibilityAddTraits(.isModal)
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func picture(_ index: Int) -> some View {
        let tile = session.tiles[index]
        ZStack {
            if tile.liveModel == nil {
                GeometryReader { picture in
                    let fill = session.feedAspect == .fill
                    let ratio = tile.decoder.pictureAspect
                    MultiviewVideoLayer(tile: tile, hdrDisplay: model.hdrDisplayActive)
                        .frame(
                            width: fill
                                ? max(picture.size.width, picture.size.height * ratio)
                                : picture.size.width,
                            height: fill
                                ? max(picture.size.height, picture.size.width / ratio)
                                : picture.size.height
                        )
                        .position(x: picture.size.width / 2, y: picture.size.height / 2)
                }
            }
            #if DEBUG
                if reviewPictures {
                    MultiviewUIReviewPicture(index: index, fill: session.feedAspect == .fill)
                }
            #endif
        }
    }

    private func toggleLUT() {
        let enabled = !session.tiles.filter { $0.camera != nil }.allSatisfy(\.lutEnabled)
        for tile in session.tiles where tile.camera != nil && tile.lutEnabled != enabled {
            tile.toggleLUT()
        }
        session.persistStage()
    }

    private func add(_ slot: Int) {
        selectedCamera = nil
        if session.networkConfigured { adding = session.tiles[slot] } else { showNetwork = true }
    }

    private func perform(_ action: String, _ slot: Int) {
        let tile = session.tiles[slot]
        switch action {
        case MultiviewCameraAction.lut:
            tile.toggleLUT()
            session.persistStage()
        case MultiviewCameraAction.reconnect: Task { await session.reconnect(tile) }
        case MultiviewCameraAction.experimental: Task { await session.tryExperimentalNetwork(tile) }
        // A removed camera's options close with it.
        case MultiviewCameraAction.remove: Task { _ = await session.remove(tile) }
        default: break
        }
    }

    private func openLiveView(_ slot: Int) {
        let tile = session.tiles[slot]
        guard tile.controlHost != nil, !tile.recovering else { return }
        session.openLiveView(tile)
        if tile.liveModel != nil { liveTile = tile }
    }

    private func close() {
        if session.tiles.contains(where: { $0.camera != nil }) {
            showLeave = true
        } else {
            Task { if await session.closeStage() { dismiss() } }
        }
    }

    private var availableCameras: [DjiAppleSighting] {
        session.found.filter { camera in
            camera.appearsInMultiview
                && !session.tiles.contains { $0.camera?.id == camera.id }
        }
    }

    private func cameraPicker(_ tile: MultiviewSession.Tile) -> some View {
        let cameras = availableCameras
        return MultiviewCameraPicker(
            rows: cameras.map { camera in
                MultiviewPickerRow(
                    id: camera.id.uuidString, title: camera.name,
                    detail: camera.hasMultiviewPreview
                        ? nil : "Try experimental shared Wi-Fi · Preview unavailable",
                    limited: !camera.hasMultiviewPreview)
            },
            footer: "Each camera will join \(session.ssid). Approve on the camera if asked.",
            cancel: {
                adding = nil
                selectedCamera = nil
            }
        ) { id in
            guard let camera = cameras.first(where: { $0.id.uuidString == id }) else { return }
            adding = nil
            Task {
                session.enqueueAdd(
                    camera, to: tile, experimental: !camera.hasMultiviewPreview)
            }
        }
    }

}

/// The stage's video backdrop: every live tile's picture, placed where the stage canvas put it.
private struct MultiviewBackdrop: ViewModifier {
    let session: MultiviewSession
    let layout: MultiviewPresentationLayout
    let geometry: MultiviewStageGeometry
    let enabled: Bool

    func body(content: Content) -> some View {
        content.monitorVideoBackdrop(
            renderer: session.backdropRenderer,
            configuration: session.tiles.enumerated().map { index, tile in
                let frame = layout.tiles[index]
                return MonitorVideoBackdropConfiguration(
                    source: ObjectIdentifier(tile.decoder),
                    generation: Int(tile.sampleBus.inspectorSourceEpoch), effects: tile.effects,
                    geometry: [
                        frame.x, frame.y, frame.width, frame.height,
                        tile.pose.poseViewFlip ? 1 : 0, session.feedAspect == .fill ? 1 : 0,
                    ])
            },
            enabled: enabled
        ) { _ in
            session.tiles.enumerated().compactMap { index, tile in
                let decoder = tile.decoder, samples = tile.sampleBus
                let epoch = samples.inspectorSourceEpoch
                guard tile.liveModel == nil, tile.camera != nil,
                    let token = decoder.sourceToken, let buffer = decoder.backdropSource
                else { return nil }
                guard let placement = geometry.placement(index) else { return nil }
                let rect = placement.frame
                let effects = tile.decoder.backdropEffects
                return MonitorVideoBackdropSource(
                    buffer: buffer, effects: effects,
                    frame: MonitorVideoBackdropSource.displayedFrame(
                        sourceAspect: tile.decoder.pictureAspect, effects: effects, in: rect,
                        fill: session.feedAspect == .fill),
                    clip: placement.clip, identity: .live(token: token, epoch: epoch), admission: { [weak decoder, weak samples] in
                        guard let decoder, let samples else { return false }
                        return decoder.sourceToken == token && samples.inspectorSourceEpoch == epoch
                    })
            }
        }
    }
}

struct MultiviewVideoLayer: UIViewRepresentable {
    let tile: MultiviewSession.Tile
    var hdrDisplay = false
    func makeUIView(context: Context) -> DisplayLayerView {
        let view = DisplayLayerView(tile.decoder.displayLayer)
        view.onReady = { [decoder = tile.decoder] in decoder.noteDisplayReady() }
        tile.decoder.invalidatePictureFlipPresentation()
        updateDisplay(view)
        return view
    }
    func updateUIView(_ view: DisplayLayerView, context: Context) { updateDisplay(view) }
    func updateDisplay(_ view: DisplayLayerView) {
        guard view.ownsDisplayLayer else { return }
        tile.decoder.applyPictureMirror = { [weak view] mirrored in
            view?.setPictureMirrored(mirrored)
        }
        tile.decoder.assistMirror = false
        tile.decoder.poseViewFlip = tile.pose.poseViewFlip
        tile.decoder.processedFeed = view.ciFeed
        tile.decoder.bindSourcePublication(tile.sampleBus)
        tile.decoder.hdrDisplayEnabled = hdrDisplay
        view.applyHDRDisplay(hdrDisplay)
        if tile.decoder.effects != tile.effects { tile.decoder.effects = tile.effects }
        tile.decoder.adoptIncomingTransfer(tile.settings.monitorTransfer)
    }
}
