import OpenPocketViewCore
import SwiftUI

/// Live HEVC feed with OpenZCine landscape chrome. Video and chrome are **siblings**:
/// the feed is an explicit 16:9 well; chrome is a physical-screen overlay (`ignoresSafeArea`).
/// `VideoView` is never wrapped in a `GeometryReader` and does not host rails or decks.
struct LiveViewScreen: View {
    @Environment(AppModel.self) private var model
    @State private var interfaceLocked = false
    @State private var orientationObserver = InterfaceOrientationObserver()
    @State private var topMenu: LiveTopMenu?
    @State private var topPickerFrames: [LiveTopMenu: CGRect] = [:]
    @State private var captureTileFrames: [CaptureSheet: CGRect] = [:]
    @State private var assistIconFrames: [LiveAssistTool: CGRect] = [:]

    /// OpenZCine `DisplayChromeVisibility.cleanDefaults`: status + strips + lock off;
    /// batteries, rail (DISP / record / media / settings) stay. Lock remounts while locked.
    private var editingMode: PocketDispMode? { model.chromeEditorMode }
    private var chromeInteractive: Bool { !model.isEditingChrome }
    private var showsStatusBar: Bool { model.chromeSectionMounts(.statusBar) }
    private var showsBottomBars: Bool {
        model.chromeSectionMounts(.toolBar) || model.chromeSectionMounts(.cameraValues)
    }
    private var showsLock: Bool { model.chromeSectionMounts(.lockButton) || interfaceLocked }
    private var showsBatteries: Bool { model.chromeSectionMounts(.batteries) }

    var body: some View {
        GeometryReader { proxy in
            let _: Void = {
                LiveChromeMetrics.scale = LiveChromeMetrics.chromeScale(
                    shortestSide: min(proxy.size.width, proxy.size.height))
            }()
            let safeArea = LiveMonitorLayout.resolvedSafeArea(
                proxy.safeAreaInsets, scene: LiveMonitorLayout.sceneSafeArea)
            let base = LiveMonitorLayout.fit(
                layoutSize: proxy.size,
                safeArea: safeArea,
                screenSize: LiveMonitorLayout.sceneSize,
                showsBottomBars: showsBottomBars,
                feedAspect: LiveChromeMetrics.feedAspect,
                pictureAspect: model.session.decoder.pictureAspect,
                orientation: orientationObserver.orientation
            )
            let resolved = Self.resolvePortrait(base, model: model)
            let layout = resolved.layout
            Color.clear
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    canvas(layout, portrait: resolved.zones)
                        .frame(
                            width: layout.viewport.width,
                            height: layout.viewport.height,
                            alignment: .topLeading
                        )
                }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        // Field-monitor HUD is pinned dark. `preferredColorScheme` restyles the scene
        // (and its sheets); this pins the in-canvas environment synchronously so
        // semantic styles (`.secondary`, checkmarks, vibrancy) can never resolve light
        // no matter what the system appearance or the feed behind the chrome does.
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.22), value: orientationObserver.orientation)
        .animation(.easeInOut(duration: 0.18), value: model.assist.clean)
        .animation(.easeOut(duration: 0.10), value: model.liveOperatorPanel)
        .animation(.easeOut(duration: 0.16), value: model.chromeEditorMode)
        .animation(.easeOut(duration: 0.20), value: model.session.isFocusResetAvailable)
        .animation(.easeOut(duration: 0.22), value: model.session.isFeedWarming)
        .onAppear {
            let app = model
            orientationObserver.start()
            model.session.decoder.attach(
                sampleBus: app.frameSamples,
                effects: { [weak app] in
                    guard let app else { return LiveImageEffects() }
                    return app.assist.effects.withFaceAF(app.session.wantsFaceAF)
                },
                transfer: { [weak app] in app?.session.status.monitorTransfer }
            )
            #if targetEnvironment(simulator)
                model.session.status.colorMode = .dLog2
            #endif
            model.assist.syncLUT(
                to: model.session.status.colorMode,
                family: model.session.bodyFamily,
                cameraName: model.session.connectedCamera?.model.name)
            model.session.decoder.startSimulatorSampleIfNeeded()
            model.session.isLocked = interfaceLocked
        }
        .onDisappear {
            model.session.decoder.stopSimulatorSample()
        }
        .onChange(of: interfaceLocked) { _, locked in
            model.session.isLocked = locked
        }
        .onChange(of: model.assist.clean) { _, clean in
            if clean {
                topMenu = nil
                model.captureSheet = nil
                model.assist.configureTool = nil
            }
        }
        .onChange(of: model.chromeEditorMode) { _, mode in
            if mode != nil {
                topMenu = nil
                model.captureSheet = nil
                model.assist.configureTool = nil
            }
        }
        .sheet(isPresented: Bindable(model.assist).showLUTPicker) {
            LUTPicker(assist: model.assist)
        }
    }

    private static func portraitChoice(model: AppModel) -> (
        vertical: Bool, aspect: PortraitFeedAspect, ratio: Double, fill: Bool
    ) {
        let vertical = model.session.decoder.isVerticalPicture
        let aspect: PortraitFeedAspect = vertical ? .fill : model.portraitFeedAspect
        let ratio = vertical ? 9.0 / 16.0 : 16.0 / 9.0
        return (vertical, aspect, ratio, aspect == .fill)
    }

    private static func resolvePortrait(_ base: LiveMonitorLayout, model: AppModel) -> (
        layout: LiveMonitorLayout, zones: MonitorPortraitZones?
    ) {
        guard base.viewport.height > base.viewport.width else { return (base, nil) }
        let choice = portraitChoice(model: model)
        let mode: MonitorPortraitDispMode = model.assist.clean ? .clean : .live
        let toolbar =
            mode == .live && !choice.fill && model.chromeSectionMounts(.toolBar)
            ? MonitorPortraitLayout.assistToolbarHeight : 0
        let zones = MonitorPortraitLayout.zones(
            viewportWidth: Double(base.viewport.width),
            viewportHeight: Double(base.viewport.height),
            safeArea: MonitorEdgeInsets(
                top: Double(base.safeArea.top),
                leading: Double(base.safeArea.leading),
                bottom: Double(base.safeArea.bottom),
                trailing: Double(base.safeArea.trailing)
            ),
            mode: mode,
            aspect: choice.aspect,
            scopeCount: 0,
            assistToolbarHeight: toolbar,
            feedAspectRatio: choice.ratio
        )
        var next = base
        let well = CGRect(
            x: zones.feed.x, y: zones.feed.y, width: zones.feed.width, height: zones.feed.height)
        next.feed = well
        next.topDeck = CGRect(
            x: zones.topBar.x, y: zones.topBar.y, width: zones.topBar.width,
            height: zones.topBar.height)
        next.assist = CGRect(
            x: zones.assistToolbar.x, y: zones.assistToolbar.y,
            width: zones.assistToolbar.width, height: zones.assistToolbar.height)
        next.capture = CGRect(
            x: zones.controls.x, y: zones.controls.y, width: zones.controls.width,
            height: zones.controls.height)
        // Vertical fill: 9:16 pillarbox in the fill frame. Landscape fill: the
        // well itself (16:9 is then over-widened at draw time).
        if choice.vertical, well.height > 1 {
            let width = well.height * 9 / 16
            next.picture = CGRect(
                x: well.midX - width / 2, y: well.minY, width: width, height: well.height)
        } else {
            next.picture = well
        }
        return (next, zones)
    }

    @ViewBuilder
    private func canvas(_ layout: LiveMonitorLayout, portrait: MonitorPortraitZones?) -> some View {
        ZStack(alignment: .topLeading) {
            LiveDesign.background

            // Feed well is true black — darker than the `#141414` canvas — matching
            // OpenZCine's empty-monitor plate. Chrome sits on the canvas around it.
            let fillCrop =
                portrait != nil
                && Self.portraitChoice(model: model).fill
                && !model.session.decoder.isVerticalPicture
            let feedContentWidth =
                fillCrop ? layout.feed.height * 16 / 9 : layout.onFeed.width

            Color.black
                .frame(width: layout.feed.width, height: layout.feed.height)
                .position(x: layout.feed.midX, y: layout.feed.midY)
                .allowsHitTesting(false)

            LiveFeedPane()
                .frame(width: feedContentWidth, height: layout.onFeed.height)
                .frame(width: layout.onFeed.width, height: layout.onFeed.height)
                .clipped()
                .position(x: layout.onFeed.midX, y: layout.onFeed.midY)
                .opacity(model.session.isFeedWarming ? 0 : 1)

            LiveFeedAssistsPane()
                .frame(width: feedContentWidth, height: layout.onFeed.height)
                .frame(width: layout.onFeed.width, height: layout.onFeed.height)
                .clipped()
                .position(x: layout.onFeed.midX, y: layout.onFeed.midY)
                .opacity(model.session.isFeedWarming ? 0 : 1)
                .allowsHitTesting(false)

            // Always mounted so the first paint is the waiting plate — an
            // insert fade used to flash the leftover IDR underneath.
            ZStack(alignment: .topLeading) {
                LiveFeedWarmupCover()
                    .frame(width: layout.onFeed.width, height: layout.onFeed.height)
                    .offset(x: layout.onFeed.minX, y: layout.onFeed.minY)
            }
            .frame(
                width: layout.viewport.width,
                height: layout.viewport.height,
                alignment: .topLeading
            )
            .clipped()
            .opacity(model.session.isFeedWarming ? 1 : 0)
            .allowsHitTesting(false)

            if let portrait {
                portraitChrome(layout, zones: portrait)
                    .environment(\.interfaceLocked, interfaceLocked)
                    .allowsHitTesting(chromeInteractive && model.liveChromeInteractive)
            } else {
                chrome(layout)
                    .environment(\.interfaceLocked, interfaceLocked)
                    .allowsHitTesting(chromeInteractive && model.liveChromeInteractive)
            }

            // After chrome so the bezel stroke sits on the physical screen, not the feed well.
            LiveRecordingTallyGate()
                .frame(width: layout.viewport.width, height: layout.viewport.height)

            popups(layout)
                .zIndex(10)

            if let panel = model.liveOperatorPanel, !model.isEditingChrome {
                operatorPanelCover(panel, layout: layout)
                    .transition(.opacity)
                    .zIndex(20)
            }

            if model.session.sessionRecovery.isRecovering {
                MonitorRecoveryOverlay()
                    .frame(width: layout.viewport.width, height: layout.viewport.height)
                    .zIndex(30)
                    .animation(.easeOut(duration: 0.2), value: model.session.sessionRecovery)
            }
        }
        .coordinateSpace(name: LiveCanvasSpace.name)
        .onPreferenceChange(LiveTopPickerFramesKey.self) { topPickerFrames = $0 }
        .onPreferenceChange(LiveCaptureTileFramesKey.self) { captureTileFrames = $0 }
        .onPreferenceChange(AssistIconFrameKey.self) { frames in
            assistIconFrames = frames
            if let tool = model.assist.configureTool, let frame = frames[tool], frame.width > 1 {
                model.assist.longPressAnchor = frame
            }
        }
        .overlayPreferenceValue(ChromeEditBoundsKey.self) { boxes in
            if let mode = editingMode {
                ChromeEditBadgeLayer(mode: mode, boxes: boxes, viewport: layout.viewport)
                    .frame(
                        width: layout.viewport.width,
                        height: layout.viewport.height,
                        alignment: .topLeading
                    )
                    .environment(\.colorScheme, .dark)
            }
        }
        .overlay {
            if let mode = editingMode {
                ChromeEditBanner(mode: mode)
                    .position(x: layout.feed.midX, y: chromeEditBannerY(layout))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(40)
            }
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    private func chromeEditBannerY(_ layout: LiveMonitorLayout) -> CGFloat {
        let floor =
            showsBottomBars
            ? min(layout.assist.minY, layout.capture.minY)
            : layout.feed.maxY
        return floor - 28
    }

    /// Physical-screen overlay. OpenZCine `canvasLayer` + `ignoresSafeArea` — not the safe-area box.
    @ViewBuilder
    private func chrome(_ layout: LiveMonitorLayout) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .allowsHitTesting(false)

            // Pinch + DISP swipe (OpenZCine feed well). Under chip + scopes;
            // chrome `Color.clear` must not cover this well.
            LiveZoomPinchWell(
                feed: layout.onFeed,
                chip: layout.zoomButton,
                stick: layout.gimbalStick,
                reset: model.session.isFocusResetAvailable ? layout.focusReset : .zero,
                cancel: trackingCancelRect(in: layout),
                enabled: !interfaceLocked && model.liveOperatorPanel == nil && chromeInteractive
            )

            if showsStatusBar {
                LiveTopChrome(menu: $topMenu)
                    .chromeEditable(.statusBar, editing: editingMode)
                    .frame(maxWidth: layout.topDeck.width)
                    .position(x: layout.topDeck.midX, y: layout.topDeck.midY)
            }

            if showsLock {
                LiveLockButton(locked: $interfaceLocked)
                    .chromeEditable(.lockButton, editing: editingMode)
                    .liveModuleFrame(layout.lock)
            }

            if showsBatteries {
                LiveBatteryCluster()
                    .chromeEditable(.batteries, editing: editingMode)
                    .frame(
                        width: layout.battery.width, height: layout.battery.height,
                        alignment: .topLeading
                    )
                    .position(x: layout.battery.midX, y: layout.battery.midY)
            }

            if model.chromeSectionMounts(.railSettings) || model.session.status.isRecording {
                LiveSettingsButton { model.liveOperatorPanel = .settings }
                    .chromeEditable(.railSettings, editing: editingMode)
                    .liveModuleFrame(layout.settings)
            }
            if model.chromeSectionMounts(.railMedia) {
                LiveMediaButton { model.liveOperatorPanel = .media }
                    .chromeEditable(.railMedia, editing: editingMode)
                    .liveModuleFrame(layout.media)
            }
            if model.chromeSectionMounts(.railRecord) || model.session.status.isRecording {
                LiveRecordButton()
                    .chromeEditable(.railRecord, editing: editingMode)
                    .liveModuleFrame(layout.record)
            }
            LiveDispToggle()
                .liveModuleFrame(layout.disp)

            LiveScopeOverlays(
                layout: layout,
                interfaceLocked: interfaceLocked
            )

            // After the scope well — that well covers this chip and used to eat the tap.
            if model.chromeSectionMounts(.zoomChip) {
                LiveZoomChip()
                    .chromeEditable(.zoomChip, editing: editingMode)
                    .liveModuleFrame(layout.zoomButton)
                    .allowsHitTesting(!interfaceLocked)
                    .zIndex(2)
            }

            if model.chromeSectionMounts(.gimbalStick) {
                LiveGimbalStick(
                    enabled: !interfaceLocked && model.liveOperatorPanel == nil
                        && chromeInteractive,
                    feed: layout.onFeed,
                    frame: layout.gimbalStick
                )
                .chromeEditable(.gimbalStick, editing: editingMode)
                .liveModuleFrame(layout.gimbalStick)
                .zIndex(3)
            }

            if !interfaceLocked, model.session.isFocusResetAvailable, chromeInteractive {
                LiveFocusResetButton()
                    .liveModuleFrame(layout.focusReset)
                    .zIndex(3)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }

            if !interfaceLocked, chromeInteractive,
                case .subject(let box) = model.session.focusOverlay
            {
                LiveTrackingCancelButton()
                    .liveModuleFrame(
                        LiveTrackingChrome.cancelRect(
                            box: box, feed: layout.onFeed, mirrored: model.livePictureViewFlip
                        )
                    )
                    .zIndex(4)
            }

            LiveSessionBanners(
                feed: layout.onFeed,
                topBar: showsStatusBar ? layout.topDeck : nil
            )

            if model.chromeSectionMounts(.toolBar) {
                LiveAssistBar(isLocked: interfaceLocked)
                    .chromeEditable(.toolBar, editing: editingMode)
                    .liveModuleFrame(layout.assist, alignment: .bottom)
                    .opacity(interfaceLocked ? 0.4 : 1)
                    .allowsHitTesting(!interfaceLocked)
            }
            if model.chromeSectionMounts(.cameraValues) {
                LiveCameraControlBar()
                    .chromeEditable(.cameraValues, editing: editingMode)
                    .liveModuleFrame(layout.capture, alignment: .bottom)
                    .opacity(interfaceLocked ? 0.4 : 1)
                    .allowsHitTesting(!interfaceLocked)
            }
        }
        .frame(width: layout.viewport.width, height: layout.viewport.height)
        // Pin the overlay tree itself. `preferredColorScheme` on the screen is
        // not enough — iOS 26 glass / vibrancy can still resolve light from the
        // feed. Chrome materials must stay dark glass + light text.
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func portraitChrome(_ layout: LiveMonitorLayout, zones: MonitorPortraitZones)
        -> some View
    {
        let choice = Self.portraitChoice(model: model)
        let isFill = choice.fill
        let well = layout.feed
        let picture = layout.onFeed
        let captureH =
            isFill && model.chromeSectionMounts(.cameraValues) && zones.controls.height > 1
            ? CGFloat(zones.controls.height) : 0
        let keySize: CGFloat = 40
        let keyClearance = captureH + 10
        let onFeed = Self.portraitOnFeedControls(
            picture: picture,
            fill: isFill,
            bottomClearance: keyClearance,
            floorY: Self.portraitBelowFeedFloor(fill: isFill, zones: zones)
        )
        let stickFrame = onFeed.stick
        let zoomFrame = onFeed.zoom
        ZStack(alignment: .topLeading) {
            Color.clear.allowsHitTesting(false)

            LiveZoomPinchWell(
                feed: picture,
                chip: zoomFrame,
                stick: stickFrame,
                reset: .zero,
                cancel: trackingCancelRect(in: layout),
                enabled: !interfaceLocked && model.liveOperatorPanel == nil && chromeInteractive
            )

            if showsStatusBar {
                LivePortraitTopBar()
                    .chromeEditable(.statusBar, editing: editingMode)
                    .frame(width: CGFloat(zones.topBar.width), height: CGFloat(zones.topBar.height))
                    .offset(x: CGFloat(zones.topBar.x), y: CGFloat(zones.topBar.y))
            }

            if model.chromeSectionMounts(.railRecord), editingMode == nil {
                LivePortraitRecOptionsButton()
                    .opacity(interfaceLocked ? 0.4 : 1)
                    .offset(x: well.maxX - 50, y: CGFloat(zones.topBar.maxY) + 8)
            }

            LiveScopeOverlays(layout: layout, interfaceLocked: interfaceLocked)

            if !isFill, model.chromeSectionMounts(.toolBar), zones.assistToolbar.height > 0 {
                LiveAssistBar(isLocked: interfaceLocked)
                    .chromeEditable(.toolBar, editing: editingMode)
                    .frame(
                        width: max(0, CGFloat(zones.assistToolbar.width) - 24),
                        height: max(0, CGFloat(zones.assistToolbar.height) - 8)
                    )
                    .offset(
                        x: CGFloat(zones.assistToolbar.x) + 12,
                        y: CGFloat(zones.assistToolbar.y) + 4
                    )
                    .opacity(interfaceLocked ? 0.4 : 1)
            }

            if isFill, model.chromeSectionMounts(.toolBar) {
                let feedRegion = MonitorLayoutRegion(
                    x: Double(well.minX), y: Double(well.minY),
                    width: Double(well.width), height: Double(well.height))
                let captureTop = captureH > 0 ? Double(well.maxY - captureH) : nil
                let expanded = MonitorPortraitLayout.fillAssistRail(
                    feed: feedRegion, captureStripTop: captureTop, expanded: true)
                let collapsed = MonitorPortraitLayout.fillAssistRail(
                    feed: feedRegion, captureStripTop: captureTop, expanded: false)
                LivePortraitAssistRail(
                    isLocked: interfaceLocked, expanded: Bindable(model).portraitRailExpanded
                )
                .chromeEditable(.toolBar, editing: editingMode)
                .frame(
                    width: model.portraitRailExpanded
                        ? CGFloat(expanded.width) : CGFloat(collapsed.width),
                    height: model.portraitRailExpanded
                        ? CGFloat(expanded.height) : CGFloat(collapsed.height),
                    alignment: .bottomLeading
                )
                .offset(
                    x: CGFloat(model.portraitRailExpanded ? expanded.x : collapsed.x),
                    y: CGFloat(model.portraitRailExpanded ? expanded.y : collapsed.y)
                )
            }

            // Fill only — OpenZCine fit leftover is the command grid, which Pocket does not ship.
            if isFill, model.chromeSectionMounts(.cameraValues), zones.controls.height > 1 {
                LiveCameraControlBar()
                    .chromeEditable(.cameraValues, editing: editingMode)
                    .frame(width: well.width, height: captureH)
                    .offset(x: well.minX, y: well.maxY - captureH)
                    .opacity(interfaceLocked ? 0.4 : 1)
                    .allowsHitTesting(!interfaceLocked)
            }

            if editingMode == nil, !choice.vertical {
                LivePortraitAspectToggle(aspect: Bindable(model).portraitFeedAspect)
                    .opacity(interfaceLocked ? 0.4 : 1)
                    .allowsHitTesting(!interfaceLocked)
                    .liveModuleFrame(
                        Self.portraitAspectToggleFrame(picture: picture, fill: isFill, zones: zones)
                    )
                    .zIndex(6)
            }

            if model.chromeSectionMounts(.zoomChip) {
                LiveZoomChip()
                    .chromeEditable(.zoomChip, editing: editingMode)
                    .liveModuleFrame(zoomFrame)
                    .allowsHitTesting(!interfaceLocked)
                    .zIndex(2)
            }

            if model.chromeSectionMounts(.gimbalStick) {
                LiveGimbalStick(
                    enabled: !interfaceLocked && model.liveOperatorPanel == nil
                        && chromeInteractive,
                    feed: picture,
                    frame: stickFrame
                )
                .chromeEditable(.gimbalStick, editing: editingMode)
                .liveModuleFrame(stickFrame)
                .zIndex(3)
            }

            if !interfaceLocked, model.session.isFocusResetAvailable, chromeInteractive {
                LiveFocusResetButton()
                    .frame(width: 40, height: 40)
                    .offset(
                        x: picture.maxX - 50,
                        y: picture.maxY - keyClearance - 50
                            - (choice.vertical ? 0 : keySize + 10)
                    )
                    .zIndex(3)
            }

            LiveSessionBanners(
                feed: picture,
                topBar: showsStatusBar ? layout.topDeck : nil
            )

            Rectangle()
                .fill(LiveDesign.glass)
                .frame(
                    width: layout.viewport.width,
                    height: max(0, layout.viewport.height - CGFloat(zones.systemBar.y))
                )
                .offset(y: CGFloat(zones.systemBar.y))
                .allowsHitTesting(false)

            LivePortraitSystemBar(
                interfaceLocked: $interfaceLocked, chromeInteractive: chromeInteractive
            )
            .frame(width: CGFloat(zones.systemBar.width), height: CGFloat(zones.systemBar.height))
            .offset(x: CGFloat(zones.systemBar.x), y: CGFloat(zones.systemBar.y))
        }
        .frame(width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }

    /// Full-screen overlays — not in-flow, not `.sheet` for live capture.
    @ViewBuilder
    private func popups(_ layout: LiveMonitorLayout) -> some View {
        let floorY =
            showsBottomBars
            ? min(layout.assist.minY, layout.capture.minY) - LiveChromeMetrics.popupGap
            : nil
        let ceilingY =
            showsStatusBar
            ? layout.topDeck.maxY + LiveChromeMetrics.topPickerGap
            : max(layout.safeArea.top + 4, LiveChromeMetrics.chromeTop)

        if chromeInteractive, showsStatusBar, topMenu != nil {
            LiveTopPickerHost(
                menu: $topMenu,
                frames: topPickerFrames,
                viewport: layout.viewport,
                topDeck: layout.topDeck,
                safeArea: layout.safeArea,
                floorY: floorY
            )
        }

        if chromeInteractive, let tool = model.assist.configureTool, !interfaceLocked {
            AssistLongPressOverlay(
                tool: tool,
                assist: model.assist,
                anchor: liveAssistAnchor(for: tool),
                toolbar: layout.assist,
                viewport: layout.viewport,
                safeArea: layout.safeArea,
                ceilingY: ceilingY,
                onDismiss: { model.assist.configureTool = nil }
            )
            .transition(.opacity)
            .animation(AssistLongPressChrome.revealCurve, value: tool)
            .animation(.easeInOut(duration: 0.22), value: orientationObserver.orientation)
        }

        if chromeInteractive, showsBottomBars, model.captureSheet != nil, !interfaceLocked {
            LiveCapturePickerHost(
                sheet: Bindable(model).captureSheet,
                frames: captureTileFrames,
                bar: layout.capture,
                viewport: layout.viewport,
                safeArea: layout.safeArea,
                ceilingY: max(
                    layout.safeArea.top + LivePopupPlacement.assistTopInset,
                    LivePopupPlacement.edgeMargin
                )
            )
        }
    }

    private static func portraitBelowFeedFloor(fill: Bool, zones: MonitorPortraitZones) -> Double {
        if fill, zones.controls.height > 1 { return zones.controls.y }
        if zones.assistToolbar.height > 1 { return zones.assistToolbar.y }
        return zones.systemBar.y
    }

    private static func portraitAspectToggleFrame(
        picture: CGRect, fill: Bool, zones: MonitorPortraitZones
    ) -> CGRect {
        let toggle = MonitorPortraitLayout.aspectToggle(
            feed: MonitorFeedFrame(
                x: Double(picture.minX), y: Double(picture.minY),
                width: Double(picture.width), height: Double(picture.height)),
            floorY: portraitBelowFeedFloor(fill: fill, zones: zones))
        return CGRect(x: toggle.x, y: toggle.y, width: toggle.width, height: toggle.height)
    }

    private static func portraitOnFeedControls(
        picture: CGRect,
        fill: Bool,
        bottomClearance: CGFloat,
        floorY: Double
    ) -> (stick: CGRect, zoom: CGRect) {
        let feed = MonitorLayoutRegion(
            x: Double(picture.minX), y: Double(picture.minY),
            width: Double(picture.width), height: Double(picture.height))
        let cluster: GimbalCluster
        if fill {
            cluster = GimbalCluster.inTrailingBottom(
                well: feed,
                floorY: Double(picture.maxY - bottomClearance),
                canvasMaxY: Double(picture.maxY),
                stickSize: Double(LiveChromeMetrics.gimbalStickSize),
                zoomSize: Double(LiveChromeMetrics.zoomButtonSize),
                gap: Double(LiveChromeMetrics.gimbalStickGap),
                inset: Double(LiveChromeMetrics.gimbalStickInset)
            )
        } else {
            cluster = GimbalCluster.belowWell(
                well: feed,
                floorY: floorY,
                stickSize: Double(LiveChromeMetrics.gimbalStickSize),
                zoomSize: Double(LiveChromeMetrics.zoomButtonSize),
                gap: Double(LiveChromeMetrics.gimbalStickGap),
                inset: Double(LiveChromeMetrics.gimbalStickInset)
            )
        }
        return (
            CGRect(
                x: cluster.stick.x, y: cluster.stick.y, width: cluster.stick.width,
                height: cluster.stick.height),
            CGRect(
                x: cluster.zoom.x, y: cluster.zoom.y, width: cluster.zoom.width,
                height: cluster.zoom.height)
        )
    }

    /// Live icon frame while the popup is open — a snapshot at long-press
    /// stays on the old side when the phone rolls landscape-left ↔ right.
    private func liveAssistAnchor(for tool: LiveAssistTool) -> CGRect {
        if let frame = assistIconFrames[tool], frame.width > 1 { return frame }
        return model.assist.longPressAnchor
    }

    /// Live rail presents the real pages with `onClose`. Home still uses `model.homePanel`.
    /// Settings gets OpenZCine `fullScreenPanelSafeArea` from the monitor's real insets —
    /// this overlay sits on an `ignoresSafeArea` canvas, so a child GeometryReader reads 0.
    @ViewBuilder
    private func operatorPanelCover(_ panel: LiveOperatorPanel, layout: LiveMonitorLayout)
        -> some View
    {
        switch panel {
        case .settings:
            SettingsRootView(
                safeArea: settingsSafeArea(from: layout),
                onClose: { model.liveOperatorPanel = nil }
            )
            .frame(width: layout.viewport.width, height: layout.viewport.height)
        case .media:
            MediaLibraryView(
                safeArea: settingsSafeArea(from: layout),
                onClose: { model.liveOperatorPanel = nil }
            )
            .frame(width: layout.viewport.width, height: layout.viewport.height)
        }
    }

    /// OpenZCine `MonitorFullScreenPanelOverlay.fullScreenPanelSafeArea`.
    private func settingsSafeArea(from layout: LiveMonitorLayout) -> EdgeInsets {
        let raw = OperatorPanelMetrics.resolvedDeviceSafeArea(layout.safeArea)
        return OperatorPanelMetrics.fullScreenPanelSafeArea(
            from: raw,
            isPortrait: layout.viewport.height > layout.viewport.width,
            mirrored: LiveMonitorLayout.shouldMirror(
                leading: raw.leading,
                trailing: raw.trailing,
                orientation: orientationObserver.orientation
            )
        )
    }
}

/// HEVC + LUT/PEAK present. Isolated so 25 Hz decode / 5 Hz status cannot rebuild chrome.
private struct LiveFeedPane: View {
    @Environment(AppModel.self) private var model

    private var liveEffects: LiveImageEffects {
        var fx = model.assist.effects.withFaceAF(model.session.wantsFaceAF)
        fx.mirror = model.assist.isVisible(.mirror)
        return fx
    }

    var body: some View {
        VideoView(
            decoder: model.session.decoder,
            effects: liveEffects,
            sampleBus: model.frameSamples,
            transfer: model.session.status.monitorTransfer,
            pictureFlip: model.livePictureViewFlip
        )
        .onChange(of: model.assist.effects) { _, fx in
            model.session.decoder.effects = fx.withFaceAF(model.session.wantsFaceAF)
        }
        .onChange(of: model.session.wantsFaceAF) { _, wants in
            model.session.decoder.effects = model.assist.effects.withFaceAF(wants)
        }
        .onChange(of: model.session.status.colorMode) { _, mode in
            model.session.decoder.incomingColorMode = mode
            guard !model.session.status.inPlayback else { return }
            model.assist.syncLUT(
                to: mode,
                family: model.session.bodyFamily,
                cameraName: model.session.connectedCamera?.model.name)
        }
    }
}

/// Empty / frozen feed well until a rolling picture exists.
private struct LiveFeedWarmupCover: View {
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                    .tint(LiveDesign.text.opacity(0.72))
                Text("WAITING FOR LIVE VIEW")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.72))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Waiting for live view")
    }
}

private struct LiveFeedAssistsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let showBox = model.chromeSectionMounts(.focusBox)
        let dimmed = focusBoxEditDimmed
        ZStack {
            FeedAlignedAssists(
                grid: model.assist.isVisible(.grid),
                crosshair: model.assist.isVisible(.crosshair),
                guides: model.assist.isVisible(.guides),
                guideAspect: model.assist.guideAspect,
                focusPoint: model.session.focusPoint,
                overlay: model.session.focusOverlay,
                sceneFaces: showBox ? model.session.dimmedFaces : [],
                showFocusChrome: showBox,
                showTapFocusBox: model.session.supportsTapFocus,
                pictureMirrored: model.livePictureViewFlip
            )
            .opacity(dimmed ? 0.3 : 1)

            if model.chromeEditorMode != nil {
                GeometryReader { proxy in
                    let feed = CGRect(origin: .zero, size: proxy.size)
                    let rect = LiveChromeEditGeometry.focusEditRect(
                        overlay: model.session.focusOverlay,
                        faces: model.session.dimmedFaces,
                        focusPoint: model.session.focusPoint,
                        mirrored: model.livePictureViewFlip,
                        in: feed
                    )
                    Color.clear
                        .frame(width: rect.width, height: rect.height)
                        .chromeEditable(.focusBox, editing: model.chromeEditorMode)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
    }

    private var focusBoxEditDimmed: Bool {
        guard let mode = model.chromeEditorMode else { return false }
        return !model.chrome(for: mode).focusBox
    }
}

enum LiveChromeEditGeometry {
    /// Badge the drawn AF / head box; stand in at the AF point when nothing is locked.
    static func focusEditRect(
        overlay: FocusOverlay,
        faces: [TrackingBox],
        focusPoint: CGPoint,
        mirrored: Bool,
        in feed: CGRect
    ) -> CGRect {
        let tracked: TrackingBox?
        switch overlay {
        case .search(let box), .subject(let box), .face(let box):
            tracked = box
        case .focus:
            tracked = faces.first
        }
        if let box = tracked {
            let drawn =
                mirrored
                ? TrackingBox(
                    x: 1 - box.x - box.width, y: box.y, width: box.width, height: box.height)
                : box
            return CGRect(
                x: feed.minX + drawn.x * feed.width,
                y: feed.minY + drawn.y * feed.height,
                width: max(1, drawn.width * feed.width),
                height: max(1, drawn.height * feed.height)
            )
        }
        let side = min(feed.width, feed.height) * 0.14
        let x = mirrored ? 1 - focusPoint.x : focusPoint.x
        return CGRect(
            x: feed.minX + x * feed.width - side / 2,
            y: feed.minY + focusPoint.y * feed.height - side / 2,
            width: side,
            height: side
        )
    }
}

private struct LiveSessionBanners: View {
    @Environment(AppModel.self) private var model
    var feed: CGRect
    var topBar: CGRect?

    var body: some View {
        let chromeBottom =
            (topBar?.height ?? 0) > 1 ? topBar.map { Double($0.maxY) } : nil
        let toastY = CGFloat(
            ControlHud.toastCenterY(feedMinY: Double(feed.minY), chromeBottomY: chromeBottom))
        Group {
            if model.session.feedRecovering {
                Text("Reconnecting")
                    .font(LiveType.ui(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiveDesign.text)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .liveChromeCapsule()
                    .position(x: feed.midX, y: toastY)
                    .zIndex(3)
                    .allowsHitTesting(false)
            }
            if let note = model.session.controlNote, !note.isEmpty, !model.session.feedRecovering {
                Text(note)
                    .font(LiveType.ui(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(LiveDesign.text.opacity(0.92))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .liveChromeCapsule()
                    .opacity(ControlHud.toastOpacity)
                    .position(x: feed.midX, y: toastY)
                    .zIndex(3)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                    .task(id: note) {
                        try? await Task.sleep(for: .seconds(ControlHud.toastHoldSeconds))
                        guard !Task.isCancelled, model.session.controlNote == note else { return }
                        model.session.controlNote = nil
                    }
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.session.controlNote)
        .animation(.easeOut(duration: 0.18), value: toastY)
    }
}

private struct LiveRecordingTallyGate: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.session.status.isRecording {
            LiveRecordingTally()
        }
    }
}

/// Scope panels observe `frameSamples.bundle` themselves (≤25 Hz). This host
/// only tracks assist on/off flags — not `generation`.
private struct LiveScopeOverlays: View {
    @Environment(AppModel.self) private var model
    var layout: LiveMonitorLayout
    var interfaceLocked: Bool

    var body: some View {
        let canvas = CGRect(origin: .zero, size: layout.viewport)
        let picture = layout.onFeed
        let clearance = EdgeInsets(
            top: layout.topDeck.maxY,
            leading: 0,
            bottom: max(0, layout.viewport.height - layout.assist.minY),
            trailing: 0)
        if model.assist.isVisible(.waveform) {
            WaveformOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
                .allowsHitTesting(!interfaceLocked)
        }
        if model.assist.isVisible(.parade) {
            ParadeOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
                .allowsHitTesting(!interfaceLocked)
        }
        if model.assist.isVisible(.vectorscope) {
            VectorscopeOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
                .allowsHitTesting(!interfaceLocked)
        }
        if model.assist.isVisible(.histogram) {
            HistogramOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
                .allowsHitTesting(!interfaceLocked)
        }
        if model.assist.isVisible(.trafficLights) {
            TrafficLightsOverlay(
                bounds: canvas,
                feed: picture,
                chromeClearance: EdgeInsets(
                    top: layout.topDeck.maxY,
                    leading: 0,
                    bottom: max(0, layout.viewport.height - layout.assist.minY),
                    trailing: max(0, layout.viewport.width - picture.maxX))
            )
            .allowsHitTesting(!interfaceLocked)
        }
    }
}

enum LiveCanvasSpace {
    static let name = "liveCanvas"
}

extension LiveViewScreen {
    fileprivate func trackingCancelRect(in layout: LiveMonitorLayout) -> CGRect {
        guard case .subject(let box) = model.session.focusOverlay else { return .zero }
        return LiveTrackingChrome.cancelRect(
            box: box, feed: layout.onFeed, mirrored: model.livePictureViewFlip)
    }
}
