import CoreImage
import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Sampling demand is independent of whether an assist is enabled on the main
/// picture. The existing decoder and scope tap remain the only producers.
extension LiveImageEffects {
    func withInspectorDemand(_ tool: LiveAssistTool?) -> LiveImageEffects {
        guard let tool else { return self }
        var next = self
        switch tool {
        case .waveform: next.waveform = true
        case .parade: next.parade = true
        case .histogram: next.histogram = true
        case .vectorscope: next.vectorscope = true
        case .trafficLights: next.trafficLights = true
        case .ndMeter: next.ndMeter = true
        case .evMeter: break
        default: next.inspectorSample = AssistInspectorPreviewPolicy.isImage(tool)
        }
        return next
    }
}

enum AssistInspectorPreviewPolicy {
    static let maximumImageDimension: CGFloat = 320
    static let refreshInterval: Duration = .nanoseconds(
        Int64(MonitorPreviewAdmission.minimumIntervalNanoseconds))

    static func height(width: CGFloat, tool: LiveAssistTool) -> CGFloat {
        let ratio: CGFloat
        switch tool {
        case .waveform, .parade: ratio = 0.612
        case .histogram: ratio = 0.42
        case .vectorscope: ratio = 0.9
        case .trafficLights: ratio = 0.62
        default: ratio = 0.5625
        }
        return min(196, max(56, width * ratio))
    }

    static func isImage(_ tool: LiveAssistTool) -> Bool {
        switch tool {
        case .lut, .peaking, .falseColor, .zebra, .guides, .grid, .crosshair, .mirror, .desqueeze:
            true
        default: false
        }
    }

    /// The inspector forces its selected image tool on in this local copy only.
    /// Other pixel warnings are omitted so the operator can assess this tool.
    @MainActor
    static func imageEffects(
        assist: LiveAssistState, tool: LiveAssistTool, transfer: MonitorTransfer
    ) -> LiveImageEffects {
        var result = imageOptions(assist: assist, tool: tool, transfer: transfer)
        if tool == .lut {
            let lut = assist.inspectorLUT(transfer: transfer)
            result.lutDimension = lut.dimension
            result.lutRGBA = lut.rgba
        }
        return result
    }

    /// Cheap option snapshot, including settings of a tool that is off on the
    /// main picture. This must not resolve or prepare a preview-only LUT.
    @MainActor
    static func imageOptions(
        assist: LiveAssistState, tool: LiveAssistTool, transfer: MonitorTransfer
    ) -> LiveImageEffects {
        var result = assist.gradesClip ? assist.playbackEffects : assist.effects
        result.peaking = tool == .peaking
        result.falseColor = tool == .falseColor
        result.zebra = tool == .zebra
        result.histogram = false
        result.waveform = false
        result.parade = false
        result.vectorscope = false
        result.trafficLights = false
        result.ndMeter = false
        result.faceAF = false
        result.inspectorSample = false
        result.colorMode = transfer.colorMode
        result.mirror = tool == .mirror || result.mirror
        if tool == .lut {
            result.splitComparison = assist.splitComparison
        }
        if tool == .desqueeze { result.desqueezeFactor = assist.desqueezeFactor }
        return result
    }
}

/// Identifies image meaning without observing every retained source buffer.
/// Cached picture effects and LUT inputs are cheap to compare. Resolving a
/// preview-only LUT is deferred until the retained worker admits a job.
private struct AssistInspectorImageConfiguration: Equatable {
    let source: ObjectIdentifier
    let sourceEpoch: UInt64
    let playback: Bool
    let tool: LiveAssistTool
    let effects: LiveImageEffects
    let transfer: MonitorTransfer
    let lutSelection: LUTSelection
    let lutExposureStops: Double
    let customLUTName: String?
    let lutColorMode: ColorMode?
    let lutFamily: CameraBodyFamily
    let lutCameraName: String?
}

/// A draw-only preview slot for the shared inspector. Scope plots reuse the
/// existing bounded sample bundle. Image tasks borrow the session's retained
/// worker, so tool changes and remounts cannot reset its one-job/5 Hz admission.
struct AssistInspectorPreview: View {
    var tool: LiveAssistTool
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.audioInspectorLevels) private var audioInspectorLevels
    @State private var owner: UUID?
    @State private var image: CGImage?
    @State private var renderedTool: LiveAssistTool?
    @State private var availableWidth: CGFloat = 0

    private var isActive: Bool {
        scenePhase == .active && model.assist.inspectorSceneActive
    }

    private var imageConfiguration: AssistInspectorImageConfiguration? {
        guard isActive, AssistInspectorPreviewPolicy.isImage(tool) else { return nil }
        let samples = model.monitorSamples
        guard let source = samples.inspectorSource else { return nil }
        return AssistInspectorImageConfiguration(
            source: ObjectIdentifier(samples), sourceEpoch: samples.inspectorSourceEpoch,
            playback: samples.usesPlaybackSource, tool: tool,
            effects: AssistInspectorPreviewPolicy.imageOptions(
                assist: model.assist, tool: tool, transfer: source.transfer),
            transfer: source.transfer,
            lutSelection: model.assist.lutSelection,
            lutExposureStops: model.assist.lutExposureStops,
            customLUTName: OperatorPrefs.selectedCustomFileName,
            lutColorMode: model.assist.monitorColorMode,
            lutFamily: model.assist.monitorFamily, lutCameraName: model.assist.monitorCameraName)
    }

    var body: some View {
        Group {
            if AssistInspectorPreviewPolicy.isImage(tool) {
                imagePreview
            } else {
                scopePreview
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: AssistInspectorPreviewPolicy.height(width: availableWidth, tool: tool))
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            availableWidth = $0
        }
        .background(MonitorTheme.canvas, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(MonitorTheme.border))
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tool.title) preview")
        .accessibilityIdentifier("monitor.inspector.preview")
        .task(id: isActive ? tool : nil) {
            guard isActive else { return }
            await updateImage()
        }
        .onChange(of: imageConfiguration) { _, _ in
            if let owner { model.inspectorPreview.invalidate(owner: owner) }
            clearImage()
        }
        .onDisappear {
            if let owner { model.inspectorPreview.deactivate(owner: owner) }
            clearImage()
        }
    }

    @ViewBuilder
    private var imagePreview: some View {
        if let image, renderedTool == tool {
            Image(decorative: image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        let imageAspect = CGFloat(image.width) / CGFloat(max(1, image.height))
                        let width = min(proxy.size.width, proxy.size.height * imageAspect)
                        let height = width / imageAspect
                        let frame = CGRect(
                            x: (proxy.size.width - width) / 2,
                            y: (proxy.size.height - height) / 2, width: width, height: height)
                        switch tool {
                        case .guides:
                            GuidesAssist.overlay(
                                feed: frame, assist: model.assist,
                                fallback: model.assist.guideAspect)
                        case .grid:
                            GridAssist.overlay(
                                feed: frame, thirds: model.assist.gridThirds,
                                phi: model.assist.gridPhi, diagonal: model.assist.gridDiagonal)
                        case .crosshair:
                            CrosshairAssist.overlay(feed: frame)
                        default:
                            EmptyView()
                        }
                    }
                }
        } else {
            Text("Waiting for picture")
                .font(MonitorTheme.font(11))
                .foregroundStyle(MonitorTheme.muted)
        }
    }

    @ViewBuilder
    private var scopePreview: some View {
        switch tool {
        case .waveform:
            fittedScope(size: WaveformAssist.panelSize(scale: WaveformAssist.store.options.scale)) {
                WaveformOverlay()
            }
        case .parade:
            fittedScope(size: ParadeAssist.panelSize(scale: ParadeAssist.store.options.scale)) {
                ParadeOverlay()
            }
        case .histogram:
            fittedScope(size: HistogramAssist.panelSize(scale: HistogramAssist.store.options.scale))
            {
                HistogramOverlay()
            }
        case .vectorscope:
            fittedScope(
                size: VectorscopeAssist.panelSize(scale: VectorscopeAssist.store.options.scale)
            ) {
                VectorscopeOverlay()
            }
        case .trafficLights:
            TrafficLightsMeterMini(reading: model.monitorSamples.displayBundle.traffic)
                .frame(width: 88, height: 120)
        case .ndMeter:
            NDMeterChip(
                reading: NDAssist.reading(from: model.monitorSamples.displayBundle),
                notation: NDAssist.store.notation
            )
            .frame(width: 120, height: 44)
        case .audioMeters:
            if let levels = audioInspectorLevels {
                audioPreview(levels: levels, sensitivity: nil)
            } else if !model.assist.gradesClip {
                audioPreview(
                    levels: model.session.status.audioMeters,
                    sensitivity: model.session.status.audioChannel?.label)
            }

        default:
            EmptyView()
        }
    }

    private func audioPreview(levels: AudioMeterLevels, sensitivity: String?) -> some View {
        let options = AudioAssist.store.options
        return fittedScope(size: AudioAssist.panelSize(orientation: options.orientation)) {
            AudioMetersPanelMini(
                levels: levels, sensitivity: sensitivity,
                orientation: options.orientation, showsDB: options.showsDB)
        }
    }

    private func fittedScope<Content: View>(size: CGSize, @ViewBuilder content: () -> Content)
        -> some View
    {
        let plot = content()
        return GeometryReader { proxy in
            let scale = min(
                1, max(1, proxy.size.width - 16) / max(1, size.width),
                max(1, proxy.size.height - 16) / max(1, size.height))
            plot.frame(width: size.width, height: size.height)
                .scaleEffect(scale)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @MainActor
    private func updateImage() async {
        guard !Task.isCancelled, AssistInspectorPreviewPolicy.isImage(tool) else { return }
        let renderer = model.inspectorPreview
        let identity = UUID()
        owner = identity
        renderer.activate(owner: identity)
        defer {
            renderer.deactivate(owner: identity)
            if owner == identity { owner = nil }
        }
        while !Task.isCancelled {
            if let configuration = imageConfiguration,
                let source = model.monitorSamples.inspectorSource
            {
                let rendered = await renderer.render(
                    owner: identity, source: source.buffer
                ) {
                    AssistInspectorPreviewPolicy.imageEffects(
                        assist: model.assist, tool: tool, transfer: source.transfer)
                }
                guard !Task.isCancelled else { return }
                if let rendered, renderer.isCurrent(rendered),
                    configuration == imageConfiguration
                {
                    image = rendered.image
                    renderedTool = tool
                }
            }
            do {
                // This inspector-local cadence cannot schedule catch-up work.
                // It stops with SwiftUI task cancellation and never paces video.
                try await Task.sleep(for: AssistInspectorPreviewPolicy.refreshInterval)
            } catch {
                return
            }
        }
    }

    private func clearImage() {
        image = nil
        renderedTool = nil
    }
}
