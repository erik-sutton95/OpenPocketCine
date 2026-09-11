import AVFoundation
import OpenPocketViewCore
import SwiftUI

/// Pocket monitor tools around a remote source. Never opens a camera session.
struct WatcherLiveView: View {
    @Environment(AppModel.self) private var model
    @State private var clean = false
    @State private var confirmRecording = false
    @State private var focusPoint: CGPoint?
    private var client: WatcherRelayClient { model.relayClient }
    private var mirrored: Bool {
        GimbalStick.liveViewFlip(
            poseViewFlip: client.decoder.poseViewFlip, assistMirror: model.assist.isVisible(.mirror)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            let viewport = CGRect(origin: .zero, size: proxy.size)
            let raster =
                client.decoder.pictureSize.width > 0
                ? client.decoder.pictureSize : CGSize(width: 1280, height: 720)
            let feed = AVMakeRect(aspectRatio: raster, insideRect: viewport)
            let bottom = max(proxy.safeAreaInsets.bottom, 10.0)
            ZStack {
                Color.black.ignoresSafeArea()
                VideoView(
                    decoder: client.decoder, effects: model.assist.effects,
                    sampleBus: client.samples, transfer: client.transfer,
                    pictureFlip: client.decoder.poseViewFlip
                )
                .frame(width: feed.width, height: feed.height)
                .contentShape(Rectangle())
                .gesture(
                    SpatialTapGesture().onEnded { value in
                        guard client.canControl,
                            let point = WatcherFocusPoint.map(
                                x: value.location.x, y: value.location.y,
                                width: feed.width, height: feed.height, mirrored: mirrored)
                        else { return }
                        focusPoint = CGPoint(x: Double(point.x) / 1000, y: Double(point.y) / 1000)
                        client.sendCommand(
                            .tapFocus(
                                cameraX: point.x, cameraY: point.y, coordinateWidth: 1000,
                                coordinateHeight: 1000))
                    }
                )
                .position(x: feed.midX, y: feed.midY)

                FeedAlignedAssists(
                    grid: model.assist.isVisible(.grid),
                    crosshair: model.assist.isVisible(.crosshair),
                    guides: model.assist.isVisible(.guides), guideAspect: model.assist.guideAspect,
                    focusPoint: focusPoint ?? CGPoint(x: 0.5, y: 0.5),
                    showFocusChrome: focusPoint != nil && client.canControl,
                    feed: feed, pictureMirrored: mirrored)

                if !clean {
                    scopes(viewport: viewport, feed: feed, bottom: bottom)
                }
                VStack(spacing: 8) {
                    header
                    if !clean { telemetry }
                    Spacer(minLength: 0)
                    connectionNotice
                    if !clean {
                        controlStrip
                        LiveAssistBar(showsAudio: false)
                            .frame(height: LiveDesign.controlHeight)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, max(proxy.safeAreaInsets.top, 10))
                .padding(.bottom, bottom)

                if !clean, let tool = model.assist.configureTool, tool != .audioMeters {
                    AssistLongPressOverlay(
                        tool: tool, assist: model.assist,
                        anchor: model.assist.longPressAnchor,
                        toolbar: CGRect(
                            x: 14, y: viewport.height - bottom - LiveDesign.controlHeight,
                            width: viewport.width - 28, height: LiveDesign.controlHeight),
                        viewport: proxy.size, safeArea: proxy.safeAreaInsets, ceilingY: 70,
                        onDismiss: { model.assist.configureTool = nil })
                }
            }
            .coordinateSpace(name: LiveCanvasSpace.name)
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { syncColor() }
        .onChange(of: client.state.color) { _, _ in syncColor() }
        .onChange(of: client.state.cameraModel) { _, _ in syncColor() }
        .onChange(of: client.canControl) { _, canControl in
            if !canControl {
                confirmRecording = false
                focusPoint = nil
            }
        }
        .onDisappear { model.assist.configureTool = nil }
        .confirmationDialog(
            client.state.isRecording ? "Stop recording?" : "Start recording?",
            isPresented: $confirmRecording, titleVisibility: .visible
        ) {
            Button(client.state.isRecording ? "Stop recording" : "Start recording") {
                client.sendCommand(.toggleRecording)
            }
        }
    }

    private func syncColor() {
        client.decoder.incomingColorMode = client.colorMode
        model.assist.syncLUT(
            to: client.colorMode, family: client.state.isNano == true ? .nano : .pocket,
            cameraName: client.state.cameraModel)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button("Leave") { model.stopWatching() }
                .accessibilityIdentifier("watcher.leave")
            VStack(alignment: .leading, spacing: 2) {
                Text(client.hostTitle).font(LiveType.ui(size: 13, weight: .semibold)).lineLimit(1)
                if !clean {
                    Text("WATCHING · \(client.receivedFPS) fps")
                        .font(LiveType.ui(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(LiveDesign.text.opacity(0.65))
                }
            }
            Spacer(minLength: 4)
            if client.state.isRecording {
                HStack(spacing: 5) {
                    Circle().fill(LiveDesign.rec).frame(width: 7, height: 7)
                    Text("REC")
                }
                .foregroundStyle(LiveDesign.rec)
                .accessibilityLabel("Camera recording")
            }
            Button(clean ? "Controls" : "Clean view") {
                model.assist.configureTool = nil
                clean.toggle()
            }
        }
        .font(LiveType.ui(size: 12, weight: .semibold))
        .foregroundStyle(LiveDesign.text)
        .padding(.horizontal, 12).padding(.vertical, 9)
        .liveChromeCapsule()
    }

    private var telemetry: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                reading("FORMAT", client.state.format)
                reading("COLOR", client.state.color)
                reading("SHUTTER", client.state.shutter)
                reading("ISO", client.state.iso)
                reading("ZOOM", client.state.zoom)
                reading(
                    "BATTERY",
                    client.state.batteryPercent >= 0 ? "\(client.state.batteryPercent)%" : "—")
            }.padding(.horizontal, 12).padding(.vertical, 7)
        }
        .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
    }

    private func reading(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(LiveType.ui(size: 8, weight: .medium)).foregroundStyle(
                LiveDesign.text.opacity(0.65))
            Text(value.isEmpty ? "—" : value).font(
                LiveType.ui(size: 12, weight: .semibold, design: .monospaced)
            )
            .foregroundStyle(LiveDesign.text)
        }
    }

    @ViewBuilder private var connectionNotice: some View {
        switch client.status {
        case .reconnecting(let attempt):
            notice(
                "Reconnecting… \(attempt) of \(WatcherRelayRecovery.maximumRetries)", retry: false)
        case .failed(let message): notice(message, retry: true)
        case .live:
            if client.waitingForPicture {
                notice("Waiting for picture from the host…", retry: false)
            }
        default: notice("Joining shared feed…", retry: false)
        }
    }

    private func notice(_ message: String, retry: Bool) -> some View {
        VStack(spacing: 10) {
            Text(message).multilineTextAlignment(.center)
            if retry {
                Button("Choose a feed") {
                    model.stopWatching()
                    model.openWatcherBrowse()
                }
                .buttonStyle(StartupFilledButtonStyle())
            }
        }
        .font(LiveType.ui(size: 14, weight: .medium))
        .foregroundStyle(LiveDesign.text)
        .padding(14)
        .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                Text(client.canControl ? "CONTROL · YOU" : "CONTROL · \(client.token.holderName)")
                    .font(LiveType.ui(size: 10, weight: .semibold))
                    .foregroundStyle(
                        client.canControl ? LiveDesign.accent : LiveDesign.text.opacity(0.65))
                if client.canControl {
                    remoteSettings
                    Button("Release") { client.releaseControl() }
                    Button(client.state.isRecording ? "Stop REC" : "REC") {
                        if model.recordConfirmationEnabled {
                            confirmRecording = true
                        } else {
                            client.sendCommand(.toggleRecording)
                        }
                    }.foregroundStyle(LiveDesign.rec)
                } else if client.status == .live, client.state.allowsControlRequests {
                    Button(client.controlRequested ? "Requested…" : "Request control") {
                        client.requestControl()
                    }
                    .disabled(client.controlRequested)
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
        }
        .font(LiveType.ui(size: 12, weight: .semibold))
        .foregroundStyle(LiveDesign.text)
        .background(.black.opacity(0.72), in: Capsule())
    }

    @ViewBuilder private var remoteSettings: some View {
        if let options = client.state.controlOptions {
            if !options.isoIndices.isEmpty {
                Menu("ISO \(client.state.iso)") {
                    ForEach(options.isoIndices, id: \.self) { raw in
                        if let iso = IsoIndex(rawValue: UInt8(clamping: raw)) {
                            Button(iso.label) { client.sendCommand(.setISO(raw)) }
                        }
                    }
                }
            }
            if !options.shutterDenominators.isEmpty {
                Menu(client.state.shutter.isEmpty ? "Shutter" : client.state.shutter) {
                    ForEach(options.shutterDenominators, id: \.self) { denom in
                        Button("1/\(denom)") { client.sendCommand(.setShutterDenom(denom)) }
                    }
                }
            }
            if !options.zoomHundredths.isEmpty {
                Menu(client.state.zoom.isEmpty ? "Zoom" : client.state.zoom) {
                    ForEach(options.zoomHundredths, id: \.self) { zoom in
                        Button(CamFov.displayLabel(factor: Double(zoom) / 100)) {
                            client.sendCommand(.setZoom(zoom))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func scopes(viewport: CGRect, feed: CGRect, bottom: CGFloat) -> some View {
        let clearance = EdgeInsets(top: 100, leading: 14, bottom: bottom + 104, trailing: 14)
        if model.assist.isVisible(.waveform) {
            WaveformOverlay(canvas: viewport, feed: feed, chromeClearance: clearance)
        }
        if model.assist.isVisible(.parade) {
            ParadeOverlay(canvas: viewport, feed: feed, chromeClearance: clearance)
        }
        if model.assist.isVisible(.histogram) {
            HistogramOverlay(canvas: viewport, feed: feed, chromeClearance: clearance)
        }
        if model.assist.isVisible(.vectorscope) {
            VectorscopeOverlay(canvas: viewport, feed: feed, chromeClearance: clearance)
        }
        if model.assist.isVisible(.trafficLights) {
            TrafficLightsOverlay(bounds: viewport, feed: feed, chromeClearance: clearance)
        }
    }
}
