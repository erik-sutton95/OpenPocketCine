import CoreImage
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
        default: next.inspectorSample = AssistInspectorPreviewPolicy.isImage(tool)
        }
        return next
    }
}

enum AssistInspectorPreviewPolicy {
    static let maximumImageDimension: CGFloat = 320
    static let refreshInterval: Duration = .milliseconds(200)

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
        var result = assist.effects
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
        result.mirror = tool == .mirror || assist.isVisible(.mirror)
        if tool == .lut {
            let lut = assist.inspectorLUT(transfer: transfer)
            result.lutDimension = lut.dimension
            result.lutRGBA = lut.rgba
            result.splitComparison = assist.splitComparison
        }
        if tool == .desqueeze { result.desqueezeFactor = assist.desqueezeFactor }
        return result
    }
}

/// A draw-only preview slot for the shared inspector. Scope plots reuse the
/// existing bounded sample bundle. Image tools own one cancellable 5 Hz task
/// while this view is mounted; closing or changing the inspector drops its work.
struct AssistInspectorPreview: View {
    var tool: LiveAssistTool
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var renderer = AssistInspectorImageRenderer()
    @State private var image: CGImage?
    @State private var renderedTool: LiveAssistTool?
    @State private var availableWidth: CGFloat = 0

    private var isActive: Bool {
        scenePhase == .active && model.assist.inspectorSceneActive
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
        .onChange(of: model.monitorSamples.inspectorSourceEpoch) { _, _ in
            image = nil
            renderedTool = nil
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
            AudioAssist.meter(
                levels: model.session.status.audioMeters,
                sensitivity: model.session.status.audioChannel?.label
            )
            .scaleEffect(0.8)
        default:
            EmptyView()
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
        guard AssistInspectorPreviewPolicy.isImage(tool) else { return }
        while !Task.isCancelled {
            if let source = model.monitorSamples.inspectorSource {
                let sourceEpoch = model.monitorSamples.inspectorSourceEpoch
                let effects = AssistInspectorPreviewPolicy.imageEffects(
                    assist: model.assist, tool: tool, transfer: source.transfer)
                let rendered = await renderer.render(source: source.buffer, effects: effects)
                guard !Task.isCancelled else { return }
                if let rendered, sourceEpoch == model.monitorSamples.inspectorSourceEpoch {
                    image = rendered
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
}
