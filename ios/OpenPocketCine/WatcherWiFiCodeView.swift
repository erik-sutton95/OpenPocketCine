import CoreImage.CIFilterBuiltins
import SwiftUI

/// Reveals credentials only while the operator has this sheet open.
struct WatcherWiFiCodeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var code: CGImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Join camera Wi-Fi")
                        .font(LiveType.ui(size: 22, weight: .bold))
                    Text(model.session.joinedSSID ?? "Camera Wi-Fi")
                        .font(LiveType.ui(size: 16, weight: .medium))
                    if scenePhase == .active, model.isLive, let code {
                        Image(decorative: code, scale: 1)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .padding(24)
                            .background(.white)
                            .privacySensitive()
                    } else {
                        Text(
                            "Wi-Fi code unavailable. Reconnect the camera or join its Wi-Fi in Settings."
                        )
                    }
                    Text(
                        "On the watching device, open Camera and scan this code. Tap Join Network, then return to OpenPocketCine → Watch a feed."
                    )
                    Text(
                        "This code shares the camera’s Wi-Fi password. Keep this phone connected to the camera; watching devices only join the shared feed."
                    )
                    .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .padding(24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            guard let payload = model.session.watcherWiFiJoinCode else { return }
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = "M"
            guard let output = filter.outputImage else { return }
            let bounds = output.extent.insetBy(dx: -4, dy: -4)
            let white = CIImage(color: CIColor.white).cropped(to: bounds)
            code = CIContext().createCGImage(output.composited(over: white), from: bounds)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                code = nil
                dismiss()
            }
        }
        .onChange(of: model.session.joinedSSID) { _, _ in
            code = nil
            dismiss()
        }
        .onChange(of: model.isLive) { _, live in
            if !live {
                code = nil
                dismiss()
            }
        }
    }
}
