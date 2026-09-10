import AVFoundation
import OpenPocketViewCore
import SwiftUI

struct MultiviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = MultiviewSession()
    @State private var adding: MultiviewSession.Tile?
    @State private var showNetwork = false
    @State private var passwordPrompt = false
    @State private var selectedCamera: FoundCamera?
    @State private var manualNetwork = false
    @State private var closing = false
    @State private var showLeave = false
    @State private var liveTile: MultiviewSession.Tile?

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
                        session.start()
                        showNetwork = !session.networkConfigured
                    }
            }
            .ignoresSafeArea(.container)
        }
        .interactiveDismissDisabled()
    }

    private func stageContent(viewport: GeometryProxy) -> some View {
        let landscape = viewport.size.width > viewport.size.height
        return VStack(spacing: 0) {
            GeometryReader { geometry in
                let frames = session.layout.frames(
                    in: geometry.size, selected: session.focusedIndex,
                    activeIndices: session.tiles.indices.filter {
                        session.tiles[$0].camera != nil
                    }, fill: session.feedAspect == .fill)
                ZStack {
                    ForEach(Array(session.tiles.enumerated()), id: \.element.id) {
                        index, tile in
                        let frame = frames[index]
                        if !frame.isEmpty {
                            tileView(
                                tile, index: index,
                                compact: frame.width < 200 || frame.height < 136
                            )
                            .frame(width: frame.width, height: frame.height)
                            .clipped()
                            .contentShape(Rectangle())
                            .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }
            }
            .padding(.top, landscape ? 0 : 48)
            .padding(.leading, landscape ? 48 : 0)
            .padding(.trailing, landscape ? LiveChromeMetrics.recordButtonSize + 16 : 0)
            bottomBar(landscape: landscape, showCount: viewport.size.width >= 360)
        }
        .overlay(alignment: .topLeading) { exitButton.padding(4) }
        .overlay(alignment: .bottomTrailing) {
            recordAll.padding(.trailing, 8).padding(.bottom, 4)
        }
        .padding(min(viewport.size.width, viewport.size.height) * 0.05)
        .background(Color.black.ignoresSafeArea())
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
                                width: fill ? max(picture.size.width, picture.size.height * ratio) : picture.size.width,
                                height: fill ? max(picture.size.height, picture.size.width / ratio) : picture.size.height)
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
                                    .font(.system(size: compact ? 9 : 11, weight: .medium, design: .monospaced))
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
                            Button { adding = empty } label: {
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
    private var exitButton: some View {
        Button {
            if session.tiles.contains(where: { $0.camera != nil }) {
                showLeave = true
            } else {
                Task { if await session.closeStage() { dismiss() } }
            }
        } label: {
            OpcIcon.x.frame(width: 22, height: 22).frame(width: 44, height: 44)
                .contentShape(Rectangle()).liveChromeCircle(interactive: true)
        }
        .buttonStyle(.zcTapTarget)
        .accessibilityLabel("Close Multiview").disabled(session.busy || session.groupRecordingBusy)
    }
    private var recordAll: some View {
        Button {
            Task { await session.toggleAllRecording() }
        } label: {
            RecordLamp(
                diameter: LiveChromeMetrics.recordButtonSize, recording: session.anyRecording
            )
            .overlay { if session.groupRecordingBusy { ProgressView().tint(.white) } }
        }.buttonStyle(.zcTapTarget).disabled(!session.canRecordTogether)
            .opacity(session.canRecordTogether || session.groupRecordingBusy ? 1 : 0.4)
            .accessibilityLabel(session.anyRecording ? "Stop all recording" : "Record all")
            .accessibilityIdentifier("multiview.recordAll")
    }
    private func bottomBar(landscape: Bool, showCount: Bool) -> some View {
        HStack(spacing: 0) {
            Menu {
                Picker("Layout", selection: $session.layout) {
                    ForEach(MultiviewLayout.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            } label: {
                stageBarLabel("LAYOUT", icon: "rectangle.split.2x2")
            }
            .buttonStyle(.zcTapTarget)
            .accessibilityLabel("Multiview layout")
            Button {
                showNetwork = true
            } label: {
                stageBarLabel("WI-FI", icon: "wifi")
            }
            .buttonStyle(.zcTapTarget)
            .accessibilityLabel("Shared Wi-Fi").disabled(session.busy || session.connectingCameras)
            LivePortraitAspectToggle(aspect: $session.feedAspect, showsLabel: true)
                .frame(width: 54, height: 50)
                .accessibilityIdentifier("multiview.fitFill")
                .onChange(of: session.feedAspect) { _, _ in session.persistStage() }
            Spacer(minLength: 0)
            if showCount {
                Text("\(session.tiles.filter { $0.hasPicture }.count)/4").font(
                    LiveType.text(13, weight: .medium)
                )
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: LiveDesign.controlHeight)
        .liveChromeGlass(in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius))
        .padding(.leading, 8)
        .padding(.trailing, LiveChromeMetrics.recordButtonSize + 24)
        .padding(.bottom, 4)
        .frame(
            height: landscape
                ? LiveDesign.controlHeight + 8 : LiveChromeMetrics.recordButtonSize + 8,
            alignment: .bottom
        )
        .foregroundStyle(LiveDesign.text)
    }

    private func stageBarLabel(_ title: String, icon: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 20, weight: .medium))
            Text(title).font(LiveType.text(11, weight: .semibold))
        }
        .frame(minWidth: 54, minHeight: 50)
        .contentShape(Rectangle())
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
                                        Image(
                                            systemName: camera.hasMultiviewPreview
                                                ? "plus" : "info.circle")
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
