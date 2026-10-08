import AVFoundation
import OpenCineAppKitApple
import OpenCineApple
import OpenPocketViewCore
import SwiftUI
import UIKit
import OpenCineMedia

/// Hosts the HEVC display layer and the Core Image feed (used only while GPU assists are on).
/// `effects` and `sampleBus` are read here so toggling PEAK/LUT/WAVE refreshes this representable
/// and pushes the current stack + bus into the decoder — LiveViewScreen body otherwise never
/// observes those flags (previous bug: `onChange(of: assist.effects)` never fired).
///
/// Mirror is OpenZCine `LiveFrameRaster.feedScale`: a negative-X transform on a host view
/// that wraps both renderers. Applied at present time (not SwiftUI `scaleEffect`) so
/// MIRROR assist lands with the presented picture. MIRROR Vertical is a negative Y on the
/// same host; it has no pose latch, so it applies on the toggle.
struct VideoView: View {
    let decoder: HevcDecoder
    var effects: MonitorFrameEffects
    var sampleBus: LiveFrameSampleBus
    /// `CameraStatus.monitorTransfer` (ColorMode `3F`/`3C`/`17`/`41`). Simulator clip is `.dlog2`.
    var transfer: MonitorTransfer?
    /// MIRROR assist. Applied on the host view so reconnect cannot skip it.
    var pictureFlip = false
    /// Outdoor HDR panel. Identity presents through Metal EDR.
    var hdrDisplay = false
    var qualification: (@MainActor () -> MonitorNativeQualificationSnapshot?)? = nil

    var body: some View {
        VideoDisplayRepresentable(
            decoder: decoder,
            effects: rasterEffects,
            assistMirror: effects.mirror,
            flipVertical: effects.mirrorVertical,
            pictureFlip: pictureFlip,
            sampleBus: sampleBus,
            transfer: transfer,
            feedUpscaler: FeedUpscaleSwitch.shared.upscaler,
            hdrDisplay: hdrDisplay,
            qualification: qualification
        )
        .transaction { $0.animation = nil }
    }

    /// Mirror stays a view-space flip so the GPU path does not also flip the buffer.
    private var rasterEffects: MonitorFrameEffects {
        var fx = effects
        fx.mirror = false
        return fx
    }
}

struct VideoDisplayRepresentable: UIViewRepresentable {
    let decoder: HevcDecoder
    var effects: MonitorFrameEffects
    var assistMirror: Bool
    var flipVertical = false
    var pictureFlip: Bool
    var sampleBus: LiveFrameSampleBus
    var transfer: MonitorTransfer?
    var feedUpscaler: MonitorUpscaler
    var hdrDisplay: Bool
    var qualification: (@MainActor () -> MonitorNativeQualificationSnapshot?)? = nil

    func makeUIView(context: Context) -> DisplayLayerView {
        let view = DisplayLayerView(decoder.displayLayer)
        view.accessibilityIdentifier = "monitor.native.picture"
        if let qualification {
            view.qualificationProbe = MonitorNativeQualificationProbe.install(in: view) { [weak view] in
                guard view?.ownsDisplayLayer == true else { return nil }
                return qualification()
            }
        }
        view.onReady = { [decoder] in decoder.noteDisplayReady() }
        decoder.processedFeed = view.ciFeed
        view.applyHDRDisplay(hdrDisplay)
        bindMirror(decoder, view: view)
        wire(decoder)
        return view
    }

    func updateUIView(_ uiView: DisplayLayerView, context: Context) {
        updateDisplay(uiView)
    }

    func updateDisplay(_ uiView: DisplayLayerView) {
        guard uiView.ownsDisplayLayer else { return }
        if let qualification {
            uiView.qualificationProbe?.snapshot = { [weak uiView] in
                guard uiView?.ownsDisplayLayer == true else { return nil }
                return qualification()
            }
        }
        uiView.onReady = { [decoder] in decoder.noteDisplayReady() }
        decoder.processedFeed = uiView.ciFeed
        uiView.applyHDRDisplay(hdrDisplay)
        bindMirror(decoder, view: uiView)
        guard
            decoder.sampleBus !== sampleBus
                || decoder.effects != effects
                || decoder.feedUpscaler != feedUpscaler
                || decoder.hdrDisplayEnabled != hdrDisplay
                || decoder.assistMirror != assistMirror
                || (transfer != nil && decoder.incomingTransfer != transfer)
        else { return }
        wire(decoder)
    }

    private func bindMirror(_ decoder: HevcDecoder, view: DisplayLayerView) {
        decoder.applyPictureMirror = { [weak view] mirrored in
            view?.setPictureMirrored(mirrored)
        }
        decoder.assistMirror = assistMirror
        view.setPictureFlippedVertically(flipVertical)
    }

    private func wire(_ decoder: HevcDecoder) {
        decoder.bindSourcePublication(sampleBus)
        decoder.effects = effects
        decoder.feedUpscaler = feedUpscaler
        decoder.hdrDisplayEnabled = hdrDisplay
        decoder.adoptIncomingTransfer(transfer)
        decoder.startSimulatorSampleIfNeeded()
    }
}

final class DisplayLayerView: OpenCineApple.MonitorVideoPictureContainer {
    let ciFeed: CIFeedView
    var qualificationProbe: MonitorNativeQualificationProbe?
    init(_ layer: AVSampleBufferDisplayLayer) {
        let feed = CIFeedView()
        self.ciFeed = feed
        super.init(layer, processedPicture: feed)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func applyHDRDisplay(_ enabled: Bool) {
        LiveHDRDisplay.app.setEnabled(enabled, screen: window?.screen)
        LiveHDRDisplay.app.configure(displayLayer, screen: window?.screen)
        ciFeed.syncHDRDisplay()
    }
}
