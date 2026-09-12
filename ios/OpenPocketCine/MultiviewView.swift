import AVFoundation
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

struct MultiviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var session = MultiviewSession()
    @State private var adding: MultiviewSession.Tile?
    @State private var showNetwork = false
    @State private var passwordPrompt = false
    @State private var selectedCamera: FoundCamera?
    @State private var manualNetwork = false
    @State private var closing = false
    @State private var showLeave = false
    @State private var liveTile: MultiviewSession.Tile?
    @State private var clean = false
    @State private var orientation = InterfaceOrientationObserver()

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
                stageContent(viewport: viewport)
                    .ignoresSafeArea(passwordPrompt ? .keyboard : [])
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
                        if showNetwork {
                            MultiviewNetworkSetup(
                                session: session, passwordPrompt: $passwordPrompt,
                                cancel: {
                                    showNetwork = false
                                    if !session.networkConfigured {
                                        Task { if await session.closeStage() { dismiss() } }
                                    }
                                }, complete: { showNetwork = false })
                        } else if let tile = adding {
                            cameraPicker(tile)
                        }
                    }
                    .fullScreenCover(item: $liveTile, onDismiss: { session.closeLiveView() }) {
                        tile in
                        if let model = tile.liveModel {
                            LiveViewScreen().environment(model)
                                .onAppear { model.multiviewExit = { liveTile = nil } }
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
                        "Close Multiview and return cameras to their own Wi-Fi? Recording continues.",
                        isPresented: $showLeave, titleVisibility: .visible
                    ) {
                        Button("Close monitoring") {
                            Task { if await session.closeStage() { dismiss() } }
                        }
                    }
                    .onChange(of: scenePhase) { _, phase in
                        session.setApplicationActive(phase == .active)
                    }
                    .onChange(of: session.layout) { _, _ in session.persistStage() }
                    .onChange(of: session.focusedIndex) { _, _ in session.persistStage() }
                    .onAppear {
                        orientation.start()
                        session.start()
                        showNetwork = !session.networkConfigured
                    }
                    .onDisappear { orientation.stop() }
            }
            .ignoresSafeArea(.container)
        }
        .interactiveDismissDisabled()
    }

    private func stageContent(viewport: GeometryProxy) -> some View {
        let safe = OsmoCameraPageAdapter.safeArea(
            viewport.safeAreaInsets, window: windowGeometry.safeArea,
            portrait: viewport.size.height > viewport.size.width,
            orientation: orientation.orientation)
        let layout = session.layout.presentation(
            in: viewport.size,
            safeArea: .init(
                top: safe.top, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing),
            selected: session.focusedIndex)
        return ZStack(alignment: .topLeading) {
            MonitorTheme.canvas
            ForEach(Array(session.tiles.enumerated()), id: \.element.id) { index, tile in
                let frame = layout.tiles[index]
                tileView(tile, index: index, compact: frame.width < 200 || frame.height < 136)
                    .frame(width: frame.width, height: frame.height)
                    .clipped()
                    .contentShape(Rectangle())
                    .position(x: frame.midX, y: frame.midY)
            }
            if !clean {
                sessionControls(
                    horizontal: layout.sessionControlsHorizontal, cellSize: layout.controlCellSize
                )
                .frame(width: layout.sessionControls.width, height: layout.sessionControls.height)
                .position(
                    x: layout.sessionControls.midX,
                    y: layout.sessionControls.midY + windowGeometry.topControlInset)
                stageAssistPalette(
                    horizontal: layout.assistsHorizontal, cellSize: layout.controlCellSize
                )
                .frame(width: layout.assists.width, height: layout.assists.height)
                .position(x: layout.assists.midX, y: layout.assists.midY)
            }
            displayButton
                .frame(width: layout.display.width, height: layout.display.height)
                .position(x: layout.display.midX, y: layout.display.midY)
            recordAll(diameter: layout.record.width)
                .position(x: layout.record.midX, y: layout.record.midY)
        }
        .frame(width: viewport.size.width, height: viewport.size.height)
        .background(MonitorTheme.canvas)
    }

    private func sessionControls(horizontal: Bool, cellSize: CGFloat) -> some View {
        let content = Group {
            exitButton(size: cellSize)
            Button {
                session.layout = session.layout == .grid ? .centerStage : .grid
            } label: {
                (session.layout == .grid ? OpcIcon.layoutList : OpcIcon.layoutGrid)
                    .frame(width: cellSize * 0.46, height: cellSize * 0.46)
                    .frame(width: cellSize, height: cellSize)
                    .contentShape(Rectangle())
            }
            .contextMenu {
                Button("Shared Wi-Fi") { showNetwork = true }
                    .disabled(session.busy || session.connectingCameras)
            }
            .accessibilityLabel(session.layout == .grid ? "Show Center stage" : "Show 2 by 2 grid")
            .accessibilityValue(session.layout.rawValue)
            .accessibilityHint("Touch and hold for Shared Wi-Fi")
            .accessibilityIdentifier("multiview.layout")
        }
        return Group {
            if horizontal { HStack(spacing: 3) { content } } else { VStack(spacing: 3) { content } }
        }
        .padding(4)
        .monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .compact)
        .foregroundStyle(MonitorTheme.secondary)
        .buttonStyle(.plain)
    }

    private func stageAssistPalette(horizontal: Bool, cellSize: CGFloat) -> some View {
        let content = Group {
            Button {
                let enabled = !session.tiles.filter { $0.camera != nil }.allSatisfy(\.lutEnabled)
                for tile in session.tiles where tile.camera != nil && tile.lutEnabled != enabled {
                    tile.toggleLUT()
                }
                session.persistStage()
            } label: {
                VStack(spacing: 2) {
                    MonitorAssistIcon.lut.frame(width: 20, height: 20)
                    Text("LUT").font(MonitorTheme.font(7.5, weight: .semibold)).tracking(0.7)
                }
                .frame(width: cellSize, height: cellSize)
                .contentShape(Rectangle())
            }
            .foregroundStyle(
                session.tiles.contains { $0.camera != nil && $0.lutEnabled }
                    ? MonitorTheme.accent : MonitorTheme.secondary
            )
            .disabled(!session.tiles.contains { $0.camera != nil })
            .accessibilityLabel("Toggle Auto LUT for all cameras")
            Button {
                session.feedAspect = session.feedAspect == .fill ? .fit16x9 : .fill
                session.persistStage()
            } label: {
                VStack(spacing: 2) {
                    (session.feedAspect == .fill ? OpcIcon.minimize : OpcIcon.maximize)
                        .frame(width: 20, height: 20)
                    Text(session.feedAspect == .fill ? "FILL" : "FIT")
                        .font(MonitorTheme.font(7.5, weight: .semibold)).tracking(0.7)
                }
                .frame(width: cellSize, height: cellSize)
                .contentShape(Rectangle())
            }
            .foregroundStyle(MonitorTheme.secondary)
            .accessibilityLabel(
                session.feedAspect == .fill ? "Fit feed in frame" : "Fill frame with feed"
            )
            .accessibilityValue(session.feedAspect == .fill ? "Fill" : "Fit")
            .accessibilityIdentifier("multiview.fitFill")
        }
        return Group {
            if horizontal { HStack(spacing: 3) { content } } else { VStack(spacing: 3) { content } }
        }
        .padding(4)
        .monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .compact)
        .buttonStyle(.plain)
    }

    private var displayButton: some View {
        Button {
            clean.toggle()
        } label: {
            VStack(spacing: 4) {
                Text("DISP").font(MonitorTheme.font(12, weight: .bold)).tracking(0.4)
                HStack(spacing: 3) {
                    Capsule().fill(clean ? Color.white.opacity(0.28) : MonitorTheme.accent)
                    Capsule().fill(clean ? MonitorTheme.accent : Color.white.opacity(0.28))
                }.frame(width: 31, height: 3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .compact)
            .contentShape(Rectangle())
        }
        .foregroundStyle(clean ? .white : MonitorTheme.muted).buttonStyle(.plain)
        .accessibilityLabel("Change display mode").accessibilityValue(clean ? "Clean" : "Live")
        .accessibilityIdentifier("multiview.display")
    }

    private func tileView(_ tile: MultiviewSession.Tile, index: Int, compact: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius).fill(LiveDesign.surface)
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { tap in
                        guard tile.camera != nil else { return }
                        switch tap {
                        case .first:
                            if tile.controlHost != nil {
                                session.openLiveView(tile)
                                liveTile = tile
                            }
                        case .second:
                            session.focusedIndex = index
                            if compact { session.layout = .centerStage }
                        }
                    })
            if tile.camera != nil {
                if tile.liveModel == nil {
                    GeometryReader { picture in
                        let fill = session.feedAspect == .fill
                        let ratio = tile.decoder.pictureAspect
                        MultiviewVideoLayer(tile: tile)
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
                    .clipShape(RoundedRectangle(cornerRadius: LiveDesign.cornerRadius))
                    .allowsHitTesting(false)
                }
                if (!tile.hasPicture || tile.failureMessage != nil || tile.recovering) && !compact {
                    VStack(spacing: 10) {
                        if tile.failureMessage == nil && !tile.networkVerified { ProgressView() }
                        Text(tile.failureMessage ?? tile.status).font(.footnote)
                            .multilineTextAlignment(.center)
                        if tile.networkVerified && tile.camera?.hasMultiviewPreview == false {
                            Text("Remove this tile to enable Record all for your other cameras.")
                                .font(.caption).multilineTextAlignment(.center)
                        }
                        if tile.failureMessage != nil {
                            if !tile.experimentalNetwork && tile.identity == nil {
                                Button("Try experimental shared Wi-Fi") {
                                    Task { await session.tryExperimentalNetwork(tile) }
                                }.buttonStyle(.bordered).disabled(
                                    session.busy || tile.connecting || tile.recovering)
                            }
                            HStack {
                                Button("Reconnect") { Task { await session.reconnect(tile) } }
                                Button("Remove", role: .destructive) {
                                    Task { _ = await session.remove(tile) }
                                }
                            }.buttonStyle(.bordered).disabled(
                                session.busy || tile.connecting || tile.recovering)
                        }
                    }.padding().background(
                        .ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16)
                    ).padding()
                }
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tile.camera?.name ?? "Camera").font(
                                LiveType.text(13, weight: .semibold)
                            ).lineLimit(1)
                            if let timecode = tile.timecodeReadout {
                                Text("TC " + timecode)
                                    .font(
                                        .system(
                                            size: compact ? 9 : 11, weight: .medium,
                                            design: .monospaced)
                                    )
                                    .monospacedDigit().lineLimit(1)
                                    .accessibilityLabel("Timecode " + timecode)
                            }
                        }
                        Spacer()
                        if session.layout == .grid,
                            (1...2).contains(session.tiles.filter { $0.camera != nil }.count),
                            index == session.tiles.lastIndex(where: { $0.camera != nil }),
                            let empty = session.tiles.first(where: { $0.camera == nil })
                        {
                            Button {
                                adding = empty
                            } label: {
                                OpcIcon.circlePlus.frame(width: 22, height: 22)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.zcTapTarget).accessibilityLabel("Add camera")
                            .disabled(session.busy || session.groupRecordingBusy)
                        }
                        if !compact {
                            Button {
                                Task { _ = await session.remove(tile) }
                            } label: {
                                OpcIcon.x.frame(width: 20, height: 20)
                                    .frame(width: 44, height: 44).contentShape(Rectangle())
                                    .liveChromeCircle(interactive: true)
                            }
                            .buttonStyle(.zcTapTarget)
                            .accessibilityLabel("Remove camera preview")
                            .disabled(
                                session.busy || tile.connecting || session.groupRecordingBusy
                                    || tile.recordingBusy
                                    || closing)
                        }
                    }
                    .padding(8).shadow(color: .black.opacity(0.9), radius: 3, y: 1)
                    Spacer()
                    if !compact && tile.camera?.hasMultiviewPreview == true {
                        HStack(alignment: .bottom) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(settingsSummary(tile.settings)).font(
                                    .system(size: 10, weight: .semibold)
                                ).lineLimit(2)
                                Text(exposureSummary(tile.settings)).font(.system(size: 9))
                                    .lineLimit(2)
                                if let note = tile.recordingNote, note != "Recording",
                                    note != "Recording stopped",
                                    note != "Waiting for camera confirmation"
                                {
                                    Text(note).font(.caption2)
                                }
                                if tile.hasPicture && tile.status != "Live · Video mode" {
                                    Text(tile.status).font(.caption2)
                                }
                            }
                            .shadow(color: .black, radius: 3, y: 1)
                            Spacer(minLength: 3)
                            Button {
                                tile.toggleLUT()
                                session.persistStage()
                            } label: {
                                Text("LUT").font(LiveType.text(13, weight: .bold))
                                    .foregroundStyle(
                                        tile.lutEnabled ? LiveDesign.accent : LiveDesign.text
                                    )
                                    .frame(width: 48, height: 44)
                                    .contentShape(Rectangle())
                                    .liveChromeGlass(
                                        in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius),
                                        interactive: true)
                            }
                            .buttonStyle(.zcTapTarget)
                            .accessibilityLabel(
                                tile.lutEnabled ? "Disable Auto LUT" : "Enable Auto LUT"
                            )
                            .accessibilityValue(tile.lutCaption)
                            .help(tile.lutCaption)
                            Button {
                                Task { await session.toggleRecording(tile) }
                            } label: {
                                ZStack {
                                    Circle().fill(LiveDesign.chromePlate)
                                    if tile.recordingBusy {
                                        ProgressView().tint(.white)
                                    } else {
                                        (tile.recordingObservation?.active == true
                                            ? OpcIcon.square : OpcIcon.play)
                                            .frame(width: 20, height: 20)
                                            .foregroundStyle(
                                                tile.recordingObservation?.active == true
                                                    ? .red : .white)
                                    }
                                }.frame(width: 44, height: 44)
                                    .liveChromeCircle(interactive: true)
                            }
                            .buttonStyle(.zcTapTarget)
                            .accessibilityLabel(
                                tile.recordingObservation?.active == true
                                    ? "Stop recording" : "Start recording"
                            )
                            .disabled(
                                tile.recordingBusy || session.groupRecordingBusy || closing
                                    || !tile.recordingAvailable
                            )
                            .opacity(tile.recordingAvailable ? 1 : 0.4)
                        }.padding(8)
                    }

                }
                .opacity(clean ? 0 : 1)
                .allowsHitTesting(!clean)
                .accessibilityHidden(clean)
            } else {
                Button {
                    selectedCamera = nil
                    if session.networkConfigured { adding = tile } else { showNetwork = true }
                } label: {
                    VStack(spacing: 8) {
                        OpcIcon.circlePlus.frame(
                            width: compact ? 24 : 34, height: compact ? 24 : 34)
                        if !compact {
                            Text("Add camera").font(LiveType.text(16, weight: .semibold))
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.zcTapTarget)
                .accessibilityLabel("Add camera")
                .disabled(session.busy || session.groupRecordingBusy)
            }
        }
        .foregroundStyle(.white)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    tile.camera == nil
                        ? Color.white.opacity(0.1)
                        : index == session.focusedIndex
                            ? MonitorTheme.accent : Color.white.opacity(0.08),
                    lineWidth: index == session.focusedIndex && tile.camera != nil ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if tile.camera != nil, tile.recordingObservation?.active == true {
                LiveRecordingTally(cornerRadius: LiveDesign.cornerRadius)
                    .accessibilityHidden(true)
            }
        }
    }
    private func settingsSummary(_ settings: CameraStatus) -> String {
        let resolution = settings.videoResolution?.label ?? "—"
        let fps = settings.fps > 0 ? "\(settings.fps)p" : "—"
        return "\(resolution) · \(fps) · \(settings.colorMode?.label ?? "Color —")"
    }
    private func exposureSummary(_ settings: CameraStatus) -> String {
        let iso = settings.iso > 0 ? "\(settings.iso)" : "—"
        let shutter = settings.shutterDenom > 0 ? "1/\(settings.shutterDenom)" : "—"
        let wb = settings.whiteBalance.map { $0.mode == .auto ? "Auto" : "\($0.kelvin)K" } ?? "—"
        return "ISO \(iso) · \(shutter) · WB \(wb)"
    }
    private func exitButton(size: CGFloat) -> some View {
        Button {
            if session.tiles.contains(where: { $0.camera != nil }) {
                showLeave = true
            } else {
                Task { if await session.closeStage() { dismiss() } }
            }
        } label: {
            OpcIcon.x.frame(width: size * 0.46, height: size * 0.46).frame(
                width: size, height: size
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Close Multiview").disabled(session.busy || session.groupRecordingBusy)
    }
    private func recordAll(diameter: CGFloat) -> some View {
        Button {
            Task { await session.toggleAllRecording() }
        } label: {
            RecordLamp(
                diameter: diameter, recording: session.anyRecording
            )
            .overlay { if session.groupRecordingBusy { ProgressView().tint(.white) } }
        }.buttonStyle(.zcTapTarget).disabled(!session.canRecordTogether)
            .opacity(session.canRecordTogether || session.groupRecordingBusy ? 1 : 0.4)
            .accessibilityLabel(session.anyRecording ? "Stop all recording" : "Record all")
            .accessibilityIdentifier("multiview.recordAll")
    }
    private var availableCameras: [FoundCamera] {
        session.found.filter { camera in
            camera.appearsInMultiview
                && !session.tiles.contains { $0.camera?.id == camera.id }
        }
    }

    private func cameraPicker(_ tile: MultiviewSession.Tile) -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Add camera").font(LiveType.display(20))
                        Spacer()
                        Button("Cancel") {
                            adding = nil
                            selectedCamera = nil
                            session.releaseNetworkCamera()
                        }
                        .frame(minWidth: 64, minHeight: 44)
                        .contentShape(Rectangle())
                    }.padding(.horizontal, 20).padding(.top, 8)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(availableCameras) { camera in
                                Button {
                                    adding = nil
                                    Task {
                                        session.enqueueAdd(
                                            camera, to: tile,
                                            experimental: !camera.hasMultiviewPreview)
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(camera.name).lineLimit(2)
                                            if !camera.hasMultiviewPreview {
                                                Text(
                                                    "Try experimental shared Wi-Fi · Preview unavailable"
                                                )
                                                .font(LiveType.text(12)).foregroundStyle(
                                                    LiveDesign.muted)
                                            }
                                        }
                                        Spacer()
                                        (camera.hasMultiviewPreview ? OpcIcon.plus : OpcIcon.info)
                                            .frame(width: 20, height: 20)
                                    }
                                    .padding(.horizontal, 16).frame(minHeight: 52)
                                    .background(
                                        LiveDesign.glassBright,
                                        in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                                    )
                                    .contentShape(Rectangle())
                                }
                            }
                            if availableCameras.isEmpty {
                                HStack(spacing: 12) {
                                    ProgressView()
                                    Text("Looking for nearby cameras…")
                                }.frame(minHeight: 52)
                            }
                            Text(
                                "Each camera will join \(session.ssid). Approve on the camera if asked."
                            )
                            .font(LiveType.text(13)).foregroundStyle(LiveDesign.muted)
                            .padding(.top, 4)
                        }.padding(.horizontal, 20).padding(.bottom, 20)
                    }
                }
                .frame(
                    width: min(460, max(0, geometry.size.width - 32)),
                    height: min(
                        CGFloat(max(1, min(4, availableCameras.count))) * 60 + 140,
                        max(0, geometry.size.height - 24))
                )
                .liveChromeGlass(in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius))
                .shadow(radius: 24)
                .accessibilityIdentifier("multiview.cameraPicker")
            }
        }
        .font(LiveType.text(16)).foregroundStyle(LiveDesign.text)
        .tint(LiveDesign.accent).buttonStyle(.zcTapTarget)
    }

}

private struct MultiviewVideoLayer: UIViewRepresentable {
    let tile: MultiviewSession.Tile
    func makeUIView(context: Context) -> DisplayLayerView {
        let view = DisplayLayerView(tile.decoder.displayLayer)
        view.onReady = { [decoder = tile.decoder] in decoder.noteDisplayReady() }
        tile.decoder.invalidatePictureFlipPresentation()
        wire(view)
        return view
    }
    func updateUIView(_ view: DisplayLayerView, context: Context) { wire(view) }
    private func wire(_ view: DisplayLayerView) {
        tile.decoder.applyPictureMirror = { [weak view] mirrored in
            view?.setPictureMirrored(mirrored)
        }
        tile.decoder.assistMirror = false
        tile.decoder.poseViewFlip = tile.pose.poseViewFlip
        tile.decoder.processedFeed = view.ciFeed
        tile.decoder.sampleBus = tile.sampleBus
        if tile.decoder.effects != tile.effects { tile.decoder.effects = tile.effects }
        tile.decoder.adoptIncomingTransfer(tile.settings.monitorTransfer)
    }
}
