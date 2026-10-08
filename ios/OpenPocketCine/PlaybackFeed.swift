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
        var value = self
        value.referenceClipByte = DJIScopeExposureCeiling.referenceClipByte(transfer: value.transfer)
        return value
    }
}
