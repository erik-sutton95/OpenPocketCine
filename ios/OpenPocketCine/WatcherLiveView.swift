import OpenCineAppKitApple
import AVFoundation
import MonitorUI
import MonitorPresentation
import OpenCineCameraControls
import OpenPocketViewCore
import SwiftUI

/// Pocket monitor tools around a remote source. Never opens a camera session.
struct WatcherLiveView: View {
    @Environment(AppModel.self) private var model
    @State private var pictureGeometry: MonitorWatcherPictureGeometry?
    private var client: WatcherRelayClient { model.relayClient }
    private var mirrored: Bool {
        GimbalStick.liveViewFlip(
            poseViewFlip: client.decoder.poseViewFlip,
            assistMirror: model.assist.mirrorsHorizontally)
    }

    var body: some View {
        MonitorOperatorWatcherScreen(host: model, value: watcherValue,
            pictureSize: client.decoder.pictureSize, mirrored: mirrored,
            confirmRecording: model.recordConfirmationEnabled, assists: assistSource,
            action: handleWatcherAction, readTapSource: { client.tapSource },
            capturedTapAction: { size in
                Self.capturedTapAction(client: client, feed: size,
                    mirrored: { mirrored }, flippedVertically: { model.assist.flipsVertically })
            }, onGeometry: { pictureGeometry = $0 }) { effects in
                VideoView(decoder: client.decoder, effects: effects, sampleBus: client.samples,
                    transfer: client.transfer, pictureFlip: client.decoder.poseViewFlip,
                    hdrDisplay: model.hdrDisplayActive)
            } preview: { AssistInspectorPreview(tool: $0)
            } lookMenu: { LUTAssist.longPressMenu(assist: model.assist) }
            .monitorVideoBackdrop(renderer: model.liveBackdrop,
                configuration: backdropConfiguration,
                enabled: model.isWatchingFeed && !model.assist.gradesClip && pictureGeometry?.belongs(to: client.tapSource) == true,
                surroundRGB: 0x000000) { _ in backdropSources() }
            .onAppear { syncColor() }
            .onChange(of: client.state.color) { _, _ in syncColor() }
            .onChange(of: client.state.cameraModel) { _, _ in syncColor() }
    }

    private var assistSource: MonitorOperatorLiveAssistSource {
        .init(stores: .app, looks: .app, haptics: .app,
            readBundle: { model.monitorSamples.displayBundle },
            readTransfer: { model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709 },
            readClipByte: { model.monitorSamples.exposureCeiling.clipByte(transfer: $0) },
            configureDisplay: scopeDisplay)
    }

    private var backdropConfiguration: [MonitorVideoBackdropConfiguration] {
        guard let geometry = pictureGeometry, geometry.belongs(to: client.tapSource) else { return [] }
        let feed = geometry.feed
        return [MonitorVideoBackdropConfiguration(source: ObjectIdentifier(client.decoder),
            generation: Int(client.samples.inspectorSourceEpoch), effects: model.assist.effects,
            geometry: [CGFloat(feed.x), CGFloat(feed.y), CGFloat(feed.width), CGFloat(feed.height), geometry.mirrored ? 1 : 0])]
    }
    private func backdropSources() -> [MonitorVideoBackdropSource] {
        guard let geometry = pictureGeometry, geometry.belongs(to: client.tapSource) else { return [] }
        let feed = CGRect(x: CGFloat(geometry.feed.x), y: CGFloat(geometry.feed.y),
            width: CGFloat(geometry.feed.width), height: CGFloat(geometry.feed.height))
        let decoder = client.decoder, samples = client.samples
        let epoch = samples.inspectorSourceEpoch
        guard let token = decoder.sourceToken, let buffer = decoder.backdropSource else { return [] }
        let effects = decoder.backdropEffects
        return [MonitorVideoBackdropSource(buffer: buffer, effects: effects,
            frame: MonitorVideoBackdropSource.displayedFrame(sourceAspect: decoder.pictureAspect, effects: effects, in: feed),
            clip: feed, identity: .live(token: token, epoch: epoch), admission: { [weak decoder, weak samples] in
                guard let decoder, let samples else { return false }
                return decoder.sourceToken == token && samples.inspectorSourceEpoch == epoch
            })]
    }

    @MainActor
    static func capturedTapAction(client: WatcherRelayClient, feed: CGSize,
        mirrored: @escaping @MainActor () -> Bool, flippedVertically: @escaping @MainActor () -> Bool
    ) -> @MainActor (CGPoint) -> MonitorWatcherFocus? {
        let captured = client.tapSource
        return { location in
            guard captured.admits(client.tapSource) else { return nil }
            let mirror = mirrored(), flip = flippedVertically()
            guard captured.admits(client.tapSource),
                let point = WatcherFocusPoint.map(x: Double(location.x), y: Double(location.y),
                    width: Double(feed.width), height: Double(feed.height),
                    mirrored: mirror, flippedVertically: flip),
                client.sendCommand(.tapFocus(cameraX: point.x, cameraY: point.y,
                    coordinateWidth: 1000, coordinateHeight: 1000), captured: captured)
            else { return nil }
            return .init(source: captured, x: Double(point.x) / 1000, y: Double(point.y) / 1000)
        }
    }

    private func syncColor() {
        client.decoder.incomingColorMode = client.colorMode
        model.assist.syncLUT(
            to: client.colorMode, family: client.state.isNano == true ? .nano : .pocket,
            cameraName: client.state.cameraModel, lookProfile: DJICameraLUTProfile.make(
                family: client.state.isNano == true ? .nano : .pocket,
                cameraName: client.state.cameraModel), persistLast: false)
    }

    private var watcherValue: MonitorWatcherPresentation {
        let context = MonitorWatcherContext(source: String(describing: ObjectIdentifier(client)),
            revision: client.actionRevision, canControl: client.canControl, recording: client.state.isRecording)
        var settings: [MonitorWatcherSettingValue] = []
        if let options = client.state.controlOptions {
            let iso = options.isoIndices.compactMap { raw -> MonitorWatcherChoice? in
                IsoIndex(rawValue: UInt8(clamping: raw)).map { MonitorWatcherChoice(id: raw, title: $0.label) }
            }
            if !iso.isEmpty { settings.append(.init(id: .iso, title: "ISO \(client.state.iso)", choices: iso)) }
            if !options.shutterDenominators.isEmpty {
                settings.append(.init(id: .shutter, title: client.state.shutter.isEmpty ? "Shutter" : client.state.shutter,
                    choices: options.shutterDenominators.map { .init(id: $0, title: "1/\($0)") }))
            }
            if !options.zoomHundredths.isEmpty {
                settings.append(.init(id: .zoom, title: client.state.zoom.isEmpty ? "Zoom" : client.state.zoom,
                    choices: options.zoomHundredths.map { raw in .init(id: raw, title: CamFov.displayLabel(factor: Double(raw) / 100)) }))
            }
        }
        let notice: MonitorWatcherNotice?
        switch client.status {
        case .reconnecting(let attempt): notice = MonitorWatcherNotices.reconnecting(attempt: attempt, maximum: WatcherRelayRecovery.maximumRetries)
        case .failed(let message): notice = MonitorWatcherNotices.failed(message)
        case .live: notice = client.waitingForPicture ? MonitorWatcherNotices.waitingForPicture : nil
        default: notice = MonitorWatcherNotices.joining
        }
        return MonitorWatcherPresentation(context: context, hostTitle: client.hostTitle, receivedFPS: client.receivedFPS,
            readings: [.init("FORMAT", value: client.state.format), .init("COLOR", value: client.state.color),
                .init("SHUTTER", value: client.state.shutter), .init("ISO", value: client.state.iso),
                .init("ZOOM", value: client.state.zoom),
                .init("BATTERY", value: client.state.batteryPercent >= 0 ? "\(client.state.batteryPercent)%" : nil)],
            settings: settings, holderName: client.token.holderName,
            canRequestControl: client.status == .live && client.state.allowsControlRequests,
            controlRequested: client.controlRequested, notice: notice)
    }

    private func handleWatcherAction(_ action: MonitorWatcherAction) {
        guard watcherValue.admits(action) else { return }
        switch action {
        case .leave: model.stopWatching()
        case .chooseFeed: model.stopWatching(); model.openWatcherBrowse()
        case .requestControl: client.requestControl()
        case .releaseControl: client.releaseControl()
        case .record: client.sendCommand(.toggleRecording)
        case .set(_, let setting, let choice):
            switch setting {
            case .iso: client.sendCommand(.setISO(choice))
            case .shutter: client.sendCommand(.setShutterDenom(choice))
            case .zoom: client.sendCommand(.setZoom(choice))
            }
        }
    }

}
