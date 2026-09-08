import OpenPocketViewCore
import SwiftUI
import UIKit

/// Watcher monitor on shared camera Wi-Fi. Local assist only; no camera session.
struct WatcherLiveView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoView(
                decoder: model.relayClient.decoder,
                effects: model.assist.effects,
                sampleBus: model.relayClient.samples,
                transfer: nil,
                pictureFlip: model.relayClient.decoder.poseViewFlip
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Button("Leave") { model.stopWatching() }
                        .font(LiveType.ui(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(LiveDesign.surface, in: Capsule())
                    Spacer()
                    Text(model.relayClient.hostTitle)
                        .font(LiveType.ui(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                    Spacer()
                    hudChip
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)

                Spacer()

                HStack(spacing: 12) {
                    Text(model.relayClient.token.holderName)
                        .font(LiveType.ui(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if model.relayClient.status == .live,
                        model.relayClient.state.allowsControlRequests
                    {
                        if model.relayClient.token.holderIsRecipient {
                            Button("Release") { model.relayClient.releaseControl() }
                                .font(LiveType.ui(size: 14, weight: .semibold))
                            Button("REC") {
                                model.relayClient.sendCommand(.toggleRecording)
                            }
                            .font(LiveType.ui(size: 14, weight: .bold))
                            .foregroundStyle(LiveDesign.rec)
                        } else {
                            Button("Request control") { model.relayClient.requestControl() }
                                .font(LiveType.ui(size: 14, weight: .semibold))
                        }
                    }
                }
                .padding(16)
            }

            if case .failed(let message) = model.relayClient.status {
                VStack(spacing: 16) {
                    Text(message)
                        .font(LiveType.ui(size: 15, weight: .medium))
                        .multilineTextAlignment(.center)
                    Button("Choose a feed") {
                        model.stopWatching()
                        model.openWatcherBrowse()
                    }
                    .buttonStyle(StartupFilledButtonStyle())
                }
                .foregroundStyle(.white)
                .padding()
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0).onEnded { value in
                guard model.relayClient.status == .live, model.relayClient.token.holderIsRecipient
                else { return }
                let size = UIScreen.main.bounds.size
                let x = Int((value.location.x / max(size.width, 1)) * 1000)
                let y = Int((value.location.y / max(size.height, 1)) * 1000)
                model.relayClient.sendCommand(
                    .tapFocus(cameraX: x, cameraY: y, coordinateWidth: 1000, coordinateHeight: 1000)
                )
            }
        )
        .preferredColorScheme(.dark)
    }

    private var hudChip: some View {
        let s = model.relayClient.state
        return Text(
            "\(s.format)  \(s.color)  \(s.iso)  \(s.zoom)  \(s.batteryPercent >= 0 ? "\(s.batteryPercent)%" : "")"
        )
        .font(LiveType.ui(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.black.opacity(0.45), in: Capsule())
    }
}
