import AVFoundation
import OpenCineApple
import OpenPocketViewCore
import SwiftUI
import OpenCineMedia

/// Stable native playback adapter; UI chrome is a sibling of this host.
struct MediaPlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    let session: MonitorPlaybackFeedSession
    var qualificationItemToken: (@MainActor () -> MonitorPlaybackItemToken?)? = nil
    var effects: MonitorFrameEffects
    var transfer: MonitorTransfer
    var sampleBus: LiveFrameSampleBus

    @MainActor final class Coordinator {
        let session: MonitorPlaybackFeedSession
        let generation: Int
        weak var qualificationProbe: MonitorNativeQualificationProbe?
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
        view.accessibilityIdentifier = "monitor.native.picture"
        let qualificationItemToken = qualificationItemToken
        context.coordinator.qualificationProbe = MonitorNativeQualificationProbe.install(in: view) { [weak view, weak session, weak player] in
            guard let view, let session, let player, session.debugBoundHost === view else { return nil }
            return .playback(player: player, layer: view.playerLayer,
                             sourcePresented: session.debugItemHasPresented,
                             itemToken: qualificationItemToken?())
        }
        view.attachGeneration = context.coordinator.generation
        session.attach(host: view, player: player)
        session.setEffects(effects.playbackFrameEffects, transfer: transfer, sampleBus: sampleBus)
        return view
    }

    func updateUIView(_ uiView: PlaybackFeedHostView, context: Context) {
        let qualificationItemToken = qualificationItemToken
        context.coordinator.qualificationProbe?.snapshot = { [weak uiView, weak session, weak player] in
            guard let uiView, let session, let player, session.debugBoundHost === uiView else { return nil }
            return .playback(player: player, layer: uiView.playerLayer,
                             sourcePresented: session.debugItemHasPresented,
                             itemToken: qualificationItemToken?())
        }
        uiView.attachGeneration = context.coordinator.generation
        session.attach(host: uiView, player: player)
        session.setEffects(effects.playbackFrameEffects, transfer: transfer, sampleBus: sampleBus)
    }

    static func dismantleUIView(_ uiView: PlaybackFeedHostView, coordinator: Coordinator) {
        coordinator.qualificationProbe?.snapshot = { nil }
        coordinator.qualificationProbe?.removeFromSuperview()
        coordinator.session.detach(host: uiView)
        uiView.playerLayer.player = nil
    }
}
