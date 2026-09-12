import AVFoundation
import OpenPocketViewCore
import SwiftUI

/// Stable native playback adapter; UI chrome is a sibling of this host.
struct MediaPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let session: PlaybackFeedSession
    var effects: LiveImageEffects
    var transfer: MonitorTransfer
    var sampleBus: LiveFrameSampleBus

    final class Coordinator {
        let session: PlaybackFeedSession
        let generation: Int
        init(session: PlaybackFeedSession) {
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
        session.setEffects(effects, transfer: transfer, sampleBus: sampleBus)
        return view
    }

    func updateUIView(_ uiView: PlaybackFeedHostView, context: Context) {
        uiView.attachGeneration = context.coordinator.generation
        session.attach(host: uiView, player: player)
        session.setEffects(effects, transfer: transfer, sampleBus: sampleBus)
    }

    static func dismantleUIView(_ uiView: PlaybackFeedHostView, coordinator: Coordinator) {
        coordinator.session.detach(host: uiView)
        uiView.playerLayer.player = nil
    }
}
