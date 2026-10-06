import OpenCineAppKitApple
import OpenCineApple
import OpenCineCameraVocabulary
import OpenCineMedia
import OpenPocketViewCore
import UIKit

/// Pocket supplies measured source calibration, display preference and diagnostics.
final class PlaybackFeedSession: OpenCineApple.MonitorPlaybackFeedSession, @unchecked Sendable {
    @MainActor init() {
        super.init(
            configuration: LiveAssistEngine.configuration,
            hdrDisplay: { LiveHDRDisplay.app.isEnabled },
            journal: { ControlLiveLog.line($0) },
            sourceAdvanced: {
                NotificationCenter.default.post(name: .monitorBackdropSourceAdvanced, object: nil)
            })
    }
}

final class PlaybackFeedHostView: OpenCineApple.MonitorPlaybackFeedHost {
    init(frame: CGRect = .zero) {
        super.init(
            frame: frame, picture: CIFeedView(),
            configurePlayerLayer: { LiveHDRDisplay.app.configure($0) })
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// A complete value projection at the native seam; it owns no sampling or presentation workflow.
extension MonitorFrameEffects {
    var playbackFrameEffects: MonitorFrameEffects {
        var value = MonitorFrameEffects()
        value.peaking = peaking
        value.zebra = zebra
        value.falseColor = falseColor
        value.histogram = histogram
        value.waveform = waveform
        value.parade = parade
        value.vectorscope = vectorscope
        value.trafficLights = trafficLights
        value.ndMeter = ndMeter
        value.lutDimension = lutDimension
        value.lutRGBA = lutRGBA
        switch peakingColor {
        case .white: value.peakingColor = .white
        case .blue: value.peakingColor = .blue
        case .red: value.peakingColor = .red
        case .green: value.peakingColor = .green
        }
        switch peakingSensitivity {
        case .low: value.peakingSensitivity = .low
        case .medium: value.peakingSensitivity = .medium
        case .high: value.peakingSensitivity = .high
        }
        switch falseColorScale {
        case .sceneStops: value.falseColorScale = .sceneStops
        case .stops: value.falseColorScale = .stops
        case .ire: value.falseColorScale = .ire
        case .limits: value.falseColorScale = .limits
        }
        value.falseColorRec709 = falseColorRec709
        value.zebraHighlight = zebraHighlight
        value.zebraMidtone = zebraMidtone
        value.zebraHighlightIRE = zebraHighlightIRE
        value.zebraMidtoneIRE = zebraMidtoneIRE
        value.zebraHighlightColor = playbackPaint(zebraHighlightColor)
        value.zebraMidtoneColor = playbackPaint(zebraMidtoneColor)
        value.transfer = MonitorTransfer(colorMode)
        value.clipByte = clipByte
        value.referenceClipByte = OpenCineCameraVocabulary.ScopeExposureCeiling.referenceClipByte(
            transfer: value.transfer)
        value.allowsTransferInference = allowsTransferInference
        value.splitComparison = splitComparison
        value.splitVertical = splitVertical
        value.mirror = mirror
        value.mirrorVertical = mirrorVertical
        value.desqueezeFactor = desqueezeFactor
        value.desqueezeHorizontal = desqueezeHorizontal
        value.trafficThreshold = trafficThreshold
        value.faceAF = faceAF
        value.inspectorSample = inspectorSample
        return value
    }

    private func playbackPaint(_ paint: MonitorZebraPaint) -> MonitorZebraPaint {
        switch paint {
        case .white: .white
        case .amber: .amber
        case .red: .red
        case .cyan: .cyan
        case .green: .green
        }
    }
}
