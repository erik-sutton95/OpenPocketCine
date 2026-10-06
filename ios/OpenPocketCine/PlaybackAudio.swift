import AVFoundation
import MonitorUI
import OSLog
import OpenCineApple
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import MonitorPresentation

private let playbackAudioLogger = Logger(
    subsystem: "OpenPocketCine", category: "media-playback-audio")

/// Configures `AVAudioSession` for in-app clip playback so audio plays through the mute switch.
enum MediaPlaybackAudioSession {
    @MainActor static func makeMeter() -> OpenCineApple.MonitorPlaybackAudioMeterRuntime {
        OpenCineApple.MonitorPlaybackAudioMeterRuntime(onTapFailure: { status in
            playbackAudioLogger.error("MTAudioProcessingTapCreate failed: \(status)")
        })
    }

    static func activateForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            playbackAudioLogger.error(
                "Failed to activate playback audio session: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    static func deactivateAfterPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            playbackAudioLogger.error(
                "Failed to deactivate playback audio session: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

/// The existing overlay consumes DJI DTOs; absence stays optional at this value seam.
extension AudioMeterLevels {
    init(_ levels: MonitorAudioMeterLevels) {
        self.init(
            left: AudioMeterChannel(
                levelDB: levels.left.levelDB, peakDB: levels.left.peakDB,
                peakAge: levels.left.peakAge),
            right: AudioMeterChannel(
                levelDB: levels.right.levelDB, peakDB: levels.right.peakDB,
                peakAge: levels.right.peakAge))
    }
}

/// Playback assist chip: existing icon, label and operator actions remain app composition.
struct PlaybackAssistToolButton: View {
    @Environment(AppModel.self) private var model
    let tool: MonitorAssistSelection
    var onConfigure: (MonitorAssistSelection) -> Void
    @State private var buildup: Task<Void, Never>?

    var body: some View {
        AssistToolChip(tool: tool, isOn: model.assist.isPlaybackVisible(tool), compact: true)
            .contentShape(Rectangle())
            .minTapTarget()
            .onTapGesture {
                model.assist.togglePlayback(tool)
            }
            .onLongPressGesture(minimumDuration: 0.25) {
                cancelBuildup()
                guard tool.hasConfiguration else { return }
                AssistBarHaptics.confirm()
                onConfigure(tool)
            } onPressingChanged: { pressing in
                guard tool.hasConfiguration else { return }
                if pressing {
                    buildup = AssistBarHaptics.buildup()
                } else {
                    cancelBuildup()
                }
            }
            .accessibilityLabel(tool.title)
    }

    private func cancelBuildup() {
        buildup?.cancel()
        buildup = nil
    }
}
