import MonitorUI
import OpenCineCameraControls
import OpenCineMulticam
import OpenPocketViewCore
import SwiftUI
import OpenCineMedia

extension MultiviewSession {
    func controlsAvailable(for tile: Tile) -> Bool {
        tile.camera != nil && tile.driver != nil && tile.controlHost != nil
            && !tile.connecting && !tile.recovering && tile.liveModel == nil
            && !busy && !closing && applicationActive && tile.recordingAvailable
            && !groupRecordingBusy && !tile.recordingBusy
    }

    /// One editor at a time; changing tabs retires queued SETs before binding the next camera.
    @discardableResult
    func openCameraSettings(_ tile: Tile) -> AppModel? {
        closeCameraSettings()
        guard let camera = tile.camera else { return nil }
        let editor = CameraSession(borrowing: tile.decoder, controlsOnly: true)
        let model = AppModel(session: editor)
        editor.updateMultiview(camera: camera, driver: tile.driver, status: tile.settings)
        // The capture drums edit through the shared control model; retiring unbinds it.
        model.control.bind(editor.control)
        model.frameSamples = tile.sampleBus
        tile.controlsModel = model
        tile.previewDemand = true
        // The engine's editor lease names this tile's session and control epoch: a replaced
        // link or camera, a lost authority or the next editor retires it (plan 7.5).
        let lease = try? editorLeases.open(
            tile.entryID, in: multicamGroup(of: [tile]), at: multicamSnapshot(of: [tile]))
        editor.multiviewControlAdmission = { [weak self, weak tile, weak editor] in
            guard let self, let tile, let editor, let lease else { return false }
            return tile.controlsModel?.session === editor
                && editorLeases.refusal(
                    for: lease, in: multicamGroup(of: [tile]), at: multicamSnapshot(of: [tile]))
                    == nil
                && controlsAvailable(for: tile)
        }
        return model
    }

    func closeCameraSettings() {
        editorLeases.closeAll()
        for tile in tiles { tile.retireControls() }
    }
}

struct MultiviewCameraSettings: View {
    let session: MultiviewSession
    let initialTile: MultiviewSession.Tile
    let viewport: CGSize
    let safeArea: EdgeInsets
    let close: () -> Void
    @State private var selectedID: UUID?
    @State private var category: CaptureSheet = .iso
    @State private var railHeight: CGFloat = 0
    @State private var column: CGSize = .zero
    /// Tallest controls seen this session, so the preview never makes a category scroll.
    @State private var controlsReserve: CGFloat = 200
    private struct PanelIdentity: Hashable {
        let model: ObjectIdentifier
        let category: CaptureSheet
        /// The panel captures its field on appear; it appears again once the freshly bound
        /// controls first describe the camera.
        let described: Bool
    }

    private var cameras: [MultiviewSession.Tile] { session.tiles.filter { $0.camera != nil } }
    private var selected: MultiviewSession.Tile? {
        cameras.first { $0.id == selectedID }
    }

    var body: some View {
        // Live View's gimbal side panel container: trailing edge, width, glass,
        // reveal and tap-outside dismissal. Its concrete root keeps editor
        // cleanup tied to closing the panel, not to camera/category identity.
        MonitorInspector(
            title: "Camera settings", viewport: viewport, safeArea: safeArea,
            trailing: true, hasNavigation: false, preferredWidth: .assist,
            scrollsContent: false, closeIdentifier: "monitor.capture.close", compactHeader: true,
            onClose: close
        ) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                cameraTabs
                if let tile = selected, let model = tile.controlsModel {
                    HStack(alignment: .top, spacing: 10) {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 10) {
                                // Live View's assist inspector preview, fed by this tile's sample bus.
                                AssistInspectorPreview(
                                    tool: .lut, pictureEffects: previewEffects(tile)
                                )
                                .accessibilityLabel("\(tile.camera?.name ?? "Camera") preview")
                                .environment(model)
                                .id(ObjectIdentifier(model))
                                .frame(maxWidth: previewWidth)
                                .frame(maxWidth: .infinity)
                                VStack(alignment: .leading, spacing: 10) {
                                    CapturePickerPanel(
                                        sheet: category,
                                        isPresented: {
                                            tile.controlsModel === model && selectedID == tile.id
                                        },
                                        controlsEnabled: session.controlsAvailable(for: tile)
                                            && categoryAvailable(category, model: model),
                                        chromeless: true, onClose: close
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                    .environment(model)
                                    .id(
                                        PanelIdentity(
                                            model: ObjectIdentifier(model), category: category,
                                            described: model.control.snapshot != nil))
                                    notes(tile: tile, model: model)
                                }
                                .onGeometryChange(for: CGFloat.self) {
                                    $0.size.height
                                } action: {
                                    controlsReserve = max(controlsReserve, $0)
                                }
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .monitorScrollFade()
                        .onGeometryChange(for: CGSize.self) {
                            $0.size
                        } action: {
                            column = $0
                        }
                        ScrollView(.vertical, showsIndicators: false) {
                            MonitorCaptureTabs(
                                options: categories(model), selection: category, title: title,
                                identifier: { "multiview.settings.control." + $0.rawValue },
                                vertical: true, minLength: railHeight
                            ) { category = $0 }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                        .monitorScrollFade()
                        .frame(width: 92)
                        .frame(maxHeight: .infinity)
                        // The rail's baseline spans the full content height.
                        .onGeometryChange(for: CGFloat.self) {
                            $0.size.height
                        } action: {
                            railHeight = $0
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .onChange(of: categories(model)) { _, choices in
                        if !choices.contains(category) { category = .iso }
                    }
                } else {
                    Text(
                        selected?.recovering == true
                            ? "Reconnect this camera before changing settings."
                            : "Waiting for camera controls…"
                    )
                    .font(MonitorTheme.font(12)).foregroundStyle(MonitorTheme.muted)
                    .padding(.vertical, 14)
                }
            }
        } footer: {
            // Recording stays on Record all and each tile's options.
            EmptyView()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("multiview.settings.panel")
        #if DEBUG
            .accessibilityValue(
                ProcessInfo.processInfo.environment["OPV_PHYSICAL_MULTIVIEW_PROBE"] == "1"
                    ? selected?.previewAccessibilityValue ?? "" : "")
        #endif
        .onAppear { select(initialTile) }
        .onDisappear { session.closeCameraSettings() }
        .onChange(of: cameras.map(\.id)) { _, _ in
            if selected == nil {
                if let next = cameras.first { select(next) } else { close() }
            }
        }
        .onChange(of: selected.map { session.controlsAvailable(for: $0) }) { _, ready in
            if ready == true, let selected, selected.controlsModel == nil { select(selected) }
        }
    }

    private func select(_ tile: MultiviewSession.Tile) {
        selectedID = tile.id
        category = .iso
        session.openCameraSettings(tile)
    }

    private var cameraTabs: some View {
        MonitorCaptureTabs(
            options: cameras.map(\.id), selection: selectedID,
            title: { id in
                guard let index = session.tiles.firstIndex(where: { $0.id == id }) else {
                    return "Camera"
                }
                return MultiviewTelemetryPresentation.letter(index) + " · "
                    + (session.tiles[index].camera?.name ?? "Camera")
            },
            identifier: { id in
                "multiview.settings.camera.\(session.tiles.firstIndex(where: { $0.id == id }) ?? 0)"
            },
            accessibilityValue: { id in
                guard let tile = cameras.first(where: { $0.id == id }) else { return "Unavailable" }
                return tile.recovering
                    ? "Reconnecting"
                    : session.controlsAvailable(for: tile) ? "Ready" : "Unavailable"
            },
            select: { id in
                if let tile = cameras.first(where: { $0.id == id }) { select(tile) }
            }
        )
    }

    /// 16:9 preview width from the measured column: full width when the tallest
    /// controls still fit below it, smaller on short (landscape) panels.
    private var previewWidth: CGFloat {
        let height = min(column.width * 9 / 16, column.height - controlsReserve - 10)
        return max(72, height) * 16 / 9
    }

    /// Compact status lines; they take space only while present.
    @ViewBuilder
    private func notes(tile: MultiviewSession.Tile, model: AppModel) -> some View {
        if !session.controlsAvailable(for: tile) {
            Text("Controls unavailable").font(MonitorTheme.font(11))
                .foregroundStyle(MonitorTheme.muted)
        } else if !categoryAvailable(category, model: model) {
            Text("Locked while recording").font(MonitorTheme.font(11))
                .foregroundStyle(MonitorTheme.muted)
        }
        if let note = model.session.controlNote {
            Text(note).font(MonitorTheme.font(11)).foregroundStyle(.orange)
                .accessibilityIdentifier("multiview.settings.error")
        }
    }

    /// The tile's own picture (color and Auto LUT), without scope or sample demand.
    private func previewEffects(_ tile: MultiviewSession.Tile) -> MonitorFrameEffects {
        var result = tile.effects
        result.inspectorSample = false
        return result
    }

    private func categories(_ model: AppModel) -> [CaptureSheet] {
        var result: [CaptureSheet] = [.iso, .shutter, .exposure, .wb]
        if model.session.supportsFocusMode { result.append(.focus) }
        if model.session.supportsAperture { result.append(.aperture) }
        result.append(.mode)
        if !model.session.status.isPhoto { result += [.resolution, .color, .audio] }
        return result
    }

    private func categoryAvailable(_ category: CaptureSheet, model: AppModel) -> Bool {
        !(model.session.status.isRecording && [.mode, .resolution, .color].contains(category))
    }

    private func title(_ category: CaptureSheet) -> String {
        switch category {
        case .wb: "WB"
        case .resolution: "Format"
        default: category.rawValue.capitalized
        }
    }
}
