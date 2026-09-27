import MonitorUI
import OpenPocketViewCore
import SwiftUI

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
        tile.controlsModel = model
        let driver = tile.driver
        editor.multiviewControlAdmission = { [weak self, weak tile, weak editor, weak driver] in
            guard let self, let tile, let editor else { return false }
            return tile.controlsModel?.session === editor && tile.camera?.id == camera.id
                && tile.driver === driver && self.controlsAvailable(for: tile)
        }
        return model
    }

    func closeCameraSettings() {
        for tile in tiles { tile.retireControls() }
    }
}

struct MultiviewCameraSettings: View {
    let session: MultiviewSession
    let initialTile: MultiviewSession.Tile
    let maximumHeight: CGFloat
    let close: () -> Void
    @State private var selectedID: UUID?
    @State private var category: CaptureSheet = .iso
    private struct PanelIdentity: Hashable {
        let model: ObjectIdentifier
        let category: CaptureSheet
    }

    private var cameras: [MultiviewSession.Tile] { session.tiles.filter { $0.camera != nil } }
    private var selected: MultiviewSession.Tile? {
        cameras.first { $0.id == selectedID }
    }

    var body: some View {
        // A concrete root keeps editor cleanup tied to closing the popup, not
        // to the conditional picker content or its camera/category identity.
        VStack(spacing: 0) {
            if let tile = selected, let model = tile.controlsModel {
                CapturePickerPanel(
                    sheet: category, maximumHeight: maximumHeight,
                    bottomCornerRadius: 16, edge: .top,
                    isPresented: { tile.controlsModel === model && selectedID == tile.id },
                    prefixContent: AnyView(tabs(tile: tile, model: model)),
                    subtitleOverride: tile.camera?.name ?? "Camera settings",
                    controlsEnabled: session.controlsAvailable(for: tile)
                        && categoryAvailable(category, model: model),
                    onClose: close
                )
                .environment(model)
                .id(PanelIdentity(model: ObjectIdentifier(model), category: category))
                .onChange(of: categories(model)) { _, choices in
                    if !choices.contains(category) { category = .iso }
                }
            } else {
                MonitorCapturePanel(
                    title: "CAMERA SETTINGS", subtitle: selected?.status ?? "Camera unavailable",
                    maximumHeight: maximumHeight, bottomCornerRadius: 16, edge: .top, close: close
                ) {
                    cameraTabs
                    Text("Waiting for camera controls…")
                        .font(MonitorTheme.font(12)).foregroundStyle(MonitorTheme.muted)
                        .padding(.vertical, 14)
                }
            }
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

    private func tabs(tile: MultiviewSession.Tile, model: AppModel) -> some View {
        VStack(spacing: 4) {
            cameraTabs
            ScrollView(.horizontal, showsIndicators: false) {
                MonitorCaptureTabs(
                    options: categories(model), selection: category, title: title,
                    identifier: { "multiview.settings.control." + $0.rawValue }
                ) { category = $0 }
                .fixedSize(horizontal: true, vertical: false)
            }
            .monitorScrollFade(.horizontal)
            HStack {
                MultiviewRecordAction(
                    session: session, tile: tile,
                    confirmationEnabled: model.recordConfirmationEnabled
                ) {
                    Text(tile.recordingActive == true ? "Stop recording" : "Start recording")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("multiview.settings.record")
                .disabled(
                    !tile.recordingAvailable || tile.recordingBusy
                        || session.groupRecordingBusy || session.closing)
                Spacer(minLength: 8)
                if !session.controlsAvailable(for: tile) {
                    Text("Controls unavailable").foregroundStyle(MonitorTheme.muted)
                } else if !categoryAvailable(category, model: model) {
                    Text("Locked while recording").foregroundStyle(MonitorTheme.muted)
                }
            }
            .font(MonitorTheme.font(11)).padding(.vertical, 2)
            if let note = model.session.controlNote {
                Text(note).font(MonitorTheme.font(11)).foregroundStyle(.orange)
                    .accessibilityIdentifier("multiview.settings.error")
            }
            if let note = tile.recordingNote, note != "Recording", note != "Recording stopped" {
                Text(note).font(MonitorTheme.font(11)).foregroundStyle(.orange)
            }
        }
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
