import AVFoundation
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

struct MultiviewView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var session: MultiviewSession
    private let startsSession: Bool
    private let reviewPictures: Bool
    @State private var adding: MultiviewSession.Tile?
    @State private var showNetwork = false
    @State private var selectedCamera: FoundCamera?
    @State private var optionsTile: MultiviewSession.Tile?
    @State private var showLeave = false
    @State private var liveTile: MultiviewSession.Tile?
    @State private var settingsTile: MultiviewSession.Tile?
    @State private var clean = false
    @State private var toolsExpanded = false
    @State private var toolUsage = MonitorToolUsage()
    @State private var stageGeometry = MultiviewStageGeometry()
    @State private var orientation = InterfaceOrientationObserver()

    init(session: MultiviewSession? = nil, startsSession: Bool = true, reviewPictures: Bool = false)
    {
        #if DEBUG
            if session == nil, let fixture = MultiviewUIReview.sessionFromEnvironment() {
                _session = State(initialValue: fixture)
                self.startsSession = false
                self.reviewPictures = true
                return
            }
        #endif
        _session = State(initialValue: session ?? MultiviewSession())
        self.startsSession = startsSession
        self.reviewPictures = reviewPictures
    }

    var body: some View {
        NavigationStack {
            GeometryReader { viewport in
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
                        if phase != .active { closePopups() }
                        if startsSession { session.setApplicationActive(phase == .active) }
                    }
                    .onReceive(
                        NotificationCenter.default.publisher(
                            for: UIApplication.willResignActiveNotification)
                    ) { _ in
                        closePopups()
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
                        orientation.start()
                        if startsSession { session.start() }
                        showNetwork = !session.networkConfigured
                    }
                    .onDisappear {
                        orientation.stop()
                        closePopups()
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

    private func stageContent(viewport: GeometryProxy) -> some View {
        let safe = OsmoCameraPageAdapter.safeArea(
            viewport.safeAreaInsets, window: windowGeometry.safeArea,
            portrait: viewport.size.height > viewport.size.width,
            orientation: orientation.orientation)
        let layout = session.layout.presentation(
            in: viewport.size,
            safeArea: .init(
                top: safe.top, leading: safe.leading, bottom: safe.bottom, trailing: safe.trailing),
            selected: session.focusedIndex, topControlInset: windowGeometry.topControlInset)
        return ZStack(alignment: .topLeading) {
            MonitorTheme.canvas
            MultiviewStageCanvas(
                ids: session.tiles.map(\.id), layout: layout, geometry: stageGeometry
            ) { index in
                let frame = layout.tiles[index]
                let overlay = layout.readoutsOverlay && index == session.focusedIndex
                tileView(
                    session.tiles[index], index: index,
                    compact: frame.width < 200 || frame.height < 136,
                    condensed: frame.height < 80,
                    readoutInset: 0,  // stage info sits inline with the camera values row
                    // Grid's selected tile carries its values between the footer columns.
                    inlineValues: overlay && session.layout == .grid,
                    // The floating View Assist palette covers the main tile's lower
                    // left; its footer starts where the stage value row does.
                    footerLeading: overlay ? layout.readouts.x - frame.x : 0)
            }
            if !clean {
                exitButton(size: layout.sessionControls.width)
                    .frame(
                        width: layout.sessionControls.width, height: layout.sessionControls.height
                    )
                    .position(
                        x: layout.sessionControls.midX,
                        y: layout.sessionControls.midY)
                stageAssistPalette(layout: layout)
                networkButton(size: layout.network.width)
                    .frame(width: layout.network.width, height: layout.network.height)
                    .position(x: layout.network.midX, y: layout.network.midY)
                if session.layout == .centerStage {
                    selectedReadouts
                        .frame(width: layout.readouts.width, height: layout.readouts.height)
                        .position(x: layout.readouts.midX, y: layout.readouts.midY)
                }
            }
            displayButton
                .frame(width: layout.display.width, height: layout.display.height)
                .position(x: layout.display.midX, y: layout.display.midY)
            recordAll(diameter: layout.record.width)
                .position(x: layout.record.midX, y: layout.record.midY)
        }
        .frame(width: viewport.size.width, height: viewport.size.height)
        .background(MonitorTheme.canvas)
        .monitorVideoBackdrop(
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
            enabled: liveTile == nil && !showNetwork && adding == nil && !session.closing
        ) { _ in
            session.tiles.enumerated().compactMap { index, tile in
                guard tile.liveModel == nil, tile.camera != nil,
                    let buffer = tile.decoder.backdropSource
                else { return nil }
                guard let placement = stageGeometry.placement(index) else { return nil }
                let rect = placement.frame
                let effects = tile.decoder.backdropEffects
                return MonitorVideoBackdropSource(
                    buffer: buffer, effects: effects,
                    frame: MonitorVideoBackdropSource.displayedFrame(
                        sourceAspect: tile.decoder.pictureAspect, effects: effects, in: rect,
                        fill: session.feedAspect == .fill),
                    clip: placement.clip)
            }
        }
        .overlay { floatingPopups(viewport: viewport.size, safe: safe) }
    }

    private func closePopups() {
        optionsTile = nil
        settingsTile = nil
        session.closeCameraSettings()
    }

    @ViewBuilder
    private func floatingPopups(viewport: CGSize, safe: EdgeInsets) -> some View {
        if let tile = optionsTile {
            let width = max(1, viewport.width - safe.leading - safe.trailing - 32)
            let height = max(1, viewport.height - safe.top - safe.bottom - 32)
            ZStack {
                Color.black.opacity(0.18).contentShape(Rectangle())
                    .onTapGesture { closePopups() }
                    .accessibilityLabel("Dismiss camera panel")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("multiview.popup.dismiss")
                MultiviewCameraOptions(
                    session: session, tile: tile, maximumHeight: min(520, height),
                    close: closePopups
                ) { openLiveView(tile) }
                .frame(width: min(440, width))
                .position(
                    x: safe.leading + (viewport.width - safe.leading - safe.trailing) / 2,
                    y: safe.top + (viewport.height - safe.top - safe.bottom) / 2)
            }
            .accessibilityAddTraits(.isModal)
            .preferredColorScheme(.dark)
        } else if let tile = settingsTile {
            // Same trailing side panel as Live View's gimbal controls.
            MultiviewCameraSettings(
                session: session, initialTile: tile, viewport: viewport, safeArea: safe,
                close: closePopups
            )
            .accessibilityAddTraits(.isModal)
            .preferredColorScheme(.dark)
        }
    }

    private var selectedReadouts: some View {
        let tile = session.tiles[min(3, max(0, session.focusedIndex))]
        let values = MultiviewTelemetryPresentation(settings: tile.settings)
        return HStack(spacing: 6) {
            readout("ISO", value: values.iso)
            readout("SHUTTER", value: values.shutter)
            readout("WB", value: values.whiteBalance)
            readout("FOCUS", value: values.focus)
        }
        .frame(maxWidth: 316)
        .opacity(tile.camera == nil ? 0 : 1)
        .accessibilityHidden(tile.camera == nil)
        .accessibilityIdentifier("multiview.readouts")
    }

    private func readout(_ title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value).font(MonitorTheme.font(14, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(MonitorTheme.font(7, weight: .semibold))
                .tracking(0.8).foregroundStyle(MonitorTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + " " + value)
    }

    @ViewBuilder
    private func stageAssistPalette(layout: MultiviewPresentationLayout) -> some View {
        if layout.portrait && session.layout == .centerStage {
            stageToolColumn(frame: layout.assists, tablet: layout.tablet)
        } else {
            stageCollapsiblePalette(layout: layout)
        }
    }

    private var stageTools: [MonitorToolItem] {
        let cameras = session.tiles.contains { $0.camera != nil }
        return [
            .init(
                id: "LAYOUT", title: session.layout == .grid ? "FOCUS" : "GRID", enabled: false,
                hasOptions: false,
                accessibilityLabel: session.layout == .grid ? "Show Center stage" : "Show grid",
                accessibilityValue: session.layout.displayName,
                accessibilityIdentifier: "multiview.layout"),
            .init(
                id: "CAMERA", title: "CAMERA", enabled: false, hasOptions: false,
                available: cameras,
                accessibilityLabel: "Camera settings", accessibilityValue: "",
                accessibilityIdentifier: "multiview.settings"),
            .init(
                id: "FIT", title: session.feedAspect == .fill ? "FILL" : "FIT", enabled: false,
                hasOptions: false,
                accessibilityLabel: session.feedAspect == .fill
                    ? "Fit feed in frame" : "Fill frame with feed",
                accessibilityValue: session.feedAspect == .fill ? "Fill" : "Fit",
                accessibilityIdentifier: "multiview.fitFill"),
            .init(
                id: "LUT", title: "LUT",
                enabled: session.tiles.contains { $0.camera != nil && $0.lutEnabled },
                hasOptions: false, available: cameras,
                accessibilityLabel: "Toggle Auto LUT for all cameras"),
        ]
    }

    @ViewBuilder
    private func stageToolIcon(_ id: String) -> some View {
        switch id {
        case "LUT": MonitorAssistIcon.lut
        case "FIT": session.feedAspect == .fill ? OpcIcon.minimize : OpcIcon.maximize
        case "LAYOUT": session.layout == .grid ? OpcIcon.layoutList : OpcIcon.layoutGrid
        default: OpcIcon.slidersHorizontal  // camera settings
        }
    }

    /// Portrait Center stage: the same tools as a plain, always-visible column
    /// spanning the secondary feeds. No chevron, drag or collapse.
    private func stageToolColumn(frame: MonitorRect, tablet: Bool) -> some View {
        let iconSide = MonitorSystemButtonMetrics.iconSide(tablet: tablet)
        return VStack(spacing: 0) {
            ForEach(stageTools) { tool in
                Button {
                    activateTool(tool.id)
                } label: {
                    stageToolIcon(tool.id)
                        .frame(width: iconSide, height: iconSide)
                        .foregroundStyle(tool.enabled ? MonitorTheme.accent : MonitorTheme.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(MonitorButtonStyle())
                .disabled(!tool.available)
                .opacity(tool.available ? 1 : 0.4)
                .accessibilityLabel(tool.accessibilityLabel ?? tool.title)
                .accessibilityValue(tool.accessibilityValue ?? (tool.enabled ? "On" : "Off"))
                .accessibilityIdentifier(tool.accessibilityIdentifier ?? "multiview.tool.\(tool.id)")
            }
        }
        .padding(4)
        .frame(width: frame.width, height: frame.height)
        .monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .compact)
        .position(x: frame.midX, y: frame.midY)
    }

    private func stageCollapsiblePalette(layout: MultiviewPresentationLayout) -> some View {
        let tools = stageTools
        // Landscape stages mount Live View's palette as Live View does:
        // horizontal, anchored at its collapsed bottom-leading slot, growing
        // trailing short of DISP. Portrait Grid keeps the vertical rail.
        let horizontal = layout.assistsHorizontal
        let palette = MonitorAssistPaletteLayout(
            portrait: !horizontal, tablet: layout.tablet, expanded: true, toolCount: tools.count,
            maximumWidth: horizontal
                ? layout.display.x - 8 - layout.assists.x : layout.assists.width,
            maximumHeight: horizontal
                ? layout.assists.maxY - max(layout.sessionControls.y, 8) : layout.assists.height)
        let frame = palette.anchored(leading: layout.assists.x, bottom: layout.assists.maxY)
        return MonitorAssistPalette(
            tools: tools, layout: palette,
            usageSeed: ["LAYOUT": 4, "CAMERA": 3, "FIT": 2, "LUT": 1],
            usage: $toolUsage, expanded: $toolsExpanded, onToggle: activateTool,
            onOptions: { _ in },
            accessibilityName: "Multiview tools", accessibilityPrefix: "multiview.toolbar"
        ) { id in
            stageToolIcon(id)
        }
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
    }

    private func activateTool(_ id: String) {
        switch id {
        case "LUT":
            let enabled = !session.tiles.filter { $0.camera != nil }.allSatisfy(\.lutEnabled)
            for tile in session.tiles where tile.camera != nil && tile.lutEnabled != enabled {
                tile.toggleLUT()
            }
            session.persistStage()
        case "FIT":
            session.feedAspect = session.feedAspect == .fill ? .fit16x9 : .fill
            session.persistStage()
        case "LAYOUT": session.layout = session.layout == .grid ? .centerStage : .grid
        case "CAMERA":
            optionsTile = nil
            settingsTile =
                session.tiles.first {
                    $0.id == session.tiles[session.focusedIndex].id && $0.camera != nil
                }
                ?? session.tiles.first { $0.camera != nil }
        default: break
        }
    }

    private func networkButton(size: CGFloat) -> some View {
        MonitorChromeButton("Shared Wi-Fi", size: CGSize(width: size, height: size)) {
            closePopups()
            showNetwork = true
        } label: {
            OpcIcon.wifi.frame(width: size * 29 / 54, height: size * 29 / 54)
        }
        .disabled(session.busy || session.connectingCameras || !startsSession)
        .accessibilityLabel("Shared Wi-Fi")
        .accessibilityValue(session.ssid)
        .accessibilityIdentifier("multiview.network")
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

    /// Center stage offers "Add camera" on the big tile while it is empty;
    /// otherwise on the first empty tile.
    private var addCameraTileID: UUID? {
        let tiles = session.tiles
        if session.layout == .centerStage, tiles.indices.contains(session.focusedIndex),
            tiles[session.focusedIndex].camera == nil
        {
            return tiles[session.focusedIndex].id
        }
        return tiles.first(where: { $0.camera == nil })?.id
    }

    private func tileView(
        _ tile: MultiviewSession.Tile, index: Int, compact: Bool, condensed: Bool,
        readoutInset: CGFloat = 0, inlineValues: Bool = false, footerLeading: CGFloat = 0
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(LiveDesign.surface)
            if tile.camera != nil {
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
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
                }
                #if DEBUG
                    if reviewPictures {
                        MultiviewUIReviewPicture(index: index, fill: session.feedAspect == .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
                #endif
                // This hit surface stays beneath the options button. Neither selecting a
                // camera nor rearranging the stage replaces its video host or decoder.
                Color.clear.contentShape(Rectangle())
                    .gesture(
                        TapGesture(count: 2).exclusively(before: TapGesture()).onEnded { tap in
                            switch tap {
                            case .first: openLiveView(tile)
                            case .second: session.focusedIndex = index
                            }
                        }
                    )
                    .accessibilityElement()
                    .accessibilityLabel(
                        "Select camera " + MultiviewTelemetryPresentation.letter(index)
                    )
                    .accessibilityValue(
                        (index == session.focusedIndex ? "Selected; " : "")
                            + tile.previewAccessibilityValue
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { session.focusedIndex = index }
                    .accessibilityIdentifier("multiview.tile.\(index)")
                if !clean {
                    MultiviewTileChrome(
                        tile: tile, index: index, selected: index == session.focusedIndex,
                        compact: compact, condensed: condensed, reservedBottom: readoutInset,
                        reservedLeading: footerLeading, inlineValues: inlineValues
                    ) {
                        closePopups()
                        optionsTile = tile
                    }
                }
                if !tile.hasPicture || tile.failureMessage != nil || tile.recovering {
                    tileRecovery(tile, compact: compact)
                }
            } else if !clean, addCameraTileID == tile.id {
                Button {
                    selectedCamera = nil
                    if session.networkConfigured { adding = tile } else { showNetwork = true }
                } label: {
                    HStack(spacing: 9) {
                        OpcIcon.plus.frame(width: 23, height: 23)
                        Text("Add camera").font(MonitorTheme.font(12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(MonitorTheme.muted)
                .accessibilityLabel("Add camera")
                .accessibilityIdentifier("multiview.add")
                .disabled(session.busy || session.groupRecordingBusy)
            }
        }
        .foregroundStyle(.white)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    tile.camera == nil
                        ? Color.white.opacity(0.08)
                        : index == session.focusedIndex && !clean
                            ? MonitorTheme.accent : Color.white.opacity(0.08),
                    lineWidth: index == session.focusedIndex && tile.camera != nil && !clean ? 2 : 1
                )
                .allowsHitTesting(false)
        }
        .overlay {
            if tile.camera != nil, tile.recordingActive == true {
                LiveRecordingTally(cornerRadius: 12).accessibilityHidden(true)
            }
        }
    }

    private func tileRecovery(_ tile: MultiviewSession.Tile, compact: Bool) -> some View {
        Button {
            optionsTile = tile
        } label: {
            HStack(spacing: 5) {
                if tile.recovering || (tile.failureMessage == nil && !tile.networkVerified) {
                    ProgressView().controlSize(.mini)
                }
                Text(
                    tile.recovering
                        ? "Restoring picture…"
                        : tile.failureMessage == nil
                            ? tile.status : "Connection failed · Options"
                )
                .font(MonitorTheme.font(compact ? 9 : 12, weight: .medium))
                .lineLimit(2).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).padding(.horizontal, 8)
        .accessibilityLabel(tile.failureMessage ?? tile.status)
        .accessibilityHint("Open camera options for details and recovery")
    }

    private func openLiveView(_ tile: MultiviewSession.Tile) {
        closePopups()
        guard tile.controlHost != nil, !tile.recovering else { return }
        session.openLiveView(tile)
        if tile.liveModel != nil { liveTile = tile }
    }

    private func exitButton(size: CGFloat) -> some View {
        MonitorChromeButton("Close Multiview", size: CGSize(width: size, height: size)) {
            if session.tiles.contains(where: { $0.camera != nil }) {
                showLeave = true
            } else {
                Task { if await session.closeStage() { dismiss() } }
            }
        } label: {
            OpcIcon.x.frame(width: size * 26 / 54, height: size * 26 / 54)
        }
        .accessibilityIdentifier("multiview.close")
        .accessibilityLabel("Close Multiview").disabled(session.busy || session.groupRecordingBusy)
    }
    private func recordAll(diameter: CGFloat) -> some View {
        MultiviewRecordAction(
            session: session, confirmationEnabled: model.recordConfirmationEnabled
        ) {
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
                    .monitorScrollFade()
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
        tile.decoder.sampleBus = tile.sampleBus
        tile.decoder.hdrDisplayEnabled = hdrDisplay
        view.applyHDRDisplay(hdrDisplay)
        if tile.decoder.effects != tile.effects { tile.decoder.effects = tile.effects }
        tile.decoder.adoptIncomingTransfer(tile.settings.monitorTransfer)
    }
}
