import OpenCineAppKitApple
import AVFoundation
import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI
import OpenCineDJIApple

/// SwiftUI may construct discarded view values; only the retained owner opens camera resources.
@MainActor
private final class MultiviewSessionOwner {
    private var retained: MultiviewSession?
    private var make: (() -> MultiviewSession)?
    init(make: @escaping () -> MultiviewSession) { self.make = make }
    /// The session, created once; it reads the app's preferences and saved cameras from `model`.
    func session(_ model: AppModel) -> MultiviewSession {
        if let retained { return retained }
        guard let make else { preconditionFailure("Missing retained Multiview constructor") }
        let created = make()
        created.appModel = model
        retained = created
        self.make = nil
        return created
    }
}

/// Pocket's Multiview: OpenCine's shared screen (`MultiviewScreen`) over this app's session, which
/// is the screen's host (pictures, backdrop, settings editor, Live View, network wizard values).
struct MultiviewView: View {
    @Environment(AppModel.self) private var model
    @State private var owner: MultiviewSessionOwner
    private let startsSession: Bool
    private let reviewPictures: Bool

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
        let session = owner.session(model)
        MultiviewScreen(coordinator: session.coordinator, host: session, startsSession: startsSession)
            .environment(\.multiviewReviewPictures, reviewPictures)
    }
}

extension EnvironmentValues {
    /// The DEBUG review fixture draws static artwork over each tile's picture.
    @Entry var multiviewReviewPictures = false
}

/// The shared screen's app half: this session's pictures, backdrop, settings editor, borrowed
/// Live View and network wizard values.
extension MultiviewSession: MultiviewScreenHost {
    var confirmsRecord: Bool { appModel?.recordConfirmationEnabled ?? true }
    var editsCameraSettings: Bool { true }
    var appliesAutoLUT: Bool { true }

    func lutChanged(slot: Int) { tiles[slot].updateLUT() }

    func openCameraSettings(slot: Int) { openCameraSettings(tiles[slot]) }

    func cameraSettings(slot: Int) -> MultiviewCameraSettingsState? {
        guard let model = tiles[slot].controlsModel else { return nil }
        return MultiviewCameraSettingsState(
            categories: MultiviewSettingsCategory.offered(
                focus: model.session.supportsFocusMode, aperture: model.session.supportsAperture,
                photo: model.session.status.isPhoto, audio: true),
            recording: model.session.status.isRecording, note: model.session.controlNote)
    }

    /// The tile's own datalink is open and no Live View borrows it.
    func admitsControls(slot: Int) -> Bool {
        tiles[slot].driver != nil && tiles[slot].liveModel == nil
    }

    func picture(slot: Int, fill: Bool) -> some View {
        MultiviewTilePicture(
            tile: tiles[slot], index: slot, fill: fill,
            hdrDisplay: appModel?.hdrDisplayActive ?? false)
    }

    func backdrop(
        layout: MultiviewPresentationLayout, geometry: MultiviewStageGeometry, enabled: Bool
    ) -> some ViewModifier {
        MultiviewBackdrop(session: self, layout: layout, geometry: geometry, enabled: enabled)
    }

    @ViewBuilder func settingsPreview(slot: Int) -> some View {
        let tile = tiles[slot]
        if let model = tile.controlsModel {
            // Live View's assist inspector preview, fed by this tile's sample bus.
            AssistInspectorPreview(tool: .lut, pictureEffects: tile.settingsPreviewEffects)
                .environment(model)
                .id(ObjectIdentifier(model))
        }
    }

    @ViewBuilder func settingsControls(
        slot: Int, category: MultiviewSettingsCategory, enabled: Bool,
        presented: @escaping () -> Bool, close: @escaping () -> Void
    ) -> some View {
        let tile = tiles[slot]
        if let model = tile.controlsModel, let sheet = CaptureSheet(rawValue: category.rawValue) {
            CapturePickerPanel(
                sheet: sheet,
                isPresented: { tile.controlsModel === model && presented() },
                controlsEnabled: enabled, chromeless: true, onClose: close
            )
            .fixedSize(horizontal: false, vertical: true)
            .environment(model)
            .id(
                MultiviewSettingsPanelIdentity(
                    model: ObjectIdentifier(model), category: sheet,
                    described: model.control.snapshot != nil))
        }
    }

    @ViewBuilder func liveView(slot: Int, exit: @escaping () -> Void) -> some View {
        if let model = tiles[slot].liveModel {
            LiveViewScreen().environment(model)
                .onAppear {
                    model.multiviewExit = {
                        model.shell.close()
                        exit()
                    }
                }
        }
    }

    var stationBrand: StationNetworkBrand { PocketStationNetwork.brand }
    var stationServices: StationNetworkServices { PocketStationNetwork.services }
    var cameraSSIDs: Set<String> { Set(appModel?.savedCameras.compactMap(\.lastSSID) ?? []) }

    /// The physical probe's preview value, DEBUG only (Release sets none, as before).
    func settingsAccessibilityValue(slot: Int?) -> String? {
        #if DEBUG
            ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_PROBE"] == "1"
                ? slot.map { tiles[$0].previewAccessibilityValue } ?? "" : ""
        #else
            nil
        #endif
    }
}

/// The settings controls start again for another camera, category or a camera's first description.
private struct MultiviewSettingsPanelIdentity: Hashable {
    let model: ObjectIdentifier
    let category: CaptureSheet
    /// The panel captures its field on appear; it appears again once the freshly bound
    /// controls first describe the camera.
    let described: Bool
}

/// One tile's picture: its decoder's display layer, Fit or Fill, while no Live View borrows it.
private struct MultiviewTilePicture: View {
    let tile: MultiviewSession.Tile
    let index: Int
    let fill: Bool
    let hdrDisplay: Bool
    @Environment(\.multiviewReviewPictures) private var reviewPictures

    var body: some View {
        ZStack {
            if tile.liveModel == nil {
                GeometryReader { picture in
                    let ratio = tile.decoder.pictureAspect
                    MultiviewVideoLayer(tile: tile, hdrDisplay: hdrDisplay)
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
                    MultiviewUIReviewPicture(index: index, fill: fill)
                }
            #endif
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
