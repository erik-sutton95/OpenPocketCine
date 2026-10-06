import AVFoundation
import OpenCineApple
import OpenPocketViewCore
import SwiftUI
import OpenCineMedia

/// Stable native playback adapter; UI chrome is a sibling of this host.
struct MediaPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let session: MonitorPlaybackFeedSession
    var effects: MonitorFrameEffects
    var transfer: MonitorTransfer
    var sampleBus: LiveFrameSampleBus

    @MainActor final class Coordinator {
        let session: MonitorPlaybackFeedSession
        let generation: Int
        init(session: MonitorPlaybackFeedSession) {
            self.session = session
            self.generation = session.reserveHostGeneration()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> PlaybackFeedHostView {
        let view = PlaybackFeedHostView()
        view.attachGeneration = context.coordinator.generation
        session.attach(host: view, player: player)
        session.setEffects(effects.playbackFrameEffects, transfer: transfer, sampleBus: sampleBus)
        return view
    }

    func updateUIView(_ uiView: PlaybackFeedHostView, context: Context) {
        uiView.attachGeneration = context.coordinator.generation
        session.attach(host: uiView, player: player)
        session.setEffects(effects.playbackFrameEffects, transfer: transfer, sampleBus: sampleBus)
    }

    static func dismantleUIView(_ uiView: PlaybackFeedHostView, coordinator: Coordinator) {
        coordinator.session.detach(host: uiView)
        uiView.playerLayer.player = nil
    }
}
