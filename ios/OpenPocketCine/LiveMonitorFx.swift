import CoreImage
import Metal
import OpenCineAppKitApple
import OpenCineApple
import OpenCineCameraVocabulary
import OpenCineMedia
import OpenPocketViewCore
import UIKit

/// The shared value owns picture and sample demand. DJI source facts remain adapter inputs.

extension MonitorFrameEffects {
    var colorMode: ColorMode {
        get { transfer.colorMode }
        set {
            transfer = MonitorTransfer(newValue)
            referenceClipByte = DJIScopeExposureCeiling.referenceClipByte(
                transfer: transfer)
        }
    }
    mutating func stamp(transfer: MonitorTransfer, ceiling: DJIScopeExposureCeiling) {
        self.transfer = transfer
        referenceClipByte = DJIScopeExposureCeiling.referenceClipByte(transfer: transfer)
        clipByte = ceiling.clipByte(transfer: transfer)
    }
    init(faceAF: Bool) { self.init(); self.faceAF = faceAF }
    init(inspectorSample: Bool) { self.init(); self.inspectorSample = inspectorSample }
    init(histogram: Bool) { self.init(); self.histogram = histogram }
}


enum LiveMonitorCompositor {
    static var fusedPeakingAvailable: Bool {
        OpenCineApple.MonitorImageCompositor.fusedPeakingAvailable
    }
    static var fusedPeakingNote: String { OpenCineApple.MonitorImageCompositor.fusedPeakingNote }
    static func apply(to source: CIImage, effects: MonitorFrameEffects, display: CIImage? = nil)
        -> CIImage
    {
        OpenCineApple.MonitorImageCompositor.apply(
            to: source, effects: effects.nativeImageEffects, display: display)
    }
    static func applyProduct(to source: CIImage, effects: MonitorFrameEffects, display: CIImage? = nil)
        -> (image: CIImage, unmanagedBake: Bool)
    {
        OpenCineApple.MonitorImageCompositor.applyProduct(
            to: source, effects: effects.nativeImageEffects, display: display)
    }
    static func assistOverlay(from source: CIImage, effects: MonitorFrameEffects) -> CIImage {
        OpenCineApple.MonitorImageCompositor.assistOverlay(
            from: source, effects: effects.nativeImageEffects)
    }
    static func place(_ overlay: CIImage, over base: CIImage) -> CIImage {
        OpenCineApple.MonitorImageCompositor.place(overlay, over: base)
    }
}

extension MonitorFrameEffects {
    var nativeImageEffects: OpenCineApple.MonitorImageEffects {
        var result = nativeImagePlan
        if falseColor,
            let maps = PocketFalseColorMap.overlayPairData(
                scale: falseColorScale, mode: colorMode, rec709: falseColorRec709,
                clipByte: resolvedClipByte)
        {
            result.falseColorMaps = OpenCineApple.MonitorOverlayMaps(
                dimension: maps.dimension, paint: maps.paint, weight: maps.weight)
        }
        return result
    }

}

/// The app supplies operator choices; the stable native host owns rendering and presentation.
final class CIFeedView: OpenCineApple.MonitorPictureHost {
    init(frame: CGRect = .zero) {
        super.init(
            frame: frame,
            options: { screen in
                LiveHDRDisplay.app.refreshGain(screen: screen)
                return OpenCineApple.MonitorPresentationOptions(
                    upscaler: FeedUpscaleSwitch.rendererReadsUpscaler,
                    hdr: LiveHDRDisplay.app.isEnabled, hdrGain: LiveHDRDisplay.app.presentGain,
                    previewSuperResolutionInput: FeedUpscaleSwitch.presentsSuperResolutionInput)
            }, logSubsystem: "com.opencapture.openpocketcine")
        #if DEBUG
            onSuccessfulPresent = { FeedStressAutomation.notePresent() }
        #endif
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
