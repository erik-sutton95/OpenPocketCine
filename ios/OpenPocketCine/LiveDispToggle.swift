import MonitorPresentation
import MonitorUI
import SwiftUI

/// OpenZCine `MonitorSystemCluster.displayButton` (`MonitorUnified.swift` ~1143).
/// DISP 1 = live chrome. DISP 2 = clean (OpenZCine `DisplayChromeVisibility.cleanDefaults`).
struct LiveDispToggle: View {
    var size: CGSize = CGSize(
        width: LiveChromeMetrics.displayButtonWidth, height: LiveChromeMetrics.displayButtonHeight)
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked

    var body: some View {
        MonitorChromeButton("Change display mode", size: size) {
            guard !interfaceLocked else { return }
            model.assist.clean.toggle()
            if model.assist.clean {
                model.captureSheet = nil
            }
        } label: {
            VStack(spacing: 3) {
                Text("DISP")
                    .font(
                        LiveType.ui(
                            size: CGFloat(MonitorCapturePopupChrome.dispSize), weight: .bold)
                    )
                    .tracking(CGFloat(MonitorCapturePopupChrome.dispTracking))
                HStack(spacing: 3) {
                    Capsule()
                        .fill(model.assist.clean ? LiveDesign.hairlineStrong : LiveDesign.info)
                        .frame(width: 14, height: 3)
                    Capsule()
                        .fill(model.assist.clean ? LiveDesign.info : LiveDesign.hairlineStrong)
                        .frame(width: 14, height: 3)
                }
            }
            .foregroundStyle(model.assist.clean ? LiveDesign.text : LiveDesign.muted)
        }
        .disabled(interfaceLocked)
        .sensoryFeedback(.selection, trigger: model.assist.clean)
        .accessibilityLabel("Change display mode")
        .accessibilityValue(model.assist.clean ? "DISP 2 clean" : "DISP 1 live")
        .accessibilityIdentifier("monitor.system.display")
    }
}
