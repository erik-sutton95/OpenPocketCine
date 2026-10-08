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
    @MainActor static func makeMeter() -> MonitorPlaybackAudioMeterRuntime {
        MonitorPlaybackAudioMeterRuntime(onTapFailure: tapFailure)
    }
    nonisolated static func tapFailure(_ status: Int32) {
        playbackAudioLogger.error("MTAudioProcessingTapCreate failed: \(status)")
    }
    nonisolated static func audioFailure(_ message: String) {
        playbackAudioLogger.error("Playback audio session failed: \(message, privacy: .public)")
    }
}
