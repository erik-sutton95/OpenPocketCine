import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Live HEVC feed with OpenZCine landscape chrome. Video and chrome are **siblings**:
/// the feed is an explicit 16:9 well; chrome is a physical-screen overlay (`ignoresSafeArea`).
/// `VideoView` is never wrapped in a `GeometryReader` and does not host rails or decks.
struct LiveViewScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var interfaceLocked = false
    @State private var gamepad = GimbalGamepadBridge()
    @State private var headphones = HeadphoneMotionBridge()
    @State private var orientationObserver = InterfaceOrientationObserver()
    @State private var topMenu: LiveTopMenu?
    @State private var topPickerFrames: [LiveTopMenu: CGRect] = [:]
    @State private var captureTileFrames: [CaptureSheet: CGRect] = [:]
    @State private var assistIconFrames: [LiveAssistTool: CGRect] = [:]
    @State private var zoomDialVisible = false
    @State private var assistsExpanded = false
    @State private var zoomGestureAnchor = 1.0

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
    private var showsGimbalButton: Bool {
        OsmoMonitorPresentation.capabilities(model.session).gimbal
            && model.chromeSectionMounts(.gimbalStick)
    }
    /// The transient value drum is a draw-only preview of an existing touch.
    private var hasInteractivePopup: Bool {
        guard chromeInteractive, !interfaceLocked else { return false }
        return (showsStatusBar && topMenu != nil)
            || (model.liveOperatorPanel == nil && !model.assist.gradesClip
                && model.assist.configureTool != nil)
            || (showsGimbalButton && model.liveGimbalPanel == .sheet)
            || model.captureSheet != nil
            || zoomDialVisible
    }

    private func gimbalCluster(_ layout: LiveMonitorLayout) -> GimbalCluster {
        layout.gimbalCluster(showGimbalButton: showsGimbalButton)
    }

    /// Portrait parks the cluster on the picture; landscape uses the cinema well.

    private static func cgRect(_ region: MonitorLayoutRegion) -> CGRect {
        CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
    }

    var body: some View {
        GeometryReader { proxy in
            let safeArea = LiveMonitorLayout.resolvedSafeArea(
                proxy.safeAreaInsets, scene: windowGeometry.safeArea)
            let size = LiveMonitorLayout.canvasSize(
                layoutSize: proxy.size, safeArea: safeArea,
                screenSize: windowGeometry.validSize)
            let layout = LiveMonitorLayout.fieldMonitor(
                size: size, safeArea: safeArea,
                sourceAspect: model.session.decoder.pictureAspect,
                fill: model.portraitFeedAspect == .fill,
                showsValues: model.chromeSectionMounts(.cameraValues),
                showsBottomBars: showsBottomBars,
                topControlInset: windowGeometry.topControlInset)
            Color.clear
                .ignoresSafeArea()
                .overlay(alignment: .topLeading) {
                    canvas(layout)
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
            gamepad.attach(model: model)
            headphones.attach(model: model)
        }
        .onDisappear {
            model.captureDrum = nil
            orientationObserver.stop()
            closeZoomDial()
            headphones.detach()
            gamepad.detach()
            model.session.decoder.stopSimulatorSample()
        }
        .onChange(of: interfaceLocked) { _, locked in
            model.session.isLocked = locked
            if locked {
                assistsExpanded = false
                model.captureDrum = nil
                closeZoomDial()
                topMenu = nil
                model.captureSheet = nil
                model.assist.configureTool = nil
                gamepad.noteBlocked()
                headphones.noteBlocked()
                model.liveGimbalPanel = .none
                model.session.cancelProgrammedMove()
            }
        }
        .onChange(of: model.liveOperatorPanel) { _, panel in
            if panel != nil {
                model.captureDrum = nil
                model.assist.configureTool = nil
                closeZoomDial()
                gamepad.noteBlocked()
                headphones.noteBlocked()
                model.liveGimbalPanel = .none
            } else {
                headphones.sync()
            }
        }
        .onChange(of: model.headTrackingEnabled) { _, _ in
            headphones.sync()
        }
        .onChange(of: model.isEditingChrome) { _, editing in
            if editing {
                headphones.noteBlocked()
                model.liveGimbalPanel = .none
            } else {
                headphones.sync()
            }
        }
        .onChange(of: model.session.gimbalLimitPulse) { _, _ in
            gamepad.pulseLimit(
                model.session.gimbalLimitContact,
                panSign: model.session.gimbalLimitPanSign,
                tiltSign: model.session.gimbalLimitTiltSign,
                enabled: model.hapticsEnabled)
        }
        .onChange(of: model.assist.clean) { _, clean in
            if clean {
                assistsExpanded = false
                model.captureDrum = nil
                closeZoomDial()
                topMenu = nil
                model.captureSheet = nil
                model.assist.configureTool = nil
            }
        }
        .onChange(of: model.chromeEditorMode) { _, mode in
            if mode != nil {
                assistsExpanded = false
                model.captureDrum = nil
                topMenu = nil
                model.captureSheet = nil
                model.assist.configureTool = nil
            }
        }
        .onChange(of: model.chromeSectionMounts(.toolBar)) { _, mounted in
            if !mounted { assistsExpanded = false }
        }
        .onChange(of: orientationObserver.orientation) { _, _ in model.captureDrum = nil }
        .onChange(of: topMenu) { _, value in if value != nil { selectOverlay(.top) } }
        .onChange(of: model.captureSheet) { _, value in if value != nil { selectOverlay(.capture) }
        }
        .onChange(of: model.captureDrum?.id) { _, value in if value != nil { selectOverlay(.drum) }
        }
        .onChange(of: model.assist.configureTool) { _, value in
            if value != nil { selectOverlay(.assist) }
        }
        .onChange(of: model.liveGimbalPanel) { _, value in
            if value != .none { selectOverlay(.gimbal) }
        }
        .sheet(isPresented: Bindable(model.assist).showLUTPicker) {
            LUTPicker(assist: model.assist)
        }
    }

    @ViewBuilder
    private func canvas(_ layout: LiveMonitorLayout) -> some View {
        let geometry =
            layout.presentation
            ?? FieldMonitorLayout(width: layout.viewport.width, height: layout.viewport.height)
        MonitorCanvas(layout: geometry, sourceAspect: model.session.decoder.pictureAspect) {
            LiveFeedPane().opacity(model.session.isFeedWarming ? 0 : 1)
        } assists: {
            LiveFeedAssistsPane().opacity(model.session.isFeedWarming ? 0 : 1)
        } chrome: {
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
            .accessibilityHidden(!model.session.isFeedWarming)
            .allowsHitTesting(false)

            chrome(layout)
                .environment(\.interfaceLocked, interfaceLocked)
                .opacity(zoomDialVisible ? 0.16 : 1)
                .allowsHitTesting(
                    chromeInteractive && model.liveChromeInteractive && !zoomDialVisible)

            // Keep these controls mounted above the zoom disc. Their identity
            // and recording-confirmation state survive opening and closing it.
            ZStack(alignment: .topLeading) {
                if model.chromeSectionMounts(.railRecord) || model.session.status.isRecording {
                    LiveRecordButton(diameter: layout.record.width)
                        .chromeEditable(.railRecord, editing: editingMode)
                        .liveModuleFrame(layout.record)
                }
                LiveDispToggle(size: layout.disp.size)
                    .liveModuleFrame(layout.disp)
            }
            .frame(
                width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading
            )
            .environment(\.interfaceLocked, interfaceLocked)
            .allowsHitTesting(chromeInteractive && model.liveChromeInteractive)
            .zIndex(zoomDialVisible ? 11 : 0)

            // After chrome so the bezel stroke sits on the physical screen, not the feed well.
            LiveRecordingTallyGate()
                .frame(width: layout.viewport.width, height: layout.viewport.height)

            popups(layout)
                // Clear the container's full-screen hit region as its last
                // popup leaves; a dismissed picker must not swallow Lock.
                .allowsHitTesting(hasInteractivePopup)
                .zIndex(10)

            // The expanded Motion editor owns its outside-tap minimization
            // region above camera controls, including the stable Record layer.
            if showsGimbalButton, chromeInteractive, !interfaceLocked,
                model.liveOperatorPanel == nil
            {
                LiveGimbalOverlay(layout: layout, feed: layout.onFeed)
                    .environment(\.interfaceLocked, interfaceLocked)
                    .allowsHitTesting(model.liveChromeInteractive && !zoomDialVisible)
                    .zIndex(15)
            }

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
                chip: Self.cgRect(self.gimbalCluster(layout).zoom),
                stick: Self.cgRect(self.gimbalCluster(layout).stick),
                gimbalButton: Self.cgRect(self.gimbalCluster(layout).controls),
                reset: model.session.isFocusResetAvailable ? layout.focusReset : .zero,
                cancel: trackingCancelRect(in: layout),
                calibrate: model.headTrackingEnabled
                    && OsmoMonitorPresentation.capabilities(model.session).headTracking
                    ? layout.gimbalCalibrate : .zero,
                enabled: !interfaceLocked && model.liveOperatorPanel == nil && chromeInteractive
            )

            LiveScopeOverlays(
                layout: layout,
                interfaceLocked: interfaceLocked,
                chromeClearance: scopeClearance(layout: layout)
            )

            // The collapse backdrop is above the picture/scopes and below
            // fixed controls. A Record or Settings tap keeps its own action.
            if assistsExpanded, model.chromeSectionMounts(.toolBar), !interfaceLocked,
                chromeInteractive
            {
                Color.clear
                    .frame(width: layout.viewport.width, height: layout.viewport.height)
                    .contentShape(Rectangle())
                    .onTapGesture { assistsExpanded = false }
                    .accessibilityHidden(true)
            }

            if showsStatusBar {
                FieldMonitorStatusChrome(menu: $topMenu, layout: layout)
                    .chromeEditable(.statusBar, editing: editingMode)
                    .frame(maxWidth: layout.topDeck.width)
                    .position(x: layout.topDeck.midX, y: layout.topDeck.midY)
            }

            if let p = layout.presentation, p.portrait {
                LiveDesign.background.frame(width: p.system.width, height: p.system.height)
                    .position(x: p.system.midX, y: p.system.midY).allowsHitTesting(false)
                if !model.session.decoder.isVerticalPicture, editingMode == nil {
                    LivePortraitAspectToggle(aspect: Bindable(model).portraitFeedAspect)
                        .liveModuleFrame(p.aspectToggle.cgRect)
                        .allowsHitTesting(!interfaceLocked)
                }
            }

            if let exit = model.multiviewExit {
                Button(action: exit) {
                    OpcIcon.layoutGrid.frame(width: 22, height: 22).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Return to Multiview").liveModuleFrame(layout.lock)
            } else if showsLock {
                LiveLockButton(locked: $interfaceLocked, size: layout.lock.width)
                    .chromeEditable(.lockButton, editing: editingMode)
                    .liveModuleFrame(layout.lock)
            }

            if showsBatteries {
                FieldMonitorGauges(
                    horizontal: layout.presentation?.portrait == true
                        && layout.presentation?.tablet == false
                )
                .chromeEditable(.batteries, editing: editingMode)
                .frame(
                    width: layout.battery.width, height: layout.battery.height,
                    alignment: .topLeading
                )
                .position(x: layout.battery.midX, y: layout.battery.midY)
            }

            if model.chromeSectionMounts(.railSettings) || model.session.status.isRecording {
                LiveSettingsButton(size: layout.settings.width) {
                    model.liveOperatorPanel = .settings
                }
                .chromeEditable(.railSettings, editing: editingMode)
                .liveModuleFrame(layout.settings)
            }
            if model.chromeSectionMounts(.railMedia) && !model.session.isMultiviewBorrowed {
                LiveMediaButton(size: layout.media.width) { model.liveOperatorPanel = .media }
                    .chromeEditable(.railMedia, editing: editingMode)
                    .liveModuleFrame(layout.media)
            }

            // After the scope well — that well covers this chip and used to eat the tap.
            if OsmoMonitorPresentation.capabilities(model.session).zoom
                && model.chromeSectionMounts(.zoomChip)
            {
                LiveZoomChip(onOpenDial: openZoomDial)
                    .chromeEditable(.zoomChip, editing: editingMode)
                    .liveModuleFrame(Self.cgRect(self.gimbalCluster(layout).zoom))
                    .allowsHitTesting(!interfaceLocked)
                    .zIndex(2)
            }

            if showsGimbalButton {
                LiveGimbalButton()
                    .liveModuleFrame(Self.cgRect(self.gimbalCluster(layout).controls))
                    .allowsHitTesting(!interfaceLocked)
                    .zIndex(2)
            }

            if OsmoMonitorPresentation.capabilities(model.session).gimbal
                && model.chromeSectionMounts(.gimbalStick)
            {
                LiveGimbalStick(
                    enabled: !interfaceLocked && model.liveOperatorPanel == nil
                        && chromeInteractive
                )
                .chromeEditable(.gimbalStick, editing: editingMode)
                .liveModuleFrame(Self.cgRect(self.gimbalCluster(layout).stick))
                .zIndex(3)
            }

            if model.headTrackingEnabled,
                OsmoMonitorPresentation.capabilities(model.session).headTracking,
                !interfaceLocked, chromeInteractive,
                model.liveOperatorPanel == nil
            {
                LiveHeadTrackCalibrateButton(
                    title: model.headTrackControlTitle, onTap: { headphones.tapControl() }
                )
                .liveModuleFrame(layout.gimbalCalibrate)
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
                FieldMonitorAssistPalette(
                    layout: layout, isLocked: interfaceLocked,
                    otherOverlayPresented: topMenu != nil || zoomDialVisible,
                    expanded: $assistsExpanded
                )
                .opacity(interfaceLocked ? 0.4 : 1)
                .allowsHitTesting(!interfaceLocked)
                .zIndex(6)
            }
            if model.chromeSectionMounts(.cameraValues) {
                LiveCameraControlBar(columns: layout.capture.height > 60 ? 3 : 6)
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

        if chromeInteractive, model.liveOperatorPanel == nil, !model.assist.gradesClip,
            let tool = model.assist.configureTool, !interfaceLocked
        {
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

        if chromeInteractive, showsGimbalButton, model.liveGimbalPanel == .sheet, !interfaceLocked {
            LiveGimbalSheetHost(
                layout: layout,
                cluster: gimbalCluster(layout)
            )
        }

        if chromeInteractive, model.captureSheet != nil, !interfaceLocked {
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

        if chromeInteractive, model.captureDrum != nil, !interfaceLocked {
            LiveCaptureDrumHost(
                frames: captureTileFrames, bar: layout.capture,
                viewport: layout.viewport, safeArea: layout.safeArea)
        }

        if zoomDialVisible, chromeInteractive, !interfaceLocked {
            MonitorZoomDial(
                viewport: layout.viewport, safeArea: layout.safeArea,
                scale: MonitorZoomScale(minimum: 1, maximum: model.session.zoomMax),
                marks: Array(Set([1, 1.5, 2, 4, 6, 9] + model.session.zoomStops)).sorted(),
                opticalStops: model.session.zoomStops.contains(3) ? [1, 3] : [1],
                caption: OsmoMonitorPresentation.zoomCaption(model.session),
                value: Binding(
                    get: { model.session.zoomReadout },
                    set: {
                        model.session.updateZoomPinch(magnification: $0 / max(1, zoomGestureAnchor))
                    }),
                label: { CamFov.displayLabel(factor: $0) },
                onEditing: { editing in
                    if editing {
                        zoomGestureAnchor =
                            model.session.status.zoomFactor ?? model.session.zoomOptimistic
                            ?? model.session.zoomStop
                    } else {
                        model.session.endZoomPinch()
                    }
                }, onClose: closeZoomDial)
        }
    }

    private func openZoomDial() {
        guard !interfaceLocked else { return }
        assistsExpanded = false
        selectOverlay(.zoom)
        withAnimation(.easeOut(duration: 0.18)) { zoomDialVisible = true }
    }

    /// Presentation arbitration only. The existing model fields remain the
    /// adapter boundary for camera- and playback-owned native controls.
    private enum OverlayOwner { case top, capture, drum, assist, gimbal, zoom }

    private func selectOverlay(_ owner: OverlayOwner) {
        guard !interfaceLocked else {
            topMenu = nil
            model.captureSheet = nil
            model.captureDrum = nil
            model.assist.configureTool = nil
            model.liveGimbalPanel = .none
            closeZoomDial()
            return
        }
        if owner != .top { topMenu = nil }
        if owner != .capture { model.captureSheet = nil }
        if owner != .drum { model.captureDrum = nil }
        if owner != .assist { model.assist.configureTool = nil }
        if owner != .gimbal { model.liveGimbalPanel = .none }
        if owner != .zoom { closeZoomDial() }
    }

    private func closeZoomDial() {
        guard zoomDialVisible else { return }
        model.session.endZoomPinch()
        withAnimation(.easeOut(duration: 0.18)) { zoomDialVisible = false }
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
        let raw = OperatorPanelMetrics.resolvedDeviceSafeArea(
            layout.safeArea, window: windowGeometry.safeArea)
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
    @Environment(AppModel.self) private var model
    @State private var showVPNHint = false

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
                if showVPNHint {
                    Text(LocalVPNFilter.liveHint)
                        .font(LiveType.ui(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(LiveDesign.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            showVPNHint
                ? "Waiting for live view. \(LocalVPNFilter.liveHint)"
                : "Waiting for live view"
        )
        .task(id: model.session.isFeedWarming) {
            showVPNHint = false
            guard model.session.isFeedWarming else { return }
            let delay = UInt64(LocalVPNFilter.liveHintDelaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            showVPNHint = LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive: LocalVPNProbe.isActive(),
                hadVideo: !model.session.isFeedWarming,
                secondsWithoutVideo: LocalVPNFilter.liveHintDelaySeconds)
        }
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
            if model.headTrackingEnabled, let pose = model.headTrackAxisPose {
                VStack(alignment: .leading, spacing: 6) {
                    LiveHeadTrackAxisDials(pose: pose)
                    if !model.headTrackImuReadout.isEmpty {
                        Text(model.headTrackImuReadout)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(LiveDesign.text)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: 220, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .liveChromeCapsule()
                    }
                }
                .position(x: feed.minX + 118, y: feed.minY + 118)
                .zIndex(5)
                .allowsHitTesting(false)
                .transaction { $0.animation = nil }
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
    var chromeClearance: EdgeInsets

    var body: some View {
        let canvas = CGRect(origin: .zero, size: layout.viewport)
        let picture = layout.onFeed
        let clearance = chromeClearance
        if model.assist.isVisible(.waveform) {
            WaveformOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
        }
        if model.assist.isVisible(.parade) {
            ParadeOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
        }
        if model.assist.isVisible(.vectorscope) {
            VectorscopeOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
        }
        if model.assist.isVisible(.histogram) {
            HistogramOverlay(canvas: canvas, feed: picture, chromeClearance: clearance)
        }
        if model.assist.isVisible(.trafficLights) {
            TrafficLightsOverlay(
                bounds: canvas,
                feed: picture,
                chromeClearance: clearance
            )
        }
        if model.assist.isVisible(.ndMeter) {
            NDMeterOverlay(
                bounds: canvas,
                feed: picture,
                chromeClearance: clearance
            )
        }
    }
}

enum LiveCanvasSpace {
    static let name = "liveCanvas"
}

extension LiveViewScreen {
    /// One rectangle shared by all movable tools; full-canvas coordinates remain persisted.
    private func scopeClearance(layout: LiveMonitorLayout) -> EdgeInsets {
        let portrait = layout.presentation?.portrait == true
        let floor =
            portrait ? (layout.presentation?.system.y ?? layout.rail.minY) : layout.viewport.height
        let right =
            portrait ? layout.viewport.width - layout.safeArea.trailing : layout.settings.minX - 6
        return EdgeInsets(
            top: layout.safeArea.top,
            leading: layout.safeArea.leading,
            bottom: max(0, layout.viewport.height - floor),
            trailing: max(0, layout.viewport.width - right))
    }

    fileprivate func trackingCancelRect(in layout: LiveMonitorLayout) -> CGRect {
        guard case .subject(let box) = model.session.focusOverlay else { return .zero }
        return LiveTrackingChrome.cancelRect(
            box: box, feed: layout.onFeed, mirrored: model.livePictureViewFlip)
    }
}
