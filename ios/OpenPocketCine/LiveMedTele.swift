import OpenPocketViewCore
import SwiftUI

/// Pocket 3 Med-Tele (MT): the second, 2× lens, beside the zoom chip. Its own
/// button rather than a zoom stop, because the body decides where the zoom
/// lands after the swap.
///
/// Reads the session itself, like `LiveZoomChip`, so a swap redraws this button
/// and nothing around it. Dimmed while a swap runs, when it takes no taps, and
/// in the states `CamFov.medTeleRefusal` names, where it stays tappable so the
/// note can say why.
struct LiveMedTeleButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked

    private var session: CameraSession { model.session }
    private var on: Bool {
        session.medTeleSwap
            ?? session.status.zoomLensMin.map { CamFov.isMedTele(lensMin: $0) } ?? false
    }
    private var refused: Bool {
        CamFov.medTeleRefusal(
            colorMode: session.status.colorMode, isRecording: session.status.isRecording,
            shootingMode: session.status.shootingMode) != nil
    }
    private var enabled: Bool { !interfaceLocked && session.medTeleSwap == nil }

    var body: some View {
        Button {
            session.toggleMedTele()
        } label: {
            Text("MT")
                .font(LiveType.ui(size: 9, weight: .bold))
                .foregroundStyle(on ? LiveDesign.accent : LiveDesign.text)
                .frame(width: GimbalCluster.medTeleSize, height: GimbalCluster.medTeleSize)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(
                    Circle().strokeBorder(
                        on ? LiveDesign.accent : LiveDesign.hairline, lineWidth: 1))
        }
        .buttonStyle(.zcTapTarget)
        .opacity(enabled && !refused ? 1 : 0.4)
        .disabled(!enabled)
        .accessibilityLabel(on ? "Turn Med-Tele off" : "Turn Med-Tele on")
        .accessibilityValue(on ? "On" : "Off")
    }
}

/// Black over the picture while an MT swap runs, so the body's lens change
/// never shows. Its own layer, outside the warm-up cover, so a swap redraws
/// only this.
struct LiveMedTeleFade: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let swapping = model.session.medTeleSwap != nil
        let fadeMs = swapping ? CamFov.medTeleFadeMs : Self.fadeInMs
        Color.black
            .opacity(swapping ? 1 : 0)
            .animation(.easeInOut(duration: Double(fadeMs) / 1000), value: swapping)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The picture comes back a little slower than it goes.
    private static let fadeInMs = 160
}
