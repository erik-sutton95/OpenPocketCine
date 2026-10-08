import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenCineCore
import OpenPocketViewCore
import SwiftUI
import OpenCineMedia

/// Integration and native picture adapters for the shared complete operator surface.
struct LiveViewScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var interaction = MonitorOperatorInteraction()
    @State private var gamepad = GimbalGamepadBridge()
    @State private var headphones = HeadphoneMotionBridge.appBridge()
    @State private var orientationObserver = InterfaceOrientationObserver()
    private var interfaceLocked: Bool { interaction.locked }
    private var showsBottomBars: Bool {
        model.chromeSectionMounts(.toolBar) || model.chromeSectionMounts(.cameraValues)
    }

    var body: some View {
        nativeSurface
        .monitorOperatorInteraction(host: model, interaction: interaction,
            covered: model.shell.cover != nil, motion: Bindable(model).liveGimbalPanel,
            orientation: orientationObserver.orientation, onInputAdmission: updateInputAdmission)
        // Camera-body gallery follows DJI Mimo: open Media with it, and close
        // Media (which returns the camera to live) when the body leaves it.
        .onChange(of: model.session.cameraGalleryOpen) { _, open in
            if open, model.shell.cover == nil {
                model.shell.open(.media)
            } else if !open, model.shell.cover == .media {
                model.shell.dismissCover()
            }
        }
        .onChange(of: model.shell.cover) { oldPanel, panel in
            model.session.incidentSettingsCovered = panel == .settings
            if oldPanel == .settings { model.session.recordFeedBreadcrumb(.settingsExit) }
            if panel == .settings { model.session.recordFeedBreadcrumb(.settingsEnter) }
        }
        .onChange(of: model.headTrackingEnabled) { _, _ in
            headphones.sync()
        }
        .onChange(of: model.session.gimbalLimitPulse) { _, _ in
            gamepad.pulseLimit(
                model.session.gimbalLimitContact,
                panSign: model.session.gimbalLimitPanSign,
                tiltSign: model.session.gimbalLimitTiltSign,
                enabled: model.hapticsEnabled)
        }
        .sheet(isPresented: Bindable(model.assist).showLUTPicker) { LUTPicker(assist: model.assist) }
    }

    private func updateInputAdmission(_ admission: MonitorInputAdmission) {
        model.session.isLocked = interaction.locked
        switch admission {
        case .blocked(let reason):
            gamepad.noteBlocked(); headphones.noteBlocked()
            if reason == .lock { model.session.gimbal.cancelProgrammedMove() }
        case .resumed: headphones.sync()
        }
    }

    private var nativeSurface: some View {
        GeometryReader { proxy in
            let safeArea = LiveMonitorLayout.resolvedSafeArea(proxy.safeAreaInsets, scene: windowGeometry.safeArea)
            let size = LiveMonitorLayout.canvasSize(layoutSize: proxy.size, safeArea: safeArea, screenSize: windowGeometry.validSize)
            let layout = LiveMonitorLayout.fieldMonitor(size: size, safeArea: safeArea,
                sourceAspect: model.session.pictureAspect,
                fill: model.portraitFeedAspect == .fill && !model.assist.isVisible(.desqueeze),
                showsValues: model.chromeSectionMounts(.cameraValues), showsBottomBars: showsBottomBars,
                topControlInset: windowGeometry.topControlInset, joystick: model.virtualJoystickSize)
            Color.clear.ignoresSafeArea().overlay(alignment: .topLeading) {
                canvas(layout).frame(width: layout.viewport.width, height: layout.viewport.height, alignment: .topLeading)
            }
        }.ignoresSafeArea().preferredColorScheme(.dark).environment(\.colorScheme, .dark)
            .animation(.easeInOut(duration: 0.22), value: orientationObserver.orientation)
            .animation(.easeInOut(duration: 0.18), value: model.assist.clean)
            .animation(.easeOut(duration: 0.16), value: model.chromeEditorMode)
            .animation(.easeOut(duration: 0.22), value: model.session.isFeedWarming)
        .onAppear {
            let app = model
            orientationObserver.start()
            model.session.decoder.attach(
                sampleBus: app.frameSamples,
                effects: { [weak app] in
                    guard let app else { return MonitorFrameEffects() }
                    return app.assist.effects.withFaceAF(app.session.wantsFaceAF)
                },
                transfer: { [weak app] in
                    guard let app else { return nil }
                    return LiveMonitorColorScience.transfer(
                        isPhoto: app.session.status.isPhoto,
                        colorMode: app.session.status.colorMode)
                }
            )
            #if targetEnvironment(simulator)
                if !MonitorUIReview.isActive { model.session.status.colorMode = .dLog2 }
            #endif
            model.syncLiveMonitorColor()
            model.session.decoder.startSimulatorSampleIfNeeded()
            model.session.isLocked = interfaceLocked
            gamepad.attach(model: model)
            headphones.attach(host: model)
        }
        .onDisappear {
            orientationObserver.stop()
            headphones.detach()
            gamepad.detach()
            model.session.decoder.stopSimulatorSample()
        }
    }

    private func canvas(_ layout: LiveMonitorLayout) -> some View {
        let capability = OsmoMonitorPresentation.capabilities(model.session)
        return MonitorOperatorLiveSurface(host: model, layout: layout, interaction: interaction,
            source: MonitorOperatorLivePresentation(pictureAspect: model.session.pictureAspect,
                pictureWaiting: model.session.isFeedWarming, verticalPicture: model.session.isVerticalPicture,
                recovering: model.session.feedRecovering, zoom: capability.zoom, gimbal: capability.gimbal,
                headTracking: capability.headTracking, watching: model.isWatchingFeed),
            capture: MonitorOperatorLiveCaptureSource(confirmRecording: model.recordConfirmationEnabled,
                busy: { model.session.controlBusy }, takePhoto: { model.session.control.shutter() }),
            zoom: zoomSource, focus: focusSource, assists: assistSource,
            portraitAspect: Bindable(model).portraitFeedAspect, orientation: orientationObserver.orientation,
            controlNote: Bindable(model.session).controlNote,
            headTracking: MonitorOperatorHeadTrackingSource(enabled: model.headTrackingEnabled,
                title: model.headTrackControlTitle, readPose: { model.headTrackAxisPose },
                readIMU: { model.headTrackImuReadout }, calibrate: { headphones.tapControl() }),
            readLevel: { now, viewFlip in
                LevelAssist.display(model.session.gimbal.levelReading.mode(now: now, viewFlip: viewFlip))
            }
        ) { LiveFeedPane()
        } preview: { AssistInspectorPreview(tool: $0)
        } lookMenu: { LUTAssist.longPressMenu(assist: model.assist) }
        .overlay {
            if model.session.sessionRecovery.isRecovering {
                MonitorRecoveryOverlay().frame(width: layout.viewport.width, height: layout.viewport.height)
                    .animation(.easeOut(duration: 0.2), value: model.session.sessionRecovery.isRecovering)
            }
        }
        .monitorVideoBackdrop(
            renderer: model.liveBackdrop,
            configuration: [
                MonitorVideoBackdropConfiguration(
                    source: ObjectIdentifier(model.session.decoder),
                    generation: Int(model.frameSamples.inspectorSourceEpoch),
                    effects: model.assist.effects,
                    geometry: [
                        layout.onFeed.minX, layout.onFeed.minY,
                        layout.onFeed.width, layout.onFeed.height,
                        model.livePictureViewFlip ? 1 : 0,
                        model.portraitFeedAspect == .fill ? 1 : 0,
                    ])
            ],
            enabled: model.shell.cover == nil && !model.assist.gradesClip
                && !model.isWatchingFeed
                && !model.session.isFeedWarming
        ) { _ in
            let decoder = model.session.decoder, samples = model.frameSamples
            let epoch = samples.inspectorSourceEpoch
            guard let token = decoder.sourceToken, let buffer = decoder.backdropSource else { return [] }
            let effects = decoder.backdropEffects
            return [
                MonitorVideoBackdropSource(
                    buffer: buffer, effects: effects,
                    frame: MonitorVideoBackdropSource.displayedFrame(
                        sourceAspect: decoder.pictureAspect, effects: effects, in: layout.onFeed,
                        fill: layout.presentation?.portrait == true
                            && layout.presentation?.fillsPicture == true
                            && decoder.pictureAspect >= 1),
                    clip: layout.onFeed, identity: .live(token: token, epoch: epoch), admission: { [weak decoder, weak samples] in
                        guard let decoder, let samples else { return false }
                        return decoder.sourceToken == token && samples.inspectorSourceEpoch == epoch
                    })
            ]
        }
    }

    private var zoomSource: MonitorOperatorZoomPresentation {
        MonitorOperatorZoomPresentation(maximum: model.session.zoomMax,
            opticalStops: model.session.zoomStops.contains(3) ? [1, 3] : [1],
            caption: OsmoMonitorPresentation.zoomCaption(model.session),
            readValue: { model.session.zoomDialReadout },
            readOrigin: { model.session.status.zoomFactor ?? model.session.zoomOptimistic ?? model.session.zoomStop },
            label: { CamFov.displayLabel(factor: $0) })
    }

    private var focusSource: MonitorOperatorFocusSource {
        MonitorOperatorFocusSource(read: {
            let session = model.session
            return MonitorOperatorFocusObservation(point: session.focusPoint, overlay: session.focusOverlay,
                faces: session.dimmedFaces, resetAvailable: session.isFocusResetAvailable,
                supportsTapFocus: session.supportsTapFocus, tracking: session.isTracking,
                search: session.searchBox, subject: session.subjectBox)
        }, cancelTracking: { model.session.cancelSubjectTracking() })
    }

    private var assistSource: MonitorOperatorLiveAssistSource {
        MonitorOperatorLiveAssistSource(stores: .app, looks: .app, haptics: .app,
            readBundle: { model.monitorSamples.displayBundle },
            readTransfer: { model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709 },
            readClipByte: { model.monitorSamples.exposureCeiling.clipByte(transfer: $0) },
            configureDisplay: scopeDisplay)
    }


}

/// HEVC + LUT/PEAK present. Isolated so 25 Hz decode / 5 Hz status cannot rebuild chrome.
private struct LiveFeedPane: View {
    @Environment(AppModel.self) private var model

    private var liveEffects: MonitorFrameEffects {
        var fx = model.assist.effects.withFaceAF(model.session.wantsFaceAF)
        fx.mirror = model.assist.mirrorsHorizontally
        return fx
    }

    var body: some View {
        VideoView(
            decoder: model.session.decoder,
            effects: liveEffects,
            sampleBus: model.frameSamples,
            transfer: LiveMonitorColorScience.transfer(
                isPhoto: model.session.status.isPhoto,
                colorMode: model.session.status.colorMode),
            pictureFlip: model.livePictureViewFlip,
            hdrDisplay: model.hdrDisplayActive,
            qualification: { [weak session = model.session] in session?.nativeQualificationSnapshot }
        )
        .onChange(of: model.assist.effects) { _, fx in
            model.session.decoder.effects = fx.withFaceAF(model.session.wantsFaceAF)
        }
        .onChange(of: model.session.wantsFaceAF) { _, wants in
            model.session.decoder.effects = model.assist.effects.withFaceAF(wants)
        }
        .onChange(of: model.session.status.colorMode) { _, _ in
            model.syncLiveMonitorColor()
        }
        .onChange(of: model.session.status.isPhoto) { _, _ in
            model.syncLiveMonitorColor()
        }
        .onChange(of: model.assist.gradesClip) { _, grading in
            if !grading { model.syncLiveMonitorColor() }
        }
    }
}
