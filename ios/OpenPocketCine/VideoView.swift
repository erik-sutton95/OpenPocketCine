import AVFoundation
import OpenPocketViewCore
import SwiftUI

/// Hosts the HEVC display layer and the Core Image feed (used only while GPU assists are on).
/// `effects` and `sampleBus` are read here so toggling PEAK/LUT/WAVE refreshes this representable
/// and pushes the current stack + bus into the decoder — LiveViewScreen body otherwise never
/// observes those flags (previous bug: `onChange(of: assist.effects)` never fired).
///
/// Mirror is OpenZCine `LiveFrameRaster.feedScale`: a negative-X `scaleEffect` above both
/// renderers. Flipping the CI buffer looked vertical once VideoToolbox orientation landed.
struct VideoView: View {
    let decoder: HevcDecoder
    var effects: LiveImageEffects
    var sampleBus: LiveFrameSampleBus
    /// `CameraStatus.monitorTransfer` (ColorMode `3F`/`3C`/`17`/`41`). Simulator clip is `.dlog2`.
    var transfer: MonitorTransfer?

    var body: some View {
        VideoDisplayRepresentable(
            decoder: decoder,
            effects: rasterEffects,
            sampleBus: sampleBus,
            transfer: transfer,
            feedUpscaler: FeedUpscaleSwitch.shared.upscaler
        )
        .scaleEffect(MirrorAssist.feedScale(mirrored: effects.mirror), anchor: .center)
    }

    /// Mirror stays a view-space flip so the GPU path does not also flip the buffer.
    private var rasterEffects: LiveImageEffects {
        var fx = effects
        fx.mirror = false
        return fx
    }
}

private struct VideoDisplayRepresentable: UIViewRepresentable {
    let decoder: HevcDecoder
    var effects: LiveImageEffects
    var sampleBus: LiveFrameSampleBus
    var transfer: MonitorTransfer?
    var feedUpscaler: FeedUpscaler

    func makeUIView(context: Context) -> DisplayLayerView {
        let view = DisplayLayerView(decoder.displayLayer)
        view.onReady = { [decoder] in decoder.noteDisplayReady() }
        decoder.processedFeed = view.ciFeed
        wire(decoder)
        return view
    }

    func updateUIView(_ uiView: DisplayLayerView, context: Context) {
        uiView.onReady = { [decoder] in decoder.noteDisplayReady() }
        decoder.processedFeed = uiView.ciFeed
        guard
            decoder.sampleBus !== sampleBus
                || decoder.effects != effects
                || decoder.feedUpscaler != feedUpscaler
                || (transfer != nil && decoder.incomingTransfer != transfer)
        else { return }
        wire(decoder)
    }

    private func wire(_ decoder: HevcDecoder) {
        decoder.sampleBus = sampleBus
        decoder.effects = effects
        decoder.feedUpscaler = feedUpscaler
        decoder.adoptIncomingTransfer(transfer)
        decoder.startSimulatorSampleIfNeeded()
    }
}

final class DisplayLayerView: UIView {
    private let displayLayer: AVSampleBufferDisplayLayer
    let ciFeed = CIFeedView()
    var onReady: (() -> Void)?

    init(_ layer: AVSampleBufferDisplayLayer) {
        displayLayer = layer
        super.init(frame: .zero)
        backgroundColor = .black
        isUserInteractionEnabled = false
        layer.videoGravity = .resizeAspect
        self.layer.addSublayer(layer)
        addSubview(ciFeed)
        ciFeed.isUserInteractionEnabled = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer.frame = bounds
        ciFeed.frame = bounds
        if bounds.width > 1, bounds.height > 1 { onReady?() }
    }
}
